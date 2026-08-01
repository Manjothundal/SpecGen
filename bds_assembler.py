"""
bds_assembler.py — ADaM analysis datasets (SAS or R)

Two code paths by dataset class:

  Findings (ADVS, ADLB, ADEG, ADTR) — one row per subject per PARAMCD per
    visit, built from an SDTM findings domain. PARAMCD/PARAM reshape, baseline
    pass (BASE/CHG/PCHG), visit windows (AWLO/AWHI), analysis flag (ANL01FL).
    See generate_bds_domain() — dispatches SAS or R on config.LANGUAGE.

  Events (ADAE, ADCM) — one row per event/record (no baseline, no reshape).
    Merge ADSL treatment dates, convert dates to numeric, derive emergent /
    on-treatment and first-occurrence flags. (SAS only so far.)

  Oncology (ADRS, ADTTE) — RECIST response and time-to-event. (SAS only.)

Language: config.LANGUAGE ("sas" or "r") selects output for the Findings
generator, matching the ADSL assembler's toggle. Events/Oncology are SAS-only
for now (next to be ported). __main__ writes .sas or .R accordingly.

Every derived variable is wrapped in BEGIN/END markers so spec_differ.py /
spec_patcher.py work unchanged. Output: one file per dataset into adam_programs/.
"""

import os
import pandas as pd
import config

from visit_windows import build_visit_windows, generate_awlo_awhi_sas

BEGIN = "/*-- BEGIN {var} --*/"
END = "/*-- END {var} --*/"


def wrap(var, code):
    return f"{BEGIN.format(var=var)}\n{code}\n{END.format(var=var)}\n"


# ---------------------------------------------------------------------------
# Findings BDS domains (ADVS, ADLB, ADEG, ADTR)
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


def generate_bds_domain(sdtm_source_df_name, param_spec_rows, domain_code,
                        baseline_visit="BASELINE", language=None):
    """
    Findings BDS generator — dispatches SAS or R on config.LANGUAGE (or the
    explicit language arg). domain_code e.g. "ADVS"; the SDTM --STRESN column
    it reads is derived from the domain code (ADVS -> VSSTRESN).
    """
    language = (language or config.LANGUAGE).lower()
    if language == "sas":
        return _generate_bds_domain_sas(sdtm_source_df_name, param_spec_rows,
                                        domain_code, baseline_visit)
    elif language == "r":
        return _generate_bds_domain_r(sdtm_source_df_name, param_spec_rows,
                                      domain_code, baseline_visit)
    else:
        raise ValueError(f"Unknown language: {language!r} (expected 'sas' or 'r')")


# ---- SAS findings path (unchanged) ----

def _generate_bds_domain_sas(sdtm_source_df_name, param_spec_rows, domain_code, baseline_visit="BASELINE"):
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


# ---- R findings path (plain tidyverse; baseline via join, NA guarded) ----

