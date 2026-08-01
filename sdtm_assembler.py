"""
sdtm_assembler.py - Generate SDTM SAS programs from a draft SDTM spec.

Phase 5c in the SpecGen pipeline:
  sdtm_spec_draft.xlsx --> dm.sas, ae.sas, vs.sas, cm.sas, ...

Unlike the ADaM assembler (variable-by-variable), SDTM generates one
complete program per domain because the variables are interdependent
(e.g. VSTESTCD and VSORRES must be built together in the same data step).

Domain class determines the code structure:
  DM         : one row per subject, merge demographics from multiple sources
  Events     : one row per event (AE, DS, MH, DV) — read source, derive timing
  Interventions : one row per intervention (CM, EX) — read source, derive timing
  Findings   : one row per test per timepoint (VS, EG) — transpose or stack tests
  Findings About Events : one row per assessment (TU, TR, RS) — similar to Findings
  SUPP--     : vertical QNAM/QVAL structure from parent domain; appended into
               the parent domain's own .sas file (e.g. SUPPAE lives inside
               ae.sas), not written as a separate program

Uses the existing three-agent pipeline:
  Writer (Ollama or API) --> Improver (API) --> Reviewer (API)

Usage:
  # Generate all domains
  python sdtm_assembler.py sdtm_spec_draft.xlsx --output sdtm_programs/

  # Generate one domain
  python sdtm_assembler.py sdtm_spec_draft.xlsx --domain DM --output sdtm_programs/

  # Offline mode (Ollama only, no API)
  python sdtm_assembler.py sdtm_spec_draft.xlsx --offline --output sdtm_programs/

  # As a module
  from sdtm_assembler import generate_all_domains
  generate_all_domains("sdtm_spec_draft.xlsx", "sdtm_programs/")
"""

import os
import re
import sys
import argparse
import openpyxl

# Claude's responses (review verdicts, generated code) commonly contain
# Unicode punctuation (em-dashes, curly quotes) that Windows' default console
# codepage (cp1252) can't encode. Printing that text would otherwise crash
# this entire subprocess with UnicodeEncodeError the moment any domain's
# review happens to contain such a character — silently killing every
# domain's generation, not just the one that triggered it.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from config import WRITER, REVIEWER, LOCAL_MODEL, API_MODEL
from generator import generate_local, generate_api, review_sas
from improver import improve_block
from runlog import log_run


# ── Domain classification ───────────────────────────────────────────

EVENTS_DOMAINS = {"AE", "DS", "MH", "DV", "CE"}
INTERVENTIONS_DOMAINS = {"CM", "EC", "EX", "PR", "SU"}
FINDINGS_DOMAINS = {"VS", "LB", "EG", "PE", "QS", "SC", "DA", "MB", "MS", "PC", "PP"}
FINDINGS_ABOUT_EVENTS_DOMAINS = {"TU", "TR", "RS"}


def get_domain_class(domain):
    if domain.startswith("SUPP"):
        return "SUPP"
    if domain == "DM":
        return "DM"
    if domain in EVENTS_DOMAINS:
        return "Events"
    if domain in INTERVENTIONS_DOMAINS:
        return "Interventions"
    if domain in FINDINGS_DOMAINS:
        return "Findings"
    if domain in FINDINGS_ABOUT_EVENTS_DOMAINS:
        return "Findings About Events"
    return "General"


# ── Read SDTM spec ──────────────────────────────────────────────────

def read_domain_spec(xlsx_path, domain):
    """
    Read one domain sheet from sdtm_spec_draft.xlsx.
    Returns a list of variable dicts.
    """
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    if domain not in wb.sheetnames:
        wb.close()
        return []

    ws = wb[domain]

    # Find header row (skip domain label rows)
    header_row = None
    for row_num, row in enumerate(ws.iter_rows(values_only=False), 1):
        vals = [cell.value for cell in row]
        if "Variable" in vals and "Label" in vals:
            header_row = row_num
            break

    if header_row is None:
        wb.close()
        return []

    headers = [cell.value for cell in ws[header_row]]
    variables = []

    for row in ws.iter_rows(min_row=header_row + 1, values_only=True):
        record = dict(zip(headers, row))
        if record.get("Variable"):
            variables.append(record)

    wb.close()
    return variables


