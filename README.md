# SpecGen

An offline-first AI tool that generates clinical statistical programs (SAS,
with R planned) from study documents — specifications, aCRF, SAP, and TLF mock
shells — and verifies the outputs. Built by a clinical statistical programmer,
for clinical statistical programmers.

## What it does

- **Generate** — reads an ADaM specification and writes the program: structural
  code (pre-steps, merges) built deterministically by the harness; derivation
  logic drafted by an LLM
- **Improve** — a principal-programmer AI pass rewrites drafts to sign-off
  quality
- **Review** — a QC agent checks every block against the known-variable list;
  failures become visible flags, never silent edits
- **Update** — diffs spec versions and patches existing programs (the
  amendment workflow), surgically updating only the touched blocks
- **Verify** — compares rendered TLF outputs (PDF/Word/RTF) against each
  other or against a mock shell, section-by-section, not page-number based
- **Reuse** — embedding-based retrieval (Chroma) over the company macro
  library, so generated code calls validated macros before writing new logic
- **QC** — an independent double-programming pass re-derives ADSL from the
  same spec and reconciles it against production via PROC COMPARE

## Three modes, one codebase

| Mode | Writer | Improver / Reviewer | Trade-off |
|------|--------|---------------------|-----------|
| Offline | local LLM (Ollama) | local | Nothing leaves the machine; rough drafts |
| Hybrid | local LLM | Claude API | Drafts stay local; senior-quality rewrite via API |
| API | Claude API | Claude API | Best quality; spec content sent to the API |

Configured in `config.py`. The mode and every model used are recorded per run.

## How a variable is built

1. **Parse** — the spec's Variables sheet is read (pandas); each variable is
   routed by its Source: straight copy, main-step derivation, or a domain
   pre-step
2. **Pre-steps** — multi-row SDTM domains are collapsed to one row per subject
   by the harness, not the model: EX (summarize), SUPPDM (transpose),
   SE (select). Structure is deterministic; only logic goes to the LLM
3. **Draft → Improve → QC** — each derivation travels the agent pipeline for
   the current mode
4. **Assemble** — blocks are stitched in spec order into one program with
   header, merge, and keep list

## Part 11-ready by design

Every run appends to `runlog.csv`: timestamp, spec, mode, models, output.
Inputs and outputs are Git-versioned. Generated code is a draft until a human
reviews it — the QC flags exist to direct that review, not replace it.

## Status

Working today: spec parsing with domain routing, EX/SUPPDM/SE pre-steps,
three-agent generation (local draft, API improve, API review) — the
patch/insert path's Writer->Improver->Reviewer chain runs as a LangGraph
state graph — full ADSL output, run logging, Chroma-backed macro retrieval,
CI (GitHub Actions), Docker image (deployable to AWS App Runner or EC2 —
see `aws/`, not deployed by default), SDTM's real 3-mode pipeline, a SAS
log checker, independent double-programming QC for ADSL, and Compare &
verify (deterministic PDF/Word/RTF diffing and mock-shell validation —
standalone tools at `/tools/log-check` and `/tools/compare`), a data-driven
SDTM automapper (raw data -> proposed SDTM mappings, no spec needed —
`/tools/sdtm-automap`), spec-driven ADaM BDS generation (ADVS/ADLB/ADAE/
ADCM/ADEFF), and a desktop app window (`desktop_app.py` — same Flask app,
opened in a native OS window instead of a browser tab).
In progress: run-log model recording, fuller-spec testing.
Planned: draft spec generation from aCRF/SAP, define.xml support, a fully
standalone (no Python required) .exe build.
See [ROADMAP.md](ROADMAP.md).

## Tech

Python 3.13 · pandas / openpyxl · Anthropic API · Ollama (qwen2.5-coder) ·
LangGraph (agent pipeline) · Chroma (macro catalog retrieval) ·
pdfplumber / python-docx / striprtf (output parsing) · pyreadstat (SAS7BDAT) ·
pywebview (desktop window) · Docker · GitHub Actions · Git

## Note

This is a personal learning and portfolio project. All specifications and data
in this repo are synthetic. Generated code is always a draft requiring review
by a qualified programmer.