"""findings.py - the Finding model, severity ordering, dedupe, root-cause
grouping and the Excel export.

A Finding is one row of the findings sheet. The sheet has exactly seven columns
and no others:

    #  |  Output / File  |  What is wrong  |  Evidence  |  Source ref  |  Severity  |  Decision

Root causes. Several findings can share one cause. The cause may sit in a dataset
or in an output (one wrong number in a table header is the cause of the
percentages and cross-table findings that read it). The cause keeps
root_cause_id = None; every finding raised because of it has root_cause_id set to
the cause's id. There is NO column for this - the link is carried in the text of
"What is wrong", the way findings sheets are written by hand:

    on a dataset cause: "This is the dataset-level cause of the findings raised
                         against Table 14.1.1 and Table 14.3.1.1."
    on an output cause: "This is the cause of the findings raised against
                         Table 14.3.1."
    on the pointers:    "Root cause: see finding F-012 against ADaM/adsl.xpt."

Two identifiers (spec 4.4). finding_id is the F-nnn label printed in "#", and it
is positional: it is assigned in final order and renumbers whenever the set of
findings changes, so it means something only inside one run. finding_key is a
hash of the rule, the object and the detail the check keyed on, with every count
left out; it is the same from run to run, so a decision recorded against it still
attaches to the issue next time. finding_key is not exported as a column.

Workflow: build findings (review.checks gives dicts), then finalise(): it orders
them (a root cause directly above the findings that point at it), numbers them
F-001, F-002 ... in that order, and writes the link text. The "#" column carries
the finding id itself, so "see finding F-012" can be looked up in the sheet.

Design rule 2 (evidence or it does not exist) is enforced here, in the model: a
finding without a source reference or without numeric evidence cannot be built.
No model calls; nothing here reads or writes anything but the xlsx it is given.
"""

import hashlib
import re
from typing import Literal, Optional

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from pydantic import BaseModel, ConfigDict, field_validator, model_validator

SEVERITIES = ("critical", "major", "minor")
SEVERITY_ORDER = {s: i for i, s in enumerate(SEVERITIES)}
DECISIONS = ("open", "accepted", "rejected")

COLUMNS = ["#", "Output / File", "What is wrong", "Evidence", "Source ref", "Severity", "Decision"]

_ID_RE = re.compile(r"^F-(\d+)$")
# a trailing "(...)" on an object name is the file it was read from, or a short
# gloss; neither identifies the object, and the file name changes between runs
_OBJECT_SUFFIX = re.compile(r"\s*\([^()]*\)\s*$")
_TABLE_REF = re.compile(r"\b(Table|Listing|Figure) (\d+(?:\.\d+)*)")


class Finding(BaseModel):
    """One finding. Field names follow spec 4.2, plus rule_id (dedupe key) and
    root_cause_id (nullable link to the dataset-level finding that causes this one)."""

    model_config = ConfigDict(extra="forbid")

    finding_id: Optional[str] = None
    run_id: Optional[str] = None
    output_file: str
    what_is_wrong: str
    evidence: str
    source_ref: str
    severity: Literal["critical", "major", "minor"]
    decision: Literal["open", "accepted", "rejected"] = "open"
    decided_by: Optional[str] = None
    decided_at: Optional[str] = None
    rule_id: Optional[str] = None
    root_cause_id: Optional[str] = None
    # set by a check only when rule_id plus the object cannot tell two of its own
    # findings apart (the variable or parameter it keyed on). Never a count.
    key_object: Optional[str] = None

    @property
    def finding_key(self):
        """Stable across runs, unlike finding_id. See spec 4.4: decisions attach
        to this, F-nnn is only the label for one run."""
        return make_finding_key(self.rule_id, self.output_file, self.key_object)

    @field_validator("output_file", "what_is_wrong", "evidence", "source_ref")
    @classmethod
    def _not_blank(cls, v, info):
        v = (v or "").strip()
        if not v:
            raise ValueError(f"{info.field_name} must not be empty")
        return v

    @field_validator("evidence")
    @classmethod
    def _evidence_has_a_number(cls, v):
        if not re.search(r"\d", v):
            raise ValueError("evidence must contain real counts or values, not prose alone")
        return v

    @model_validator(mode="after")
    def _a_decision_needs_a_person_and_a_time(self):
        if self.decision != "open" and not (self.decided_by and self.decided_at):
            raise ValueError("a decision other than 'open' needs decided_by and decided_at")
        return self