def list_domains(xlsx_path):
    """List all domain sheets in the spec (excluding Cover)."""
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    domains = [s for s in wb.sheetnames if s != "Cover"]
    wb.close()
    return domains


# ── Prompt building per domain class ────────────────────────────────

def _var_table(variables):
    """Format variable list as a readable table for the prompt."""
    lines = []
    lines.append(f"{'Variable':<16} {'Label':<45} {'Type':<6} {'Len':<5} {'Origin':<10} {'Codelist'}")
    lines.append(f"{'-'*16} {'-'*45} {'-'*6} {'-'*5} {'-'*10} {'-'*20}")
    for v in variables:
        var = str(v.get("Variable", ""))
        label = str(v.get("Label", ""))[:45]
        vtype = str(v.get("Type", ""))
        length = str(v.get("Length", ""))
        origin = str(v.get("Origin", ""))
        codelist = str(v.get("Codelist", "") or "")
        lines.append(f"{var:<16} {label:<45} {vtype:<6} {length:<5} {origin:<10} {codelist}")
    return "\n".join(lines)


def build_dm_prompt(domain, variables):
    """Prompt for DM domain - one row per subject."""
    var_table = _var_table(variables)
    return f"""You are a senior CDISC SDTM programmer. Generate a complete, production-quality SAS program
for the {domain} (Demographics) domain.

SDTM specification for {domain}:
{var_table}

Requirements:
- Read source data from raw. library (raw.dm, raw.ex as needed)
- Set STUDYID, DOMAIN as constants
- Derive USUBJID = catx('-', STUDYID, SITEID, SUBJID)
- Map CRF fields to SDTM variables per the spec
- Derive RFSTDTC (first dose date) and RFENDTC (last dose date) from EX domain
- Derive RFXSTDTC, RFXENDTC from exposure data
- ARM and ARMCD from randomization/CRF; ACTARM/ACTARMCD derived or same as planned
- Compute AGE from BRTHDTC and RFSTDTC if not directly collected
- COUNTRY from site-level metadata
- Apply proper lengths, labels, and formats per the spec
- Sort by STUDYID USUBJID
- Output to sdtm.{domain} with a KEEP statement listing all spec variables in order
- Include variable labels in a LABEL statement
- Add clear comments for each derivation section
- Use /*-- BEGIN {domain} --*/ and /*-- END {domain} --*/ markers around the main code block

Generate the complete SAS program. No explanations, just the code."""


def build_events_prompt(domain, variables):
    """Prompt for Events domains (AE, DS, MH, DV) - one row per event."""
    var_table = _var_table(variables)
    domain_lower = domain.lower()
    prefix = domain[:2]
    return f"""You are a senior CDISC SDTM programmer. Generate a complete, production-quality SAS program
for the {domain} domain (Events class - one row per event per subject).

SDTM specification for {domain}:
{var_table}

Requirements:
- Read source data from raw.{domain_lower} (and raw.dm for STUDYID/USUBJID if needed)
- Set DOMAIN = '{domain}'
- Derive {prefix}SEQ as a sequence number within each subject (by USUBJID)
- Derive USUBJID = catx('-', STUDYID, SITEID, SUBJID) or merge from DM
- Map --TERM, --DECOD from source verbatim and coded terms
- Map --STDTC, --ENDTC from source start/end dates (ISO 8601 character format)
- Derive --STDY, --ENDY as study day relative to RFSTDTC from DM
- Derive EPOCH based on date relative to treatment period
- Apply --BODSYS from MedDRA/WHO coding if applicable
- Apply --CAT, --SCAT from source categories
- Handle domain-specific variables (severity for AE, disposition terms for DS, etc.)
- Apply proper lengths, labels, and formats per the spec
- Sort by STUDYID USUBJID {prefix}SEQ
- Output to sdtm.{domain} with a KEEP statement listing all spec variables in order
- Include variable labels in a LABEL statement
- Add clear comments for each derivation section
- Use /*-- BEGIN {domain} --*/ and /*-- END {domain} --*/ markers

Generate the complete SAS program. No explanations, just the code."""


