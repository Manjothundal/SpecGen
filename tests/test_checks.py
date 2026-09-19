"""Piece B tests: the twelve deterministic checks in review.checks.

Every check has a pass fixture (no findings) and a fail fixture. A fail
fixture must fail for the INTENDED reason, so each one is pinned to the exact
counts in its evidence string; a missing or misspelled variable must raise
CheckInputError, never produce a finding.

Run from the repo root:  python -m pytest tests/test_checks.py -v
Print the evidence of every failing fixture:  python -m tests.test_checks
"""

import os

import pandas as pd
import pytest

from review import checks
from review.checks import CHECKS, CheckInputError
from review.dataset_reader import read_datasets
from review.output_reader import read_outputs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------------------
# Small builders (synthetic frames - no real study data)
# ---------------------------------------------------------------------------

def make_rule(check, params=None, severity="major", sap_ref="SAP 1.1", rule_id="R-001"):
    return {"rule_id": rule_id, "scope": "cross", "topic": check, "description": "test rule",
            "sap_ref": sap_ref, "severity": severity, "check": check, "params": params or {},
            "status": "approved", "owner": "Biostatistics", "version": 1,
            "created_by": "test", "created_at": "2026-09-19T10:00:00"}


def make_table(table_id, headers, rows, subtitle="Safety Population", kind="table"):
    return {"table_id": table_id, "kind": kind, "title": f"Table {table_id} Test Title",
            "subtitle": subtitle, "footnotes": [], "column_headers": headers, "rows": rows,
            "page": 1, "source_file": f"t_{table_id.replace('.', '_')}.rtf"}


DAY0 = pd.Timestamp("2023-01-10")


def day(offset):
    return DAY0 + pd.Timedelta(days=offset)


def make_adsl():
    """9 subjects. ITT: Placebo 5, Drug A 4 (total 9). Safety: Placebo 4, Drug A 4
    (total 8) - S9 is randomised but never dosed. Dosed subjects: first dose day 0,
    last dose day 30."""
    rows = []
    for i in (1, 2, 3, 4):
        rows.append((f"S{i}", "Placebo", "Placebo", "Y", "Y", day(0), day(30)))
    rows.append(("S9", "Placebo", "", "Y", "N", pd.NaT, pd.NaT))
    for i in (5, 6, 7, 8):
        rows.append((f"S{i}", "Drug A", "Drug A", "Y", "Y", day(0), day(30)))
    return pd.DataFrame(rows, columns=["USUBJID", "TRT01P", "TRT01A", "ITTFL", "SAFFL", "TRTSDT", "TRTEDT"])


def adsl_only():
    return {"ADSL": make_adsl()}


def make_adae(extra=()):
    """(subject, start offset in days from first dose, TRTEMFL). Window end = day 37."""
    base = [("S1", 5, "Y"), ("S2", 10, "Y"), ("S3", 36, "Y"), ("S4", -3, "N"), ("S5", 38, "N"), ("S6", 20, "Y")]
    recs = base + list(extra)
    return pd.DataFrame([(u, day(o), f) for u, o, f in recs], columns=["USUBJID", "ASTDT", "TRTEMFL"])


HDR3 = ["Category", "Placebo (N=20)", "Drug A (N=25)"]


# ---------------------------------------------------------------------------
# One runner per check: run_<check>(fail) -> findings. fail=False is the pass fixture.
# ---------------------------------------------------------------------------

def run_check_bign(fail):
    placebo = "Placebo (N=5)" if fail else "Placebo (N=4)"
    out = make_table("14.1.1", ["Parameter", placebo, "Drug A (N=4)", "Total (N=8)"], [["n", "4", "4", "8"]])
    return CHECKS["check_bign"](adsl_only(), [out], make_rule("check_bign"), {})


def run_check_population_filter(fail):
    subtitle = "Intent-to-Treat Population" if fail else "Safety Population"
    out = make_table("14.3.1", ["Category", "Placebo (N=4)", "Drug A (N=4)", "Total (N=8)"],
                     [["Any TEAE", "3", "3", "6"]], subtitle=subtitle)
    rule = make_rule("check_population_filter", {"table_populations": {"14.3.1": "safety"}})
    return CHECKS["check_population_filter"](adsl_only(), [out], rule, {})


