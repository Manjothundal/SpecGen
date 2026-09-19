# SpecGen - Feature Spec: Review module + multi-agent chat

Drop this file in the repo at `docs/FEATURE_SPEC_review_and_chat.md` and point Claude Code at it.

## 0. Read this first (project rules)

- Repo: `github.com/Manjothundal/SpecGen`, local `C:\sas_agent_project`. Windows, Python 3.13, Anaconda, VS Code.
- Existing app: Flask (`app.py` + `templates/index.html`), 3 tabs (ADaM / SDTM / TLF), 4 screens (Spec -> Generate -> Review & sign off -> Export & audit), background jobs with Abort, Commit to Git.
- Modes: offline (Ollama `qwen2.5-coder`), hybrid, api (Claude `claude-sonnet-4-5`). Mock mode via `SPECGEN_WRITER_MODE` / `SPECGEN_REVIEWER_MODE` for CI.
- Language toggle: `config.LANGUAGE` = `sas` | `r`, plus `--lang` CLI flags.
- Part 11 posture: versioned inputs and outputs, audit trail (`runlog.py`), human sign-off on everything.
- Work rules for this feature: **one piece at a time**, full file pastes (not partial diffs), **plain hyphens only - no em-dashes** (they break Windows encoding), and each piece must run and be testable before starting the next.
- Do NOT add LangGraph to this feature. `agent_graph.py` stays where it is. This feature uses plain deterministic dispatch so the audit trail stays simple.
- Do NOT touch `docs/` (the React showcase deployed to Netlify). That is separate from the working Flask app.

## 1. What is being added

Two things, sharing one new module folder `review/`:

**A. Review module (new 4th tab "Review")**
Check a study package for disagreement between three sources:
1. the SAP (rules extracted from the document),
2. the datasets (SDTM/ADaM `.xpt` / `.sas7bdat`),
3. the outputs (RTF / Word / PDF TLFs).

Output is a findings sheet with the columns already used at work:
`# | Output/File | What is wrong | Evidence | Source ref | Severity | Decision`.

**B. Multi-agent chat box (in every tab, docked right-hand pane)**
One text box. The user types plain English; an orchestrator routes to a narrow agent; the agent returns a **proposal**, never a direct write. The user approves, edits or discards. Examples that must work:
- "the code is incorrect, TEAE should be first dose to last dose + 7 days" -> Code agent returns a patch preview + re-run result.
- "add the SUPPAE qualifiers to the AE listing" -> Data agent shows what it would merge and how many records, then asks.
- "add a rule: flag when baseline is only in Period 1" -> Rule agent drafts a rule, saved as `status=draft`.

## 2. Hard design rules

1. **Deterministic first.** Every number (counts, N, percentages, differences) is computed in Python with pandas / pyreadstat. The model never does arithmetic. The model reads documents, compares wording, classifies, and writes the explanation.
2. **Evidence or it does not exist.** A finding is dropped unless it has (a) a source reference (SAP section, protocol, or `rule_id`) and (b) data evidence (record counts or values). Enforce this in code, not in the prompt.
3. **Proposals, not writes.** Agents return a proposal object. Nothing touches disk or the database until the user approves in the UI.
4. **Narrow agents.** Each agent has its own prompt, its own tool allow-list, and a JSON output schema validated with pydantic before anything is stored. A malformed response is rejected, logged, and retried once.
5. **Mock mode must work.** Everything new runs in `SPECGEN_WRITER_MODE=mock` so CI stays free and offline.

## 3. New files

```
review/
  __init__.py
  sap_parser.py        # SAP PDF/DOCX -> structured rules
  rules_store.py       # load/save/version review rules
  dataset_reader.py    # .xpt / .sas7bdat -> pandas, metadata profile
  output_reader.py     # RTF / DOCX / PDF TLF -> title, footnotes, table grid
  checks.py            # deterministic check functions (no model calls)
  review_engine.py     # orchestrates: load -> run checks -> model pass -> findings
  findings.py          # Finding model, severity, evidence, xlsx export
agents/
  __init__.py
  schemas.py           # pydantic schemas for every agent proposal
  orchestrator.py      # intent classification + routing + role scope
  agent_code.py        # patch proposals for existing programs
  agent_data.py        # dataset questions, supplementary data merges
  agent_rule.py        # plain English -> rule draft
  agent_review.py      # run checks, write findings text
  agent_qc.py          # compare two outputs / two datasets
tests/
  test_checks.py
  test_sap_parser.py
  test_findings_export.py
  test_orchestrator.py
data/
  review_rules.csv     # the rule library (versioned, committed)
  sample_sap.pdf       # built by build_sample_sap.py
build_sample_sap.py    # reportlab, mirrors build_sample_protocol.py
```

