# SpecGen

Offline-first AI tool that generates clinical statistical programs
(SAS or R) from specifications, aCRF, SAP, and mock shells — and verifies
the outputs.

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
- [x] Phase 4.5: Agentic RAG on the macro library
      - [x] Phase 4.5a: Macro catalog + plain retrieval (variable-level, 15 variables covered)
      - [x] Phase 4.5b: Agentic retrieval — Claude queries the catalog as a tool
- [x] Phase 5: SDTM + TLF generation
      - [x] 5a: aCRF parser (PDF/Word annotations → structured domain/variable metadata) — acrf_parser.py
      - [x] 5b: Draft SDTM spec from aCRF metadata (human reviews and completes before pipeline) — sdtm_spec_builder.py
      - [x] 5c: SDTM program generation from approved spec (new multi-row assembly mode) — sdtm_assembler.py, sdtm_programs/
            SUPP-- domains (SUPPAE/SUPPCM/SUPPDM/SUPPEG/SUPPRS/SUPPVS) used to be
            written as their own standalone program (suppae.sas, etc.) — a
            separate SDTM "domain" in the code, but not a separate program in most
            real SOPs, since it's a supplemental-qualifier view of the SAME
            dataset built from the same source pull as its parent. Now
            append_supp_domain() appends each SUPP-- domain's generated code into
            its parent's own .sas file (e.g. SUPPAE lives inside ae.sas) instead
            of writing suppae.sas; idempotency (skip-if-exists) now checks for the
            SUPP domain's BEGIN/END marker inside the parent file rather than a
            separate file's existence. Existing standalone SUPP files were merged
            into their parents and removed (no regeneration needed — same content,
            just relocated).
            SDTM generation gained a real R path: every prompt builder (DM, Events,
            Interventions, Findings, Findings About Events, SUPP) now has an R
            (tidyverse) variant alongside its SAS one, selected via a new --lang
            flag (generate_domain_program/generate_single_domain/append_supp_domain/
            generate_all_domains all thread language through); assemble_program's
            header/footer differ by language (R gets no libname/proc steps); the
            Improver prompt is language-aware too. app.py passes --lang through and
            reads back .R files; the web UI's Language toggle is no longer
            disabled for SDTM. Verified: Offline mode produces correctly-structured
            (if rough, as expected for the local model) R; API mode produces
            genuinely good tidyverse code (proper left_join/mutate/if_else/select,
            correct row_number()-based --SEQ derivation).
            SDTM generation was slow even in API mode — measured ~66s/domain average
            (20-143s range) across real runs, because each domain is 3 sequential
            API round-trips (Writer drafts the whole program, Improver re-sends the
            entire draft for a rewrite, Reviewer re-sends it again for a verdict)
            generating/reviewing 100-300+ lines each time, and domains were
            processed one at a time in a plain loop despite not depending on each
            other. generate_all_domains now runs each phase (standard domains, then
            SUPP domains) through a ThreadPoolExecutor — up to --workers (default 5)
            domains generating concurrently instead of strictly sequentially; only
            SUPP domains still wait for the standard-domain phase to finish (their
            parent file must exist first). log_run()'s shared CSV write is now
            lock-guarded against concurrent-write corruption. Verified: 5 domains
            that would take ~330s sequential (5 x 66s avg) completed in 75.8s with
            5 workers — about 4.3x faster, close to the theoretical 5x ceiling.
      - [x] 5d: TLF from SAP + mock shells — tlf_assembler.py, tlf_programs/ (demographics 14.1.1, AE summary 14.3.1)
- [x] Phase 6: Update mode — CORE WORKING (differ + marker-based patcher)
      - spec_differ.py: v1 vs v2 comparison (new / changed / deleted / unchanged)
      - spec_patcher.py: replaces changed blocks via BEGIN/END markers, appends new, rebuilds keep
      - Open: log patch runs to runlog.csv; update catalog params instead of bypassing; em-dash encoding fix
