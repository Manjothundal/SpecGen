"""Piece C tests: review.review_engine - rule selection, skipping, root-cause
linking, and the CLI, run against the Piece A sample package.

Run from the repo root:  python -m pytest tests/test_review_engine.py -v
"""

import os
import shutil

import pytest

from build_sample_review_rules import build as build_seed_rules
from review import rules_store as rs
from review.findings import Finding, finalise, read_findings_xlsx
from review.review_engine import ReviewError, link_root_causes, main, run_review

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATASETS = os.path.join(ROOT, "data", "sample_datasets")
OUTPUTS = os.path.join(ROOT, "data", "sample_outputs")
SEED = os.path.join(ROOT, "data", "review_rules.csv")


@pytest.fixture
def seed_copy(tmp_path):
    path = str(tmp_path / "rules.csv")
    shutil.copy(SEED, path)
    return path


def run(rules, **kw):
    return run_review(DATASETS, OUTPUTS, rules, run_id="RUN-T", **kw)


# --- the seed rules --------------------------------------------------------------

def test_every_seed_rule_is_a_draft_and_none_is_approved():
    history = rs.load_history(SEED)
    assert len(history) == 10
    assert {r["status"] for r in history} == {"draft"} and {r["version"] for r in history} == {1}
    assert rs.load_rules(SEED, status="approved") == []
    assert {r["created_by"] for r in history} == {"SpecGen sample seed"}


def test_the_seed_builder_reproduces_the_committed_file(tmp_path):
    rebuilt = build_seed_rules(str(tmp_path / "again.csv"))
    assert rs.load_history(rebuilt) == rs.load_history(SEED)


# --- approved-only is the default -------------------------------------------------------

def test_default_run_refuses_draft_rules(seed_copy):
    with pytest.raises(ReviewError, match="--include-drafts"):
        run(seed_copy)


def test_cli_default_run_exits_2_and_writes_nothing(tmp_path, capsys):
    out = tmp_path / "findings.xlsx"
    code = main(["--datasets", DATASETS, "--outputs", OUTPUTS, "--rules", SEED, "--out", str(out)])
    assert code == 2 and not out.exists()
    assert "none is approved" in capsys.readouterr().err


def test_a_run_never_changes_the_rules_file(seed_copy):
    before = open(seed_copy, "rb").read()
    run(seed_copy, include_drafts=True)
    assert open(seed_copy, "rb").read() == before


def test_approved_rules_run_by_default_and_the_run_is_not_labelled_draft(seed_copy):
    rs.approve_rule("R-006", seed_copy)                        # a person approves one rule
    result = run(seed_copy)
    assert [r["rule_id"] for r in result.rule_results] == ["R-006"]
    assert len(result.findings) == 1 and result.used_drafts is False
    assert dict(result.run_info["summary"])["Draft rules"] == "none - approved rules only"


def test_a_draft_revision_does_not_replace_the_approved_version_unless_drafts_are_included(seed_copy):
    rs.approve_rule("R-006", seed_copy)
    rs.revise_rule("R-006", {"params": {"window_days": 14}}, seed_copy)       # v2, draft
    approved_only = run(seed_copy).findings[0].evidence
    with_drafts = [f for f in run(seed_copy, include_drafts=True).findings if f.rule_id == "R-006"][0].evidence
    assert "more than 7 days after last dose" in approved_only
    assert "more than 14 days after last dose" in with_drafts


# --- the sample run -----------------------------------------------------------------------

def test_sample_run_with_drafts_finds_the_planted_problems_and_says_it_used_drafts(seed_copy):
    result = run(seed_copy, include_drafts=True)
    f = {x.rule_id: x for x in result.findings}
    assert set(f) == {"R-001", "R-003", "R-006", "R-007", "R-010"}

    assert "9 of 66 records with TRTEMFL='Y' start more than 7 days after last dose" in f["R-006"].evidence
    assert "Placebo prints N=20, ADSL has 19" in f["R-001"].evidence
    assert "1 missing: 14.3.2" in f["R-010"].evidence
    assert f["R-006"].output_file == "ADAE (adae.xpt)"

    assert [x.finding_id for x in result.findings] == ["F-001", "F-002", "F-003", "F-004", "F-005"]
    assert [x.severity for x in result.findings] == ["critical"] + ["major"] * 4
    assert all(x.decision == "open" and x.run_id == "RUN-T" for x in result.findings)
    assert all(x.evidence and x.source_ref for x in result.findings)

    assert result.used_drafts is True
    assert dict(result.run_info["summary"])["Draft rules"].startswith("INCLUDED")
    assert all(r["status"] == "draft" for r in result.rule_results)


