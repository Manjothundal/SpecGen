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
- [ ] Phase 3: Generator (first ADSL program)
- [ ] Phase 4: Validation + Ollama swap
- [ ] Phase 5: SDTM from aCRF, TLF from SAP + mock shells
- [ ] Phase 6: Update mode (spec diff -> code patch)

## Later ideas
- Package as Windows .exe
- Publish on GitHub portfolio