"""
bds_assembler.py — ADaM analysis datasets

Two code paths by dataset class:

  Findings (ADVS, ADLB, ADEG) — one row per subject per PARAMCD per visit,
    built from an SDTM findings domain (VS, LB, EG). PARAMCD/PARAM reshape,
    baseline pass (BASE/CHG/PCHG), visit windows (AWLO/AWHI), analysis flag
    (ANL01FL). See generate_bds_domain().

  Events (ADAE, ADCM) — one row per event/record (no baseline, no reshape;
    already one-row-per-record in SDTM). Merge ADSL treatment dates, convert
    dates to numeric, derive treatment-emergent / on-treatment and first-
    occurrence flags. See generate_events_domain().

Every derived variable is wrapped in /*-- BEGIN var --*/ ... END markers, so
spec_differ.py / spec_patcher.py work on these programs unchanged.

Output: one .sas file per dataset into adam_programs/ (mirrors sdtm_programs/).
"""

import os
import pandas as pd

from visit_windows import build_visit_windows, generate_awlo_awhi_sas

BEGIN = "/*-- BEGIN {var} --*/"
END = "/*-- END {var} --*/"


def wrap(var, code):
    return f"{BEGIN.format(var=var)}\n{code}\n{END.format(var=var)}\n"


# ---------------------------------------------------------------------------
# Findings BDS domains (ADVS, ADLB, ADEG)
# ---------------------------------------------------------------------------

def build_param_spec_from_acrf(acrf_df, sdtm_domain_code, source_testcd_var):
    """
    Auto-derive PARAMCD/PARAM from acrf_metadata.xlsx Qualifier rows
    ("VSTESTCD=SYSBP"), a 1:1 carry-forward of the SDTM --TESTCD. Covers
    straightforward domains only; derived/composite/unit-converted params
    would need a manual override layer (backlog).
    """
    qualifier_prefix = f"{source_testcd_var}="
    domain_rows = acrf_df[acrf_df["Domain"] == sdtm_domain_code]
    test_rows = domain_rows[domain_rows["Qualifier"].astype(str).str.startswith(qualifier_prefix)]

    if test_rows.empty:
        raise ValueError(
            f"No '{qualifier_prefix}CODE' qualifier rows found for {sdtm_domain_code} in acrf_metadata"
        )

    param_spec_rows = []
    for _, row in test_rows.iterrows():
        code = row["Qualifier"].split("=", 1)[1].strip()
        label = str(row["CRF Label"]).rstrip(":").strip()
        param_spec_rows.append({
            "paramcd": code,
            "param": label,
            "source_testcd": code,
            "source_testcd_var": source_testcd_var,
        })
    return param_spec_rows


def generate_bds_domain(sdtm_source_df_name, param_spec_rows, domain_code, baseline_visit="BASELINE"):
    """
    Findings BDS generator. domain_code e.g. "ADVS"; the SDTM --STRESN column
    it reads is derived from the domain code (ADVS -> VSSTRESN).
    """
    lookup_lines = [
        f'    if {p["source_testcd_var"]} = "{p["source_testcd"]}" then do;'
        f' PARAMCD = "{p["paramcd"]}"; PARAM = "{p["param"]}"; end;'
        for p in param_spec_rows
    ]
    lookup_block = "\n".join(lookup_lines)

    paramcd_code = f"""data {domain_code.lower()}_paramcd;
    set {sdtm_source_df_name};
    length PARAMCD $8 PARAM $40;
{lookup_block}
    AVAL = {domain_code[2:]}STRESN;  /* standardized numeric result */
run;"""

    program = wrap(f"{domain_code}_PARAMCD", paramcd_code)

    baseline_code = f"""proc sort data={domain_code.lower()}_paramcd;
    by USUBJID PARAMCD VISITNUM;
run;

data {domain_code.lower()}_base;
    set {domain_code.lower()}_paramcd;
    by USUBJID PARAMCD;
    retain BASE;
    if VISIT = "{baseline_visit}" then BASE = AVAL;
    if first.PARAMCD then if VISIT ne "{baseline_visit}" then BASE = .;
    CHG = AVAL - BASE;
    if BASE ne 0 and not missing(BASE) then PCHG = 100 * (CHG / BASE);
    else PCHG = .;
run;"""
    program += wrap(f"{domain_code}_BASELINE", baseline_code)

    windows = build_visit_windows()
    program += wrap("AWLO_AWHI", generate_awlo_awhi_sas(windows, domain=domain_code.lower()))

    anl01fl_code = """    /* Analysis flag: within visit window and non-missing AVAL */
    length ANL01FL $1;
    label ANL01FL = "Analysis Flag 01";
    if not missing(AVAL) and AWLO <= VISITNUM <= AWHI then ANL01FL = 'Y';
    else call missing(ANL01FL);"""
    program += wrap("ANL01FL", anl01fl_code)

    return program


