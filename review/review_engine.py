"""review_engine.py - run a review: load -> run checks -> findings -> xlsx.

    python -m review.review_engine --datasets <folder> --outputs <folder> \\
        --rules data/review_rules.csv --out findings.xlsx [--include-drafts]

Rules. By default only APPROVED rules run. Approval is a decision a person makes;
nothing in this tool approves a rule. --include-drafts lets a trial run use draft
rules as well; the run is then labelled as such on the "Run info" sheet and in the
console, so a sheet made from draft rules cannot be mistaken for an approved review.

A rule whose check cannot look (dataset or variable missing, param missing) is
SKIPPED and listed - it is never turned into a finding and never counted as a pass.
A rule with no check function is text-only and is not run.

Root causes. A dataset-level rule can declare, in its params, which other checks'
findings it is the cause of:  "root_cause_of": ["check_percentages", ...]. An
output finding from one of those checks is linked to the dataset finding when the
table it is raised against names that dataset in its "Source:" footnote. The link
is written into the text of both findings (see review.findings); the first
matching root, by rule id, wins. No rule, no link.

This piece runs the deterministic checks only. The model pass is added later.
"""

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime

from review import rules_store
from review.checks import CHECKS, CheckInputError
from review.dataset_reader import read_datasets
from review.findings import (Finding, SEVERITIES, dedupe, export_findings_xlsx, finalise,
                             table_refs)
from review.output_reader import read_outputs

_DATASET_TOKEN = re.compile(r"^([A-Z][A-Z0-9_]*)(?=$|\.| )")


class ReviewError(Exception):
    """The run cannot start (bad folder, no usable rules). Printed, not a crash."""


@dataclass
class ReviewResult:
    run_id: str
    findings: list
    rule_results: list
    used_drafts: bool
    links: int
    run_info: dict = field(default_factory=dict)

    @property
    def skipped(self):
        return [r for r in self.rule_results if r["result"].startswith("SKIPPED")]


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

def select_rules(rules_path, include_drafts=False):
    """Approved rules only, unless include_drafts (then the latest version of
    every rule, whatever its status)."""
    history = rules_store.load_history(rules_path)
    if not history:
        raise ReviewError(f"no rules found in {rules_path}")
    rules = (rules_store.load_rules(rules_path) if include_drafts
             else rules_store.load_rules(rules_path, status="approved"))
    if not rules:
        n = len({r["rule_id"] for r in history})
        raise ReviewError(
            f"{rules_path} has {n} rule(s) but none is approved. A rule is approved by a person, "
            f"not by this tool. Approve rules before a real review, or pass --include-drafts "
            f"for a trial run (the output will say the rules were drafts).")
    return rules


# ---------------------------------------------------------------------------
# Naming and linking
# ---------------------------------------------------------------------------

def _dataset_token(output_file, names):
    """'ADAE' from 'ADAE' or 'ADPC.AVAL' (a dataset-level finding); else None."""
    m = _DATASET_TOKEN.match(output_file or "")
    return m.group(1) if m and m.group(1) in names and not table_refs(output_file) else None


def _name_dataset_files(findings, profiles):
    """'ADAE' -> 'ADAE (adae.xpt)', like tables are named 'Table 14.1.1 (t_14_1_1.rtf)'."""
    for f in findings:
        ds = _dataset_token(f.output_file, profiles)
        if ds:
            f.output_file = f"{f.output_file} ({os.path.basename(profiles[ds]['path'])})"


def _sources_by_table(outputs):
    """{'Table 14.1.1': {'ADSL'}, ...} from each table's 'Source: ADSL, ADAE.' footnote."""
    sources = {}
    for o in outputs:
        if not o["table_id"]:
            continue
        key = f"{o['kind'].capitalize()} {o['table_id']}"
        for line in o["footnotes"]:
            m = re.search(r"Source:\s*([^.]*)", line)
            if m:
                sources.setdefault(key, set()).update(re.findall(r"\b[A-Z][A-Z0-9_]{1,7}\b", m.group(1)))
    return sources


def link_root_causes(findings, rules_by_id, outputs, dataset_names):
    """Set root_cause_id on output findings caused by a dataset-level finding (see
    module docstring). Findings need finding_ids (temporary ones are fine). Changes
    the findings in place; returns the number of links made."""
    sources = _sources_by_table(outputs)
    roots = sorted((f for f in findings
                    if f.root_cause_id is None and _dataset_token(f.output_file, dataset_names)),
                   key=lambda f: (f.rule_id or "", f.output_file))
    made = 0
    for root in roots:
        explained = ((rules_by_id.get(root.rule_id) or {}).get("params") or {}).get("root_cause_of") or []
        if not explained:
            continue
        ds = _dataset_token(root.output_file, dataset_names)
        for f in findings:
            check = (rules_by_id.get(f.rule_id) or {}).get("check")
            if (f is root or f.root_cause_id is not None or check not in explained
                    or not any(ds in sources.get(t, ()) for t in table_refs(f.output_file))):
                continue
            f.root_cause_id = root.finding_id
            made += 1
    return made


# ---------------------------------------------------------------------------
# The run
# ---------------------------------------------------------------------------