def object_of(output_file):
    """The thing a finding is raised against, without the file it was read from:
    'Table 14.1.1 (t_14_1_1.rtf)' and 'Table 14.1.1 (t_14_1_1_v2.rtf)' are the
    same table, and 'ADAE (adae.xpt)' is ADAE."""
    return _OBJECT_SUFFIX.sub("", output_file or "").strip()


def make_finding_key(rule_id, output_file, key_object=None):
    """Identity of an issue, stable from run to run: the rule, the object it is
    raised against, and the detail the check keyed on. No counts and no computed
    values go in - the same issue with different numbers is the same finding, and
    the decision a reviewer made about it still applies."""
    parts = [(rule_id or "").strip(), object_of(output_file), (key_object or "").strip()]
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()[:16]


def to_findings(items):
    """Accept Finding objects or plain dicts (what review.checks returns)."""
    return [i if isinstance(i, Finding) else Finding.model_validate(i) for i in items]


# ---------------------------------------------------------------------------
# Dedupe, ordering, numbering
# ---------------------------------------------------------------------------

def dedupe(findings):
    """Same rule + same object = one finding. The first one is kept, at the
    highest severity any of the duplicates had. Findings with no rule_id (raised
    by hand) are never merged."""
    kept, index = [], {}
    for f in (x.model_copy() for x in to_findings(findings)):
        key = (f.rule_id, f.output_file) if f.rule_id else None
        if key is not None and key in index:
            first = kept[index[key]]
            if SEVERITY_ORDER[f.severity] < SEVERITY_ORDER[first.severity]:
                first.severity = f.severity
            continue
        if key is not None:
            index[key] = len(kept)
        kept.append(f)
    return kept


def table_refs(text):
    """['Table 14.1.1', ...] mentioned in an output_file string, in order."""
    return [f"{kind} {num}" for kind, num in _TABLE_REF.findall(text or "")]


def _sort_key(f):
    return (SEVERITY_ORDER[f.severity], f.output_file, f.rule_id or "", f.evidence)


def order_findings(findings):
    """Severity first (critical, major, minor), then output, then rule - except
    that a root cause is always followed directly by the findings that point at
    it, and the whole group sorts by its most severe member. A finding pointing
    at a root that is not in the list is treated as a stand-alone finding."""
    findings = list(findings)
    roots = {f.finding_id for f in findings if f.finding_id and f.root_cause_id is None}
    dependents, standalone = {}, []
    for f in findings:
        if f.root_cause_id and f.root_cause_id in roots:
            dependents.setdefault(f.root_cause_id, []).append(f)
        else:
            standalone.append(f)

    groups = []
    for f in standalone:
        members = [f] + sorted(dependents.get(f.finding_id, []), key=_sort_key)
        rank = min(SEVERITY_ORDER[m.severity] for m in members)
        # Ties on group severity are broken by the root's output and rule, not by
        # the root's own severity (a minor cause with major consequences is major).
        groups.append((rank, f.output_file, f.rule_id or "", f.evidence, members))
    groups.sort(key=lambda g: g[:4])
    return [m for g in groups for m in g[4]]


def _join_and(items):
    items = list(items)
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def _add_sentence(text, sentence):
    if sentence in text:
        return text
    text = text.rstrip()
    if not text.endswith((".", "!", "?")):
        text += "."
    return f"{text} {sentence}"


