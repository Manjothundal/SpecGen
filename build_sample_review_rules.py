"""
Build data/review_rules.csv - the rule library for the sample SAP
(data/sample_sap.pdf).

Every rule is written as status=draft, version 1. Nothing here approves a rule:
approval is a decision a person makes, so the review CLI ignores these rules
unless it is run with --include-drafts.

One rule per SAP requirement that has a deterministic check. Two checks are
not seeded because the sample SAP does not state them: check_label_units and
check_ts_vs_protocol (the TS check compares against the protocol, not the SAP).
Two of the rules (5.1 baseline, 5.2 visit windows) point at ADVS, which the
sample package does not contain, so a run against it lists them as skipped.

Rebuilding overwrites the file with identical content (fixed created_at).
"""

import os

from review import rules_store

BASE = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(BASE, "data", "review_rules.csv")
CREATED_BY = "SpecGen sample seed"
CREATED_AT = "2026-09-19T10:00:00"

SAP_TABLES = [
    {"id": "14.1.1", "title": "Summary of Demographic and Baseline Characteristics"},
    {"id": "14.3.1", "title": "Overview of Treatment-Emergent Adverse Events"},
    {"id": "14.3.2", "title": "Treatment-Emergent Adverse Events by System Organ Class and Preferred Term"},
]

RULES = [
    dict(scope="tlf", topic="big_n", severity="major", sap_ref="SAP 4.5", check="check_bign",
         params={"root_cause_of": ["check_cross_table_n", "check_percentages"]},
         description="Big N in each column header equals the analysis-population count in ADSL "
                     "(Safety: SAFFL='Y' by TRT01A)."),
    dict(scope="tlf", topic="population_filter", severity="critical", sap_ref="SAP 4.3",
         check="check_population_filter",
         params={"table_populations": {"14.1.1": "safety", "14.3.1": "safety", "14.3.2": "safety"}},
         description="Demographic and safety tables are built on the Safety Population."),
    dict(scope="cross", topic="cross_table_n", severity="major", sap_ref="SAP 4.5",
         check="check_cross_table_n",
         description="The same N is used for a treatment group in every Safety Population table."),
    dict(scope="adam", topic="baseline_per_period", severity="major", sap_ref="SAP 5.1",
         check="check_baseline_per_period", params={"dataset": "ADVS"},
         description="Baseline is defined per treatment period: ABLFL='Y' in each period a subject has records in."),
    dict(scope="adam", topic="visit_windows", severity="major", sap_ref="SAP 5.2", check="check_visit_windows",
         params={"dataset": "ADVS", "day_var": "ADY",
                 "windows": {"Baseline": [None, 1], "Week 4": [22, 35], "Week 8": [50, 63]}},
         description="Analysis visits use the SAP windows (Baseline up to Day 1, Week 4 22-35, Week 8 50-63)."),
    dict(scope="adam", topic="teae_window", severity="critical", sap_ref="SAP 6.2", check="check_teae_window",
         params={"window_days": 7},
         description="TEAE is onset on or after first dose and on or before last dose + 7 days (TRTEMFL)."),
    dict(scope="tlf", topic="percentages", severity="major", sap_ref="SAP 7.2", check="check_percentages",
         description="Printed percentages are n divided by the column Big N, shown to one decimal place."),
    dict(scope="tlf", topic="totals", severity="major", sap_ref="SAP 7.2", check="check_totals",
         description="The Total column equals the sum of the treatment arms."),
    dict(scope="tlf", topic="soc_pt", severity="major", sap_ref="SAP 7.3", check="check_soc_pt",
         description="A subject is counted once per SOC and once per PT, so a SOC count is at least its largest PT."),
    dict(scope="cross", topic="tlf_inventory", severity="major", sap_ref="SAP 9", check="check_tlf_inventory",
         params={"tables": SAP_TABLES},
         description="Every table in the SAP table inventory is delivered."),
]


def build(path=OUT_PATH):
    if os.path.exists(path):
        os.remove(path)
    for rule in RULES:
        rules_store.add_rule(rule, path, created_by=CREATED_BY, created_at=CREATED_AT)
    stored = rules_store.load_history(path)
    assert all(r["status"] == "draft" and r["version"] == 1 for r in stored)
    return path


if __name__ == "__main__":
    out = build()
    print(f"Wrote {out}: {len(RULES)} rules, all status=draft")