def advs_frame(partial):
    rows = []
    for i in range(1, 7):
        for period in (1, 2):
            has_flag = not (partial and i >= 4 and period == 2)
            rows.append((f"S{i}", "SYSBP", period, "Y" if has_flag else "", 120.0))
            rows.append((f"S{i}", "SYSBP", period, "", 125.0))
    rows.append(("S7", "SYSBP", 1, "Y", 118.0))          # one period only - never counted
    return pd.DataFrame(rows, columns=["USUBJID", "PARAMCD", "APERIOD", "ABLFL", "AVAL"])


def run_check_baseline_per_period(fail):
    rule = make_rule("check_baseline_per_period", {"dataset": "ADVS"})
    return CHECKS["check_baseline_per_period"]({"ADVS": advs_frame(fail)}, [], rule, {})


def run_check_teae_window(fail):
    extra = [("S7", 45, "Y"), ("S8", 50, "Y")] if fail else []
    rule = make_rule("check_teae_window", {"window_days": 7})
    return CHECKS["check_teae_window"]({"ADSL": make_adsl(), "ADAE": make_adae(extra)}, [], rule, {})


def run_check_percentages(fail):
    any_teae = "15 (80.0%)" if fail else "15 (75.0%)"
    out = make_table("14.3.1", HDR3, [["Any TEAE", any_teae, "10 (40.0%)"],
                                     ["Any serious TEAE", "2 (10.0%)", "1 (4.0%)"]])
    return CHECKS["check_percentages"]({}, [out], make_rule("check_percentages"), {})


def run_check_totals(fail):
    male_total = "24 (53.3%)" if fail else "23 (51.1%)"
    out = make_table("14.1.1", ["Parameter", "Placebo (N=20)", "Drug A (N=25)", "Total (N=45)"],
                     [["Age (years)", "", "", ""], ["n", "20", "25", "45"],
                      ["Male", "11 (55.0%)", "12 (48.0%)", male_total],
                      ["Mean (SD)", "5.1 (1.2)", "6.0 (1.1)", "5.6 (1.2)"]])
    return CHECKS["check_totals"]({}, [out], make_rule("check_totals"), {})


def soc_ae_frame():
    rows = [("Nervous system disorders", "Headache"), ("Nervous system disorders", "Dizziness"),
            ("Gastrointestinal disorders", "Nausea")]
    return pd.DataFrame(rows, columns=["AEBODSYS", "AEDECOD"])


def run_check_soc_pt(fail):
    nervous_placebo = "4 (20.0%)" if fail else "7 (35.0%)"
    out = make_table("14.3.2", ["SOC / PT", "Placebo (N=20)", "Drug A (N=25)"], [
        ["Any TEAE", "12 (60.0%)", "15 (60.0%)"],
        ["Nervous system disorders", nervous_placebo, "9 (36.0%)"],
        ["Headache", "5 (25.0%)", "6 (24.0%)"],
        ["Dizziness", "4 (20.0%)", "5 (20.0%)"],
        ["Gastrointestinal disorders", "4 (20.0%)", "6 (24.0%)"],
        ["Nausea", "4 (20.0%)", "6 (24.0%)"]])
    return CHECKS["check_soc_pt"]({"ADAE": soc_ae_frame()}, [out], make_rule("check_soc_pt"), {})


PC_CTX = {"profiles": {"ADPC": {"variables": [{"name": "AVAL", "label": "Concentration per kg"}]}}}


def adpc_frame(normalised):
    src = [100.0, 120.0, 140.0, 160.0, 200.0]
    weight = [50.0, 60.0, 70.0, 80.0, 100.0]
    aval = [s / w for s, w in zip(src, weight)]                   # all 2.0
    if not normalised:
        aval[2:] = src[2:]                                        # last 3 left at the raw value
    return pd.DataFrame({"USUBJID": [f"S{i}" for i in range(5)], "PCSTRESN": src,
                         "WEIGHT": weight, "AVAL": aval})


def run_check_label_units(fail):
    rule = make_rule("check_label_units", {"dataset": "ADPC", "value_var": "AVAL", "source_var": "PCSTRESN"})
    return CHECKS["check_label_units"]({"ADPC": adpc_frame(not fail)}, [], rule, PC_CTX)