# ---------------------------------------------------------------------------
# Events BDS domains (ADAE, ADCM)
# ---------------------------------------------------------------------------

def generate_events_domain(domain_code, sdtm_source, prefix, decod_var,
                           stdtc, endtc, emergent_flag="TRTEMFL"):
    """
    Generic Events-class BDS generator (ADAE, ADCM share this shape).

    domain_code:  e.g. "ADAE" / "ADCM"
    sdtm_source:  input SDTM dataset name, e.g. "ae" / "cm"
    prefix:       SDTM var prefix, e.g. "AE" / "CM"
    decod_var:    coded-term var for first-occurrence grouping, e.g. AEDECOD / CMDECOD
    stdtc/endtc:  SDTM ISO start/end date vars, e.g. AESTDTC/AEENDTC, CMSTDTC/CMENDTC
    emergent_flag: name of the on/after-first-dose flag (TRTEMFL for AE;
                   ONTRTFL is the more usual concept for CM, but kept
                   configurable — same derivation).

    No baseline, no reshape. Merge ADSL treatment dates, convert dates to
    numeric, flag records starting on/after first dose, flag first occurrence
    per subject per coded term.

    BACKLOG: emergent/on-treatment flag only checks ">= first dose"; stricter
    rules also bound by last dose + window.
    """
    ds = domain_code.lower()
    program = ""

    merge_code = f"""proc sort data={sdtm_source} out={ds}_src; by USUBJID; run;
proc sort data=adsl(keep=USUBJID TRTSDT TRTEDT) out={ds}_adsl; by USUBJID; run;

data {ds}_merged;
    merge {ds}_src(in=a) {ds}_adsl;
    by USUBJID;
    if a;  /* keep only {prefix} records */
run;"""
    program += wrap(f"{domain_code}_MERGE", merge_code)

    dates_code = f"""    /* {prefix} start/end as numeric analysis dates */
    length ASTDT AENDT 8;
    format ASTDT AENDT date9.;
    ASTDT = input(substr({stdtc},1,10), ?? E8601DA.);
    AENDT = input(substr({endtc},1,10), ?? E8601DA.);"""
    program += wrap("ASTDT_AENDT", dates_code)

    flag_code = f"""    /* On/after first dose */
    length {emergent_flag} $1;
    if not missing(ASTDT) and not missing(TRTSDT) and ASTDT >= TRTSDT
        then {emergent_flag} = 'Y';
    else call missing({emergent_flag});"""
    program += wrap(emergent_flag, flag_code)

    aoccfl_code = f"""proc sort data={ds}_merged;
    by USUBJID {decod_var} ASTDT;
run;

data {ds};
    set {ds}_merged;
    by USUBJID {decod_var};
    length AOCCFL $1;
    /* flag the first record per subject per coded term */
    if first.{decod_var} then AOCCFL = 'Y';
    else call missing(AOCCFL);
run;"""
    program += wrap("AOCCFL", aoccfl_code)

    return program


def generate_ae_domain(domain_code="ADAE"):
    """ADAE — Events class. Treatment-emergent flag = TRTEMFL."""
    return generate_events_domain(
        domain_code=domain_code, sdtm_source="ae", prefix="AE",
        decod_var="AEDECOD", stdtc="AESTDTC", endtc="AEENDTC",
        emergent_flag="TRTEMFL",
    )


def generate_cm_domain(domain_code="ADCM"):
    """ADCM — Events class. On-treatment flag = ONTRTFL."""
    return generate_events_domain(
        domain_code=domain_code, sdtm_source="cm", prefix="CM",
        decod_var="CMDECOD", stdtc="CMSTDTC", endtc="CMENDTC",
        emergent_flag="ONTRTFL",
    )



# ---------------------------------------------------------------------------
# Oncology ADaM domains (ADTR, ADRS, ADTTE)
# ---------------------------------------------------------------------------