Reuse, do not duplicate: `config.py`, `generator.py` (`generate_code` / `review_code` and mock mode), `prompt_builder.py`, `runlog.py`, `spec_patcher.locate_and_update()` for the code agent, `macro_lookup.py`.

## 4. Data shapes

### 4.1 SAP rule (from `sap_parser.py`, stored by `rules_store.py`)

```python
{
  "rule_id": "R-014",
  "scope": "adam" | "sdtm" | "tlf" | "cross",
  "topic": "teae_window",
  "description": "TEAE is onset from first dose to last dose + 7 days, per period",
  "sap_ref": "SAP 9.4",
  "severity": "critical" | "major" | "minor",
  "check": "check_teae_window",     # function name in checks.py, or None for text-only rules
  "params": {"window_days": 7},
  "status": "draft" | "approved",
  "owner": "Biostatistics",
  "version": 2,
  "created_by": "mhundal",
  "created_at": "2026-09-19T10:00:00"
}
```

`review_rules.csv` is the on-disk form. Never edit an approved rule in place - bump `version` and write a new row, keep history.

### 4.2 Finding (from `findings.py`)

```python
{
  "finding_id": "F-012",
  "run_id": "...",
  "output_file": "ADaM/adae.xpt; Table 14.3.1.1",
  "what_is_wrong": "plain English, one short paragraph",
  "evidence": "record counts and values, computed in Python",
  "source_ref": "SAP 9.4" | "rule R-014" | "protocol",
  "severity": "critical" | "major" | "minor",
  "decision": "open" | "accepted" | "rejected",
  "decided_by": None,
  "decided_at": None
}
```

Export column order must be exactly: `#`, `Output / File`, `What is wrong`, `Evidence`, `Source ref`, `Severity`, `Decision`.

### 4.3 Agent proposal (in `agents/schemas.py`)

```python
class Proposal(BaseModel):
    kind: Literal["patch", "data_merge", "rule_draft", "finding", "answer"]
    summary: str                  # one line for the chat bubble
    detail: str                   # diff text, merge plan, rule code, or the answer
    evidence: str | None          # counts / values, computed deterministically
    source_ref: str | None
    affected: list[str]           # files or datasets touched
    requires_approval: bool = True
```

## 5. Checks to implement in `checks.py` (Piece B)

All pure functions: `check_x(datasets, outputs, rule, ctx) -> list[Finding]`. No model calls, no I/O.

Start with these twelve, each with a pass fixture and a fail fixture:

1. `check_bign` - table header N vs population flag count in ADSL.
2. `check_population_filter` - population used by a table vs the SAP-stated population.
3. `check_baseline_per_period` - ABLFL present in one period only when the SAP defines baseline per period.
4. `check_teae_window` - TRTEMFL against first dose and last dose + `window_days`.
5. `check_percentages` - printed % vs recomputed n/N in an output table.
6. `check_totals` - Total column equals the sum of arms.
7. `check_soc_pt` - SOC count not lower than its largest PT count.
8. `check_label_units` - variable label claims per-mg or per-kg while values are not normalised.
9. `check_visit_windows` - AWLO/AWHI vs SAP or protocol window.
10. `check_tlf_inventory` - tables listed in the SAP vs tables delivered.
11. `check_cross_table_n` - randomised / safety N consistent across disposition, demographics, efficacy.
12. `check_ts_vs_protocol` - TS domain values vs protocol title and design.

Each returns findings with evidence strings built from real counts, for example:
`"ADAE: 212 records TRTEMFL='Y'; 9 start more than 7 days after last dose. Subjects with any TEAE in Trt B: 38 current vs 35 under SAP rule."`

## 6. Build order - one piece at a time

Do not start a piece until the previous one runs and its tests pass.

**Piece A - readers and fixtures**
- `build_sample_sap.py` writes `data/sample_sap.pdf` with numbered sections covering: populations, baseline definition per period, TEAE window, visit windows, decimal rules, statistical methods, and a table inventory. Plant three deliberate inconsistencies against the existing sample data so there is something to catch.
- `dataset_reader.py`: read `.xpt` and `.sas7bdat` via pyreadstat, return a dataframe plus a metadata profile (variable names, labels, types, record counts, distinct values for flags).
- `output_reader.py`: read RTF first (striprtf or a small parser), then DOCX (python-docx), then PDF (pdfplumber). Return per output: `table_id`, `title`, `footnotes`, `column_headers`, `rows` (list of lists), `page`.
- Test: read the existing generated TLFs and assert the grid shape and title.