def build_interventions_prompt(domain, variables):
    """Prompt for Interventions domains (CM, EX) - one row per intervention."""
    var_table = _var_table(variables)
    domain_lower = domain.lower()
    prefix = domain[:2]
    return f"""You are a senior CDISC SDTM programmer. Generate a complete, production-quality SAS program
for the {domain} domain (Interventions class - one row per intervention per subject).

SDTM specification for {domain}:
{var_table}

Requirements:
- Read source data from raw.{domain_lower} (and raw.dm for STUDYID/USUBJID if needed)
- Set DOMAIN = '{domain}'
- Derive {prefix}SEQ as a sequence number within each subject (by USUBJID)
- Derive USUBJID = catx('-', STUDYID, SITEID, SUBJID) or merge from DM
- Map --TRT (reported treatment name) and --DECOD (standardized name) from source
- Map --DOSE, --DOSU, --DOSFRQ, --ROUTE from source dosing fields
- Map --STDTC, --ENDTC from source start/end dates (ISO 8601 character format)
- Derive --STDY, --ENDY as study day relative to RFSTDTC from DM
- Derive EPOCH based on date relative to treatment period
- Apply --CAT from source categories
- Apply proper lengths, labels, and formats per the spec
- Sort by STUDYID USUBJID {prefix}SEQ
- Output to sdtm.{domain} with a KEEP statement listing all spec variables in order
- Include variable labels in a LABEL statement
- Add clear comments for each derivation section
- Use /*-- BEGIN {domain} --*/ and /*-- END {domain} --*/ markers

Generate the complete SAS program. No explanations, just the code."""


def build_findings_prompt(domain, variables):
    """Prompt for Findings domains (VS, EG) - one row per test per timepoint."""
    var_table = _var_table(variables)
    domain_lower = domain.lower()
    prefix = domain[:2]
    return f"""You are a senior CDISC SDTM programmer. Generate a complete, production-quality SAS program
for the {domain} domain (Findings class - one row per test per timepoint per subject).

SDTM specification for {domain}:
{var_table}

Requirements:
- Read source data from raw.{domain_lower} (and raw.dm for STUDYID/USUBJID if needed)
- Set DOMAIN = '{domain}'
- Derive {prefix}SEQ as a sequence number within each subject (by USUBJID)
- Derive USUBJID = catx('-', STUDYID, SITEID, SUBJID) or merge from DM
- Each test parameter becomes one row: set {prefix}TESTCD and {prefix}TEST per measurement
- If source is wide format (one column per test), transpose to vertical (one row per test)
- If source is already vertical, map directly
- Map {prefix}ORRES (original result as character), {prefix}ORRESU (original units) from source
- Derive {prefix}STRESC (standardized character result) and {prefix}STRESN (numeric result)
- Derive {prefix}STRESU (standard units) - apply unit conversions if needed
- Map VISITNUM, VISIT from source visit data
- Map {prefix}DTC from source collection date (ISO 8601 character format)
- Derive {prefix}DY as study day relative to RFSTDTC from DM
- Handle {prefix}STAT = 'NOT DONE' and {prefix}REASND for missing measurements
- Apply proper lengths, labels, and formats per the spec
- Sort by STUDYID USUBJID {prefix}TESTCD VISITNUM {prefix}DTC
- Output to sdtm.{domain} with a KEEP statement listing all spec variables in order
- Include variable labels in a LABEL statement
- Add clear comments for each derivation section
- Use /*-- BEGIN {domain} --*/ and /*-- END {domain} --*/ markers

Generate the complete SAS program. No explanations, just the code."""


