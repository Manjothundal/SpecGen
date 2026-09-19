"""rules_store.py - load and save the versioned review rule library
(data/review_rules.csv).

One CSV row per rule VERSION. The file is history: nothing is ever deleted.

Lifecycle
    add_rule      new rule_id, version 1, always status=draft
    revise_rule   latest row is a draft    -> edited in place (same version)
                  latest row is approved   -> a NEW row, version + 1, status=draft.
                                              The approved row is left untouched.
    approve_rule  flips one draft row to approved (the only status change allowed)

What the review engine runs is load_rules(status="approved"): the latest
APPROVED version of each rule. A draft revision therefore does not switch off
the approved rule it revises until someone approves it.

Rule shape (spec 4.1): rule_id, scope, topic, description, sap_ref, severity,
check, params, status, owner, version, created_by, created_at. params is a
dict, stored as JSON in the CSV. No model calls, no dependency on checks.py.
"""

import csv
import json
import os
import re
import tempfile
from datetime import datetime

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PATH = os.path.join(BASE, "data", "review_rules.csv")

COLUMNS = ["rule_id", "scope", "topic", "description", "sap_ref", "severity",
           "check", "params", "status", "owner", "version", "created_by", "created_at"]
SCOPES = ("adam", "sdtm", "tlf", "cross")
SEVERITIES = ("critical", "major", "minor")
STATUSES = ("draft", "approved")

_ID_RE = re.compile(r"^R-(\d+)$")
_LOCKED_FIELDS = ("rule_id", "version", "status", "created_at")


class RuleError(ValueError):
    """A rule failed validation, or an operation is not allowed on it."""


def _now():
    return datetime.now().isoformat(timespec="seconds")


def validate_rule(rule):
    """Raise RuleError unless the rule has every field, with legal values."""
    missing = [c for c in COLUMNS if c not in rule]
    if missing:
        raise RuleError(f"rule is missing fields: {', '.join(missing)}")
    for field in ("rule_id", "topic", "description", "owner", "created_by"):
        if not str(rule[field]).strip():
            raise RuleError(f"rule field {field!r} must not be empty")
    if not _ID_RE.match(str(rule["rule_id"])):
        raise RuleError(f"rule_id {rule['rule_id']!r} must look like R-014")
    if rule["scope"] not in SCOPES:
        raise RuleError(f"scope {rule['scope']!r} must be one of {SCOPES}")
    if rule["severity"] not in SEVERITIES:
        raise RuleError(f"severity {rule['severity']!r} must be one of {SEVERITIES}")
    if rule["status"] not in STATUSES:
        raise RuleError(f"status {rule['status']!r} must be one of {STATUSES}")
    if not isinstance(rule["version"], int) or rule["version"] < 1:
        raise RuleError("version must be an integer >= 1")
    if rule["check"] is not None and not str(rule["check"]).strip():
        raise RuleError("check must be a function name or None")
    if not isinstance(rule["params"], dict):
        raise RuleError("params must be a dict")
    try:
        json.dumps(rule["params"])
    except TypeError as exc:
        raise RuleError(f"params must be JSON-serialisable: {exc}") from exc


def _to_row(rule):
    row = {c: rule[c] for c in COLUMNS}
    row["check"] = rule["check"] or ""
    row["params"] = json.dumps(rule["params"], sort_keys=True)
    row["version"] = str(rule["version"])
    return row


def _from_row(row):
    rule = {c: row.get(c, "") for c in COLUMNS}
    rule["check"] = rule["check"] or None
    rule["params"] = json.loads(rule["params"]) if rule["params"] else {}
    rule["version"] = int(rule["version"])
    return rule


def load_history(path=DEFAULT_PATH):
    """Every row in the file, in file order. A missing file is an empty library."""
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as f:
        return [_from_row(r) for r in csv.DictReader(f)]