def test_no_root_cause_is_linked_in_the_sample_run(seed_copy):
    # The three P2 findings are all output-level, and no seed rule declares a
    # dataset-level cause, so nothing is linked. Links exist only where a rule says so.
    result = run(seed_copy, include_drafts=True)
    assert result.links == 0 and all(f.root_cause_id is None for f in result.findings)
    assert all("Root cause" not in f.what_is_wrong for f in result.findings)


def test_rules_that_cannot_look_are_skipped_and_listed_never_findings(seed_copy):
    result = run(seed_copy, include_drafts=True)
    skipped = {r["rule_id"]: r["result"] for r in result.skipped}
    assert set(skipped) == {"R-004", "R-005"}
    assert all("dataset ADVS was not supplied" in v for v in skipped.values())
    assert not any(f.rule_id in skipped for f in result.findings)


def test_unknown_check_and_text_only_rules_are_reported_not_crashed(tmp_path):
    path = str(tmp_path / "rules.csv")
    base = {"scope": "adam", "topic": "t", "severity": "major", "description": "d", "sap_ref": "SAP 1"}
    rs.add_rule({**base, "check": "check_does_not_exist"}, path)
    rs.add_rule({**base, "check": None}, path)
    for rid in ("R-001", "R-002"):
        rs.approve_rule(rid, path)
    result = run(path)
    assert result.rule_results[0]["result"].startswith("SKIPPED: no check function named")
    assert result.rule_results[1]["result"].startswith("not run: text-only")
    assert result.findings == []


def test_missing_folder_is_a_clean_error(seed_copy, tmp_path, capsys):
    with pytest.raises(ReviewError, match="datasets folder not found"):
        run_review(str(tmp_path / "nope"), OUTPUTS, seed_copy, include_drafts=True)
    assert main(["--datasets", str(tmp_path / "nope"), "--outputs", OUTPUTS, "--rules", seed_copy,
                 "--include-drafts"]) == 2


# --- the CLI end to end ---------------------------------------------------------------------

def test_cli_with_drafts_writes_the_workbook_and_warns(tmp_path, capsys):
    out = tmp_path / "findings.xlsx"
    code = main(["--datasets", DATASETS, "--outputs", OUTPUTS, "--rules", SEED, "--out", str(out),
                 "--include-drafts", "--run-id", "RUN-CLI"])
    text = capsys.readouterr().out
    assert code == 0 and out.exists()
    assert "DRAFT RULES INCLUDED" in text and "WARNING: 2 rule(s) were skipped" in text
    assert "Findings: 5 (1 critical, 4 major, 0 minor)" in text
    rows = read_findings_xlsx(str(out))
    assert [r["#"] for r in rows] == [1, 2, 3, 4, 5]
    assert rows[0]["Severity"] == "Critical" and rows[0]["Source ref"] == "SAP 6.2"
    assert all(r["Evidence"] and r["Source ref"] for r in rows)


# --- root-cause linking ----------------------------------------------------------------------

def table(table_id, sources):
    return {"table_id": table_id, "kind": "table", "title": f"Table {table_id} T", "subtitle": "Safety Population",
            "footnotes": [f"Source: {sources}. Program: t.sas"], "column_headers": [], "rows": [],
            "page": 1, "source_file": "t.rtf"}


def fnd(fid, rule_id, output_file):
    return Finding(finding_id=fid, rule_id=rule_id, output_file=output_file, what_is_wrong="Wrong.",
                   evidence="2 of 9 cells", source_ref="SAP 1", severity="major")


LINK_RULES = {
    "R-100": {"check": "check_teae_window", "params": {"root_cause_of": ["check_bign", "check_percentages"]}},
    "R-001": {"check": "check_bign", "params": {}},
    "R-007": {"check": "check_percentages", "params": {}},
    "R-003": {"check": "check_cross_table_n", "params": {}},
}
LINK_OUTPUTS = [table("14.1.1", "ADSL"), table("14.3.1.1", "ADSL, ADAE"), table("14.9.9", "ADLB")]