def generate_rs_domain(domain_code="ADRS"):
    """
    ADRS — RECIST response analysis. Not baseline/change: it maps the RS
    overall-response records (CR/PR/SD/PD/NE) and derives best overall
    response (BOR) per subject by response ranking.

    Built from the RS SDTM domain, keeping only the overall-response records
    (RSTESTCD='OVRLRESP'). AVALC holds the response text; AVAL a numeric rank
    used to pick the best (lowest rank = best response).

    BACKLOG: full RECIST BOR rules require confirmation (a PR/CR must be
    confirmed at a later visit) and handle SD-minimum-duration and PD timing.
    This is the simplified un-confirmed best response.
    """
    ds = domain_code.lower()
    program = ""

    # Keep only overall-response rows, assign numeric rank for "best"
    paramcd_code = f"""data {ds}_ovr;
    set rs;
    where RSTESTCD = "OVRLRESP";
    length PARAMCD $8 PARAM $40 AVALC $20;
    PARAMCD = "OVRLRESP";
    PARAM = "Overall Response";
    AVALC = strip(RSORRES);
    /* response ranking: lower = better (CR best) */
    select (upcase(AVALC));
        when ("CR") AVAL = 1;
        when ("PR") AVAL = 2;
        when ("SD") AVAL = 3;
        when ("PD") AVAL = 4;
        when ("NE") AVAL = 5;
        otherwise AVAL = .;
    end;
run;"""
    program += wrap(f"{domain_code}_PARAMCD", paramcd_code)

    # Best overall response per subject = the minimum rank across visits
    bor_code = f"""proc sort data={ds}_ovr;
    by USUBJID AVAL;
run;

data {ds};
    set {ds}_ovr;
    by USUBJID;
    length ANL01FL $1;
    /* flag the best (lowest-rank) response record per subject */
    if first.USUBJID then ANL01FL = 'Y';
    else call missing(ANL01FL);
run;"""
    program += wrap("ANL01FL_BOR", bor_code)

    return program


def generate_tte_domain(domain_code="ADTTE"):
    """
    ADTTE — time-to-event (PFS, OS). Entirely different structure: one row
    per subject per endpoint (PARAMCD), with:
      AVAL  — time in days from treatment start to event or censor
      CNSR  — censoring flag (0 = event occurred, 1 = censored)
      STARTDT — origin date (TRTSDT from ADSL)
      ADT   — event or censor date

    PFS event = progression (RS PD) or death; censored at last assessment.
    OS event  = death; censored at last known alive.

    This generator emits a template with both PARAMCD blocks. The actual
    event/censor date sourcing depends on study data (death date from DM/DS,
    progression from ADRS), so those are marked with clear derivation stubs.

    BACKLOG: wire real event dates — death from DS/DM (DSDECOD='DEATH' or
    DTHDTC), progression from ADRS first PD visit; last-assessment date for
    censoring from ADRS/ADTR max ADT.
    """
    ds = domain_code.lower()
    program = ""

    setup_code = f"""proc sort data=adsl(keep=USUBJID TRTSDT) out={ds}_adsl; by USUBJID; run;

data {ds};
    set {ds}_adsl;
    length PARAMCD $8 PARAM $40 CNSR 8 AVAL 8 STARTDT ADT 8;
    format STARTDT ADT date9.;
    STARTDT = TRTSDT;
"""
    program += wrap(f"{domain_code}_SETUP", setup_code)

    pfs_code = """    /* --- PFS: progression-free survival --- */
    PARAMCD = "PFS";
    PARAM = "Progression-Free Survival (days)";
    /* TODO: set ADT = earliest of (progression date from ADRS PD),
       (death date from DS/DM); CNSR=0 if event, else ADT = last
       assessment date and CNSR=1 */
    if not missing(ADT) and not missing(STARTDT) then AVAL = ADT - STARTDT + 1;
    output;"""
    program += wrap("PFS", pfs_code)

    os_code = """    /* --- OS: overall survival --- */
    PARAMCD = "OS";
    PARAM = "Overall Survival (days)";
    /* TODO: set ADT = death date (CNSR=0) or last-known-alive date (CNSR=1) */
    if not missing(ADT) and not missing(STARTDT) then AVAL = ADT - STARTDT + 1;
    output;
run;"""
    program += wrap("OS", os_code)

    return program


# ---------------------------------------------------------------------------
# Build all BDS programs and write them to files
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    out_dir = "adam_programs"
    os.makedirs(out_dir, exist_ok=True)

    acrf = pd.read_excel("acrf_metadata.xlsx", sheet_name="By Domain")

    programs = {}

    # --- Findings ---
    vs_params = build_param_spec_from_acrf(acrf, "VS", "VSTESTCD")
    programs["advs"] = generate_bds_domain("vs", vs_params, "ADVS")

    lb_params = build_param_spec_from_acrf(acrf, "LB", "LBTESTCD")
    programs["adlb"] = generate_bds_domain("lb", lb_params, "ADLB")

    eg_params = build_param_spec_from_acrf(acrf, "EG", "EGTESTCD")
    programs["adeg"] = generate_bds_domain("eg", eg_params, "ADEG")

    # --- Events ---
    programs["adae"] = generate_ae_domain("ADAE")
    programs["adcm"] = generate_cm_domain("ADCM")

    # --- Oncology ---
    tr_params = build_param_spec_from_acrf(acrf, "TR", "TRTESTCD")
    programs["adtr"] = generate_bds_domain("tr", tr_params, "ADTR")
    programs["adrs"] = generate_rs_domain("ADRS")
    programs["adtte"] = generate_tte_domain("ADTTE")

    for name, code in programs.items():
        path = os.path.join(out_dir, f"{name}.sas")
        with open(path, "w", encoding="utf-8") as f:
            f.write(code)
        print(f"Wrote {path}")
