## SpecGen — Claude Code Instructions for Next Features

You are continuing development on SpecGen, an offline-first AI tool that generates clinical SAS/R programs. The project is at C:\sas_agent_project\ and on GitHub at github.com/Manjothundal/SpecGen.

Read ROADMAP.md for full phase history. Read the existing code before modifying anything.

### What's already built (don't rebuild these):
- spec_parser.py, assembler.py, prompt_builder.py, generator.py, config.py — ADaM ADSL pipeline
- acrf_parser.py — parses aCRF PDFs, extracts SDTM annotations by color
- sdtm_spec_builder.py — builds SDTM spec from aCRF metadata with structural vars
- sdtm_assembler.py — generates SAS programs for 18 SDTM domains (DM, AE, VS, CM, DS, MH, DV, EG, EX, TU, TR, RS + 6 SUPP)
- protocol_parser.py — extracts trial design (TA, TE, TV, TI, TS) from protocol PDFs
- spec_differ.py, spec_patcher.py — amendment handling
- macro_lookup.py, macro_catalog.csv, macros/ — macro catalog with RAG
- generator.py uses generate_api() and generate_local(); max_tokens=8192; config.py has WRITER/REVIEWER/LOCAL_MODEL/API_MODEL

### Build these two new features:

---

### Feature 1: Data-Driven SDTM Automapper (sdtm_automapper.py)

Purpose: Generate SDTM spec and programs directly from raw clinical data — no spec needed. The user drops in raw SAS/CSV datasets and the tool figures out the SDTM mappings.

What it should do:
1. Read raw datasets from a folder (SAS7BDAT or CSV files)
2. For each dataset, extract metadata: variable names, types, labels, sample values (first 10 rows), formats
3. Send metadata to Claude API with a prompt like: "You are a CDISC SDTM expert. Given this raw clinical dataset metadata, classify which SDTM domain(s) these variables map to, and propose source-to-target variable mappings."
4. Claude returns JSON: [{source_var, sdtm_domain, sdtm_var, mapping_logic, confidence}]
5. Write proposed mappings to sdtm_automap.xlsx for human review (columns: Source Dataset, Source Variable, Source Label, Sample Values, SDTM Domain, SDTM Variable, Mapping Logic, Confidence, Review Status)
6. After review, feed the approved mappings into sdtm_spec_builder.py and sdtm_assembler.py to generate programs

CLI usage:
  python sdtm_automapper.py raw_data/ --output sdtm_automap.xlsx
  python sdtm_automapper.py raw_data/ --output sdtm_automap.xlsx --offline

Key design decisions:
- Read SAS7BDAT files using pyreadstat (pip install pyreadstat)
- Read CSV files using pandas
- Group source variables by likely domain before sending to Claude (send per-dataset, not all at once)
- Include sample values in the prompt so Claude can infer types (dates vs text vs numeric)
- Confidence scores: High (>90%), Medium (70-90%), Low (<70%) — flag low-confidence for human attention
- The output xlsx should be compatible as input to sdtm_spec_builder.py after review

Do NOT modify existing files. Create sdtm_automapper.py as a new standalone module.

---

### Feature 2: ADaM BDS Generator (adam_bds_assembler.py)

Purpose: Generate ADaM BDS datasets (ADAE, ADVS, ADLB, ADCM, ADEFF) from three inputs:
1. SDTM datasets (the source data)
2. ADaM spec (derivation rules — Excel like existing adam_spec.xlsx but for BDS)
3. Mock shells (TLF requirements — Excel/Word files that define which PARAMCDs, analysis flags, visit windows, and summary statistics are needed)

What it should do:
1. Read SDTM dataset metadata (from sdtm_spec_draft.xlsx or actual SDTM datasets)
2. Read ADaM BDS spec (Excel with columns: Dataset, Variable, Label, Type, Length, Source, Derivation)
3. Read mock shells — parse the mock TLF Excel files to extract:
   - Which PARAMCDs are needed (e.g. SYSBP, DIABP, HR for ADVS)
   - Which analysis flags (ANL01FL, ANL02FL) and their conditions
   - Which visit windows (AVISIT, AVISITN mappings)
   - Which summary statistics (n, mean, SD, median, min, max)
   - Baseline definition (which visit is baseline)
4. Build domain-class-aware prompts for BDS datasets:
   - ADAE: one record per AE per subject, treatment-emergent flag, severity grades
   - ADVS: one record per parameter per visit per subject, BASE, CHG, PCHG, AVAL, shift tables
   - ADLB: same as ADVS but for labs, with ANRLO/ANRHI for normal ranges
   - ADCM: one record per med per subject, ATC classification, prior/concomitant flags
5. Send through the existing three-agent pipeline (generate_api → improve → review_sas)
6. Output SAS programs to adam_programs/ folder
7. Log to runlog.csv

CLI usage:
  python adam_bds_assembler.py adam_bds_spec.xlsx --sdtm sdtm_spec_draft.xlsx --shells mock_shells/ --output adam_programs/
  python adam_bds_assembler.py adam_bds_spec.xlsx --dataset ADVS --output adam_programs/

Also create:
- build_sample_adam_bds_spec.py — generates a sample ADaM BDS spec for ADVS and ADAE (like build_sample_acrf.py does for aCRF)
- build_sample_shell.py — generates sample mock shell Excel files (demographics table, AE summary, VS shift table) that adam_bds_assembler.py can read

Key BDS variables to handle:
  ADAE: TRTEMFL, AESEV, AESEVN, AESER, AEREL, AEBODSYS, AEDECOD, ASTDT, AENDT, ASTDY, AENDY
  ADVS: PARAMCD, PARAM, PARAMN, AVAL, AVALU, BASE, CHG, PCHG, ABLFL, ANL01FL, AVISIT, AVISITN, DTYPE, ATPT, ATPTN
  ADLB: same as ADVS + ANRLO, ANRHI, ANRIND, LBSTNRLO, LBSTNRHI, SHIFT1
  ADCM: CMTRT, CMDECOD, CMCLAS, ASTDT, AENDT, ONTRTFL, PREFL, CONFL

Do NOT modify existing files. Create new modules only.

---

### General rules:
- Use the existing generator.py (generate_api, generate_local) and config.py — don't rebuild the LLM layer
- Use openpyxl for Excel read/write
- Follow the same code style as existing files (docstrings, clear comments, CLI with argparse)
- Add --offline flag for Ollama-only mode on all new modules
- Test with sample data before marking complete
- Commit after each feature works: git add, git commit, git push
- Plain English in comments, no tutorial-speak