- [ ] Phase 7: Draft spec generation (aCRF + protocol + SAP -> proposed spec)
- [x] Phase 8: R output alongside SAS (admiral-style pipelines; language toggle)
      - [x] ADaM BDS (ADVS/ADLB/ADEG/ADTR/ADAE/ADCM/ADRS/ADTTE) — bds_assembler.py, full parity via --lang
      - [x] TLF (demographics, AE summary) — tlf_assembler.py
      - [x] ADSL core Writer/Improver/Reviewer pipeline — generator.py/prompt_builder.py/
            improver.py/reviewer.py/assembler.py ported (language="sas"|"r"); spec_parser.py
            given a --lang flag to match. Ran end-to-end against adam_spec_full.xlsx (Hybrid
            mode: local Writer, API Improver/Reviewer) -> adsl.R, 20 variables.
            Found and fixed during validation:
              - assembler.py bug: when the Writer produced only comments for a variable
                (no code), the assembler emitted a bare "," instead of the column — invalid
                mutate() call and a missing column at the final select(). Now emits a typed
                NA stub instead.
              - 5 of 20 generated blocks needed a hand QC pass after the Reviewer's own
                pass (RACEN used ARM instead of RACE; DTHDT/RFICDT/DTHDY mixed Date and
                NA_real_ types in case_when — R's case_when requires one type per branch,
                unlike SAS; EOSDY referenced a nonexistent EXDTC column; DTHDY also mapped
                pre-treatment deaths to NA instead of the correct negative day count).
                Expected per the three-agent model — the Reviewer flags, a human fixes —
                but confirms R output needs the same sign-off scrutiny as SAS, not less.
- [ ] Phase 9: Compare & verify module
      - Output-to-output comparison: RTF, Word, PDF; full vs cut
      - Content-block alignment (not page-number based)
      - Output-to-mock-shell validation
      - Deterministic parsing and diffing (no AI in this module)
      - Findings written to the audit trail