def build_fae_prompt(domain, variables):
    """Prompt for Findings About Events domains (TU, TR, RS)."""
    var_table = _var_table(variables)
    domain_lower = domain.lower()
    prefix = domain[:2]
    return f"""You are a senior CDISC SDTM programmer. Generate a complete, production-quality SAS program
for the {domain} domain (Findings About Events class - tumor/response assessments).

SDTM specification for {domain}:
{var_table}

Requirements:
- Read source data from raw.{domain_lower} (and raw.dm for STUDYID/USUBJID if needed)
- Set DOMAIN = '{domain}'
- Derive {prefix}SEQ as a sequence number within each subject (by USUBJID)
- Derive USUBJID from DM
- Each assessment becomes one row: set {prefix}TESTCD and {prefix}TEST per measurement
- Map {prefix}ORRES (original result), {prefix}STRESC, {prefix}STRESN from source
- Map {prefix}EVAL (evaluator: INVESTIGATOR or INDEPENDENT ASSESSOR)
- Map {prefix}LNKID for linking between TU/TR/RS domains
- Map VISITNUM, VISIT, {prefix}DTC from source
- Derive {prefix}DY relative to RFSTDTC from DM
- Apply {prefix}CAT for assessment criteria (e.g. RECIST 1.1)
- Apply proper lengths, labels, and formats per the spec
- Sort by STUDYID USUBJID {prefix}TESTCD VISITNUM {prefix}DTC
- Output to sdtm.{domain} with a KEEP statement
- Include variable labels in a LABEL statement
- Use /*-- BEGIN {domain} --*/ and /*-- END {domain} --*/ markers

Generate the complete SAS program. No explanations, just the code."""


def build_supp_prompt(domain, variables):
    """Prompt for SUPP-- domains - vertical QNAM/QVAL structure."""
    var_table = _var_table(variables)
    parent = domain.replace("SUPP", "")
    parent_lower = parent.lower()

    # Separate structural vars from qualifier values
    structural = [v for v in variables if v.get("Variable") in
                  ("STUDYID", "RDOMAIN", "USUBJID", "IDVAR", "IDVARVAL",
                   "QNAM", "QLABEL", "QVAL", "QORIG", "QEVAL")]
    qualifiers = [v for v in variables if v.get("Variable") not in
                  ("STUDYID", "RDOMAIN", "USUBJID", "IDVAR", "IDVARVAL",
                   "QNAM", "QLABEL", "QVAL", "QORIG", "QEVAL")]

    qual_list = []
    for q in qualifiers:
        qual_list.append(f"  QNAM='{q['Variable']}', QLABEL='{q.get('Label', q['Variable'])}'")

    return f"""You are a senior CDISC SDTM programmer. Generate a complete, production-quality SAS program
for the {domain} supplemental qualifier domain.

Parent domain: {parent}
RDOMAIN = '{parent}'
IDVAR = '{parent}SEQ'

SUPP structure (fixed columns):
{_var_table(structural)}

Qualifier variables to transpose into QNAM/QVAL rows:
{chr(10).join(qual_list)}

Requirements:
- Read source data from raw.{parent_lower} (the parent domain's source)
- Read sdtm.{parent} to get {parent}SEQ values for IDVARVAL
- For each qualifier variable, create one row per subject per parent record:
  - STUDYID = study constant
  - RDOMAIN = '{parent}'
  - USUBJID = from parent
  - IDVAR = '{parent}SEQ'
  - IDVARVAL = put({parent}SEQ, best.)
  - QNAM = variable name (e.g. '{qualifiers[0]["Variable"] if qualifiers else "QVAR"}')
  - QLABEL = variable label
  - QVAL = the actual data value (always character)
  - QORIG = 'CRF'
  - QEVAL = '' (blank unless evaluator-dependent)
- Stack all qualifier rows together using SET statements or PROC TRANSPOSE
- Only output rows where QVAL is non-missing
- Sort by STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM
- Output to sdtm.{domain}
- Include variable labels in a LABEL statement
- Use /*-- BEGIN {domain} --*/ and /*-- END {domain} --*/ markers

Generate the complete SAS program. No explanations, just the code."""


# ── Build prompt router ─────────────────────────────────────────────

def build_domain_prompt(domain, variables):
    """Route to the correct prompt builder based on domain class."""
    dclass = get_domain_class(domain)

    if dclass == "DM":
        return build_dm_prompt(domain, variables)
    elif dclass == "Events":
        return build_events_prompt(domain, variables)
    elif dclass == "Interventions":
        return build_interventions_prompt(domain, variables)
    elif dclass == "Findings":
        return build_findings_prompt(domain, variables)
    elif dclass == "Findings About Events":
        return build_fae_prompt(domain, variables)
    elif dclass == "SUPP":
        return build_supp_prompt(domain, variables)
    else:
        return build_events_prompt(domain, variables)