**Piece B - rules and deterministic checks**
- `rules_store.py` load/save `data/review_rules.csv`, with `status` and `version` handling.
- `checks.py` with the twelve checks and fixtures.
- `tests/test_checks.py`: every check has one pass case and one fail case, using small synthetic frames built in the test file (no real study data).
- No model calls anywhere in this piece.

**Piece C - findings and Excel export**
- `findings.py` with the model, severity ordering, dedupe (same rule + same object = one finding), and `export_findings_xlsx(findings, path)` producing the exact column order in section 4.2, with header styling similar to the existing export code.
- CLI: `python -m review.review_engine --datasets <folder> --outputs <folder> --rules data/review_rules.csv --out findings.xlsx`
- Test: `tests/test_findings_export.py` round-trips a findings list to xlsx and back.

**Piece D - SAP parsing and the model pass**
- `sap_parser.py`: PDF/DOCX -> candidate rules. Use the model in `api`/`hybrid` mode to turn section text into the rule shape in 4.1; in `offline` mode fall back to regex for the obvious sections. Every extracted rule starts as `status=draft` and must carry its `sap_ref`.
- `review_engine.py` model pass: after deterministic checks, send the model (a) the SAP rule text, (b) the dataset and output **metadata plus computed summaries only - never subject-level rows**, and ask it to flag disagreements that a rule did not cover. Validate the response against the finding schema and drop anything without `source_ref` and `evidence`.
- Test: with `SPECGEN_WRITER_MODE=mock`, the engine still produces findings from the deterministic layer and the model pass is skipped cleanly.

**Piece E - Review tab in the Flask app**
- Fourth tab "Review", with the same 4-screen pattern: Inputs (pick SAP, dataset folder, output folder) -> Run checks (background job + Abort, reuse the existing job plumbing) -> Findings (table, filter by severity, Accept / Reject per row) -> Export & audit (xlsx download, Commit to Git).
- Decisions write to the audit trail via `runlog.py` (extend with `log_decision`): finding id, user, decision, timestamp, rule version, model version.
- Keep the per-otype state slice pattern already used by the ADaM / SDTM / TLF tabs.

**Piece F - agent chat pane**
- Right-hand docked pane, present on all four tabs, with the tab and current file as context.
- `POST /chat` -> `agents/orchestrator.py`:
  1. classify intent (code fix / data question / new rule / re-run review / QC compare / general question),
  2. check the intent is allowed for the current tab,
  3. call the agent, which returns a `Proposal`,
  4. store the proposal in the run state, return it to the UI.
- `POST /chat/approve` applies it: `patch` goes through `spec_patcher.locate_and_update()` so the existing preview-and-apply path is reused; `rule_draft` writes to `review_rules.csv` with `status=draft`; `data_merge` regenerates the affected block; `finding` appends to the current run.
- The chat bubble shows: agent name, one-line summary, evidence, and the buttons Approve / Edit / Discard.
- `tests/test_orchestrator.py`: intent classification in mock mode, and a test that an unapproved proposal never writes to disk.

## 7. Acceptance criteria

- `python -m review.review_engine ...` produces `findings.xlsx` with the exact column order, on the sample SAP plus the existing generated datasets and TLFs.
- The three planted inconsistencies in `sample_sap.pdf` are all caught, with correct counts in the evidence column.
- Every finding in the export has a non-empty `Source ref` and `Evidence`.
- The Review tab runs the same flow in the browser, and Accept / Reject writes to the audit log.
- In the chat pane: the three example instructions in section 1B each return a proposal with a preview, and nothing is written until Approve is pressed.
- `pytest` passes locally and in CI with `SPECGEN_WRITER_MODE=mock`.
- No em-dashes in any generated file. No subject-level data in any model prompt.

## 8. Out of scope for this feature

- Figure / image comparison in outputs (text and tables only for now).
- Real Word/RTF **shell** parsing for TLF generation (shells stay Excel).
- Multi-user login and role-based access (single user for now; design the code so a `role` argument can be added later).
- Anything in `docs/` (the Netlify showcase).