WINDOWS = {"Baseline": [None, 1], "Week 4": [22, 35], "Week 8": [50, 63]}


def advs_windows_frame(week4_lo=22.0, week4_days=(29, 29, 29, 29)):
    rows = [("Baseline", None, 1.0, 1.0)] * 4
    rows += [("Week 4", lo, 35.0, d) for lo, d in zip([week4_lo, week4_lo, 22.0, 22.0], week4_days)]
    rows += [("Week 8", 50.0, 63.0, 57.0)] * 2
    return pd.DataFrame(rows, columns=["AVISIT", "AWLO", "AWHI", "ADY"])


def run_check_visit_windows(fail):
    rule = make_rule("check_visit_windows", {"dataset": "ADVS", "windows": WINDOWS, "day_var": "ADY"})
    frame = advs_windows_frame(week4_lo=21.0 if fail else 22.0)
    return CHECKS["check_visit_windows"]({"ADVS": frame}, [], rule, {})


SAP_TABLES = [{"id": "14.1.1", "title": "Demographics"}, "14.3.1",
              {"id": "14.3.2", "title": "TEAE by SOC and PT"}]


def run_check_tlf_inventory(fail):
    ids = ["14.1.1", "14.3.1"] + ([] if fail else ["14.3.2"])
    outs = [make_table(i, HDR3, [["n", "1", "2"]]) for i in ids]
    return CHECKS["check_tlf_inventory"]({}, outs, make_rule("check_tlf_inventory", {"tables": SAP_TABLES}), {})


def run_check_cross_table_n(fail):
    placebo = "Placebo (N=5)" if fail else "Placebo (N=4)"
    demog = make_table("14.1.1", ["Parameter", placebo, "Drug A (N=4)", "Total (N=8)"], [["n", "4", "4", "8"]])
    aes = make_table("14.3.1", ["Category", "Placebo (N=4)", "Drug A (N=4)", "Total (N=8)"], [["Any TEAE", "3", "3", "6"]])
    return CHECKS["check_cross_table_n"]({}, [demog, aes], make_rule("check_cross_table_n"), {})


PROTOCOL = {"TITLE": "A Phase III Study of Drug A versus Placebo", "TPHASE": "Phase III", "STYPE": "Interventional"}


def run_check_ts_vs_protocol(fail):
    rows = [("TITLE", "a phase III study of drug a versus placebo."), ("TPHASE", "PHASE III")]   # case/punctuation differ
    if fail:
        rows = [("TITLE", "A Phase III Study of Drug A versus Placebo"), ("TPHASE", "PHASE II")]  # wrong phase, no STYPE
    else:
        rows.append(("STYPE", "INTERVENTIONAL"))
    ts = pd.DataFrame(rows, columns=["TSPARMCD", "TSVAL"])
    rule = make_rule("check_ts_vs_protocol", {"expected": PROTOCOL}, sap_ref="Protocol 1.1")
    return CHECKS["check_ts_vs_protocol"]({"TS": ts}, [], rule, {})


RUNNERS = {name: globals()[f"run_{name}"] for name in CHECKS}