def run_review(datasets_dir, outputs_dir, rules_path, include_drafts=False, run_id=None, now=None):
    """Run every selected rule's check and return a ReviewResult with finalised
    findings (ordered, numbered F-001..., root causes linked)."""
    for label, folder in (("datasets", datasets_dir), ("outputs", outputs_dir)):
        if not os.path.isdir(folder):
            raise ReviewError(f"{label} folder not found: {folder}")
    now = now or datetime.now()
    run_id = run_id or f"RUN-{now:%Y%m%d-%H%M%S}"

    rules = select_rules(rules_path, include_drafts)
    try:
        loaded = read_datasets(datasets_dir)
    except ValueError as exc:
        raise ReviewError(str(exc)) from exc
    datasets = {n: df for n, (df, _) in loaded.items()}
    profiles = {n: p for n, (_, p) in loaded.items()}
    outputs = read_outputs(outputs_dir)
    ctx = {"profiles": profiles}

    raw, results = [], []
    for rule in rules:
        entry = {k: rule[k] for k in ("rule_id", "version", "status", "check", "sap_ref")}
        if not rule["check"]:
            entry["result"] = "not run: text-only rule (no check function)"
        elif rule["check"] not in CHECKS:
            entry["result"] = f"SKIPPED: no check function named {rule['check']!r}"
        else:
            try:
                found = CHECKS[rule["check"]](datasets, outputs, rule, ctx)
                raw.extend(found)
                entry["result"] = f"{len(found)} finding(s)" if found else "no findings"
            except CheckInputError as exc:
                entry["result"] = f"SKIPPED: {exc}"
        results.append(entry)

    findings = [Finding.model_validate(d) for d in raw]
    _name_dataset_files(findings, profiles)
    findings = dedupe(findings)
    for i, f in enumerate(findings, 1):
        f.finding_id = f"tmp-{i}"
    rules_by_id = {r["rule_id"]: r for r in rules}
    links = link_root_causes(findings, rules_by_id, outputs, set(datasets))
    findings = finalise(findings, run_id=run_id)

    n_draft = sum(1 for r in rules if r["status"] == "draft")
    result = ReviewResult(run_id, findings, results, n_draft > 0, links)
    result.run_info = _run_info(result, rules, rules_path, include_drafts, datasets_dir, outputs_dir,
                                sorted(datasets), outputs, now, n_draft)
    return result


def _run_info(result, rules, rules_path, include_drafts, datasets_dir, outputs_dir, ds_names, outputs, now, n_draft):
    by_sev = {s: sum(1 for f in result.findings if f.severity == s) for s in SEVERITIES}
    tables = [f"{o['kind'].capitalize()} {o['table_id']}" for o in outputs if o["table_id"]]
    summary = [
        ("Run ID", result.run_id),
        ("Run time", now.isoformat(timespec="seconds")),
        ("Rules file", rules_path),
        ("Rules used", f"{len(rules)} ({n_draft} draft, {len(rules) - n_draft} approved)"),
        ("Draft rules", ("INCLUDED (--include-drafts): this is a trial run, not a review against approved rules"
                         if result.used_drafts else "none - approved rules only")),
        ("Datasets read", f"{', '.join(ds_names) or 'none'}  ({datasets_dir})"),
        ("Outputs read", f"{len(outputs)}: {', '.join(tables) or 'none'}  ({outputs_dir})"),
        ("Findings", f"{len(result.findings)} ({by_sev['critical']} critical, {by_sev['major']} major, "
                     f"{by_sev['minor']} minor)"),
        ("Rules skipped", str(len(result.skipped))),
        ("Root causes linked", str(result.links)),
        ("Model pass", "not run"),
    ]
    return {"summary": summary, "rules": result.rule_results}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _print_summary(result, out_path, rules_path):
    print(f"SpecGen review {result.run_id}")
    print(f"Rules file: {rules_path}")
    if result.used_drafts:
        print("*** DRAFT RULES INCLUDED (--include-drafts): trial run, not an approved review. ***")
    for r in result.rule_results:
        print(f"  {r['rule_id']} v{r['version']} [{r['status']}] {r['check'] or '(text-only)'}: {r['result']}")
    by_sev = {s: sum(1 for f in result.findings if f.severity == s) for s in SEVERITIES}
    print(f"Findings: {len(result.findings)} ({by_sev['critical']} critical, {by_sev['major']} major, "
          f"{by_sev['minor']} minor); root causes linked: {result.links}")
    if result.skipped:
        print(f"WARNING: {len(result.skipped)} rule(s) were skipped and did NOT check anything.")
    print(f"Wrote {out_path}")


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(prog="python -m review.review_engine",
                                 description="Check a study package: rules vs datasets vs outputs.")
    ap.add_argument("--datasets", required=True, help="folder of .xpt / .sas7bdat files")
    ap.add_argument("--outputs", required=True, help="folder of RTF / DOCX / PDF outputs")
    ap.add_argument("--rules", default=rules_store.DEFAULT_PATH, help="rules CSV (default: data/review_rules.csv)")
    ap.add_argument("--out", default="findings.xlsx", help="findings workbook to write")
    ap.add_argument("--include-drafts", action="store_true",
                    help="also run draft rules (default: approved rules only)")
    ap.add_argument("--run-id", default=None, help="label for this run (default: RUN-<timestamp>)")
    args = ap.parse_args(argv)

    try:
        result = run_review(args.datasets, args.outputs, args.rules, args.include_drafts, args.run_id)
    except ReviewError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    export_findings_xlsx(result.findings, args.out, run_info=result.run_info)
    _print_summary(result, args.out, args.rules)
    return 0


if __name__ == "__main__":
    sys.exit(main())
