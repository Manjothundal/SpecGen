# SAS Program Generator

An offline-first AI tool that generates clinical SAS programs (SDTM, ADaM, TLF)
from study documents: specifications, aCRF, SAP, and TLF mock shells.

Built by a clinical statistical programmer, for clinical statistical programmers.

## What it does

- **Generate** — reads an ADaM specification and writes the SAS program:
  simple copies handled by Python, derived variables drafted by an LLM
- **Update** (planned) — diffs spec versions and patches existing programs
  instead of regenerating (the amendment workflow)
- **Reuse** (planned) — indexes the company macro library so generated code
  calls validated macros before writing new code

## Example

One row of the spec:

| Variable | Type | Derivation |
|----------|------|------------|
| AGEGR1 | text (10) | If AGE < 65 then "<65"; else if 65 <= AGE <= 80 then "65-80"; else ">80" |

Generated output:

```sas
/* Derive AGEGR1: Pooled Age Group 1 */
length AGEGR1 $10;
label AGEGR1 = "Pooled Age Group 1";
if AGE < 65 then AGEGR1 = "<65";
else if 65 <= AGE <= 80 then AGEGR1 = "65-80";
else if AGE > 80 then AGEGR1 = ">80";
```

## Architecture

Spec (.xlsx) -> parser -> prompt builder -> Writer agent -> assembled .sas program
                                              |
                                    Reviewer agent (optional QC)

- **Writer agent**: drafts code. Currently Claude API; moving to a local LLM
  (Ollama) so nothing leaves the machine
- **Reviewer agent**: optional cloud QC pass - a toggle, not a dependency
- **Part 11-ready design**: Git-versioned inputs/outputs, run logging,
  human sign-off before any generated code is considered final

## Status

Working today: spec parsing, prompt building, full ADSL generation via API.
In progress: correctness fixes (pre-processing steps, hallucination checks),
code style rules, offline Writer via Ollama.
See [ROADMAP.md](ROADMAP.md) for the full plan.

## Tech

Python 3.13 - pandas / openpyxl - Anthropic API - Ollama (planned) - Git

## Note

This is a personal learning and portfolio project. All specifications and data
in this repo are synthetic. Generated code is always a draft requiring review
by a qualified programmer.