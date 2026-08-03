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
      - [x] Phase 4.5c: "Use company macro catalog" as a UI option (web app, ADaM tab).
            Until now the catalog was always on for ADSL SAS generation with no way to
            turn it off. assemble_adsl (and both _assemble_adsl_sas/_assemble_adsl_r)
            take a `use_macros` flag; when False, every ADSL variable goes through
            Writer/Improver/Reviewer even where an exact catalog match exists — for a
            study whose macros haven't been validated yet, or where fully custom logic
            is wanted. Real edge case found and fixed while wiring this up:
            MACRO_SIDE_EFFECTS (AGEGR1N, TRT01PN — variables produced as a side effect
            of another variable's macro call, e.g. %adsl_agegr derives both AGEGR1 and
            AGEGR1N) were unconditionally skipped in the main-step loop; with macros
            off nothing produces them as a side effect anymore, so skipping them would
            have silently dropped them from the output. Fixed by only skipping them
            when use_macros is actually True. Verified directly against assemble_adsl:
            AGEGR1 with use_macros=True emits the `%adsl_agegr` call, with False it
            goes through Writer/Improver instead; AGEGR1N is present in the output
            either way. Only affects the SAS path — the catalog has no R macros, so R
            generation already always used Writer/Improver/Reviewer regardless.
            Scope note: this toggled the EXISTING 15-variable ADSL catalog only —
            SDTM/TLF coverage followed in Phase 4.5d below.
      - [x] Phase 4.5d: extended the macro catalog and the "use company macros"
            toggle to SDTM and TLF. macro_catalog.csv gained a `scope` column
            (adam/sdtm/tlf, all 15 existing rows backfilled to adam so ADaM's
            lookup behavior is unchanged) plus 5 new illustrative macros (self-
            authored, matching the existing ADSL demo style — not a real
            company's macro library, since none exists in this repo to pull
            from; the user chose this over pasting in real macros or leaving
            the catalog empty). New macros/*.sas: sdtm_dtc.sas (raw date/time ->
            ISO 8601 --DTC, preserving partial dates), sdtm_seq.sas (--SEQ
            numbering within USUBJID), sdtm_suppqual.sas (build one SUPP-- row
            from a non-standard variable), tlf_bign.sas (Big-N denominator per
            arm), tlf_pctfmt.sas (standard n (%) display format, an inline
            open-code macro rather than a data-step one since it's used as an
            expression).
            The two otypes needed genuinely different wiring, not just a copy
            of ADaM's pattern, because they generate differently:
              - SDTM generates a whole domain per model call (not per-variable
                like ADSL), so an exact "skip the Writer, substitute this call"
                approach doesn't fit — macro_lookup.find_sdtm_macros() does a
                suffix match (e.g. any variable ending "SEQ") against the
                domain's variable list and the matches are appended to that
                domain's prompt as a hint for the Writer to use where it
                actually fits (build_domain_prompt/generate_domain_program/
                generate_single_domain/append_supp_domain/generate_all_domains/
                _run_concurrently and a new --no-macros CLI flag all thread
                use_macros through). It's advisory, same spirit as the existing
                find_by_pattern ADaM hint — not a guarantee the Writer uses it.
              - TLF has NO model calls at all (pure deterministic Python string
                templates — confirmed by reading tlf_assembler.py, not
                assumed), so "using a macro" there means literally branching
                the generated code between the macro CALL and the equivalent
                longhand PROC SQL/expression at codegen time. Two exact
                substitution points, both duplicated identically across the
                demographics and AE-summary table generators: the Big-N
                PROC SQL block (-> %tlf_bign call) and the n (%) display
                expression (-> %tlf_pctfmt call, an inline macro since it
                produces a value, not a step). generate_table/
                _generate_demog_sas/_generate_ae_sas take use_macros; the R
                generators are untouched (no R macro concept, same as ADaM).
            Verified directly: build_domain_prompt with/without use_macros for
            a real AE-domain variable list (hint present/absent correctly);
            generate_table with/without use_macros for both table types
            (macro calls present/absent correctly, R output byte-identical
            either way); the full toggle round-tripped through the live
            /generate route and persisted in per-tab state correctly.
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
      - [x] Phase 6b: wired into the web app as "Update ADSL from a new spec version"
            (ADaM tab, Spec screen — SAS only, only once ADSL has been generated at
            least once). Two-step flow mirroring the app's existing Parse->Generate
            shape: POST /spec_diff previews the diff (new/changed/deleted counts and
            variable names) against `adsl_spec_path` — the spec ADSL was actually last
            generated from, tracked in state since generate_adam itself is a pure
            function with no state access — WITHOUT touching the program; POST
            /apply_patch is the separate, deliberate commit. Runs as a background job
            (same _GENERATE_LOCKS/job_status/job_note machinery as Generate, tagged
            with a new `job_kind` field so the Generate screen and this panel don't
            show each other's status) — patch_program calls the model once per
            changed/new variable, which can take a while, and the single-threaded dev
            server would otherwise be unable to serve any other request (including
            another tab's Generate polling) while it ran. No abort support for patch
            jobs specifically (patch_program doesn't check a cancel_event) — an
            accepted, narrower scope than Generate's abort, since patches only touch
            a handful of variables rather than a whole spec.
            The real payoff versus a full regenerate: _patch_blocks() surgically
            updates only the touched blocks in state — every OTHER variable's block
            (code AND approved/signed-off status) is left completely alone, so
            updating one changed variable doesn't force re-review of the 20 others
            that didn't change.
            Three real bugs fixed in spec_patcher.py while wiring it up (Phase 6's
            open items above were a symptom of the same underlying issues, not fully
            separate items):
              - `from config import WRITER, REVIEWER` at module level — the exact
                stale-import bug already fixed once this session in generator.py (binds
                the name at import time, so the web app's Mode switcher would have
                silently done nothing for patches). Switched to explicit writer_mode/
                reviewer_mode params threaded from the route, config.WRITER/REVIEWER
                read as a fallback only for the CLI/test_patcher.py path.
              - The "changed" variable path was a raw one-shot generate_api() call with
                NO Improver or Reviewer step — patched blocks silently skipped QC
                entirely, unlike every other code path in the app, which always runs
                Writer->Improver->Reviewer. New shared `_build_block()` mirrors
                assemble_adsl's main-step loop exactly (including the QC FLAG marker
                on FAIL and the use_macros-gated exact-match/pattern-hint logic), used
                for both the changed and new-variable paths.
              - patch_program took a file PATH and read it internally — meant the web
                app would have had to write its in-memory (possibly hand-edited via
                "Send back to Improver") program out to disk first just to patch it,
                risking staleness. Changed to take the program TEXT directly; the
                caller (web app or the CLI smoke script) reads/writes wherever the
                program actually lives.
            Verified directly against the repo's real adam_spec.xlsx -> adam_spec_v2.xlsx
            pair (1 new var, 2 changed, 23 unchanged): AGEGR1 (exact catalog match)
            correctly substituted the validated macro call; ITTFL (no match) correctly
            went through Writer/Improver/Reviewer; AGEGR2 (new) was correctly added;
            the original adsl.sas on disk was confirmed untouched (proving the
            text-based interface has no file side effects).
            Known limitation, NOT introduced by this change — pre-existing in the
            whole macro-substitution design since Phase 4.5: an exact catalog match's
            `call` is a static template string, not reparametrized from the new
            derivation rule — so if AGEGR1's cut points change from 65|80 to 65|75,
            the substituted macro call still says `cuts=65|80` unless the catalog
            entry itself is hand-updated. Flagging this rather than silently
            "fixing" it, since it'd need the model to write a customized call guided
            by the macro as a hint (closer to the pattern-match path) rather than a
            direct substitution — a real design change, not a bug fix.
            Scope not carried over from the CLI engine: BDS/SDTM/TLF (no BEGIN/END
            per-variable markers to patch — SDTM/TLF's generation is domain/table-
            level, not variable-level, same reason the macro catalog needed different
            wiring for them in Phase 4.5d) and ADSL's R path (different block format,
            no marker-based regex patching for it either) are both out of scope here,
            unchanged from before.
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
      - [x] Piece 7: Export & audit's file list was dead text — `<li>{{ f }}</li>`
            for each exported path, no way to view or actually get the file short
            of finding it on disk yourself. Each exported file is now a card
            (same "view code" expandable style as Review & sign off) with an
            inline preview (read from disk at render time — _read_exported_previews)
            and a real Download link. New GET /download route validates
            otype+path against that TAB'S OWN exported_files list before
            serving anything — an app-controlled list, not an arbitrary path
            taken from the query string — so it can't be used to fetch any
            other file on disk; verified directly (a file that exists but was
            never exported, and a `../../` traversal attempt, both 404).
            Verified live end-to-end: generate -> approve -> export -> click
            Download -> real file, correct content, correct filename.
            Follow-up: a plain `<a download>` can't choose WHERE the browser
            saves a file — that's entirely up to the browser's own settings
            (its configured downloads folder, unless the user separately
            turned on "always ask" themselves). Changed the Download button
            to call a new downloadTo() JS helper using the File System
            Access API (window.showSaveFilePicker()) — a genuine native
            Save As dialog the user can pick any folder/drive in, same
            experience as the upload fields' own browse dialog. Chromium-
            only (Chrome/Edge; Firefox/Safari don't implement this API), so
            it falls back to a normal browser download — not an error —
            when unsupported, and to the same fallback if the user cancels
            vs. any other failure (checked via the picker's own AbortError).
            Verified live: correct save-dialog invocation with the right
            suggested filename, both for a plain filename and for one with
            a path separator in it (only the basename is suggested).

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
- True live per-variable generation progress, not just running/done/aborted —
  Generate became a background job (polled) in Piece 6 for Abort's sake, but
  the Generate screen still shows no per-variable/per-domain detail while
  running, just a spinner
- Edit an existing program (a previously validated one, or one just
  generated) from a free-text instruction — "the programmer tells the agent
  what to change, agent edits the code" — separate from a spec-driven update
  (below): no spec diff to anchor the edit, so this needs its own scoping
  (which block/variable is being targeted, how the edit is bounded so the
  model doesn't rewrite the whole file, how the result re-enters Review &
  sign off for QC). No existing infra for this; would be new end to end.
- Update an already-generated program when its SPEC changes, from inside the
  web app — DONE, see Phase 6b. Still SAS/ADSL-only (BDS/SDTM/TLF have no
  per-variable BEGIN/END markers to patch); em-dash encoding fix from Phase
  6's original open items not separately revisited.
- SDTM: a real 3-mode (Offline/Hybrid/API) pipeline instead of today's binary
  use_api flag, so its Mode switcher stops collapsing Hybrid into API
- Log checker: parse SAS .log, flag ERRORs / WARNINGs / NOTEs, suggest fixes
- QC mode: generate independent verification code + PROC COMPARE harness
- Define.xml support (read specs from define.xml; later write draft define.xml)
- P21 awareness: prompt rules to avoid common Pinnacle 21 findings
- Package as Windows .exe
- Public showcase repo + private working repo (two-repo split)