def finalise(findings, run_id=None):
    """Order, number and cross-reference a run's findings. Returns new Finding
    objects; the input is not changed.

    Every finding needs a unique finding_id on the way in (temporary ids are fine,
    they are replaced by F-001, F-002 ... in final order). A finding's
    root_cause_id must name another finding in the list that is itself a root
    (no chains). Calling finalise twice on its own output gives the same result.
    """
    work = [f.model_copy() for f in to_findings(findings)]
    for i, f in enumerate(work, 1):
        if not f.finding_id:
            f.finding_id = f"tmp-{i}"
    ids = [f.finding_id for f in work]
    if len(set(ids)) != len(ids):
        raise ValueError("finalise needs unique finding_ids")
    by_id = {f.finding_id: f for f in work}
    for f in work:
        if f.root_cause_id is None:
            continue
        root = by_id.get(f.root_cause_id)
        if root is None:
            raise ValueError(f"{f.finding_id} points at root cause {f.root_cause_id}, which is not in the run")
        if root is f or root.root_cause_id is not None:
            raise ValueError(f"root cause {f.root_cause_id} must be a finding with no root of its own")

    ordered = order_findings(work)
    remap = {f.finding_id: f"F-{n:03d}" for n, f in enumerate(ordered, 1)}
    for f in ordered:
        f.root_cause_id = remap[f.root_cause_id] if f.root_cause_id else None
        f.finding_id = remap[f.finding_id]
        if run_id:
            f.run_id = run_id

    by_new = {f.finding_id: f for f in ordered}
    pointing = {}
    for f in ordered:
        if f.root_cause_id:
            pointing.setdefault(f.root_cause_id, []).append(f)
    for root_id, deps in pointing.items():
        root = by_new[root_id]
        # commas inside the brackets, so the "and" joining the findings stays readable
        labels = [f"{d.finding_id} ({', '.join(table_refs(d.output_file) or [d.output_file])})"
                  for d in deps]
        level = "dataset-level " if not table_refs(root.output_file) else ""
        word = "finding" if len(labels) == 1 else "findings"
        root.what_is_wrong = _add_sentence(
            root.what_is_wrong,
            f"This is the {level}cause of {word} {_join_and(labels)}.")
        for d in deps:
            d.what_is_wrong = _add_sentence(
                d.what_is_wrong, f"Root cause: see finding {root_id} against {root.output_file}.")
    return [Finding.model_validate(f.model_dump()) for f in ordered]


# ---------------------------------------------------------------------------
# Excel export - same look as the other SpecGen workbooks
# ---------------------------------------------------------------------------

_HEADER_FONT = Font(name="Arial", bold=True, size=11, color="FFFFFF")
_HEADER_FILL = PatternFill(start_color="1A3C6E", end_color="1A3C6E", fill_type="solid")
_HEADER_ALIGN = Alignment(horizontal="center", vertical="center", wrap_text=True)
_BODY_FONT = Font(name="Arial", size=10)
_BODY_ALIGN = Alignment(vertical="top", wrap_text=True)
_CENTER = Alignment(horizontal="center", vertical="top", wrap_text=True)
_BORDER = Border(left=Side(style="thin"), right=Side(style="thin"),
                 top=Side(style="thin"), bottom=Side(style="thin"))
_SEVERITY_FILL = {
    "critical": PatternFill(start_color="FFC7CE", end_color="FFC7CE", fill_type="solid"),
    "major": PatternFill(start_color="FFEB9C", end_color="FFEB9C", fill_type="solid"),
    "minor": PatternFill(start_color="E2EFDA", end_color="E2EFDA", fill_type="solid"),
}
_WIDTHS = [6, 34, 62, 78, 14, 11, 11]


def _row_numbers(items):
    """The '#' column: the finding_id itself when every finding has a distinct
    F-nnn id, so "see finding F-012" can be found in the sheet by reading the
    column - the id is printed nowhere else, and the sheet survives filtering and
    re-sorting. Falls back to 1, 2, 3 ... in export order for a list that has not
    been through finalise()."""
    nums = [_ID_RE.match(f.finding_id or "") for f in items]
    if all(nums) and len({m.group(1) for m in nums}) == len(nums):
        return [f.finding_id for f in items]
    return list(range(1, len(items) + 1))


