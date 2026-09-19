"""Piece B tests: review.rules_store - versioned rule library.

Run from the repo root:  python -m pytest tests/test_rules_store.py -v
"""

import pytest

from review import rules_store as rs


def new_rule(**over):
    rule = {"scope": "adam", "topic": "teae_window", "severity": "critical",
            "description": "TEAE is first dose to last dose + 7 days, per period",
            "sap_ref": "SAP 6.2", "check": "check_teae_window",
            "params": {"window_days": 7, "windows": {"Week 4": [22, 35], "Baseline": [None, 1]}}}
    rule.update(over)
    return rule


@pytest.fixture
def path(tmp_path):
    return str(tmp_path / "review_rules.csv")


def test_missing_file_is_an_empty_library(path):
    assert rs.load_history(path) == [] and rs.load_rules(path) == []


def test_add_rule_assigns_id_and_is_always_draft_v1(path):
    r = rs.add_rule(new_rule(status="approved", version=9), path, created_by="mhundal")
    assert (r["rule_id"], r["version"], r["status"], r["created_by"]) == ("R-001", 1, "draft", "mhundal")
    assert rs.add_rule(new_rule(), path)["rule_id"] == "R-002"


def test_params_round_trip_including_nested_values_and_null(path):
    rs.add_rule(new_rule(), path)
    stored = rs.get_rule("R-001", path)
    assert stored["params"] == new_rule()["params"]
    assert stored["params"]["windows"]["Baseline"] == [None, 1]
    assert stored["check"] == "check_teae_window" and isinstance(stored["version"], int)


def test_rule_with_no_check_is_text_only(path):
    rs.add_rule(new_rule(check=None, params={}), path)
    assert rs.get_rule("R-001", path)["check"] is None


def test_draft_is_not_active_until_approved(path):
    rs.add_rule(new_rule(), path)
    assert rs.load_rules(path, status="approved") == []
    rs.approve_rule("R-001", path)
    assert [r["rule_id"] for r in rs.load_rules(path, status="approved")] == ["R-001"]


def test_approving_twice_is_refused(path):
    rs.add_rule(new_rule(), path)
    rs.approve_rule("R-001", path)
    with pytest.raises(rs.RuleError):
        rs.approve_rule("R-001", path)


def test_revising_a_draft_edits_it_in_place(path):
    rs.add_rule(new_rule(), path)
    r = rs.revise_rule("R-001", {"severity": "minor"}, path)
    assert (r["version"], r["status"], r["severity"]) == (1, "draft", "minor")
    assert len(rs.load_history(path)) == 1


def test_revising_an_approved_rule_adds_a_new_draft_version_and_keeps_the_old_row(path):
    rs.add_rule(new_rule(), path)
    rs.approve_rule("R-001", path)
    before = rs.get_rule("R-001", path, version=1)

    v2 = rs.revise_rule("R-001", {"params": {"window_days": 14}}, path, created_by="reviewer2")
    assert (v2["version"], v2["status"], v2["created_by"]) == (2, "draft", "reviewer2")

    history = rs.load_history(path)
    assert len(history) == 2
    assert rs.get_rule("R-001", path, version=1) == before          # approved row untouched
    assert rs.get_rule("R-001", path, version=1)["params"]["window_days"] == 7

    # The draft revision does not switch off the approved v1 ...
    assert [(r["version"]) for r in rs.load_rules(path, status="approved")] == [1]
    # ... but the latest row overall is the draft.
    assert [(r["version"], r["status"]) for r in rs.load_rules(path)] == [(2, "draft")]

    rs.approve_rule("R-001", path)                                    # promotes v2, the latest
    assert [r["version"] for r in rs.load_rules(path, status="approved")] == [2]
    assert len(rs.load_history(path)) == 2                            # history kept


def test_revise_cannot_touch_locked_fields(path):
    rs.add_rule(new_rule(), path)
    for field, value in [("status", "approved"), ("version", 5), ("rule_id", "R-099"), ("created_at", "x")]:
        with pytest.raises(rs.RuleError):
            rs.revise_rule("R-001", {field: value}, path)
    with pytest.raises(rs.RuleError):
        rs.revise_rule("R-001", {"not_a_column": 1}, path)


def test_validation_rejects_bad_values(path):
    for bad in ({"scope": "everything"}, {"severity": "urgent"}, {"topic": "  "}, {"params": "text"},
                {"rule_id": "014"}):
        with pytest.raises(rs.RuleError):
            rs.add_rule(new_rule(**bad), path)
    assert rs.load_history(path) == []                                # nothing half-written


def test_duplicate_rule_id_is_refused(path):
    rs.add_rule(new_rule(rule_id="R-014"), path)
    with pytest.raises(rs.RuleError):
        rs.add_rule(new_rule(rule_id="R-014"), path)


def test_unknown_rule_raises(path):
    rs.add_rule(new_rule(), path)
    for call in (lambda: rs.get_rule("R-050", path), lambda: rs.approve_rule("R-050", path),
                 lambda: rs.revise_rule("R-050", {"severity": "minor"}, path)):
        with pytest.raises(rs.RuleError):
            call()


def test_load_rules_returns_the_latest_version_of_each_rule_sorted(path):
    rs.add_rule(new_rule(), path)
    rs.add_rule(new_rule(topic="bign", check="check_bign", params={}), path)
    rs.approve_rule("R-001", path)
    rs.revise_rule("R-001", {"severity": "major"}, path)
    assert [(r["rule_id"], r["version"]) for r in rs.load_rules(path)] == [("R-001", 2), ("R-002", 1)]