# What each failing fixture must say - the intended reason, with the real counts.
EXPECTED_EVIDENCE = {
    "check_bign": ["Table 14.1.1: 1 of 3 column headers disagree with ADSL Safety population (SAFFL='Y')",
                   "Placebo prints N=5, ADSL has 4"],
    "check_population_filter": ["Table 14.3.1 states the Intent-to-Treat population (ITTFL='Y', 9 subjects in ADSL)",
                                "requires the Safety population (SAFFL='Y', 8 subjects in ADSL)"],
    "check_baseline_per_period": ["ADVS: 3 of 6 subject-PARAMCD pairs", "Period 2: 3"],
    "check_teae_window": ["2 of 6 records with TRTEMFL='Y' start more than 7 days after last dose",
                          "Placebo 3 current vs 3 under SAP rule", "Drug A 3 current vs 1 under SAP rule"],
    "check_percentages": ["1 of 4 n (%) cells", "printed 15 (80.0%), 15/20 = 75.0%"],
    "check_totals": ["1 of 2 count rows", "'Male': 11 + 12 = 23, Total prints 24"],
    "check_soc_pt": ["1 of 4 SOC/column combinations",
                     "'Nervous system disorders' / Placebo (N=20): SOC n=4 but PT 'Headache' n=5"],
    "check_label_units": ["ADPC.AVAL is labelled 'Concentration per kg'",
                          "3 of 5 assessable records do not equal PCSTRESN / WEIGHT",
                          "3 of those equal PCSTRESN unchanged"],
    "check_visit_windows": ["1 of 3 SAP-windowed visits disagree",
                            "'Week 4': 2 of 4 records have AWLO/AWHI = 21/35 (2) but the SAP window is 22/35"],
    "check_tlf_inventory": ["SAP lists 3 outputs; 2 delivered, 1 missing: 14.3.2 (TEAE by SOC and PT)"],
    "check_cross_table_n": ["Safety population: 1 of 3 columns shared by more than one table print different N",
                            "Placebo: N=5 in Table 14.1.1 vs N=4 in Table 14.3.1"],
    "check_ts_vs_protocol": ["2 of 3 checked parameters disagree with the protocol",
                             "TPHASE - TS has 'PHASE II', protocol says 'Phase III'",
                             "not in TS at all: STYPE"],
}


# ---------------------------------------------------------------------------
# The twelve pass / fail pairs
# ---------------------------------------------------------------------------

def test_there_are_exactly_twelve_checks_and_each_has_a_fixture():
    assert len(CHECKS) == 12
    assert set(RUNNERS) == set(EXPECTED_EVIDENCE) == set(CHECKS)


@pytest.mark.parametrize("name", sorted(CHECKS))
def test_pass_fixture_gives_no_findings(name):
    assert RUNNERS[name](fail=False) == []


@pytest.mark.parametrize("name", sorted(CHECKS))
def test_fail_fixture_fails_for_the_intended_reason_with_real_counts(name):
    findings = RUNNERS[name](fail=True)
    assert len(findings) == 1, f"{name} should give exactly one finding, got {len(findings)}"
    for needle in EXPECTED_EVIDENCE[name]:
        assert needle in findings[0]["evidence"], f"{name}: {needle!r} not in {findings[0]['evidence']!r}"


@pytest.mark.parametrize("name", sorted(CHECKS))
def test_finding_has_the_agreed_shape(name):
    f = RUNNERS[name](fail=True)[0]
    assert list(f) == ["finding_id", "run_id", "rule_id", "output_file", "what_is_wrong", "evidence",
                       "source_ref", "severity", "decision", "decided_by", "decided_at"]
    assert f["rule_id"] == "R-001" and f["severity"] == "major" and f["decision"] == "open"
    assert f["finding_id"] is None and f["decided_by"] is None
    assert f["output_file"].strip() and f["what_is_wrong"].strip()
    assert f["source_ref"] == ("Protocol 1.1" if name == "check_ts_vs_protocol" else "SAP 1.1")
    assert any(ch.isdigit() for ch in f["evidence"])


def test_source_ref_falls_back_to_the_rule_id_when_the_rule_has_no_sap_ref():
    out = make_table("14.3.1", HDR3, [["Any TEAE", "15 (80.0%)", "10 (40.0%)"]])
    f = CHECKS["check_percentages"]({}, [out], make_rule("check_percentages", sap_ref="", rule_id="R-014"), {})[0]
    assert f["source_ref"] == "rule R-014"


def test_severity_comes_from_the_rule():
    out = make_table("14.3.1", HDR3, [["Any TEAE", "15 (80.0%)", "10 (40.0%)"]])
    f = CHECKS["check_percentages"]({}, [out], make_rule("check_percentages", severity="critical"), {})[0]
    assert f["severity"] == "critical"


def test_a_finding_cannot_be_built_without_numeric_evidence():
    rule = make_rule("check_totals")
    for bad in ("", "   ", None, "the numbers look wrong"):
        with pytest.raises(ValueError):
            checks._finding(rule, "x", "wrong", bad)


