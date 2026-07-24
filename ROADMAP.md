# SpecGen

Offline-first AI tool that generates clinical statistical programs
(SAS today, R planned) from specifications, aCRF, SAP, and mock shells —
and verifies the outputs.

## Architecture
- Writer agent: local LLM via Ollama (qwen2.5-coder 7b / 14b) or Claude API
- Improver agent: Claude API — principal-programmer rewrite of the draft
- Reviewer agent: QC pass against the known-variable list
- Three modes (config.py): Offline, Hybrid, API — one codebase
- Part 11-ready: audit trail, human sign-off, versioned inputs/outputs

## Phases
- [x] Phase 0: Setup (VS Code, Git, project folder)
- [x] Phase 1: Spec parser (Excel -> Python)
- [x] Phase 2: Prompt builder (one variable -> instruction)
- [x] Phase 3: Generator (first ADSL program)
- [x] Phase 4: Validation, offline mode, and three-agent pipeline
      - Style rules + anti-hallucination rules in prompt; Format passthrough
      - Domain pre-steps: EX (summarize), SUPPDM (transpose), SE (select)
      - Reviewer agent QC pass on generated blocks
      - Improver agent (principal programmer) rewrites drafts to sign-off quality
      - Local Writer via Ollama (qwen2.5-coder 7b / 14b tested)
      - config.py: independent Writer / Reviewer settings, three named modes
      - Run log (runlog.csv) records mode, all three models, timestamps
- [ ] Phase 4.5: Agentic RAG on the macro library
      - [x] Phase 4.5a: Macro catalog + plain retrieval (variable-level, 15 variables covered)
      - [x] Phase 4.5b: Agentic retrieval — Claude queries the catalog as a tool
- [ ] Phase 5: Hard inputs — SDTM from aCRF, TLF from SAP + mock shells
- [ ] Phase 6: Update mode (spec diff -> code patch; regenerate vs change-note TBD)
- [ ] Phase 7: Draft spec generation (aCRF + protocol + SAP -> proposed spec)
- [ ] Phase 8: R output alongside SAS (admiral-style pipelines; language toggle)
- [ ] Phase 9: Compare & verify module
      - Output-to-output comparison: RTF, Word, PDF; full vs cut
      - Content-block alignment (not page-number based)
      - Output-to-mock-shell validation
      - Deterministic parsing and diffing (no AI in this module)
      - Findings written to the audit trail

## Open items (near-term)
- Test against a fuller, realistic ADSL spec (60-100+ variables)
- Fix any items surfaced by that test (informats, TRT01A edge cases)
- README + GitHub rename to `specgen`

## Later ideas
- Simple local UI (see docs/specgen_ui_mockup.html) — desktop app with mode
  and language toggles, per-block sign-off rail, audit trail view, compare screen
- Log checker: parse SAS .log, flag ERRORs / WARNINGs / NOTEs, suggest fixes
- QC mode: generate independent verification code + PROC COMPARE harness
- Define.xml support (read specs from define.xml; later write draft define.xml)
- P21 awareness: prompt rules to avoid common Pinnacle 21 findings
- Package as Windows .exe
- Public showcase repo + private working repo (two-repo split)