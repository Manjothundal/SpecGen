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
- [x] Phase 11: Engineering infrastructure (CI/CD, containerization, cloud deployment)
      - [x] 11a: Ported the Writer/Improver/Reviewer chain to a LangGraph
            StateGraph — new agent_graph.py, 4 nodes (draft/improve/review/
            flag) with a conditional edge after review (FAIL -> flag -> END,
            PASS -> END directly), compiled once at import and reused
            (same "build once, reuse" pattern as `catalog = load_catalog()`
            elsewhere). Same logic as the inline chain it replaced in
            spec_patcher._build_block's non-macro-match branch — not a new
            capability, a restructuring — because that's the one place in
            the app that still auto-chains all three steps end to end.
            Piece 10 above made Generate itself Writer-only/on-demand for
            per-click responsiveness, so the full chain now only runs
            inside patch_program's changed/new-variable paths and the
            "Insert" legacy-program path (both go through _build_block,
            which now calls agent_graph.run_pipeline instead of the three
            inline calls it used to make). app.py's separate on-demand
            Improve/Review buttons (also Piece 10) call improve_block/
            review_block directly and were deliberately left alone — they
            are independent single-step user actions, not a chain, and
            routing them through the graph would just add indirection.
            Verified directly (mocked model calls, no API cost): the exact-
            catalog-match path (AGEGR1) still bypasses the graph entirely;
            a no-match variable (AGEGR2) runs draft->improve->review and
            returns the pattern-hint-prefixed block; a forced Reviewer FAIL
            correctly routes through the flag node and prepends the QC FLAG
            comment, byte-identical in shape to the old inline chain's
            output. Also ran the full test_patcher.py smoke test (real
            adam_spec.xlsx -> adam_spec_v2.xlsx diff/patch) end to end
            through the graph with no regressions.
      - [x] 11b: Swapped the macro catalog's "agentic retrieval" step
            (find_by_pattern in macro_lookup.py) for real nearest-neighbor
            search via Chroma — an in-memory collection built once from the
            catalog's ADaM-scope rows (purpose + pattern text embedded with
            Chroma's bundled local MiniLM model; downloaded once, fully
            offline after that, same spirit as pulling an Ollama model),
            queried with "{variable}: {derivation}" and a cosine-distance
            cutoff (0.65) standing in for the old "pattern == none"
            bail-out. Replaces asking the model to classify a derivation
            into one of 6 fixed pattern names and then exact-matching that
            name — a real embedding pipeline instead of a classify-then-
            filter approximation of one, and one fewer model round-trip per
            lookup. find_macro (exact variable match) and find_sdtm_macros
            (suffix match) are untouched — deterministic lookups, not the
            "RAG" claim this replaced. Verified with real derivation text
            against the live catalog: AGEGR2's age-cutpoint derivation
            correctly nearest-matches %adsl_agegr, a completion-flag
            derivation matches %adsl_popflag, an ISO8601-to-date derivation
            matches %adsl_dtctodt, and an unrelated made-up variable
            (free-text "favorite color") correctly returns no match.
      - [x] 11c: GitHub Actions workflow (.github/workflows/tests.yml)
            running test_differ.py and test_patcher.py on every push and
            PR. Needed a real fix to run at all: test_patcher.py's default
            path uses config.WRITER="local" (Ollama, not installed on a
            GitHub-hosted runner) and config.REVIEWER="api" (a paid
            Anthropic call on every push, needing a secret). Added a third
            generator.py mode, "mock" (generate_mock — a fixed deterministic
            stub, no network call; model_name() and run_model() both
            special-case it), and had test_patcher.py read
            SPECGEN_WRITER_MODE/SPECGEN_REVIEWER_MODE env vars (unset
            outside CI, so local/manual runs are unchanged) to select it.
            This exercises the real diff -> patch -> marker-replace ->
            keep-list-rebuild pipeline, including a full pass through the
            new LangGraph graph, deterministically and for free. New
            requirements.txt (this repo had none before — dependencies were
            installed ad hoc) pins every third-party import found across
            the codebase, including langgraph/chromadb; the workflow caches
            pip and Chroma's downloaded embedding model. Verified: both
            scripts run clean (exit 0) from a from-scratch venv built only
            from requirements.txt, with SPECGEN_WRITER_MODE=SPECGEN_REVIEWER_MODE=mock
            and no ANTHROPIC_API_KEY set at all.
      - [x] 11d: Dockerized the Flask app (Dockerfile, .dockerignore) and
            wrote (but did not run) AWS deployment scripts for App Runner
            and EC2 (aws/). python:3.13-slim base, build-essential installed
            then purged in the same layer (only needed transiently for a
            couple of wheels), gunicorn (Linux-only — kept out of the
            cross-platform requirements.txt, installed only in the image)
            serving app:app as a non-root user. --workers 1 --threads 8:
            RUN_STATE in app.py is a single in-memory dict by design (see
            Piece 4 above) — multiple worker PROCESSES would each get their
            own copy and silently desync; threads still let background-job
            polling routes (/job_status etc.) get served concurrently with
            an in-flight request, matching the dev server's own threading.
            aws/deploy_apprunner.sh (build -> push to ECR -> create/update
            an App Runner service) and aws/ec2_user_data.sh (cloud-init:
            install Docker, pull from ECR, run) are deliberately NOT
            executed by anything — provisioning real cloud infrastructure
            needs the user's own AWS credentials and is a real-money
            action; aws/README.md documents both paths, cost caveats, and
            that ANTHROPIC_API_KEY is the only required runtime secret
            (Offline/Hybrid mode's local Writer would need a reachable
            Ollama instance, out of scope for "containerize the Flask
            app"). Verified live, locally: `docker build` succeeded;
            `docker run` started cleanly under gunicorn; `curl` against the
            running container's `/` returned HTTP 200 with the real
            rendered 4-screen app HTML (confirmed via response length and
            `<title>SpecGen</title>`), then the test container was removed.
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
      - [x] Piece 8: Comment column (spec) + "Bring in an existing program"
            (ADaM tab, SAS only). Two related asks: a free-text Comment column
            in the spec for per-variable mapping notes/overrides beyond the
            formal Derivation rule, and the ability to upload a program
            SpecGen didn't generate — no BEGIN/END markers to rely on — and
            update it using the spec.
              - Comment: one change, in prompt_builder.py only. build_prompt()
                is the single place every variable-level Writer call already
                goes through (assemble_adsl's main loop, spec_patcher's
                _build_block, app.py's regenerate_adsl_block) — reading
                row.get("Comment", "") there and appending an "Additional
                instructions: ..." line after Derivation (when present; safe
                no-op for specs without the column) made it available
                everywhere at once, no other file touched. Verified directly:
                present/absent renders correctly, both SAS and R.
              - "Bring in an existing program": upload -> /legacy_upload
                classifies each current spec variable as likely-present/
                likely-missing via a best-effort regex heuristic (variable
                name as an assignment target) — a hint for the checkboxes'
                default state only, fully overridable, not authoritative
                (documented as such in the UI). Two independent action paths
                from there, matching how differently ADSL generation already
                works for "new" vs. "needs the model to reason about existing
                code":
                  - Insert (new logic): reuses spec_patcher._build_block()
                    verbatim — already Comment/Derivation-aware, catalog-
                    aware, QC-reviewed — appended before `keep` (or at the
                    file's end with no assumption made about structure, if no
                    `keep` is found — genuinely arbitrary uploaded code has no
                    guaranteed shape). Freshly wrapped in real BEGIN/END
                    markers, so these merge into state["blocks"] exactly like
                    spec_patcher's own new-variable path already does.
                  - Full update (locate + rewrite existing logic): a NEW
                    spec_patcher.locate_and_update() — one BATCHED model call
                    (not one per variable) containing the whole uploaded
                    program plus every selected variable's Derivation/Comment,
                    asking the model to return the complete program with just
                    those variables' logic found and rewritten. Kept as a
                    preview only (diffed via stdlib difflib against the
                    original) — never touches state["programs"] until the
                    user explicitly applies it, per their explicit ask for a
                    review step before anything is committed, not a blind
                    patch. Verified live with a real API call against a hand-
                    written 1-variable legacy program: correctly located the
                    existing (wrong) SAFFL assignment and rewrote it to match
                    the actual spec rule, diff showing only that one change.
                    On Apply, since a whole-program rewrite can't produce
                    clean per-variable markers around content that was never
                    structured that way, the result becomes a single opaque
                    "file" block — reusing the *existing* kind:"file" pattern
                    _rebuild_blocks already uses for BDS/SDTM/TLF programs —
                    rather than forcing a third block representation onto it;
                    any stale per-variable blocks from an earlier normal
                    generate/insert are removed at apply time so Review &
                    sign off doesn't show duplicate/conflicting entries for
                    the same file. The diff + an editable `<textarea>`
                    pre-filled with the proposal (submitted verbatim on
                    Apply) IS the review step for this path — the "live
                    editing before applying" the user specifically asked for.
              - Both action paths run as background jobs (new job_kind values
                "legacy_insert"/"legacy_update", same _GENERATE_LOCKS/
                job_status machinery as Generate/patch) for the same reason
                patch got one: they can call the model, and Flask's single-
                threaded dev server would otherwise stall on any other
                request while they ran.
              - Verified route-level end to end (real Writer/Improver/
                Reviewer and real API calls, not mocked): upload+classify
                correctly flags a present variable (SAFFL) vs. a missing one
                (AGEGR1); insert correctly appends AGEGR1 as a real macro-
                matched block while leaving the original SAFFL line
                untouched; apply/cancel correctly replace-vs-discard the
                preview and clean up stale per-variable blocks.
      - [x] Piece 9: extended Piece 8 to SDTM and TLF — deliberately
            asymmetric, not a straight copy, because neither can reuse ADaM's
            Insert path safely:
              - SDTM generates a whole DOMAIN per model call, never per-
                variable — there's no `_build_block`-equivalent primitive to
                call for "just this one variable."
              - TLF has ZERO model calls (confirmed again by re-reading
                tlf_assembler.py) AND each row's generated code references
                `_tab`/`_bign`/`_ARM` helper datasets that only exist because
                of SpecGen's own TABLE_SETUP block, plus a running `ord_n`
                position counter — splicing one row into an arbitrary
                uploaded program would silently reference undefined datasets
                unless that program happened to share SpecGen's exact
                internal scaffold. Unsafe to offer.
            So SDTM and TLF only get the Full-update (locate + rewrite) path
            — one unified preview/apply flow, no separate Insert button;
            the same model call is free to add missing variables/rows too,
            so nothing is actually lost.
              - `spec_patcher.locate_and_update()` generalized from
                `(program, spec, target_vars)` (ADaM-schema-specific) to
                `(program, instruction_blocks)` — the caller now pre-builds
                each variable/row's instruction text, so the same engine
                works for all three without hardcoding one spec's shape
                inside spec_patcher.py. Three small formatters in app.py:
                `_adam_instruction_block` (Derivation + Comment, moved out of
                spec_patcher.py), `_sdtm_instruction_block` (Derivation/
                Origin/Codelist + Comment), `_tlf_instruction_block`
                (handles both Shell_Rows shapes — demographics-style
                adam_var/stat_type/decimals vs. AE-style row_label/
                condition/indent — + Comment).
              - Comment column extended to SDTM: `_var_table()` in
                sdtm_assembler.py is the single shared variable-list
                formatter all 6 domain-class prompt builders (x2 languages)
                already go through, so one change made it available
                everywhere, same pattern as ADaM's. Real effect on real
                generation, since SDTM already calls the model. TLF's
                Comment only matters to the new locate_and_update path —
                normal TLF generation has no model call to give an
                instruction to, so tlf_assembler.py's codegen itself is
                untouched.
              - `_classify_legacy_program()`'s heuristic loosened from an
                assignment-target regex (`VAR\s*=`) to a plain case-
                insensitive substring check, since ADaM's `VAR = ...` style,
                SDTM's, and TLF's `var {v};`/`tables _ARM*{v}` style don't
                share one syntactic shape — one heuristic needed to work
                across all three. Still just a checkbox-default hint, still
                fully overridable.
              - New per-otype upload requirements, since one upload isn't
                "the whole spec" the way ADaM's is: SDTM also takes a domain
                code (one file is one domain) and an optional spec re-upload
                (defaults to SDTM_SPEC); TLF also requires the shell (.xlsx)
                the table was built from (TLF has no "current shell" tracked
                in state the way ADaM tracks `adsl_spec_path`) — new
                `legacy_domain`/`legacy_spec_path`/`legacy_shell_path` state
                fields.
              - On Apply, SDTM/TLF are simpler than ADaM's case was: their
                programs are ALREADY single opaque `kind:"file"` blocks in
                `_rebuild_blocks` (no per-variable block system to reconcile
                against), so applying just replaces `state["programs"]
                [<domain-or-table-key>]` and that one block directly — no
                "stale per-variable blocks" cleanup needed.
              - Verified end to end with real API calls (not mocked) for
                both: a hand-written legacy AE domain program with a wrong
                AESER value ("1"/"0" instead of "Y"/"N" per its NY codelist)
                — correctly found and fixed via a Comment instruction, clean
                1-line diff; a hand-written legacy demographics table with a
                wrong decimal count on the AGE mean display — correctly
                found and fixed via a Comment instruction, clean 1-line
                diff. Re-ran the original ADaM SAFFL regression case after
                the `locate_and_update` generalization to confirm identical
                behavior post-refactor.
      - [x] Piece 10: split Writer/Improver/Reviewer into separate on-demand
            actions (ADaM + SDTM), traced from a real complaint: SDTM domain
            generation was slow because one domain wasn't one model call, it
            was 3 SEQUENTIAL ones (Writer -> Improver -> Reviewer), and this
            app's concurrency only parallelizes ACROSS domains — a single
            domain got zero benefit (confirmed with real runlog.csv timing,
            ~40-90s/domain in Hybrid/API mode). Generate now runs the Writer
            ONLY, in every mode; Improve and Review are separate buttons the
            user clicks per block, only when wanted.
              - ADaM: `_assemble_adsl_sas`/`_assemble_adsl_r`'s main loop no
                longer auto-calls improve_block()/review_block() — every
                variable is Writer-only by default (macro-exact-match and
                pattern-hint paths unaffected, they never called Improve/
                Review anyway). Replaced `regenerate_adsl_block()` (which
                regenerated from scratch AND ran Improve+Review together)
                with two independent functions operating on the CURRENT
                block code — `improve_adsl_block`/`review_adsl_block` — new
                routes `/adsl_improve`/`/adsl_review` replacing `/send_back`.
                Real gap found and fixed: `parse_adsl_blocks()` only had two
                QC states derived from the code text (a "QC FLAG" comment ->
                FAIL, else -> PASS) — once Review became opt-in, "never
                reviewed" would have silently rendered as PASS. Added a real
                `/* QC PASS */` marker (mirroring the existing FAIL one) so
                the code text can distinguish all 3 states; a fresh Generate
                (and even a macro-exact-match block, which also never went
                through Reviewer) now correctly shows NOT REVIEWED until the
                user clicks Review.
              - SDTM: found a second, independent bug while splitting
                `generate_domain_program()` apart — the Reviewer step called
                `review_sas(draft)` with the raw generated CODE passed in as
                if it WERE the review prompt. No "please QC this" instruction
                existed at all, so it never produced a meaningful verdict,
                and the result was discarded after printing to console —
                SDTM domains had no working QC signal, full stop. New
                `write_domain_program()` (Writer only — what Generate calls
                now), `improve_domain_program()` (the existing improve-prompt
                text, extracted into its own function), and a NEW
                `review_domain_program()` with a REAL PASS/FAIL checklist
                (mirroring reviewer.py's build_review_prompt, adapted for a
                whole domain program). New `sdtm_domain` block kind (vs. the
                generic `file` kind BDS/TLF/legacy-uploaded blocks keep) so
                Improve/Review buttons only appear where they apply. New
                routes `/sdtm_improve`/`/sdtm_review` call the sdtm_assembler
                functions directly in-process (not another subprocess) and
                write the result back to BOTH `state["programs"]` AND the
                actual `sdtm_programs/<domain>.<ext>` file on disk — Export's
                SDTM branch just lists already-on-disk paths rather than
                rewriting them, so skipping the disk write would have made
                Export silently ship the pre-improve/pre-review draft.
              - Verified directly: a fresh Generate produces NONE-qc blocks
                for both ADaM (confirmed no "Improving:"/Reviewer console
                output during generation) and SDTM (confirmed the written
                file has no reviewer-step trace either); Improve and Review
                each independently update one block without touching others,
                including the trickier ADaM R path (indent + mutate()-comma
                formatting correctly stripped before Improve/Review and
                correctly reapplied after, verified with a real round-trip);
                repeated Improve/Review cycles don't accumulate stale QC
                marker comments (checked directly); SDTM's Improve/Review
                confirmed writing to the real domain file on disk, not just
                in-memory state.

- [x] Phase 12: Later-ideas backlog — small fixes, SDTM 3-mode, log checker,
      QC mode, Compare & verify
      - [x] 12a: Small fixes flagged in ROADMAP notes above but never
            separately revisited:
              - P21 awareness: reviewer.py's SAS/R QC checklists gained a
                4th check (Common Pinnacle 21 findings — label >40 chars,
                leading/trailing whitespace on a character value, non-ASCII
                punctuation in a label/value); improver.py's rewrite
                checklists gained a matching bullet. Verified via
                build_review_prompt/build_improve_prompt output directly
                (correct numbering with and without ig_version, which now
                shifts to check #5).
              - em-dash encoding fix: app.py and sdtm_assembler.py already
                reconfigured stdout/stderr to UTF-8 (Windows' cp1252 console
                can't encode em-dashes/curly quotes that show up in spec
                text or model output) — test_differ.py and test_patcher.py
                never got the same guard, so running either directly from a
                Windows console on a spec containing one would crash with
                UnicodeEncodeError. Same 3-line guard added to both (and
                test_log_checker.py, new this phase, from the start).
              - Catalog macro-call reparametrization: an exact catalog
                match (find_macro) used to substitute its `call` template
                verbatim — so AGEGR1's cut points changing from 65|80 to
                65|75 in a spec update went out with the STALE 65|80 still
                baked in, since nothing re-examines the template against
                the current Derivation rule. find_macro gained an optional
                `derivation` argument; for pattern=="numeric_range_group"
                (the case that surfaced this), a regex extracts the N
                quoted band labels and the N-1 numeric cut points between
                them from the derivation text and substitutes them into the
                call's cuts=/labels= — no model call, so the exact-match
                fast path stays fast and deterministic. Falls back to the
                unmodified template if the derivation doesn't parse into
                that recognizable shape (never a regression). Both call
                sites (assembler.py's exact-match branch, spec_patcher's
                _build_block) now pass the variable's current Derivation
                through. Verified directly against the repo's own
                adam_spec.xlsx -> adam_spec_v2.xlsx AGEGR1 change (65|80 ->
                65|75 cuts): the substituted call now reads
                cuts=65|75, labels=<65|65-75|>75, and the full
                test_patcher.py patch run confirmed no regression.
      - [x] 12b: SDTM's real 3-mode pipeline. Turned out to be a wiring gap,
            not an sdtm_assembler.py limitation — write_domain_program/
            improve_domain_program/review_domain_program already each took
            their own independent use_api. The actual bug was entirely in
            app.py: generate_sdtm's subprocess only passed --offline for
            mode=="offline" (so Hybrid's Writer ran on the API, unlike
            ADSL's local-draft Hybrid), and /sdtm_improve, /sdtm_review
            computed use_api = state["mode"] != "offline" (collapsing
            Hybrid into API for Improve/Review too). Both now derive from
            MODE_MAP the same way ADSL's routes already do: --offline is
            passed whenever MODE_MAP's writer slot is "local" (Offline AND
            Hybrid); Improve/Review's use_api is MODE_MAP's reviewer slot
            == "api" (Hybrid AND API). Verified the resulting 3x3 matrix
            directly: offline -> (local, local-only), hybrid -> (local
            Writer, API Improve/Review), api -> (API, API) — exactly ADSL's
            semantics, closing the documented asymmetry.
      - [x] 12c: Log checker (log_checker.py) — parses a SAS .log and flags
            every ERROR/WARNING plus any NOTE matching one of ~12 known
            actionable patterns (uninitialized variable, implicit char<->
            numeric conversion, missing-value propagation, a many-to-many
            merge, an unresolved macro variable, multiple-lengths
            truncation, a missing dataset, ...), each with a canned
            suggested fix — deterministic pattern matching, no model call
            needed for any of the known families. check_log() takes an
            optional `mode` as an escape hatch (ask the model for a one-
            line suggestion on an unmatched message) but defaults to pure
            offline/free checking. Routine NOTEs (observation counts, step
            timings) are correctly left out — only ERROR/WARNING/actionable
            NOTE are findings. New standalone route (/tools/log-check,
            templates/log_checker.html) — deliberately outside the ADaM/
            SDTM/TLF tab system, since checking a log isn't tied to any
            otype's spec/generate/review/export state. Verified against a
            synthetic sample_sas.log (sample_sas.log, built to exercise 8
            distinct findings across all three severities plus 3 routine
            NOTEs that must NOT appear): all 8 correctly detected and
            classified, all 3 routine NOTEs correctly excluded, both via
            direct check_log() calls and a live upload through the running
            Flask app (curl multipart POST, confirmed 2 errors/3 warnings/
            3 notes/8 findings in the rendered page).
      - [x] 12d: QC mode — independent double-programming QC for ADSL
            (qc_generator.py). Real double-programming methodology: a
            second, independent model call re-derives every main-step
            variable (Origin=Derived, Source in DM/DERIVED — the same rows
            the production Writer/Improver/Reviewer pipeline covers) from
            the SAME spec, with a QC-programmer persona and the macro
            catalog deliberately NEVER offered (reusing production's own
            validated macro on both sides would make a bug in that macro
            invisible to a comparison that calls it twice) — into
            adsl_qc.sas/.R. A separate, fully deterministic function
            generates the reconciliation harness: PROC COMPARE for SAS
            (base=production, compare=qc, id USUBJID, out=_compare_diffs),
            an equivalent dplyr full-join/mismatch-flagging pipeline for R.
            Scope, stated directly in the module docstring: the ten ADSL
            pre-steps (EX summarize, SUPPDM transpose, SE select, ...) are
            shared, unchanged between production and QC — those are built
            deterministically by the harness, not drafted by a model (see
            README.md), so re-deriving them independently would be QC'ing
            this app's own Python against itself with an LLM in between,
            not catching the natural-language-to-code translation error
            double programming exists to catch. Both programs join/merge
            the exact same pre-step dataset names production's own main
            step does, so adsl_qc is meant to run in the same session/
            library as adsl, after it. New /qc_generate route (ADaM tab
            only, gated on ADSL already being generated) runs as a
            background job (same _GENERATE_LOCKS/job_status machinery as
            Generate — N independent model calls, same reasoning), adding
            adsl_qc/adsl_compare as two more "file"-kind blocks in Review &
            sign off without disturbing ADSL's own per-variable blocks or
            approval state. Real bug caught and fixed while building this:
            generator.py's mock mode (generate_mock, added in Phase 11 for
            CI) hardcoded SAS-flavored output (/* comment */ ... ;) — fine
            for every existing caller, since ADaM's R path never generates
            in mock mode, but qc_generator.py's R path does, and the SAS
            comment syntax isn't valid inside an R mutate() chain. Fixed by
            threading `language` through generate_code/review_code/
            run_model (all additive, default-preserving for every existing
            caller) so the mock stub can emit `# ...` for R instead.
            Verified: mock-mode generation for both SAS and R produce
            syntactically-appropriate stubs; a real (local Ollama, free)
            end-to-end run against the repo's own adam_spec.xlsx produced
            adsl_qc.sas and adsl_compare.sas (committed as samples) —
            rough in spots, as expected for an unreviewed local Writer-only
            pass (e.g. a hallucinated DM.ARM dataset prefix the prompt
            explicitly disallowed), which is itself exactly the kind of
            thing double-programming + PROC COMPARE is meant to surface,
            not something this module needed to prevent on its own; the
            live /qc_generate route confirmed end to end against the
            running app (generate ADSL, click Run independent QC, both new
            blocks appear in Review & sign off).
      - [x] 12e: Compare & verify (Phase 9), scoped realistically —
            compare_verify.py. This app never executes SAS/R, so it can't
            produce a real rendered RTF/Word/PDF report itself; what it CAN
            do deterministically (no AI in this module, per Phase 9's
            original scope note above) is read one back a user brings in
            from their own SAS/R environment and reconcile it. Two entry
            points: compare_outputs(path_a, path_b) — output-to-output,
            extracts both (pdfplumber for PDF, python-docx for Word,
            striprtf for RTF, plain text/CSV fallback), aligns
            sections/tables by TITLE TEXT similarity (difflib), not page
            position — the original scope's explicit "not page-number
            based" requirement, satisfied because a re-paginated re-run of
            the same content shouldn't register as "everything moved" —
            then diffs each aligned pair; validate_against_shell(path,
            shell) — output-to-mock-shell, a presence check that every
            Shell_Meta title and Shell_Rows label the shell promised
            actually appears somewhere in the rendered output. Findings
            logged to runlog.csv via the existing log_run() (the original
            scope's "written to the audit trail" requirement). New
            build_sample_tlf_outputs.py (mirrors the existing
            build_sample_acrf.py/build_sample_protocol.py pattern: generate
            once, commit the output as a fixture) produces a real PDF
            A/B pair (one changed cell, via reportlab, already a
            dependency), a DOCX, and an RTF — used to verify every
            extractor against REAL parsed files, not mocked objects.
            Verified directly: compare_outputs on the A/B PDF pair
            correctly found exactly the one changed cell (Age mean 52.3 ->
            53.8), nothing else; validate_against_shell against
            sample_shell_demographics.xlsx correctly flagged the 3 row
            labels and 1 title the intentionally-partial sample PDF omits,
            and correctly did NOT flag the 2 it includes; DOCX and RTF
            extraction confirmed against their own real sample files too.
            New standalone route (/tools/compare,
            templates/compare_verify.html) — the per-otype tab's disabled
            "Compare & verify" nav button (Piece 4 mockup placeholder)
            pointed here instead of becoming a real per-tab screen 5, once
            it became clear the two file uploads this needs don't belong
            in any otype's RUN_STATE at all, same reasoning as the log
            checker's standalone page. Verified end to end via Flask's
            in-process test client (didn't touch the live server, which had
            a real ADSL generation in flight at the time): GET renders the
            tool, both POST routes return the same findings as the direct
            module calls.
      - [x] 12f: New requirements.txt entries: python-docx (Word), striprtf
            (RTF) — pdfplumber and reportlab were already dependencies.
            New .github/workflows/tests.yml steps run test_qc_generator.py
            (mock mode), test_log_checker.py, and test_compare_verify.py
            (both fully deterministic, no mode needed) on every push,
            alongside the existing differ/patcher smoke tests.

- [x] Phase 13: Performance ("make this app super fast")
      - [x] 13a: _read_runlog_tail (app.py) was reading the WHOLE runlog.csv
            into memory on every single page render just to show the last 8
            rows — an O(file size) cost paid on every request to an
            append-only file that only ever grows across a project's
            lifetime. New _tail_text_lines() seeks backward from the end in
            chunks instead, bounded by the tail size, not the file size; the
            header line is still read separately (a cheap single readline()
            regardless of file size) since it isn't necessarily inside the
            tail. Verified byte-for-byte identical output against the old
            implementation on the real runlog.csv (841 lines at the time)
            and across 7 edge cases (empty file, header-only, exactly n
            rows, fewer than n rows, no trailing newline, ...); timed 2.6x
            faster already at 841 lines, a gap that widens as the file grows
            since the new version's cost barely depends on total size.
      - [x] 13b: ADSL's main-step loop (assembler.py, both SAS and R paths)
            generated one variable at a time — the exact same shape of
            problem sdtm_assembler.py's generate_all_domains already solved
            for SDTM domains (Phase 5c: ~4.3x measured on 5 concurrent
            domains), just never applied to ADSL. Confirmed safe to
            parallelize by actually reading the code, not assuming: each
            variable's Writer prompt is built ONLY from that row's own spec
            fields plus a fixed generic "available variables" description —
            it never references another variable's generated CODE (in fact
            `available = known_variables(spec)`, computed before the loop,
            turned out to be dead — never actually passed into gen_block/
            build_prompt at all, a pre-existing quirk from before this
            phase, left alone rather than "fixed" as an unrelated behavior
            change). New _build_adsl_block_sas/_build_adsl_block_r pull the
            per-variable logic out of the loop bodies unchanged; the loop
            now submits every variable to a ThreadPoolExecutor(max_workers=
            5) and reads results back via zip(rows_to_build, futures) —
            preserves spec order in the assembled output regardless of
            completion order. cancel_event is checked before reading back
            each result rather than before starting each variable (an
            abort's granularity is now "whatever's already in flight when
            you click it", up to 5 variables, instead of exactly 1) —
            executor.shutdown(wait=False, cancel_futures=True) drops
            anything not yet started and lets already-running work finish
            in the background with its result simply discarded, so an abort
            doesn't block waiting for the whole queue to drain either.
            Verified: mock-mode output byte-for-byte IDENTICAL to the
            pre-change version for both the SAS and R paths (diffed
            directly, not just eyeballed) — confirms this is a pure speed
            change, not a behavior change. Real-mode timing: a small
            (9-variable) use_macros=False API-mode run went from 5.2s
            sequential to 4.7s concurrent — a modest win here specifically
            because individual short-prompt API calls are already fast, so
            the benefit should scale up on bigger specs (the existing "test
            against 60-100+ variables" open item below would be a much
            better stress test than this repo's small demo spec). The
            bigger question — does Offline mode's local Ollama server even
            process concurrent requests in parallel, or silently queue them
            or one at a time, making this a no-op for local mode — was
            checked directly against the running Ollama server (not
            assumed): 3 short concurrent generate calls completed in 6.9s
            versus 23.0s sequential, confirming Ollama genuinely
            parallelizes and Offline mode benefits at least as much as API
            mode, likely more given how much slower each individual local
            call is (directly observed all through this session — 15-20
            minute waits for a 20-variable Offline ADSL run were common).
      - [x] 13c: sdtm_automapper.py's per-dataset loop got the same
            treatment — each uploaded raw file's mapping is one independent
            model call (no shared state between demog.csv's mapping and
            vitals.csv's), so multiple files now run concurrently instead
            of one at a time, same MAX_WORKERS=5 default. Verified with a
            monkeypatched timing test (3 simulated 0.3s calls: 0.55s
            concurrent vs. ~0.9s sequential) and confirmed the concurrent
            results still land in the correct file order in the output
            workbook.
      - Deliberately NOT parallelized: adam_bds_assembler.py's and
        qc_generator.py's per-variable loops. Unlike ADSL, these were
        BUILT with a real sequential dependency — each variable's prompt
        explicitly tells the Writer which EARLIER variables (in spec row
        order) are already available, so a later row can reference an
        earlier one by name (documented in both modules' own context-
        building functions). Parallelizing those would silently tell the
        model a variable exists before it's actually been derived —
        a correctness regression, not just a behavior change, so left
        exactly as they were.

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
- Package as Windows .exe — [x] native-window step done: desktop_app.py
  wraps app.py's existing Flask app unchanged, running it in a background
  thread and opening it in a pywebview native window (own icon/taskbar
  entry, no browser chrome) instead of "open a browser to localhost:5000".
  Verified live: launched it, the embedded Flask server came up and
  served real traffic through the native window (GET /, favicon.ico,
  two POST /parse submissions — not just my own test request). Still
  needs Python + requirements.txt installed on the machine running it —
  a fully standalone .exe with no Python required (PyInstaller bundling
  chromadb/onnxruntime, pyreadstat, langgraph, ...) is a separate, bigger
  step, not done here.
- Public showcase repo + private working repo (two-repo split)