def _write_header(ws, headers, widths):
    for ci, (h, w) in enumerate(zip(headers, widths), 1):
        c = ws.cell(row=1, column=ci, value=h)
        c.font, c.fill, c.alignment, c.border = _HEADER_FONT, _HEADER_FILL, _HEADER_ALIGN, _BORDER
        ws.column_dimensions[get_column_letter(ci)].width = w
    ws.row_dimensions[1].height = 24


def export_findings_xlsx(findings, path, run_info=None):
    """Write findings to an xlsx whose first sheet, "Findings", has exactly the
    seven columns above. Rows are ordered so a root cause sits above the findings
    that point to it (see order_findings); pass the output of finalise() so the
    '#' column matches the F-nnn ids used in the text.

    run_info (optional) adds a second sheet, "Run info", that records how the run
    was made - notably whether draft rules were used:
        {"summary": [(label, value), ...], "rules": [{"rule_id": ..., ...}, ...]}
    """
    items = order_findings(to_findings(findings))
    numbers = _row_numbers(items)

    wb = Workbook()
    ws = wb.active
    ws.title = "Findings"
    _write_header(ws, COLUMNS, _WIDTHS)
    for r, (num, f) in enumerate(zip(numbers, items), start=2):
        values = [num, f.output_file, f.what_is_wrong, f.evidence, f.source_ref,
                  f.severity.capitalize(), f.decision.capitalize()]
        for ci, v in enumerate(values, 1):
            c = ws.cell(row=r, column=ci, value=v)
            c.font, c.border = _BODY_FONT, _BORDER
            c.alignment = _CENTER if ci in (1, 5, 6, 7) else _BODY_ALIGN
        ws.cell(row=r, column=6).fill = _SEVERITY_FILL[f.severity]
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(COLUMNS))}{len(items) + 1}"

    if run_info:
        _write_run_info(wb.create_sheet("Run info"), run_info)
    wb.save(path)
    return path


def _write_run_info(ws, run_info):
    row = 1
    for label, value in run_info.get("summary", []):
        a = ws.cell(row=row, column=1, value=label)
        b = ws.cell(row=row, column=2, value=value)
        a.font, b.font = Font(name="Arial", bold=True, size=10), _BODY_FONT
        b.alignment = Alignment(wrap_text=True, vertical="top")
        row += 1
    rules = run_info.get("rules", [])
    if rules:
        row += 1
        headers = ["Rule", "Version", "Status", "Check", "SAP ref", "Result"]
        for ci, h in enumerate(headers, 1):
            c = ws.cell(row=row, column=ci, value=h)
            c.font, c.fill, c.alignment, c.border = _HEADER_FONT, _HEADER_FILL, _HEADER_ALIGN, _BORDER
        for r in rules:
            row += 1
            for ci, key in enumerate(["rule_id", "version", "status", "check", "sap_ref", "result"], 1):
                c = ws.cell(row=row, column=ci, value=r.get(key))
                c.font, c.border, c.alignment = _BODY_FONT, _BORDER, _BODY_ALIGN
    for ci, w in enumerate([24, 60, 10, 26, 12, 60], 1):
        ws.column_dimensions[get_column_letter(ci)].width = w


def read_findings_xlsx(path):
    """Read the "Findings" sheet back as a list of dicts keyed by the seven
    column headers. Raises ValueError if the header row is not exactly them."""
    wb = load_workbook(path)
    ws = wb["Findings"]
    headers = [c.value for c in ws[1]]
    if headers != COLUMNS:
        raise ValueError(f"unexpected columns {headers}; expected {COLUMNS}")
    rows = []
    for values in ws.iter_rows(min_row=2, values_only=True):
        if any(v is not None for v in values):
            rows.append(dict(zip(COLUMNS, values)))
    return rows