# ── Three-agent pipeline ────────────────────────────────────────────

def generate_domain_program(domain, variables, use_api=True):
    """
    Generate a complete SAS program for one SDTM domain
    using the three-agent pipeline: Writer -> Improver -> Reviewer.
    """
    dclass = get_domain_class(domain)
    prompt = build_domain_prompt(domain, variables)

    print(f"\n  [{domain}] Generating SAS program ({dclass}, {len(variables)} variables)")

    # Step 1: Writer
    print(f"    Writer: ", end="", flush=True)
    if use_api:
        draft = generate_api(prompt)
        writer_model = API_MODEL
        print(f"API ({API_MODEL})")
    else:
        draft = generate_local(prompt)
        writer_model = LOCAL_MODEL
        print(f"Local ({LOCAL_MODEL})")

    if not draft or len(draft.strip()) < 50:
        print(f"    WARNING: Writer produced empty/short output for {domain}")
        return None, writer_model

    # Step 2: Improver
    # Step 2: Improver (direct API call, not the ADaM variable-level improver)
    if use_api:
        print(f"    Improver: API ({API_MODEL})")
        var_names = [v["Variable"] for v in variables if v.get("Variable")]
        improve_prompt = f"""You are a principal SAS programmer with 15+ years of CDISC SDTM experience.
Review and improve this SAS program for the {domain} domain.

The program must create all these variables: {', '.join(var_names)}

Fix any issues:
- Missing or incorrect variable derivations
- Wrong lengths, types, or formats
- Missing LABEL statements
- Missing or incorrect sort order
- Hardcoded values that should be derived
- Non-standard date handling (must be ISO 8601 character)

Return ONLY the improved SAS code, no explanations.""" + "\n\n" + draft

        try:
            improved = generate_api(improve_prompt)
            if improved and len(improved.strip()) > 50:
                draft = improved
            else:
                print(f"    Improver returned empty, keeping Writer draft")
        except Exception as e:
            print(f"    Improver failed: {e}, keeping Writer draft")

    # Step 3: Reviewer
    if use_api:
        print(f"    Reviewer: API ({API_MODEL})")
        var_names = [v["Variable"] for v in variables if v.get("Variable")]
        review = review_sas(draft)
        if review:
            print(f"    Review: {review[:100]}...")
    else:
        review = None

    return draft, writer_model


# ── Program assembly ────────────────────────────────────────────────

def assemble_program(domain, code, variables):
    """
    Wrap the generated code in a standard SDTM program structure:
    header comment, libname, code, proc contents.
    """
    domain_lower = domain.lower()
    dclass = get_domain_class(domain)
    n_vars = len(variables)

    # Build variable list for the header
    var_names = [v["Variable"] for v in variables if v.get("Variable")]

    header = f"""/*******************************************************************************
* Program:    {domain_lower}.sas
* Domain:     {domain} ({dclass})
* Purpose:    Create SDTM {domain} domain dataset
* Variables:  {n_vars}
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.{domain_lower} (source CRF data)
* Output:     sdtm.{domain_lower} ({domain} domain dataset)
*
* Variables:  {', '.join(var_names[:8])}
*             {'...' if len(var_names) > 8 else ''}
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\\sas_data\\raw'  access=readonly;
libname sdtm 'C:\\sas_data\\sdtm';
"""

    footer = f"""
/*-- Final sort and output verification --*/
proc sort data=sdtm.{domain_lower};
  by STUDYID USUBJID;
run;

proc contents data=sdtm.{domain_lower} varnum;
run;

proc freq data=sdtm.{domain_lower};
  tables DOMAIN / nocum nopercent;
run;

/* End of {domain_lower}.sas */
"""

    # Clean up the generated code
    clean_code = code.strip()
    # Remove any markdown fences
    if clean_code.startswith("```"):
        clean_code = clean_code.split("\n", 1)[1]
    if clean_code.endswith("```"):
        clean_code = clean_code.rsplit("```", 1)[0]
    clean_code = clean_code.strip()

    return header + "\n" + clean_code + "\n" + footer