def test_link_needs_a_rule_that_declares_the_cause_and_a_table_that_cites_the_dataset():
    root = fnd("t1", "R-100", "ADSL (adsl.xpt)")
    a = fnd("t2", "R-001", "Table 14.1.1 (t.rtf)")            # declared check, cites ADSL      -> linked
    b = fnd("t3", "R-007", "Table 14.3.1.1 (t.rtf)")          # declared check, cites ADSL      -> linked
    c = fnd("t4", "R-003", "Table 14.1.1; Table 14.3.1.1")    # check not declared              -> not linked
    d = fnd("t5", "R-007", "Table 14.9.9 (t.rtf)")            # declared check, cites ADLB only -> not linked
    made = link_root_causes([root, a, b, c, d], LINK_RULES, LINK_OUTPUTS, {"ADSL", "ADAE", "ADLB"})
    assert made == 2
    assert (root.root_cause_id, a.root_cause_id, b.root_cause_id) == (None, "t1", "t1")
    assert c.root_cause_id is None and d.root_cause_id is None


def test_no_rule_no_link():
    rules = {**LINK_RULES, "R-100": {"check": "check_teae_window", "params": {}}}
    root, a = fnd("t1", "R-100", "ADSL (adsl.xpt)"), fnd("t2", "R-001", "Table 14.1.1 (t.rtf)")
    assert link_root_causes([root, a], rules, LINK_OUTPUTS, {"ADSL"}) == 0 and a.root_cause_id is None


def test_an_output_level_finding_is_never_a_root_cause():
    rules = {**LINK_RULES, "R-001": {"check": "check_bign", "params": {"root_cause_of": ["check_percentages"]}}}
    a, b = fnd("t1", "R-001", "Table 14.1.1 (t.rtf)"), fnd("t2", "R-007", "Table 14.3.1.1 (t.rtf)")
    assert link_root_causes([a, b], rules, LINK_OUTPUTS, {"ADSL"}) == 0


def test_linked_findings_finalise_into_the_agreed_text():
    root = fnd("t1", "R-100", "ADSL (adsl.xpt)")
    a, b = fnd("t2", "R-001", "Table 14.1.1 (t.rtf)"), fnd("t3", "R-007", "Table 14.3.1.1 (t.rtf)")
    link_root_causes([root, a, b], LINK_RULES, LINK_OUTPUTS, {"ADSL", "ADAE"})
    out = finalise([b, a, root])
    assert out[0].output_file == "ADSL (adsl.xpt)" and out[0].root_cause_id is None
    assert out[0].what_is_wrong.endswith(
        "This is the dataset-level cause of the findings raised against Table 14.1.1 and Table 14.3.1.1.")
    assert all(f.what_is_wrong.endswith("Root cause: see finding F-001 against ADSL (adsl.xpt).") for f in out[1:])


def test_linking_end_to_end_through_the_engine_with_a_deliberately_contrived_rule(tmp_path):
    # Mechanism test only: this rule declares that the ADAE flag problem is the cause of the
    # cross-table N finding. Table 14.3.1 names ADAE in its Source footnote, so they link.
    # The seed rules make no such claim, and the sample run above links nothing.
    path = str(tmp_path / "rules.csv")
    shutil.copy(SEED, path)
    rs.revise_rule("R-006", {"params": {"window_days": 7, "root_cause_of": ["check_cross_table_n"]}}, path)
    result = run(path, include_drafts=True)

    by_rule = {f.rule_id: f for f in result.findings}
    cause, pointing = by_rule["R-006"], by_rule["R-003"]
    assert result.links == 1
    assert cause.root_cause_id is None and pointing.root_cause_id == cause.finding_id
    assert result.findings.index(cause) + 1 == result.findings.index(pointing)     # root directly above
    assert cause.what_is_wrong.endswith(
        "This is the dataset-level cause of the findings raised against Table 14.1.1 and Table 14.3.1.")
    assert pointing.what_is_wrong.endswith(f"Root cause: see finding {cause.finding_id} against ADAE (adae.xpt).")
    assert all(f.root_cause_id is None for f in result.findings if f.rule_id not in ("R-003",))