def _write_all(rules, path):
    """Rewrite the whole file atomically (temp file, then replace)."""
    for r in rules:
        validate_rule(r)
    folder = os.path.dirname(os.path.abspath(path))
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=COLUMNS)
            writer.writeheader()
            writer.writerows(_to_row(r) for r in rules)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def load_rules(path=DEFAULT_PATH, status=None):
    """The current rules: the latest version of each rule_id, sorted by id.

    With status="approved" (what the engine uses) it is the latest APPROVED
    version of each rule; rules with no approved version are left out.
    """
    latest = {}
    for r in load_history(path):
        if status is not None and r["status"] != status:
            continue
        cur = latest.get(r["rule_id"])
        if cur is None or r["version"] > cur["version"]:
            latest[r["rule_id"]] = r
    return [latest[k] for k in sorted(latest)]


def get_rule(rule_id, path=DEFAULT_PATH, version=None):
    """One rule row: the given version, or the latest version of any status."""
    rows = [r for r in load_history(path) if r["rule_id"] == rule_id]
    if version is not None:
        rows = [r for r in rows if r["version"] == version]
    if not rows:
        raise RuleError(f"no rule {rule_id}" + (f" version {version}" if version else ""))
    return max(rows, key=lambda r: r["version"])


def next_rule_id(path=DEFAULT_PATH):
    nums = [int(_ID_RE.match(r["rule_id"]).group(1)) for r in load_history(path)]
    return f"R-{max(nums, default=0) + 1:03d}"


def add_rule(rule, path=DEFAULT_PATH, created_by=None):
    """Add a brand-new rule. Always saved as version 1, status=draft - a rule
    only becomes active through approve_rule(). rule_id is assigned if absent.
    Returns the stored rule."""
    rule = dict(rule)
    rule.setdefault("rule_id", None)
    rule["rule_id"] = rule["rule_id"] or next_rule_id(path)
    rule.setdefault("sap_ref", "")
    rule.setdefault("check", None)
    rule.setdefault("params", {})
    rule.setdefault("owner", "Biostatistics")
    rule["created_by"] = created_by or rule.get("created_by") or "unknown"
    rule["created_at"] = _now()
    rule["version"] = 1
    rule["status"] = "draft"
    validate_rule(rule)

    history = load_history(path)
    if any(r["rule_id"] == rule["rule_id"] for r in history):
        raise RuleError(f"{rule['rule_id']} already exists - use revise_rule to change it")
    _write_all(history + [rule], path)
    return rule


def revise_rule(rule_id, changes, path=DEFAULT_PATH, created_by=None):
    """Change a rule without ever editing an approved row in place.

    Latest row is a draft    -> that row is updated in place (same version).
    Latest row is approved   -> a new row is appended: version + 1, status=draft.
    rule_id, version, status and created_at cannot be set through `changes`.
    Returns the stored (new or updated) rule.
    """
    bad = [k for k in changes if k in _LOCKED_FIELDS or k not in COLUMNS]
    if bad:
        raise RuleError(f"cannot change field(s) through revise_rule: {', '.join(bad)}")

    history = load_history(path)
    rows = [r for r in history if r["rule_id"] == rule_id]
    if not rows:
        raise RuleError(f"no rule {rule_id}")
    latest = max(rows, key=lambda r: r["version"])

    if latest["status"] == "draft":
        latest.update(changes)
        stored = latest
    else:
        stored = {**latest, **changes, "version": latest["version"] + 1, "status": "draft",
                  "created_by": created_by or latest["created_by"], "created_at": _now()}
        history.append(stored)
    validate_rule(stored)
    _write_all(history, path)
    return stored


def approve_rule(rule_id, path=DEFAULT_PATH, version=None):
    """Promote one draft row to approved (default: the latest version).
    The only status change the store allows. Returns the stored rule."""
    history = load_history(path)
    rows = [r for r in history if r["rule_id"] == rule_id
            and (version is None or r["version"] == version)]
    if not rows:
        raise RuleError(f"no rule {rule_id}" + (f" version {version}" if version else ""))
    target = max(rows, key=lambda r: r["version"])
    if target["status"] == "approved":
        raise RuleError(f"{rule_id} version {target['version']} is already approved")
    target["status"] = "approved"
    _write_all(history, path)
    return target
