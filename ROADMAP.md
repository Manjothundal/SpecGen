# SAS Program Generator

Offline-first tool that generates and updates SAS programs
(SDTM, ADaM, TLF) from specifications, aCRF, SAP, and mock shells.

## Architecture
- Writer agent: local LLM via Ollama (offline)
- Reviewer agent: Claude API (optional, toggle on/off)
- Part 11-ready design: audit trail, human sign-off, versioned inputs/outputs

## Phases
- [x] Phase 0: Setup (VS Code, Git, project folder)
- [x] Phase 1: Spec parser (Excel -> Python)
- [x] Phase 2: Prompt builder (one variable -> instruction)
- [x] Phase 3: Generator (first ADSL program)
- [ ] Phase 4: Validation + Ollama swap
      - Fix known issues: multi-record merge, hallucinated variables, Format not passed
      - Style rules in prompt (explicit vs compact knob)
      - Reviewer agent: check code against known-variable list
      - Run log / audit file (runlog.csv)
- [ ] Phase 4.5: Macro catalog (RAG) - reuse company macro library
- [ ] Phase 5: SDTM from aCRF, TLF from SAP + mock shells
- [ ] Phase 6: Update mode (spec diff -> code patch)
- [ ] Phase 7: Draft spec generation (aCRF + protocol + SAP -> proposed spec, human-completed)

## Later ideas
- Log checker: parse SAS .log, flag ERRORs/WARNINGs/notes, suggest fixes
- QC mode: generate independent verification code + PROC COMPARE harness
- Define.xml support: read specs from define.xml; later write draft define.xml
- P21 awareness: prompt rules to avoid common Pinnacle 21 findings
- Simple local UI: file picker, generate button, approve/reject preview
- R output mode: same spec, generate R instead of SAS
- Package as Windows .exe
- Multi-agent toggle: offline Writer only vs Writer + cloud Reviewer