# ── Main entry points ───────────────────────────────────────────────

def generate_single_domain(xlsx_path, domain, output_dir, use_api=True, force=False):
    """Generate the SAS program for one domain.

    By default, skips generation if output_dir/<domain>.sas already exists —
    each Writer/Improver run is a fresh, non-deterministic draft, so
    regenerating on every call would silently overwrite any hand-QC fix
    applied to a prior draft (see ROADMAP.md Phase 10 piece 3). Pass
    force=True to regenerate anyway (e.g. after a spec change).
    """
    domain_lower = domain.lower()
    output_file = os.path.join(output_dir, f"{domain_lower}.sas")
    if not force and os.path.exists(output_file):
        print(f"  [{domain}] Skipping — {output_file} already exists (use --force to regenerate)")
        return output_file

    variables = read_domain_spec(xlsx_path, domain)
    if not variables:
        print(f"  No variables found for domain {domain}")
        return None

    code, writer_model = generate_domain_program(domain, variables, use_api=use_api)
    if not code:
        print(f"  Failed to generate code for {domain}")
        return None

    program = assemble_program(domain, code, variables)

    # Write to file
    os.makedirs(output_dir, exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as f:
        f.write(program)

    print(f"    Written to {output_file} ({len(program)} chars)")

    # Log the run
    try:
        log_run(
            spec_file=xlsx_path,
            mode="sdtm_generate",
            writer_model=writer_model,
            improver_model=API_MODEL if use_api else "none",
            reviewer_model=API_MODEL if use_api else "none",
            n_vars=len(variables),
            output_file=output_file,
        )
    except Exception as e:
        print(f"    Warning: could not log run: {e}")

    return output_file


FOOTER_MARKER = "/*-- Final sort and output verification --*/"


def append_supp_domain(xlsx_path, supp_domain, output_dir, use_api=True, force=False):
    """Generate a SUPP-- domain and append its code into its PARENT domain's
    .sas file (e.g. SUPPAE lives inside ae.sas) instead of writing a separate
    program. SUPP-- is a supplemental-qualifier view of the same dataset, not
    an independent domain — most SOPs build it in the same program as its
    parent, since it shares the same source pull.

    Skips (like generate_single_domain) if the parent file already has this
    SUPP domain's /*-- BEGIN {supp_domain} --*/ marker, unless force=True, in
    which case the old block is cut out and replaced with a fresh one.
    """
    parent = supp_domain.replace("SUPP", "")
    parent_file = os.path.join(output_dir, f"{parent.lower()}.sas")
    if not os.path.exists(parent_file):
        print(f"  [{supp_domain}] Parent domain file {parent_file} not found — skipping")
        return None

    with open(parent_file, encoding="utf-8") as f:
        parent_code = f.read()

    begin_marker = f"/*-- BEGIN {supp_domain} --*/"
    end_marker = f"/*-- END {supp_domain} --*/"
    already_present = begin_marker in parent_code

    if already_present and not force:
        print(f"  [{supp_domain}] Skipping — already present in {parent_file} (use --force to regenerate)")
        return parent_file

    variables = read_domain_spec(xlsx_path, supp_domain)
    if not variables:
        print(f"  No variables found for domain {supp_domain}")
        return None

    code, writer_model = generate_domain_program(supp_domain, variables, use_api=use_api)
    if not code:
        print(f"  Failed to generate code for {supp_domain}")
        return None

    clean_code = code.strip()
    if clean_code.startswith("```"):
        clean_code = clean_code.split("\n", 1)[1]
    if clean_code.endswith("```"):
        clean_code = clean_code.rsplit("```", 1)[0]
    clean_code = clean_code.strip()
    supp_block = f"\n{clean_code}\n"

    if already_present:  # force=True got us here — cut out the stale block first
        pattern = re.compile(re.escape(begin_marker) + r".*?" + re.escape(end_marker), re.DOTALL)
        parent_code = pattern.sub(clean_code, parent_code, count=1)
    elif FOOTER_MARKER in parent_code:
        parent_code = parent_code.replace(FOOTER_MARKER, supp_block + "\n" + FOOTER_MARKER, 1)
    else:
        parent_code = parent_code + supp_block

    with open(parent_file, "w", encoding="utf-8") as f:
        f.write(parent_code)

    print(f"    Appended {supp_domain} into {parent_file} ({len(clean_code)} chars)")

    try:
        log_run(
            spec_file=xlsx_path,
            mode="sdtm_generate",
            writer_model=writer_model,
            improver_model=API_MODEL if use_api else "none",
            reviewer_model=API_MODEL if use_api else "none",
            n_vars=len(variables),
            output_file=parent_file,
        )
    except Exception as e:
        print(f"    Warning: could not log run: {e}")

    return parent_file


def generate_all_domains(xlsx_path, output_dir, use_api=True, domains=None, force=False):
    """
    Generate SAS programs for all domains in the spec.
    Processes standard domains first, then SUPP domains
    (SUPP needs parent domain to exist first).

    Domains whose output file already exists are skipped unless force=True
    (see generate_single_domain) — repeated runs (e.g. every "Generate" click
    in the web app) are idempotent by default instead of overwriting hand-QC
    fixes with a fresh non-deterministic draft each time.
    """
    all_domains = list_domains(xlsx_path)

    if domains:
        all_domains = [d for d in all_domains if d in domains]

    std_domains = [d for d in all_domains if not d.startswith("SUPP")]
    supp_domains = [d for d in all_domains if d.startswith("SUPP")]

    print(f"SpecGen Phase 5c: SDTM Program Generation")
    print(f"  Spec: {xlsx_path}")
    print(f"  Output: {output_dir}")
    print(f"  Standard domains ({len(std_domains)}): {', '.join(std_domains)}")
    print(f"  SUPP domains ({len(supp_domains)}): {', '.join(supp_domains)}")
    print(f"  Mode: {'API' if use_api else 'Offline'}{' (force regenerate)' if force else ''}")

    results = {}
    failed = []

    # Standard domains first
    for domain in std_domains:
        result = generate_single_domain(xlsx_path, domain, output_dir, use_api, force=force)
        if result:
            results[domain] = result
        else:
            failed.append(domain)

    # SUPP domains after (they reference parent domain) — appended into the
    # parent domain's own .sas file, not written as a separate program
    for domain in supp_domains:
        result = append_supp_domain(xlsx_path, domain, output_dir, use_api, force=force)
        if result:
            results[domain] = result
        else:
            failed.append(domain)

    # Summary
    print(f"\n{'='*60}")
    print(f"SDTM Generation Summary")
    print(f"{'='*60}")
    print(f"  Generated: {len(results)} programs")
    for domain, path in sorted(results.items()):
        dclass = get_domain_class(domain)
        print(f"    {domain:<10} [{dclass}] -> {path}")
    if failed:
        print(f"  Failed: {len(failed)} - {', '.join(failed)}")
    print(f"{'='*60}")

    return results


# ── CLI entry point ─────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate SDTM SAS programs from a draft SDTM specification.")
    parser.add_argument("spec", help="Path to sdtm_spec_draft.xlsx")
    parser.add_argument("--output", "-o", default="sdtm_programs",
                        help="Output directory (default: sdtm_programs/)")
    parser.add_argument("--domain", "-d",
                        help="Generate for a single domain (e.g. DM, AE, VS)")
    parser.add_argument("--offline", action="store_true",
                        help="Use local Ollama only, no API calls")
    parser.add_argument("--force", action="store_true",
                        help="Regenerate domains even if their output .sas file already "
                             "exists (default: skip existing files, so hand-QC fixes "
                             "aren't overwritten by a fresh draft)")

    args = parser.parse_args()

    if args.domain:
        domains = [d.strip().upper() for d in args.domain.split(",")]
        generate_all_domains(args.spec, args.output,
                             use_api=not args.offline, domains=domains, force=args.force)
    else:
        generate_all_domains(args.spec, args.output,
                             use_api=not args.offline, force=args.force)
