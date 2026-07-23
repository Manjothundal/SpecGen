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
- **Update** (planned) — diffs spec versions and patches existing programs
  (the amendment workflow)
- **Verify** (planned) — compares TLF outputs (RTF/Word/PDF) against QC
  outputs and mock shells, with a difference summary and drill-down
- **Reuse** (planned) — agentic RAG over the company macro library, so
  generated code calls validated macros before writing new logic

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
three-agent generation (local draft, API improve, API review), full ADSL
output, run logging.
In progress: run-log model recording, fuller-spec testing, macro catalog (RAG).
Planned: R output (admiral-style), update mode, TLF comparison module, draft
spec generation from aCRF/SAP.
See [ROADMAP.md](ROADMAP.md).

## Tech

Python 3.13 · pandas / openpyxl · Anthropic API · Ollama (qwen2.5-coder) · Git

## Note

This is a personal learning and portfolio project. All specifications and data
in this repo are synthetic. Generated code is always a draft requiring review
by a qualified programmer.