# ---------------------------------------------------------------------------
# Missing or misspelled input raises - it is never a finding, never a silent pass
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("name", sorted(CHECKS))
def test_a_check_given_nothing_raises_check_input_error(name):
    with pytest.raises(CheckInputError):
        CHECKS[name]({}, [], make_rule(name), {})


def test_misspelled_variable_raises_not_a_finding():
    def call(name, datasets, params=None, ctx=None, outputs=()):
        return CHECKS[name](datasets, list(outputs), make_rule(name, params), ctx or {})

    ae = make_adae([("S7", 45, "Y")])
    with pytest.raises(CheckInputError, match="TRTEMF"):
        call("check_teae_window", {"ADSL": make_adsl(), "ADAE": ae.rename(columns={"TRTEMFL": "TRTEMF"})},
             {"window_days": 7})
    with pytest.raises(CheckInputError, match="TRTSD"):
        call("check_teae_window", {"ADSL": make_adsl().rename(columns={"TRTSDT": "TRTSD"}), "ADAE": ae},
             {"window_days": 7})
    with pytest.raises(CheckInputError, match="ABLF"):
        call("check_baseline_per_period", {"ADVS": advs_frame(True).rename(columns={"ABLFL": "ABLF"})})
    with pytest.raises(CheckInputError, match="AEBODSY"):
        call("check_soc_pt", {"ADAE": soc_ae_frame()}, {"soc_var": "AEBODSY"},
             outputs=[make_table("14.3.2", HDR3, [["x", "1", "2"]])])
    with pytest.raises(CheckInputError, match="PCSTRSN"):
        call("check_label_units", {"ADPC": adpc_frame(False)},
             {"dataset": "ADPC", "value_var": "AVAL", "source_var": "PCSTRSN"}, PC_CTX)
    with pytest.raises(CheckInputError, match="AWL0"):
        call("check_visit_windows", {"ADVS": advs_windows_frame()},
             {"dataset": "ADVS", "windows": WINDOWS, "lo_var": "AWL0"})
    with pytest.raises(CheckInputError, match="TSVAL"):
        call("check_ts_vs_protocol", {"TS": pd.DataFrame({"TSPARMCD": ["TITLE"]})}, {"expected": PROTOCOL})
    with pytest.raises(CheckInputError, match="SAFFL"):
        call("check_bign", {"ADSL": make_adsl().drop(columns="SAFFL")},
             outputs=[make_table("14.1.1", ["P", "Placebo (N=4)"], [["n", "4"]])])


def test_label_units_needs_the_dataset_profile_for_the_label():
    rule = make_rule("check_label_units", {"dataset": "ADPC", "value_var": "AVAL", "source_var": "PCSTRESN"})
    with pytest.raises(CheckInputError, match="profile"):
        CHECKS["check_label_units"]({"ADPC": adpc_frame(False)}, [], rule, {})


# ---------------------------------------------------------------------------
# Extra behaviour worth pinning down
# ---------------------------------------------------------------------------

def test_teae_under_flagging_is_reported_separately():
    rule = make_rule("check_teae_window", {"window_days": 7})
    ae = make_adae([("S2", 12, "N")])                    # inside the window, not flagged
    f = CHECKS["check_teae_window"]({"ADSL": make_adsl(), "ADAE": ae}, [], rule, {})
    assert len(f) == 1
    assert "1 of 3 records with TRTEMFL!='Y' start inside the window" in f[0]["evidence"]
    assert "start more than" not in f[0]["evidence"]


def test_teae_flag_on_an_undosed_subject_is_reported():
    rule = make_rule("check_teae_window", {"window_days": 7})
    ae = pd.concat([make_adae(), pd.DataFrame({"USUBJID": ["S9"], "ASTDT": [day(15)], "TRTEMFL": ["Y"]})])
    f = CHECKS["check_teae_window"]({"ADSL": make_adsl(), "ADAE": ae}, [], rule, {})
    assert "1 of 5 records with TRTEMFL='Y' belong to subjects with no first dose date" in f[0]["evidence"]


