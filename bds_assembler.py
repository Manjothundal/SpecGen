from visit_windows import build_visit_windows, generate_awlo_awhi_sas
"""
bds_assembler.py — ADaM BDS domains (ADVS, ADLB, ADAE, ADCM, ADEFF)

Same long-format problem as SDTM Findings (sdtm_assembler.py), one level up:
ADaM BDS is one row per subject per PARAMCD per visit, built FROM the SDTM
Findings dataset (e.g. ADVS is built from VS), with derived analysis columns
that don't exist yet at the SDTM level:

    AVAL    — analysis value (numeric, standardized units)
    BASE    — baseline value for this PARAMCD (from the baseline visit)
    CHG     — AVAL - BASE (change from baseline)
    PCHG    — 100 * CHG / BASE (percent change from baseline)
    ANL01FL — analysis flag (e.g. "Y" for the record used in the primary analysis)

Reuses the same PARAMCD/PARAM reshape idea as VSTESTCD/VSTEST, then adds a
second BY-group pass for BASE/CHG/PCHG that SDTM never needed, since SDTM
findings domains don't carry a baseline concept at all.
"""

import pandas as pd

BEGIN = "/*-- BEGIN {var} --*/"
END = "/*-- END {var} --*/"


def wrap(var, code):
    return f"{BEGIN.format(var=var)}\n{code}\n{END.format(var=var)}\n"


def build_param_spec_from_acrf(acrf_df: pd.DataFrame, sdtm_domain_code: str, source_testcd_var: str) -> list:
    """
    Auto-derives the PARAMCD/PARAM mapping straight from acrf_metadata.xlsx,
    instead of requiring a hand-authored ADaM BDS spec.

    For straightforward BDS domains (ADVS from VS, ADLB from LB), PARAMCD is
    a 1:1 carry-forward of the SDTM --TESTCD — no separate ADaM-side mapping
    decision needed. The same Qualifier rows ("VSTESTCD=SYSBP") that drove
    the SDTM reshape in sdtm_assembler.py double as the PARAMCD source.

    ASSUMPTION (flagged): this 1:1 carry-forward covers simple cases only.
    Domains where PARAMCD deviates from TESTCD (derived/composite params,
    unit-converted params, or params that don't exist at the SDTM level at
    all — e.g. a calculated BMI param) need a manual override layer on top
    of this. Not built yet — backlog until a real case surfaces.
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


def generate_bds_domain(sdtm_source_df_name: str, param_spec_rows: list, domain_code: str,
                         baseline_visit: str = "BASELINE") -> str:
    """
    sdtm_source_df_name: the SDTM findings dataset this BDS domain is built
                          from, e.g. "vs" for ADVS. Assumed already in long
                          form (one row per subject/visit/--TESTCD) from
                          Phase 5c's sdtm_assembler.py output.
    param_spec_rows:     list of dicts, each {paramcd, param, source_testcd}
                          mapping an ADaM PARAMCD to the SDTM --TESTCD it's
                          derived from. This mapping is 1:1 for simple cases
                          (PARAMCD=SYSBP <- VSTESTCD=SYSBP) but may need
                          unit conversion or aggregation for others (backlog).
    domain_code:         e.g. "ADVS"
    baseline_visit:      which VISIT value counts as baseline for BASE calc;
                          study-specific, defaults to a placeholder.

    Returns SAS wrapped in BEGIN/END markers, same convention as ADSL and
    SDTM assemblers, so spec_differ.py / spec_patcher.py work unchanged.
    """
    # --- Pass 1: PARAMCD/PARAM assignment, mapped from the SDTM --TESTCD ---
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

    # --- Pass 2: BASE/CHG/PCHG, one BY-group per subject*PARAMCD ---
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

    # --- Analysis flag stub — ANL01FL logic is study/endpoint-specific,
    #     routed to the Writer/Improver/Reviewer pipeline like ADSL vars ---
    anl01fl_code = """    /* Analysis flag: within visit window and non-missing AVAL */
    length ANL01FL $1;
    label ANL01FL = "Analysis Flag 01";
    if not missing(AVAL) and AWLO <= VISITNUM <= AWHI then ANL01FL = 'Y';
    else call missing(ANL01FL);"""
    program += wrap("ANL01FL", anl01fl_code)

    return program


if __name__ == "__main__":
    acrf = pd.read_excel("acrf_metadata.xlsx", sheet_name="By Domain")

    # ADVS
    vs_params = build_param_spec_from_acrf(acrf, sdtm_domain_code="VS", source_testcd_var="VSTESTCD")
    print(generate_bds_domain("vs", vs_params, "ADVS"))

    # ADLB
    lb_params = build_param_spec_from_acrf(acrf, sdtm_domain_code="LB", source_testcd_var="LBTESTCD")
    print(generate_bds_domain("lb", lb_params, "ADLB"))