def _generate_bds_domain_r(sdtm_source_df_name, param_spec_rows, domain_code, baseline_visit="BASELINE"):
    stresn = f"{domain_code[2:]}STRESN"                 # ADVS -> VSSTRESN
    testcd = param_spec_rows[0]["source_testcd_var"]    # e.g. VSTESTCD
    ds = domain_code.lower()

    when_arms = "\n".join(
        f'      {testcd} == "{p["source_testcd"]}" ~ "{p["paramcd"]}",'
        for p in param_spec_rows
    )
    param_arms = "\n".join(
        f'      {testcd} == "{p["source_testcd"]}" ~ "{p["param"]}",'
        for p in param_spec_rows
    )

    lines = []
    lines.append("# ********************************")
    lines.append(f"# Program: {ds}.R")
    lines.append("# Generated by SpecGen (target = r)")
    lines.append(f"# Findings ADaM: {domain_code} from SDTM {sdtm_source_df_name}")
    lines.append("# ********************************")
    lines.append("library(dplyr)")
    lines.append("")
    lines.append(f"# -- BEGIN {domain_code}_PARAMCD -- #")
    lines.append(f"{ds}_paramcd <- {sdtm_source_df_name} |>")
    lines.append("  mutate(")
    lines.append("    PARAMCD = case_when(")
    lines.append(when_arms)
    lines.append("      TRUE ~ NA_character_")
    lines.append("    ),")
    lines.append("    PARAM = case_when(")
    lines.append(param_arms)
    lines.append("      TRUE ~ NA_character_")
    lines.append("    ),")
    lines.append(f"    AVAL = {stresn}  # standardized numeric result")
    lines.append("  )")
    lines.append(f"# -- END {domain_code}_PARAMCD -- #")
    lines.append("")
    lines.append(f"# -- BEGIN {domain_code}_BASELINE -- #")
    lines.append(f"{ds}_baseline <- {ds}_paramcd |>")
    lines.append(f'  filter(VISIT == "{baseline_visit}") |>')
    lines.append("  group_by(USUBJID, PARAMCD) |>")
    lines.append('  summarise(BASE = dplyr::first(AVAL), .groups = "drop")')
    lines.append("")
    lines.append(f"{ds}_base <- {ds}_paramcd |>")
    lines.append(f'  left_join({ds}_baseline, by = c("USUBJID", "PARAMCD")) |>')
    lines.append("  mutate(")
    lines.append("    CHG  = AVAL - BASE,")
    lines.append("    PCHG = if_else(!is.na(BASE) & BASE != 0, 100 * (CHG / BASE), NA_real_)")
    lines.append("  )")
    lines.append(f"# -- END {domain_code}_BASELINE -- #")
    lines.append("")
    lines.append(_awlo_awhi_r(build_visit_windows(), domain=ds))
    lines.append("")
    lines.append(_anl01fl_r(domain=ds))
    lines.append("")

    return "\n".join(lines)


def _awlo_awhi_r(windows, domain="advs"):
    ds = domain
    arms_lo = "\n".join(f'      VISITNUM == {w["visitnum"]} ~ {w["awlo"]},' for w in windows)
    arms_hi = "\n".join(f'      VISITNUM == {w["visitnum"]} ~ {w["awhi"]},' for w in windows)
    return "\n".join([
        "# -- BEGIN AWLO_AWHI -- #",
        f"{ds}_windows <- {ds}_base |>",
        "  mutate(",
        "    AWLO = case_when(",
        arms_lo,
        "      TRUE ~ NA_real_",
        "    ),",
        "    AWHI = case_when(",
        arms_hi,
        "      TRUE ~ NA_real_",
        "    )",
        "  )",
        "# -- END AWLO_AWHI -- #",
    ])


def _anl01fl_r(domain="advs"):
    ds = domain
    return "\n".join([
        "# -- BEGIN ANL01FL -- #",
        f"{ds} <- {ds}_windows |>",
        "  mutate(",
        "    # Analysis flag: within visit window and non-missing AVAL",
        "    ANL01FL = if_else(",
        "      !is.na(AVAL) & !is.na(AWLO) & !is.na(AWHI) &",
        "        VISITNUM >= AWLO & VISITNUM <= AWHI,",
        '      "Y", NA_character_',
        "    )",
        "  )",
        "# -- END ANL01FL -- #",
    ])


# ---------------------------------------------------------------------------
# Events BDS domains (ADAE, ADCM) — SAS only for now
# ---------------------------------------------------------------------------