def test_teae_window_edge_day_37_is_inside_and_day_38_is_outside():
    rule = make_rule("check_teae_window", {"window_days": 7})
    adsl = make_adsl()

    def run(offset):
        ae = pd.DataFrame({"USUBJID": ["S1"], "ASTDT": [day(offset)], "TRTEMFL": ["Y"]})
        return CHECKS["check_teae_window"]({"ADSL": adsl, "ADAE": ae}, [], rule, {})

    assert run(37) == []                                  # last dose day 30 + 7: still treatment-emergent
    (f,) = run(38)
    assert "1 of 1 records with TRTEMFL='Y' start more than 7 days after last dose" in f["evidence"]
    assert run(0) == []                                   # first dose day itself counts
    assert "start before first dose" in run(-1)[0]["evidence"]


def test_percentages_round_half_up_at_the_printed_precision():
    ok = make_table("14.3.1", ["C", "A (N=8)"], [["x", "1 (12.5%)"], ["y", "1 (13%)"]])
    bad = make_table("14.3.1", ["C", "A (N=8)"], [["x", "1 (12%)"]])
    rule = make_rule("check_percentages")
    assert CHECKS["check_percentages"]({}, [ok], rule, {}) == []
    assert len(CHECKS["check_percentages"]({}, [bad], rule, {})) == 1


def test_percentages_ignore_columns_that_print_no_n():
    out = make_table("14.3.1", ["C", "Placebo"], [["x", "5 (99.0%)"]])
    assert CHECKS["check_percentages"]({}, [out], make_rule("check_percentages"), {}) == []


def test_population_filter_catches_a_table_built_on_the_wrong_population():
    out = make_table("14.3.1", ["Category", "Placebo (N=5)", "Drug A (N=4)", "Total (N=9)"],
                     [["Any TEAE", "3", "3", "6"]], subtitle="Safety Population")
    rule = make_rule("check_population_filter", {"table_populations": {"14.3.1": "safety"}})
    f = CHECKS["check_population_filter"](adsl_only(), [out], rule, {})
    assert len(f) == 1
    assert "all 2 column(s) whose N differs between populations print the Intent-to-Treat count" in f[0]["evidence"]
    assert "Placebo prints N=5, ITTFL='Y' gives 5, SAFFL='Y' gives 4" in f[0]["evidence"]


def test_population_filter_leaves_a_single_wrong_header_to_check_bign():
    out = make_table("14.3.1", ["Category", "Placebo (N=5)", "Drug A (N=4)", "Total (N=8)"],
                     [["Any TEAE", "3", "3", "6"]])
    rule = make_rule("check_population_filter", {"table_populations": {"14.3.1": "safety"}})
    assert CHECKS["check_population_filter"](adsl_only(), [out], rule, {}) == []
    assert len(CHECKS["check_bign"](adsl_only(), [out], make_rule("check_bign"), {})) == 1


def test_visit_window_study_day_outside_the_sap_window_is_reported():
    rule = make_rule("check_visit_windows", {"dataset": "ADVS", "windows": WINDOWS, "day_var": "ADY"})
    frame = advs_windows_frame(week4_days=(29, 29, 29, 40))
    f = CHECKS["check_visit_windows"]({"ADVS": frame}, [], rule, {})
    assert len(f) == 1
    assert "1 of 4 records have ADY outside the SAP window 22/35" in f[0]["evidence"]
    assert "AWLO/AWHI" not in f[0]["evidence"]


def test_label_without_a_per_unit_claim_is_not_checked():
    ctx = {"profiles": {"ADPC": {"variables": [{"name": "AVAL", "label": "Concentration (ng/mL)"}]}}}
    rule = make_rule("check_label_units", {"dataset": "ADPC", "value_var": "AVAL", "source_var": "PCSTRESN"})
    assert CHECKS["check_label_units"]({"ADPC": adpc_frame(False)}, [], rule, ctx) == []


def test_inventory_reports_delivered_tables_the_sap_does_not_list():
    outs = [make_table(i, HDR3, [["n", "1", "2"]]) for i in ("14.1.1", "14.3.1", "14.3.2", "14.9.9")]
    f = CHECKS["check_tlf_inventory"]({}, outs, make_rule("check_tlf_inventory", {"tables": SAP_TABLES}), {})
    assert len(f) == 1 and f[0]["severity"] == "minor"
    assert "4 outputs delivered; 1 not listed in the SAP inventory (3 listed): 14.9.9" in f[0]["evidence"]