- [x] Phase 10: Web app (Flask UI) — app.py, templates/index.html
      - [x] Piece 1: skeleton — generates ADVS (SAS/R) in the browser
      - [x] Piece 2: Output dropdown (SDTM / ADaM / TLF) + language toggle, generates the
            full set per output type, collapsible per-file view
      - [x] Piece 3: file upload — one optional upload field, meaning changes with the
            Output dropdown (ACRF metadata for ADaM, SDTM spec for SDTM, shell(s) for TLF,
            multi-select for TLF); falls back to the sample inputs when nothing is
            uploaded. Verified live: index page renders the field, ADaM/TLF/SDTM all
            generate correctly with no upload, and ADaM with an uploaded file is
            correctly picked up over the default.
            Bug found and fixed during this test: generate_sdtm() re-ran
            sdtm_assembler.py --offline on every request, regenerating ALL 19 domain
            .sas files from scratch (fresh, non-deterministic local-LLM draft each
            time) — not just the target spec's domains — silently overwriting any
            hand-QC fix in sdtm_programs/ (e.g. the ae.sas fixes from the Phase 5c
            validation pass; happened twice during testing, each a differently-broken
            draft). ADaM/TLF didn't have this problem (they regenerate deterministically
            from their inputs each time, so a fix belongs upstream in the input spec).
            Fixed at the root: sdtm_assembler.py now skips a domain whose output file
            already exists unless --force is passed (generate_single_domain/
            generate_all_domains, new --force CLI flag). app.py passes --force only when
            the request included an uploaded spec (deliberate regenerate intent); the
            no-upload default path is now idempotent. Verified: re-running with
            --domain AE,DM and no --force skipped both instantly.
      - [x] Piece 4: real 4-screen app (Spec -> Generate -> Review & sign off ->
            Export & audit), matching docs/specgen_ui_mockup (1).html's concept for
            everything except Compare & verify (Phase 9 — not started, a from-scratch
            RTF/Word/PDF diff engine, out of scope for this pass).
              - Mode switcher (Offline/Hybrid/API) now genuinely changes which model
                writes/improves/reviews ADSL and SDTM (BDS stays deterministic either
                way). Required fixing two real bugs to work at all:
                  - generator.py did `from config import WRITER, REVIEWER` — binds the
                    name at import time, so a per-request mode override would have
                    silently done nothing. Switched to `import config` + explicit
                    mode= param, same pattern as the existing language= threading.
                  - improver.py's improve_block() called generate_code() (the WRITER
                    role) instead of review_code() (the REVIEWER role) — a regression
                    from the uncommitted R-port work found and committed earlier this
                    session. In Hybrid mode this meant the "Improver" step was silently
                    running on the local model instead of Claude, contradicting the
                    README and the mockup. Confirmed the fix mattered: an ADSL run
                    against the same spec went from 4 QC-flagged variables (pre-fix,
                    validated during the Phase 8 pass above) to 0 (post-fix, this run).
              - ADaM otype merges ADSL into the same output: uploaded files are sniffed
                by sheet name ("By Domain" -> drives BDS, "Variables" -> drives ADSL);
                either, both, or neither may be present, each falling back to its own
                sample default. BDS datasets (ADVS/ADLB/ADEG/ADTR/ADAE/ADCM/ADRS/ADTTE)
                are now spec-driven — generated only for SDTM domains actually present
                in the ACRF metadata, instead of unconditionally always generating all
                8 (previously would hard-crash if VS/LB/EG/TR were missing from a
                custom upload). No more hardcoded "(8 datasets)" label.
              - Review & sign off: ADSL is parsed into its existing per-variable
                BEGIN/END blocks (no new parsing infra — those markers already existed
                for spec_differ.py/spec_patcher.py) with QC PASS/FAIL badges; BDS/SDTM/
                TLF are one block per file. Every block needs an explicit Approve
                before Export unlocks. "Send back to Improver" re-runs Writer->
                Improver->Reviewer for one flagged ADSL variable and re-splices it into
                the stored program (fresh regex offsets each time, so re-generating one
                block doesn't corrupt another edited earlier in the same run).
              - Export & audit: Export writes files to disk (locked until 100%
                approved) and reads runlog.csv for the audit table. "Commit to Git"
                stages exactly the exported files (never `git add -A`), commits, and
                pushes to origin/main for real — verified live: a real ADSL regeneration
                was approved, exported, and committed+pushed through the app itself
                (commit 18073bb).
              - State was one in-memory RUN_STATE dict — a deliberate choice given this
                is a single-operator local tool on Flask's synchronous dev server, so
                there's only ever one run in flight; no session/DB layer was worth
                adding. (Superseded by Piece 5 below — split into per-otype slices,
                still one dict, no DB.)
              - Progress is synchronous by design (click Generate, wait, see the
                finished result) — true live per-variable streaming would need a
                background job + SSE/polling, deferred as a future enhancement.
                (Generate itself became a background job in Piece 6 below, for
                Abort's sake — per-variable progress detail is still deferred.)
              - Known asymmetry: SDTM's pipeline only has a binary use_api flag (no
                true Hybrid) — the Mode switcher maps Hybrid to the same behavior as
                API for SDTM. Rearchitecting SDTM's pipeline to a real 3-mode model is
                separate future scope.
      - [x] Piece 5: ADaM/SDTM/TLF split into three independent tabs, replacing the
            single shared "Output:" dropdown from Piece 2. The shared dropdown had
            caused a real class of bugs: a stray Mode/Language form submission could
            silently revert the dropdown mid-flow (patched once with a JS sync, but
            the underlying sharing was still there to break again), and an upload for
            one otype could bleed into another if the dropdown changed without a
            fresh upload. Root fix instead of another patch: RUN_STATE is now
            `{"active_otype": ..., "otypes": {"adam": {...}, "sdtm": {...}, "tlf":
            {...}}}` — each tab has its own lang/mode/routing/programs/blocks/
            uploaded_paths/etc via a `_new_otype_state()` slice, and its own upload
            subfolder (`UPLOAD_DIR/<otype>/`) so same-named files across tabs can't
            collide. otype is no longer a form field the user can edit — every
            tab's forms carry a hardcoded hidden `otype` input, and /approve and
            /send_back recover otype from the block_key's existing `"{otype}:{name}"`
            prefix instead of a separate field, so there is no longer any path by
            which one tab's submission can act on another tab's state. Frontend:
            a Jinja `otype_tab()` macro renders each tab's full 4-screen markup
            (called once per otype) inside a `.tabpanel[data-otype]`, with a small
            top-level tab bar (`goTab()`) toggling which panel is visible; the
            per-tab step-nav JS (`go()`) is scoped to query only within the
            currently active tab's own panel, so it can't cross-toggle another
            tab's screens. The old `controlform`/`controlform-otype` JS sync hack
            from Piece 4 is gone — each tab's modebar is self-contained, so there's
            nothing left to desync. Verified: Flask-test-client isolation test
            (parse+generate SDTM, then parse ADaM, confirmed SDTM's routing/
            available_domains/mode were untouched) and a live curl smoke test of
            parse/generate against all 3 tabs on the running server.
      - [x] Piece 6: Abort button on the Generate screen. Required turning
            /generate from a blocking request into a background-thread job per
            tab (`_run_generate_job`, tracked in `_JOB_CTRL[otype]`) — a request
            handler stuck in subprocess.run()/assemble_adsl() for minutes can't
            also service a separate /abort POST meant to interrupt it, so
            /generate now just starts the thread and returns immediately
            (confirmed live: 47ms response), and the Generate screen polls
            `/job_status?otype=...` every 2s while running, reloading once the
            job leaves "running". Each otype cancels differently since only one
            of the three actually spawns an OS process:
              - SDTM: generate_sdtm switched from `subprocess.run()` to `Popen`
                so the live process handle can be stored in `_JOB_CTRL[otype]
                ["proc"]` and `.terminate()`d immediately from /abort. Also
                switched stdout/stderr from `capture_output=True` (a pipe) to a
                disk-backed `tempfile.TemporaryFile` — sdtm_assembler's per-
                variable progress printing over a multi-minute run can exceed
                the ~64KB OS pipe buffer, and an undrained Popen pipe deadlocks
                the child the moment that fills; a file never applies that
                backpressure. Found and fixed a real race during testing: since
                /abort's terminate() call comes from a different thread than
                generate_sdtm's own poll loop, `while proc.poll() is None`
                could exit (process already dead) before the loop body ever
                ran again to notice `cancel_event` was set — misreporting a
                clean abort as "sdtm_assembler failed partway through." Fixed
                by checking `cancel_event` once more after the loop
                unconditionally, not only inside it.
              - ADaM: assemble_adsl (both SAS and R paths in assembler.py) takes
                an optional `cancel_event`, checked once per variable at the
                top of the main-step loop — up to 3 model calls per variable,
                so checking between variables (not mid-call) was the natural
                granularity. Verified directly (no server involved): calling
                assemble_adsl with a pre-set cancel_event returns instantly
                with zero model calls and an "aborted before variable X"
                marker in the output.
              - TLF: generate_tlf checks cancel_event between shells — mostly
                symmetry, since BDS/TLF generation is fast deterministic string
                templates with little to abort in practice.
            Whatever finished before an abort is kept (same partial-result
            philosophy as the existing SDTM timeout handling) — the tab lands
            on the Review screen with just the completed items instead of
            nothing. Verified live end-to-end: started an SDTM run, polled
            /job_status mid-run, aborted, confirmed the tab recovered to
            job_status "aborted" with a partial-results note and no dangling
            lock (next Generate click worked immediately, not blocked).

## Open items (near-term)
- Test against a fuller, realistic ADSL spec (60-100+ variables)
- Fix any items surfaced by that test (informats, TRT01A edge cases)
- Side-effect variables (AGEGR1N, TRT01PN) now skipped in main loop — covered by paired macro calls
- Known gap: DURDSGR1 missing-value guard not applied by model; macro would fix this
- Known gap: TRTDURD missing else branch (call missing)
- TRT01PN pattern hint shows SAFFL example instead of TRT01P — catalog suggestion needs variable-specific call

## Later ideas
- Compare screen (see docs/specgen_ui_mockup (1).html) — the per-block sign-off
  rail and audit trail view from that mockup are now real (Phase 10 piece 4);
  Compare & verify is still just a mockup, waiting on Phase 9
- True live per-variable generation progress (background job + SSE/polling),
  instead of today's synchronous "click Generate, wait, see the result"
- SDTM: a real 3-mode (Offline/Hybrid/API) pipeline instead of today's binary
  use_api flag, so its Mode switcher stops collapsing Hybrid into API
- Log checker: parse SAS .log, flag ERRORs / WARNINGs / NOTEs, suggest fixes
- QC mode: generate independent verification code + PROC COMPARE harness
- Define.xml support (read specs from define.xml; later write draft define.xml)
- P21 awareness: prompt rules to avoid common Pinnacle 21 findings
- Package as Windows .exe
- Public showcase repo + private working repo (two-repo split)