def generate_events_domain(domain_code, sdtm_source, prefix, decod_var,
                           stdtc, endtc, emergent_flag="TRTEMFL"):
    """
    Generic Events-class BDS generator (ADAE, ADCM share this shape).
    No baseline, no reshape. Merge ADSL treatment dates, convert dates to
    numeric, flag records starting on/after first dose, flag first occurrence
    per subject per coded term.

    BACKLOG: emergent/on-treatment flag only checks ">= first dose"; stricter
    rules also bound by last dose + window. Not yet ported to R.
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


def generate_events_domain_r(domain_code, sdtm_source, prefix, decod_var,
                             stdtc, endtc, emergent_flag="TRTEMFL"):
    """
    R/tidyverse version of the Events-class generator (ADAE, ADCM).
    SAS sort + first.<decod> becomes group_by + row_number()==1; every flag
    is NA-guarded (R comparisons with NA yield NA, not FALSE).
    """
    ds = domain_code.lower()
    lines = []
    lines.append("# ********************************")
    lines.append(f"# Program: {ds}.R")
    lines.append("# Generated by SpecGen (target = r)")
    lines.append(f"# Events ADaM: {domain_code} from SDTM {sdtm_source}")
    lines.append("# ********************************")
    lines.append("library(dplyr)")
    lines.append("")
    lines.append(f"# -- BEGIN {domain_code}_MERGE -- #")
    lines.append(f"{ds}_adsl <- adsl |> select(USUBJID, TRTSDT, TRTEDT)")
    lines.append("")
    lines.append(f"{ds}_merged <- {sdtm_source} |>")
    lines.append(f'  left_join({ds}_adsl, by = "USUBJID")')
    lines.append(f"# -- END {domain_code}_MERGE -- #")
    lines.append("")
    lines.append("# -- BEGIN ASTDT_AENDT -- #")
    lines.append(f"{ds}_dates <- {ds}_merged |>")
    lines.append("  mutate(")
    lines.append(f"    ASTDT = as.Date(substr({stdtc}, 1, 10)),")
    lines.append(f"    AENDT = as.Date(substr({endtc}, 1, 10))")
    lines.append("  )")
    lines.append("# -- END ASTDT_AENDT -- #")
    lines.append("")
    lines.append(f"# -- BEGIN {emergent_flag} -- #")
    lines.append(f"{ds}_flag <- {ds}_dates |>")
    lines.append("  mutate(")
    lines.append("    # On/after first dose")
    lines.append(f"    {emergent_flag} = if_else(")
    lines.append("      !is.na(ASTDT) & !is.na(TRTSDT) & ASTDT >= TRTSDT,")
    lines.append('      "Y", NA_character_')
    lines.append("    )")
    lines.append("  )")
    lines.append(f"# -- END {emergent_flag} -- #")
    lines.append("")
    lines.append("# -- BEGIN AOCCFL -- #")
    lines.append(f"{ds} <- {ds}_flag |>")
    lines.append(f"  group_by(USUBJID, {decod_var}) |>")
    lines.append("  arrange(ASTDT, .by_group = TRUE) |>")
    lines.append("  mutate(")
    lines.append("    # flag the first record per subject per coded term")
    lines.append('    AOCCFL = if_else(row_number() == 1, "Y", NA_character_)')
    lines.append("  ) |>")
    lines.append("  ungroup()")
    lines.append("# -- END AOCCFL -- #")
    lines.append("")
    return "\n".join(lines)


def generate_ae_domain(domain_code="ADAE", language=None):
    """ADAE — Events class. Treatment-emergent flag = TRTEMFL. SAS or R."""
    language = (language or config.LANGUAGE).lower()
    fn = generate_events_domain_r if language == "r" else generate_events_domain
    return fn(
        domain_code=domain_code, sdtm_source="ae", prefix="AE",
        decod_var="AEDECOD", stdtc="AESTDTC", endtc="AEENDTC",
        emergent_flag="TRTEMFL",
    )


def generate_cm_domain(domain_code="ADCM", language=None):
    """ADCM — Events class. On-treatment flag = ONTRTFL. SAS or R."""
    language = (language or config.LANGUAGE).lower()
    fn = generate_events_domain_r if language == "r" else generate_events_domain
    return fn(
        domain_code=domain_code, sdtm_source="cm", prefix="CM",
        decod_var="CMDECOD", stdtc="CMSTDTC", endtc="CMENDTC",
        emergent_flag="ONTRTFL",
    )


# ---------------------------------------------------------------------------
# Oncology ADaM domains (ADRS, ADTTE) — SAS only for now
# ---------------------------------------------------------------------------

def generate_rs_domain_r(domain_code="ADRS"):
    """R/tidyverse ADRS. filter overall-response rows, rank via case_when,
    best response per subject via slice_min(AVAL). NA-guarded."""
    ds = domain_code.lower()
    lines = []
    lines.append("# ********************************")
    lines.append(f"# Program: {ds}.R")
    lines.append("# Generated by SpecGen (target = r)")
    lines.append(f"# Oncology ADaM: {domain_code} (RECIST overall response) from SDTM rs")
    lines.append("# ********************************")
    lines.append("library(dplyr)")
    lines.append("")
    lines.append(f"# -- BEGIN {domain_code}_PARAMCD -- #")
    lines.append(f"{ds}_ovr <- rs |>")
    lines.append('  filter(RSTESTCD == "OVRLRESP") |>')
    lines.append("  mutate(")
    lines.append('    PARAMCD = "OVRLRESP",')
    lines.append('    PARAM   = "Overall Response",')
    lines.append("    AVALC   = trimws(RSORRES),")
    lines.append("    # response ranking: lower = better (CR best)")
    lines.append("    AVAL = case_when(")
    lines.append('      toupper(AVALC) == "CR" ~ 1,')
    lines.append('      toupper(AVALC) == "PR" ~ 2,')
    lines.append('      toupper(AVALC) == "SD" ~ 3,')
    lines.append('      toupper(AVALC) == "PD" ~ 4,')
    lines.append('      toupper(AVALC) == "NE" ~ 5,')
    lines.append("      TRUE ~ NA_real_")
    lines.append("    )")
    lines.append("  )")
    lines.append(f"# -- END {domain_code}_PARAMCD -- #")
    lines.append("")
    lines.append("# -- BEGIN ANL01FL_BOR -- #")
    lines.append(f"{ds} <- {ds}_ovr |>")
    lines.append("  group_by(USUBJID) |>")
    lines.append("  arrange(AVAL, .by_group = TRUE) |>")
    lines.append("  mutate(")
    lines.append("    # flag the best (lowest-rank) response record per subject")
    lines.append('    ANL01FL = if_else(row_number() == 1, "Y", NA_character_)')
    lines.append("  ) |>")
    lines.append("  ungroup()")
    lines.append("# -- END ANL01FL_BOR -- #")
    lines.append("")
    return "\n".join(lines)


def generate_rs_domain(domain_code="ADRS"):
    """
    ADRS — RECIST response analysis. Maps RS overall-response records
    (CR/PR/SD/PD/NE), derives best overall response by ranking (lower = better).
    BACKLOG: real RECIST BOR needs confirmation at a later visit + SD-min-
    duration + PD timing. This is simplified un-confirmed best response.
    """
    ds = domain_code.lower()
    program = ""

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


def generate_tte_domain_r(domain_code="ADTTE"):
    """R/tidyverse ADTTE. One row per subject per endpoint via bind_rows of
    two per-endpoint frames. Event/censor dates STUBBED (same TODO as SAS)."""
    ds = domain_code.lower()
    lines = []
    lines.append("# ********************************")
    lines.append(f"# Program: {ds}.R")
    lines.append("# Generated by SpecGen (target = r)")
    lines.append(f"# Oncology ADaM: {domain_code} (time-to-event PFS/OS) from ADSL")
    lines.append("# ********************************")
    lines.append("library(dplyr)")
    lines.append("")
    lines.append(f"# -- BEGIN {domain_code}_SETUP -- #")
    lines.append(f"{ds}_base <- adsl |>")
    lines.append("  select(USUBJID, TRTSDT) |>")
    lines.append("  mutate(STARTDT = TRTSDT)")
    lines.append(f"# -- END {domain_code}_SETUP -- #")
    lines.append("")
    lines.append("# -- BEGIN PFS -- #")
    lines.append(f"{ds}_pfs <- {ds}_base |>")
    lines.append("  mutate(")
    lines.append('    PARAMCD = "PFS",')
    lines.append('    PARAM   = "Progression-Free Survival (days)",')
    lines.append("    # TODO: set ADT = earliest of (progression date from ADRS PD),")
    lines.append("    #       (death date from DS/DM); CNSR=0 if event, else ADT =")
    lines.append("    #       last assessment date and CNSR=1")
    lines.append("    ADT  = as.Date(NA),")
    lines.append("    CNSR = NA_real_,")
    lines.append("    AVAL = if_else(!is.na(ADT) & !is.na(STARTDT),")
    lines.append("                   as.numeric(ADT - STARTDT) + 1, NA_real_)")
    lines.append("  )")
    lines.append("# -- END PFS -- #")
    lines.append("")
    lines.append("# -- BEGIN OS -- #")
    lines.append(f"{ds}_os <- {ds}_base |>")
    lines.append("  mutate(")
    lines.append('    PARAMCD = "OS",')
    lines.append('    PARAM   = "Overall Survival (days)",')
    lines.append("    # TODO: set ADT = death date (CNSR=0) or last-known-alive (CNSR=1)")
    lines.append("    ADT  = as.Date(NA),")
    lines.append("    CNSR = NA_real_,")
    lines.append("    AVAL = if_else(!is.na(ADT) & !is.na(STARTDT),")
    lines.append("                   as.numeric(ADT - STARTDT) + 1, NA_real_)")
    lines.append("  )")
    lines.append("")
    lines.append(f"{ds} <- bind_rows({ds}_pfs, {ds}_os)")
    lines.append("# -- END OS -- #")
    lines.append("")
    return "\n".join(lines)


def generate_tte_domain(domain_code="ADTTE"):
    """
    ADTTE — time-to-event (PFS, OS). One row per subject per endpoint, with
    AVAL (days), CNSR (0=event,1=censored), STARTDT (TRTSDT), ADT (event/censor).
    BACKLOG: event/censor dates STUBBED — wire death (DS/DM), progression
    (ADRS first PD), last-assessment date for censoring.
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
# Build all BDS programs and write them to files (.sas or .R per config)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Generate ADaM programs (SAS or R).")
    parser.add_argument("--lang", choices=["sas", "r"], default=None,
                        help="Output language. Overrides config.LANGUAGE. "
                             "Omit to use config.LANGUAGE.")
    args = parser.parse_args()

    out_dir = "adam_programs"
    os.makedirs(out_dir, exist_ok=True)

    lang = (args.lang or config.LANGUAGE).lower()
    ext = "R" if lang == "r" else "sas"
    print(f"Language: {lang}")

    acrf = pd.read_excel("acrf_metadata.xlsx", sheet_name="By Domain")

    programs = {}

    # --- Findings (SAS or R via config.LANGUAGE) ---
    vs_params = build_param_spec_from_acrf(acrf, "VS", "VSTESTCD")
    programs["advs"] = generate_bds_domain("vs", vs_params, "ADVS", language=lang)

    lb_params = build_param_spec_from_acrf(acrf, "LB", "LBTESTCD")
    programs["adlb"] = generate_bds_domain("lb", lb_params, "ADLB", language=lang)

    eg_params = build_param_spec_from_acrf(acrf, "EG", "EGTESTCD")
    programs["adeg"] = generate_bds_domain("eg", eg_params, "ADEG", language=lang)

    tr_params = build_param_spec_from_acrf(acrf, "TR", "TRTESTCD")
    programs["adtr"] = generate_bds_domain("tr", tr_params, "ADTR", language=lang)

    # --- Events (SAS or R) ---
    programs["adae"] = generate_ae_domain("ADAE", language=lang)
    programs["adcm"] = generate_cm_domain("ADCM", language=lang)

    # --- Oncology (SAS or R) ---
    if lang == "r":
        programs["adrs"] = generate_rs_domain_r("ADRS")
        programs["adtte"] = generate_tte_domain_r("ADTTE")
    else:
        programs["adrs"] = generate_rs_domain("ADRS")
        programs["adtte"] = generate_tte_domain("ADTTE")

    for name, code in programs.items():
        path = os.path.join(out_dir, f"{name}.{ext}")
        with open(path, "w", encoding="utf-8") as f:
            f.write(code)
        print(f"Wrote {path}")