def test_inventory_with_nothing_delivered_lists_everything_missing():
    f = CHECKS["check_tlf_inventory"]({}, [], make_rule("check_tlf_inventory", {"tables": SAP_TABLES}), {})
    assert "SAP lists 3 outputs; 0 delivered, 3 missing" in f[0]["evidence"]


def test_cross_table_n_does_not_compare_different_populations():
    demog = make_table("14.1.1", ["Parameter", "Placebo (N=5)"], [["n", "5"]], subtitle="Intent-to-Treat Population")
    aes = make_table("14.3.1", ["Category", "Placebo (N=4)"], [["x", "3"]], subtitle="Safety Population")
    assert CHECKS["check_cross_table_n"]({}, [demog, aes], make_rule("check_cross_table_n"), {}) == []


def test_baseline_only_flags_partial_periods_not_a_subject_with_no_baseline_anywhere():
    frame = advs_frame(False)
    frame.loc[frame["USUBJID"] == "S1", "ABLFL"] = ""     # S1: no baseline in either period
    assert CHECKS["check_baseline_per_period"]({"ADVS": frame}, [], make_rule(
        "check_baseline_per_period", {"dataset": "ADVS"}), {}) == []


# ---------------------------------------------------------------------------
# The real package built in Piece A: the planted problems, found with real counts
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def package():
    loaded = read_datasets(os.path.join(ROOT, "data", "sample_datasets"))
    return ({n: df for n, (df, _) in loaded.items()},
            read_outputs(os.path.join(ROOT, "data", "sample_outputs")))


def run_on_package(package, name, params=None):
    datasets, outputs = package
    return CHECKS[name](datasets, outputs, make_rule(name, params), {})


def test_package_p1_teae_window_9_of_66(package):
    (f,) = run_on_package(package, "check_teae_window", {"window_days": 7})
    assert "9 of 66 records with TRTEMFL='Y' start more than 7 days after last dose" in f["evidence"]
    assert ("Placebo 15 current vs 14 under SAP rule; Drug A 50mg 17 current vs 15 under SAP rule; "
            "Drug A 100mg 11 current vs 8 under SAP rule") in f["evidence"]


def test_package_p2_bign_placebo_20_vs_19(package):
    (f,) = run_on_package(package, "check_bign")
    assert "1 of 4 column headers disagree" in f["evidence"] and "Placebo prints N=20, ADSL has 19" in f["evidence"]
    assert f["output_file"] == "Table 14.1.1 (t_14_1_1.rtf)"


def test_package_p3_inventory_14_3_2_missing(package):
    tables = [{"id": "14.1.1"}, {"id": "14.3.1"}, {"id": "14.3.2", "title": "TEAE by SOC and PT"}]
    (f,) = run_on_package(package, "check_tlf_inventory", {"tables": tables})
    assert "3 outputs; 2 delivered, 1 missing: 14.3.2" in f["evidence"]


def test_package_wrong_placebo_header_also_shows_up_in_percentages_and_cross_table_n(package):
    # Same root cause as P2, seen from two other angles: the Placebo cells were
    # computed on 19 subjects but the header says 20; and 14.3.1 says 19.
    (pct,) = run_on_package(package, "check_percentages")
    assert pct["output_file"] == "Table 14.1.1 (t_14_1_1.rtf)"
    assert "5 of 20 n (%) cells" in pct["evidence"] and "Placebo (N=20)" in pct["evidence"]
    (xt,) = run_on_package(package, "check_cross_table_n")
    assert "Placebo: N=20 in Table 14.1.1 vs N=19 in Table 14.3.1" in xt["evidence"]


def test_package_has_no_false_positives_on_the_checks_it_should_pass(package):
    pops = {"table_populations": {"14.1.1": "safety", "14.3.1": "safety"}}
    assert run_on_package(package, "check_population_filter", pops) == []
    assert run_on_package(package, "check_totals") == []


if __name__ == "__main__":
    print("Evidence produced by each failing fixture:\n")
    for name in CHECKS:
        for f in RUNNERS[name](fail=True):
            print(f"{name}\n  file:     {f['output_file']}\n  severity: {f['severity']}   source: {f['source_ref']}"
                  f"\n  evidence: {f['evidence']}\n")
