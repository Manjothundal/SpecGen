"""
app.py — SpecGen web app (Flask).

Three independent tabs — ADaM, SDTM, TLF — each with its own 4-screen flow
modeled on docs/specgen_ui_mockup (1).html: Spec -> Generate -> Review &
sign off -> Export & audit. (Compare & verify is not implemented — it's
Phase 9, a from-scratch RTF/Word/PDF diff engine that doesn't exist yet.)

Each tab has its own state slice (RUN_STATE["otypes"][otype]) — this is a
single-operator local tool running on Flask's synchronous dev server, so
there's still only ever one run in flight per tab; no session/DB layer is
needed. The tabs used to share one flat state behind a single "Output:"
dropdown, which caused real bugs (uploading a spec for one otype bleeding
into another, a stray form submission silently reverting the dropdown) —
splitting them into genuinely independent slices, with otype implicit per
tab's own forms rather than a shared editable field, removes that whole
class of bug rather than patching around it.

  ADaM : BDS datasets (ADVS/ADLB/ADEG/ADTR/ADAE/ADCM/ADRS/ADTTE) are pure
         deterministic string templates in bds_assembler.py — no model calls,
         generated only for SDTM domains actually present in the uploaded (or
         sample) ACRF metadata. ADSL runs the real Writer/Improver/Reviewer
         pipeline (assembler.assemble_adsl) against a Variables-sheet spec —
         gated by the Mode switcher. Either input, both, or neither may be
         present; each falls back to its own sample default.
  TLF  : calls tlf_assembler for each shell (one table per shell file).
  SDTM : runs sdtm_assembler.py as a subprocess; skips domains whose output
         file already exists unless --force (an uploaded spec forces).

Run:  python app.py   ->   http://127.0.0.1:5000
"""

import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime

# assembler.py's gen_block/improve_block/review_block print progress messages
# (variable names, QC verdicts) that can include Unicode punctuation from
# Claude's own responses. On Windows, stdout defaults to the console codepage
# (cp1252), which can't encode that — printing it would crash whichever
# request happened to be generating at the time with UnicodeEncodeError.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import pandas as pd
import openpyxl
from flask import Flask, jsonify, render_template, request, send_file
from werkzeug.utils import secure_filename

import bds_assembler as bds
import tlf_assembler as tlf
import sdtm_assembler
import config
from assembler import assemble_adsl, clean, known_variables, _r_add_comma
from improver import improve_block
from reviewer import review_block
from spec_differ import diff_specs
from spec_patcher import patch_program, locate_and_update, _build_block
from log_checker import check_log
import qc_generator
from compare_verify import compare_outputs, validate_against_shell
import sdtm_automapper

app = Flask(__name__)

ACRF = "acrf_metadata.xlsx"
ADAM_SPEC = "adam_spec_full.xlsx"
SDTM_SPEC = "sdtm_spec_draft.xlsx"
SHELLS = ["sample_shell_demographics.xlsx", "sample_shell_ae.xlsx"]
OTYPES = ("adam", "sdtm", "tlf")

# Mode switcher (Offline/Hybrid/API) -> (writer_mode, reviewer_mode). Only
# affects ADSL and SDTM generation — BDS datasets are deterministic string
# templates with no model calls either way.
MODE_MAP = {
    "offline": ("local", "local"),
    "hybrid": ("local", "api"),
    "api": ("api", "api"),
}


def _new_otype_state():
    return {
        "lang": "sas",
        "mode": "hybrid",
        "routing": None,
        "programs": {},
        "blocks": {},        # block_key -> {label, code, qc, approved, kind, var}
        "block_order": [],
        "main_step_rows": {},  # var -> row dict, for ADSL "send back to Improver"
        "adsl_available": [],
        "exported_files": [],
        "last_commit": None,
        "uploaded_paths": [],   # persists across the Spec -> Generate request boundary
        "sdtm_force_pending": False,  # a fresh upload just arrived -> force SDTM's next
                                      # generate once, not every generate for that upload
        "available_domains": [],  # domain/dataset choices for the current spec
        "selected_domain": "all",  # "all", or one specific domain/dataset name
        "active_screen": "spec",   # which of the 4 steps this tab currently shows
        "note": None,               # last message shown on this tab, if any
        "job_status": "idle",       # idle | running | done | aborted | error
        "job_kind": None,           # "generate" | "patch" — which screen's job this is, so
                                    # the Generate screen and the Spec screen's "Update from
                                    # new spec" panel each only show their OWN running/note UI
        "job_note": None,           # shown on the Generate screen while running/after abort
        "use_macros": True,        # ADaM only: use the validated company macro catalog for
                                   # ADSL SAS where an exact match exists, instead of always
                                   # going through Writer/Improver/Reviewer. No effect on
                                   # SDTM/TLF, or on ADaM's R path (no R macro catalog exists).
        "adsl_spec_path": None,      # ADaM only: the spec file ADSL was last generated from —
                                    # the "v1" baseline an "Update from new spec" diff compares
                                    # against. None until ADSL has been generated at least once.
        "sdtmig_version": "3.4",    # SDTM only: SDTMIG version threaded into Writer/Improve/
                                    # Review prompts so generated code and QC verdicts target
                                    # this specific CDISC IG version.
        "adamig_version": "1.3",    # ADaM only: ADaMIG version threaded into ADSL's Writer/
                                    # Improve/Review prompts (the BDS domains are templated,
                                    # not LLM-authored, so this has no effect on them).
        "spec_diff": None,           # ADaM only: pending diff preview, set by /spec_diff
        "pending_spec_v2": None,     # ADaM only: uploaded v2 spec path awaiting /apply_patch
        "legacy_upload_path": None,     # all 3 otypes: an uploaded existing (non-SpecGen) SAS
                                        # program, awaiting classification/action
        "legacy_classification": None,  # all 3 otypes: [{"variable","label","present_guess"}, ...]
                                        # per current spec row/shell row, set by /legacy_upload
        "legacy_update_preview": None,  # all 3 otypes: {"program", "diff", "targeted_vars"} once
                                        # /legacy_preview_update has run — nothing is applied to
                                        # state["programs"] until /legacy_apply_update
        "legacy_domain": None,          # SDTM only: which domain the legacy upload is for
        "legacy_spec_path": None,       # SDTM only: which SDTM spec to classify/instruct against
                                        # (SDTM has no equivalent of ADaM's adsl_spec_path tracking
                                        # a "current" spec, since one domain file isn't the whole spec)
        "legacy_shell_path": None,      # TLF only: the shell file paired with the legacy upload —
                                        # needed since a shell defines the row structure a table's
                                        # code is built from, and TLF has no "current shell" tracked
                                        # in state the way ADaM tracks adsl_spec_path
    }


# Each tab is fully independent — otype is which tab's forms you're
# submitting, never a value one form can hand off to another.
RUN_STATE = {
    "active_otype": "adam",   # which TAB is visually active on page load
    "otypes": {ot: _new_otype_state() for ot in OTYPES},
}

# Uploads are saved here once per run and reused across the Spec -> Generate
# requests (the Spec screen's upload should still apply when you later click
# Generate, without re-uploading) — cleared only when a new upload replaces
# it. Namespaced by otype subfolder so two tabs uploading same-named files
# can't collide.
UPLOAD_DIR = tempfile.mkdtemp(prefix="specgen_run_")

# Generation (especially SDTM with --force, or ADSL) can legitimately take
# minutes with zero progress feedback in the UI — indistinguishable from
# "stuck" to someone waiting on it. Without this, re-clicking Generate during
# a slow run spawns ANOTHER overlapping sdtm_assembler.py/assemble_adsl call
# on top of the first instead of just waiting for it. One lock per tab, so
# a slow SDTM run doesn't block clicking Generate on the ADaM tab.
_GENERATE_LOCKS = {ot: threading.Lock() for ot in OTYPES}

# Generation runs in a background thread per tab (see _run_generate_job) so
# the /generate request returns immediately instead of blocking for minutes —
# that's what makes a real Abort button possible: an /abort POST is a normal,
# fast request the (single-threaded) dev server can service right away
# because the worker thread doing the slow work isn't tied up in a request
# handler. cancel_event is checked cooperatively (SDTM's subprocess is killed
# outright; ADaM's per-variable ADSL loop and TLF's per-shell loop check it
# between iterations). proc holds SDTM's live subprocess.Popen, if any, so
# /abort can terminate it immediately rather than waiting for a poll.
_JOB_CTRL = {ot: {"cancel_event": threading.Event(), "proc": None} for ot in OTYPES}

# Same background-job shape as the tab system above, but for the standalone
# SDTM automapper tool (see /tools/sdtm-automap below) — it isn't tied to
# any otype tab, so it gets its own single-slot lock/state instead of a
# per-otype dict (only one automap run at a time, which is the right
# scope: this is a one-off "upload data, get a mapping proposal" tool, not
# a multi-tab pipeline).
_AUTOMAP_LOCK = threading.Lock()
_AUTOMAP_CTRL = {"cancel_event": threading.Event()}
_AUTOMAP_STATE = {"status": "idle", "note": None, "rows": None, "output_path": None}


# ---------------------------------------------------------------------------
# Upload handling
# ---------------------------------------------------------------------------

def _save_uploads(files, otype):
    """Save any non-empty uploaded files into this tab's own upload
    subfolder. Returns saved paths, or [] if no files were submitted
    (caller should then fall back to this tab's previously stored paths)."""
    saved = []
    otype_dir = os.path.join(UPLOAD_DIR, otype)
    for f in files:
        if f and f.filename:
            os.makedirs(otype_dir, exist_ok=True)
            path = os.path.join(otype_dir, secure_filename(f.filename))
            f.save(path)
            saved.append(path)
    return saved


def _resolve_uploads(files, otype):
    """New files this request replace any previously uploaded ones for THIS
    tab; otherwise reuse what's already stored from an earlier step. Each
    tab has its own bucket, so there's no cross-otype case to guard against
    the way there used to be with one shared upload slot."""
    state = RUN_STATE["otypes"][otype]
    new_uploads = _save_uploads(files, otype)
    if new_uploads:
        state["uploaded_paths"] = new_uploads
        state["sdtm_force_pending"] = True  # this is a genuinely new spec — force once
    return state["uploaded_paths"]


def _sheet_names(path):
    wb = openpyxl.load_workbook(path, read_only=True)
    names = wb.sheetnames
    wb.close()
    return names


def _classify_adam_uploads(uploaded):
    """Sort uploaded files for otype=adam into (acrf_path, adsl_spec_path) by
    sheet name: a "By Domain" sheet is ACRF metadata (drives BDS); a
    "Variables" sheet is an ADaM spec (drives ADSL). Either may be absent."""
    acrf_path, adsl_spec_path = None, None
    for path in uploaded:
        try:
            sheets = _sheet_names(path)
        except Exception:
            continue
        if "By Domain" in sheets:
            acrf_path = path
        elif "Variables" in sheets:
            adsl_spec_path = path
    return acrf_path, adsl_spec_path


# ---------------------------------------------------------------------------
# ADSL spec routing (same split spec_parser.py uses)
# ---------------------------------------------------------------------------

def route_adsl_spec(spec):
    copies = spec[spec["Origin"] == "Predecessor"]
    derived = spec[spec["Origin"] == "Derived"]
    ex_summary = derived[derived["Source"] == "EX_SUMMARY"]
    main_step = derived[derived["Source"].isin(["DM", "DERIVED"])]
    return copies, derived, ex_summary, main_step


# SDTM domain -> BDS dataset name, same presence logic generate_adam() uses.
BDS_FINDINGS_MAP = [("VS", "advs"), ("LB", "adlb"), ("EG", "adeg"), ("TR", "adtr")]


def _adam_available_datasets(acrf_path, adsl_spec_path):
    """Which ADaM datasets this spec pair can actually produce — same
    domain-presence checks generate_adam() uses, so the picker only offers
    choices that will really generate something."""
    available = []
    acrf_path = acrf_path or ACRF
    if os.path.exists(acrf_path):
        acrf = pd.read_excel(acrf_path, sheet_name="By Domain")
        present = set(acrf["Domain"].unique())
        for dom, name in BDS_FINDINGS_MAP:
            if dom in present:
                available.append(name)
        if "AE" in present:
            available.append("adae")
        if "CM" in present:
            available.append("adcm")
        if "RS" in present:
            available.extend(["adrs", "adtte"])
    adsl_spec_path = adsl_spec_path or ADAM_SPEC
    if os.path.exists(adsl_spec_path):
        available.append("adsl")
    return available


# ---------------------------------------------------------------------------
# Generators
# ---------------------------------------------------------------------------

def generate_adam(lang, mode, acrf_path=None, adsl_spec_path=None, domain="all", cancel_event=None,
                  use_macros=True, ig_version=None):
    """Return (programs, adsl_context). programs: {name: code}. adsl_context
    is {"main_step_rows": {...}, "available": [...]} when ADSL was generated,
    else None (used later for "send back to Improver").

    domain: "all" (default) generates everything the spec(s) support; any
    other value (a specific dataset name — advs/adlb/adeg/adtr/adae/adcm/
    adrs/adtte/adsl) generates only that one dataset, skipping the rest
    entirely rather than generating everything and discarding it.

    use_macros: passed straight through to assemble_adsl — whether ADSL SAS
    generation may use the validated company macro catalog. No effect on
    BDS (never uses macros) or on the R path (no R macro catalog exists).

    ig_version: ADaMIG version (e.g. "1.3"), passed straight through to
    assemble_adsl's Writer prompt. No effect on BDS — those are templated
    string generators with no LLM prompt to version.

    cancel_event: optional threading.Event for the Abort button. BDS datasets
    are near-instant string templates, so it's only checked between them for
    consistency; ADSL is where it matters — its Writer/Improver/Reviewer loop
    (up to 3 model calls per variable) checks it once per variable via
    assemble_adsl's own cancel_event param.
    """
    domain = (domain or "all").lower()
    cancelled = lambda: cancel_event is not None and cancel_event.is_set()

    def want(name):
        return domain in ("all", name)

    writer_mode, reviewer_mode = MODE_MAP.get(mode, (None, None))
    out = {}
    adsl_context = None

    acrf_path = acrf_path or ACRF
    if os.path.exists(acrf_path):
        acrf = pd.read_excel(acrf_path, sheet_name="By Domain")
        present = set(acrf["Domain"].unique())

        for dom, src, code in [("VS", "vs", "ADVS"), ("LB", "lb", "ADLB"),
                               ("EG", "eg", "ADEG"), ("TR", "tr", "ADTR")]:
            if cancelled():
                return out, adsl_context
            if dom not in present or not want(code.lower()):
                continue
            try:
                params = bds.build_param_spec_from_acrf(acrf, dom, dom + "TESTCD")
            except ValueError:
                continue
            out[code.lower()] = bds.generate_bds_domain(src, params, code, language=lang)

        if "AE" in present and want("adae"):
            out["adae"] = bds.generate_ae_domain("ADAE", language=lang)
        if "CM" in present and want("adcm"):
            out["adcm"] = bds.generate_cm_domain("ADCM", language=lang)
        if "RS" in present and (want("adrs") or want("adtte")):
            if lang == "r":
                out["adrs"] = bds.generate_rs_domain_r("ADRS")
                out["adtte"] = bds.generate_tte_domain_r("ADTTE")
            else:
                out["adrs"] = bds.generate_rs_domain("ADRS")
                out["adtte"] = bds.generate_tte_domain("ADTTE")
            # ADRS/ADTTE are always derived together — if only one was asked
            # for, still show just that one.
            if domain == "adrs":
                out.pop("adtte", None)
            elif domain == "adtte":
                out.pop("adrs", None)

    adsl_spec_path = adsl_spec_path or ADAM_SPEC
    if not cancelled() and want("adsl") and os.path.exists(adsl_spec_path):
        spec = pd.read_excel(adsl_spec_path, sheet_name="Variables")
        _, derived, ex_summary, main_step = route_adsl_spec(spec)
        out["adsl"] = assemble_adsl(spec, derived, ex_summary, main_step,
                                    language=lang, writer_mode=writer_mode,
                                    reviewer_mode=reviewer_mode, cancel_event=cancel_event,
                                    use_macros=use_macros, ig_version=ig_version)
        adsl_context = {
            "main_step_rows": {row["Variable"]: row.to_dict()
                              for _, row in main_step.iterrows()},
            "available": known_variables(spec),
        }

    return out, adsl_context


def generate_tlf(lang, shells=None, domain="all", cancel_event=None, use_macros=True):
    """Return dict {name: code} for each shell (uploaded, or the sample shells).

    domain: "all" (default), or one specific shell's table_id (e.g. "14.1.1")
    to generate only that table.

    use_macros: passed straight through to tlf.generate_table — SAS only,
    substitutes the %tlf_bign/%tlf_pctfmt company macro calls for the
    equivalent longhand code (TLF generation has no model calls at all, so
    this is a direct codegen branch, not a hint). No effect in R mode.
    """
    domain = (domain or "all").lower()
    out = {}
    for shell in (shells or SHELLS):
        if cancel_event is not None and cancel_event.is_set():
            break
        if not os.path.exists(shell):
            continue
        meta, _ = tlf._read_shell(shell)
        tid = str(meta.get("table_id", "table"))
        if domain != "all" and domain != tid.lower():
            continue
        out[f"t_{tid.replace('.', '_')}"] = tlf.generate_table(shell, language=lang, use_macros=use_macros)
    return out


def generate_sdtm(lang, mode, spec_path=None, domain="all", force_pending=False, ctrl=None, use_macros=True,
                  ig_version=None):
    """Run sdtm_assembler.py as a subprocess, then read the .sas/.R files back.

    sdtm_assembler.py skips domains whose output file already exists unless
    --force is passed, so a hand-QC'd fix in sdtm_programs/ survives repeat
    "Generate" clicks. A genuinely new spec upload forces exactly ONE
    generate (force_pending, sourced from this tab's own
    sdtm_force_pending flag, set in _resolve_uploads and consumed by the
    caller before this runs) — not every subsequent click for that same
    upload, which would otherwise redo already-finished domains from scratch
    every retry (e.g. after a timeout) instead of skipping them and
    continuing. Explicitly picking ONE domain from the dropdown is also
    treated as a deliberate "(re)generate this now" request, so it forces
    just that domain regardless of whether it already exists — "all" still
    respects the default skip-if-exists behavior.

    Mode maps through MODE_MAP the same way ADSL's does: the subprocess gets
    --offline (local Writer) whenever MODE_MAP's writer slot is "local" —
    true for Offline AND Hybrid, matching ADSL's local-draft/API-review
    split — and only API mode's Writer runs against the Anthropic API.
    Improve/Review (the on-demand /sdtm_improve, /sdtm_review routes) use
    MODE_MAP's reviewer slot the same way ADSL's do.

    ctrl: optional {"cancel_event": threading.Event, "proc": None} dict shared
    with the route layer's /abort handler — this function stores the live
    Popen in ctrl["proc"] the moment it starts so /abort can terminate() it
    immediately (SDTM is the one otype whose generation is a real OS process,
    so it's the one that can be killed outright rather than just stopped
    between iterations).

    use_macros: passed to sdtm_assembler.py as --no-macros when False.
    Offered to the Writer as a hint where a domain's variables match a
    catalog entry (e.g. --DTC/--SEQ/SUPP qualifiers) — not a forced
    substitution, since SDTM generation goes through the model.

    ig_version: SDTMIG version (e.g. "3.4"), passed to sdtm_assembler.py as
    --sdtmig-version — appended to the Writer prompt so generated code
    targets that specific CDISC IG version. None skips the flag entirely.
    """
    domain = (domain or "all").upper() if domain != "all" else "all"
    single_domain_forced = domain != "all"
    force = single_domain_forced or (spec_path is not None and force_pending)
    spec_path = spec_path or SDTM_SPEC
    if not os.path.exists(spec_path):
        return {"(error)": f"{spec_path} not found in project folder."}

    # Only read back domains actually defined in THIS spec — sdtm_programs/
    # is a shared output folder reused across whichever spec was last run
    # (sample or an uploaded one), so glob("*.sas") would mix in unrelated
    # leftover files from a different spec's earlier run. SUPP-- domains
    # don't have their own file (append_supp_domain merges them into their
    # parent's) — reading one back means reading its PARENT's file instead.
    all_domains = sdtm_assembler.list_domains(spec_path)
    if single_domain_forced:
        requested = domain.replace("SUPP", "") if domain.startswith("SUPP") else domain
        domains = [d for d in all_domains if not d.startswith("SUPP") and d == requested]
    else:
        domains = [d for d in all_domains if not d.startswith("SUPP")]
    ext = "R" if lang == "r" else "sas"

    def read_back():
        """Domains are written to disk one at a time as the subprocess works
        through them, so even a timeout/crash/abort partway through still
        leaves real, valid files for whatever finished — read those back
        instead of discarding everything."""
        found = {}
        for d in domains:
            path = os.path.join("sdtm_programs", f"{d.lower()}.{ext}")
            if os.path.exists(path):
                with open(path, encoding="utf-8") as f:
                    found[d.lower()] = f.read()
        return found

    cmd = [sys.executable, "sdtm_assembler.py", spec_path, "--lang", lang]
    writer_mode, _ = MODE_MAP.get(mode, (None, None))
    if writer_mode == "local":
        cmd.append("--offline")
    if force:
        cmd.append("--force")
    if single_domain_forced:
        cmd.extend(["--domain", domain])
    if not use_macros:
        cmd.append("--no-macros")
    if ig_version:
        cmd.extend(["--sdtmig-version", ig_version])
    # A full spec (18+ domains) in API mode has run at ~70-100s/domain in
    # testing — 10 minutes was nowhere near enough and threw away every
    # domain that DID finish. Scale with domain count instead of a flat cap.
    timeout_s = max(600, 150 * (len(domains if single_domain_forced else all_domains) + 6))

    # stdout/stderr go to a real disk-backed temp file, not a pipe: sdtm_assembler
    # prints progress per variable/domain, which over a multi-minute run can
    # exceed the OS pipe buffer (~64KB) — a plain Popen(..., stdout=PIPE) that
    # isn't drained concurrently would then deadlock the child the first time
    # its write() blocks. A file never applies that backpressure.
    log_file = tempfile.TemporaryFile(mode="w+", encoding="utf-8")
    proc = subprocess.Popen(cmd, stdout=log_file, stderr=subprocess.STDOUT, text=True)
    if ctrl is not None:
        ctrl["proc"] = proc

    start = time.time()
    while proc.poll() is None:
        if ctrl is not None and ctrl["cancel_event"].is_set():
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            break
        if time.time() - start > timeout_s:
            break  # still running past the timeout — handled below, not aborted
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass

    # Checked AFTER the loop, not just inside it: /abort can terminate() the
    # process directly from a different thread (for an instant kill rather
    # than waiting for this loop's next 1s poll tick), which can make
    # `proc.poll() is None` go false and exit the while loop on its condition
    # before the body ever runs again to notice cancel_event was set.
    aborted = ctrl is not None and ctrl["cancel_event"].is_set()

    if ctrl is not None:
        ctrl["proc"] = None

    partial = read_back()
    if aborted:
        partial["(note)"] = (f"Aborted by user with {len(partial)} of {len(domains)} "
                             f"domain(s) done — showing what finished. Generate again to "
                             f"pick up the rest (already-done domains are skipped unless "
                             f"you re-upload).")
        return partial
    if proc.poll() is None:  # still running past timeout_s and not aborted
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        if partial:
            partial["(note)"] = (f"Timed out after {timeout_s}s with {len(partial)} of "
                                 f"{len(domains)} domains done — showing what finished. "
                                 f"Generate again to pick up the rest (already-done domains "
                                 f"are skipped unless you re-upload).")
            return partial
        return {"(error)": f"Timed out after {timeout_s}s with no domains completed yet."}
    if proc.returncode != 0:
        if partial:
            partial["(note)"] = "sdtm_assembler failed partway through — showing what finished."
            return partial
        log_file.seek(0)
        log_tail = log_file.read()[-4000:]
        return {"(error)": f"sdtm_assembler failed:\n{log_tail}"}

    return partial


# ---------------------------------------------------------------------------
# ADSL block parsing / re-generation (Review & sign off screen)
# ---------------------------------------------------------------------------

def parse_adsl_blocks(code):
    """Split generated ADSL code into per-variable blocks using its BEGIN/END
    markers. Returns [{"var":..., "code":..., "qc": "PASS"|"FAIL"|"NONE"}, ...].

    QC is now opt-in (Review is a separate action, not automatic during
    Generate — see improve_adsl_block/review_adsl_block below), so a block's
    code carries an explicit marker either way once reviewed: "QC FLAG: ..."
    on FAIL (unchanged), a plain "QC PASS" comment on PASS (new — previously
    PASS had no marker at all, which is what let it get silently confused
    with "never reviewed" once Review stopped running automatically). No
    marker at all means NONE, genuinely not-yet-reviewed — including a
    macro-exact-match block, which never went through Reviewer either
    unless the user explicitly clicks Review on it.
    """
    sas_pattern = re.compile(r'/\*-- BEGIN (\w+) --\*/\n(.*?)\n/\*-- END \1 --\*/', re.DOTALL)
    r_pattern = re.compile(r'# -- BEGIN (\w+) -- #\n(.*?)\n(?: {4})?# -- END \1 -- #', re.DOTALL)
    matches = list(sas_pattern.finditer(code)) or list(r_pattern.finditer(code))
    blocks = []
    for m in matches:
        var, body = m.group(1), m.group(2).strip("\n")
        if "QC FLAG" in body:
            qc = "FAIL"
        elif "QC PASS" in body:
            qc = "PASS"
        else:
            qc = "NONE"
        blocks.append({"var": var, "code": body, "qc": qc})
    return blocks


def _sas_block_pattern(var):
    return re.compile(rf'/\*-- BEGIN {re.escape(var)} --\*/\n(.*?)\n/\*-- END {re.escape(var)} --\*/', re.DOTALL)


def _r_block_pattern(var):
    return re.compile(rf'# -- BEGIN {re.escape(var)} -- #\n(.*?)\n(?: {{4}})?# -- END {re.escape(var)} -- #', re.DOTALL)


def _current_adsl_var_code(state, var):
    """The current code for one ADSL variable, suitable as input to
    improve_block/review_block — with any previous QC marker comment
    stripped (so re-running Improve/Review doesn't compound stale marker
    text on top of itself) and, for R, de-formatted back to the plain
    derivation-code shape gen_block/improve_block/review_block all deal in
    (undoing the indent + mutate()-separator-comma formatting that gets
    applied only when a block is spliced into the stored program)."""
    key = "adam:adsl:" + var
    body = state["blocks"][key]["code"]
    lang = state["lang"]

    if lang == "sas":
        return re.sub(r'^/\* QC (?:FLAG: .*?|PASS) \*/\n', '', body)

    body = re.sub(r'^ {0,4}# QC (?:FLAG: .*|PASS)\n', '', body)
    lines = body.splitlines()
    dedented = [ln[4:] if ln.startswith("    ") else ln for ln in lines]
    if dedented and "WRITER PRODUCED NO CODE" in dedented[-1]:
        dedented = dedented[:-1]
    for i in range(len(dedented) - 1, -1, -1):
        if not dedented[i].lstrip().startswith("#"):
            line = dedented[i]
            hash_pos = line.find("#")
            if hash_pos == -1:
                dedented[i] = line.rstrip().rstrip(",")
            else:
                code_part, comment_part = line[:hash_pos], line[hash_pos:]
                dedented[i] = code_part.rstrip().rstrip(",") + "  " + comment_part
            break
    return "\n".join(dedented)


def _splice_adsl_var(state, var, new_code, qc_state=None, verdict=None):
    """Format new_code for this tab's language and splice it into the
    stored adsl program text at variable var's BEGIN/END markers (fresh
    offsets looked up each call, so repeated edits to different variables
    stay correct even though earlier edits changed the surrounding text's
    length), then update state["blocks"]. qc_state: None (Improve just
    ran — no marker, matches "never reviewed" until Review runs again),
    "FAIL" (needs verdict), or "PASS"."""
    lang = state["lang"]
    row = state["main_step_rows"][var]

    if qc_state == "FAIL":
        comment = f"QC FLAG: {verdict}"
    elif qc_state == "PASS":
        comment = "QC PASS"
    else:
        comment = None

    if lang == "sas":
        block = new_code
        if comment:
            block = f"/* {comment} */\n" + block
        new_body = block
        pattern = _sas_block_pattern(var)
    else:
        raw_lines = new_code.splitlines()
        indented = ["    " + ln for ln in raw_lines]
        comma_idx = None
        for i in range(len(indented) - 1, -1, -1):
            if not indented[i].lstrip().startswith("#"):
                comma_idx = i
                break
        if comma_idx is not None:
            indented[comma_idx] = _r_add_comma(indented[comma_idx])
        else:
            na_value = "NA_character_" if str(row["Type"]).lower() == "text" else "NA_real_"
            indented.append(f"    {var} = {na_value},  # WRITER PRODUCED NO CODE for this derivation")
        new_body = "\n".join(indented)
        if comment:
            new_body = f"    # {comment}\n" + new_body
        pattern = _r_block_pattern(var)

    program = state["programs"]["adsl"]
    m = pattern.search(program)
    if m:
        program = program[:m.start(1)] + new_body + program[m.end(1):]
        state["programs"]["adsl"] = program

    key = "adam:adsl:" + var
    state["blocks"][key]["code"] = new_body
    state["blocks"][key]["qc"] = qc_state or "NONE"
    state["blocks"][key]["approved"] = False


def improve_adsl_block(var):
    """Run Improve on the CURRENT code for one ADSL variable (not a fresh
    Writer regenerate) and splice the result back in. Resets qc to NONE —
    a prior Review verdict no longer applies to code Improve just changed;
    Review is a separate action the user can re-run if they want a badge
    for the improved version."""
    state = RUN_STATE["otypes"]["adam"]
    lang = state["lang"]
    _, reviewer_mode = MODE_MAP.get(state["mode"], (None, None))
    row = state["main_step_rows"][var]
    available = state["adsl_available"]

    current_code = _current_adsl_var_code(state, var)
    improved = clean(improve_block(current_code, row, available, language=lang, mode=reviewer_mode,
                                   ig_version=state["adamig_version"]))
    _splice_adsl_var(state, var, improved, qc_state=None)


def review_adsl_block(var):
    """Run Review on the CURRENT code for one ADSL variable and set its QC
    badge — Review only reports a verdict, it never changes the code
    itself (Improve is the separate action that does)."""
    state = RUN_STATE["otypes"]["adam"]
    lang = state["lang"]
    _, reviewer_mode = MODE_MAP.get(state["mode"], (None, None))
    available = state["adsl_available"]

    current_code = _current_adsl_var_code(state, var)
    verdict = review_block(current_code, available, language=lang, mode=reviewer_mode,
                           ig_version=state["adamig_version"])
    qc_state = "FAIL" if verdict.startswith("FAIL") else "PASS"
    _splice_adsl_var(state, var, current_code, qc_state=qc_state, verdict=verdict)


# ---------------------------------------------------------------------------
# Block bookkeeping shared by the Generate / Review screens
# ---------------------------------------------------------------------------

def _rebuild_blocks(state, otype, programs, adsl_context):
    blocks = {}
    order = []

    if otype == "adam" and "adsl" in programs:
        for b in parse_adsl_blocks(programs["adsl"]):
            key = f"adam:adsl:{b['var']}"
            blocks[key] = {"label": b["var"], "code": b["code"], "qc": b["qc"],
                          "approved": False, "kind": "adsl_var", "var": b["var"]}
            order.append(key)

    for name, code in programs.items():
        if name == "adsl":
            continue
        key = f"{otype}:{name}"
        # SDTM's normal per-domain output gets its own "sdtm_domain" kind
        # (vs. the generic "file" kind BDS/TLF/legacy-uploaded programs
        # keep) so the template can offer Improve/Review only where they
        # actually apply — a domain this app wrote via write_domain_program,
        # not an opaque brought-in file from the legacy-update flow.
        kind = "sdtm_domain" if otype == "sdtm" else "file"
        blocks[key] = {"label": name, "code": code, "qc": "NONE",
                      "approved": False, "kind": kind, "var": None}
        order.append(key)

    state["blocks"] = blocks
    state["block_order"] = order
    state["main_step_rows"] = (adsl_context or {}).get("main_step_rows", {})
    state["adsl_available"] = (adsl_context or {}).get("available", [])


def _patch_blocks(state, diff, new_program):
    """After spec_patcher.patch_program() returns a new full ADSL program,
    surgically update just the touched blocks instead of a full
    _rebuild_blocks — every OTHER variable's block (code, QC badge, AND
    approved status) is left completely alone. That's the actual value of
    patching over a full regenerate: updating one changed variable doesn't
    force re-review of the 20 others that didn't change."""
    parsed = {b["var"]: b for b in parse_adsl_blocks(new_program)}
    touched = {c["variable"] for c in diff["changed"]} | set(diff["new"])

    for var in touched:
        b = parsed.get(var)
        if not b:
            continue
        key = f"adam:adsl:{var}"
        state["blocks"][key] = {"label": var, "code": b["code"], "qc": b["qc"],
                                "approved": False, "kind": "adsl_var", "var": var}
        if key not in state["block_order"]:
            state["block_order"].append(key)

    for var in diff["deleted"]:
        key = f"adam:adsl:{var}"
        state["blocks"].pop(key, None)
        if key in state["block_order"]:
            state["block_order"].remove(key)

    state["programs"]["adsl"] = new_program


def _signoff_counts(state):
    total = len(state["blocks"])
    approved = sum(1 for b in state["blocks"].values() if b["approved"])
    return approved, total


def _read_exported_previews(exported_files):
    """Export & audit used to show exported files as a dead list of path
    strings — no way to actually see or get the file short of finding it on
    disk yourself. Read each one's content at render time so the Export
    screen can show an expandable preview per file, matching the Review
    screen's existing "view code" card style."""
    previews = {}
    for path in exported_files:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                previews[path] = f.read()
        except OSError as e:
            previews[path] = f"(could not read file: {e})"
    return previews


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

def _render(active_otype=None, note=None, note_otype=None):
    """Render the whole page — all three tabs' content at once (same pattern
    the 4 step-screens already used: everything is in the DOM, CSS/JS toggles
    visibility), so switching tabs client-side needs no server round-trip and
    can never lose another tab's state."""
    if active_otype:
        RUN_STATE["active_otype"] = active_otype

    tabs = {}
    for ot in OTYPES:
        state = RUN_STATE["otypes"][ot]
        approved, total = _signoff_counts(state)
        mode = state["mode"]
        tabs[ot] = dict(
            state,
            approved=approved, total_blocks=total,
            writer_model=config.LOCAL_MODEL if mode in ("offline", "hybrid") else config.API_MODEL,
            reviewer_model=config.API_MODEL if mode in ("hybrid", "api") else config.LOCAL_MODEL,
            note=note if note_otype == ot else None,
            exported_previews=_read_exported_previews(state["exported_files"]),
        )

    return render_template(
        "index.html",
        active_otype=RUN_STATE["active_otype"],
        tabs=tabs,
        runlog_rows=_read_runlog_tail(),
    )


def _tail_text_lines(path, n, chunk_size=4096):
    """The last n non-empty lines of a text file, read by seeking backward
    from the end in chunks — bounded work regardless of total file size,
    unlike reading the whole file into a list line by line. Every page
    render calls this (via _read_runlog_tail below) for a file that's
    append-only and only grows over a project's lifetime, so this staying
    O(tail) instead of O(whole file) matters more with every run logged."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        pos = f.tell()
        blocks = []
        newline_count = 0
        while pos > 0 and newline_count <= n:
            read_size = min(chunk_size, pos)
            pos -= read_size
            f.seek(pos)
            block = f.read(read_size)
            blocks.append(block)
            newline_count += block.count(b"\n")
        data = b"".join(reversed(blocks))
    text = data.decode("utf-8", errors="replace")
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    return lines[-n:]


def _read_runlog_tail(n=8):
    path = "runlog.csv"
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        header_line = f.readline().strip()  # cheap regardless of file size — stops at the first newline
    if not header_line:
        return []
    header = header_line.split(",")

    # header itself can land in the tail slice on a small file — it's not
    # a data row, drop it if so.
    data_lines = [l for l in _tail_text_lines(path, n + 1) if l != header_line]

    rows = [dict(zip(header, l.split(","))) for l in data_lines[-n:]]
    rows.reverse()
    return rows


def _otype_from_request(default="adam"):
    otype = request.form.get("otype", default)
    return otype if otype in OTYPES else default


@app.route("/", methods=["GET"])
def index():
    return _render()


@app.route("/tools/log-check", methods=["GET", "POST"])
def log_check_tool():
    """Standalone one-shot tool, deliberately outside the ADaM/SDTM/TLF tab
    system — checking a SAS .log isn't tied to a spec/generate/review/export
    pipeline or any per-otype state, it's a stateless "upload a file, see
    findings" utility, so it gets its own tiny template instead of being
    squeezed into otype_tab()."""
    findings = None
    if request.method == "POST":
        f = request.files.get("logfile")
        if f and f.filename:
            log_text = f.read().decode("utf-8", errors="replace")
            findings = check_log(log_text)

    counts = {"error": 0, "warning": 0, "note": 0}
    for finding in findings or []:
        counts[finding["severity"]] += 1

    return render_template("log_checker.html", findings=findings, counts=counts)


def _save_upload(file_storage, subdir):
    """Save an uploaded werkzeug FileStorage to a real path on disk —
    compare_verify's extractors (pdfplumber/python-docx/striprtf) all need
    an actual file, not an in-memory stream. Reuses the same UPLOAD_DIR
    temp directory every other upload in this app writes to."""
    out_dir = os.path.join(UPLOAD_DIR, subdir)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, secure_filename(file_storage.filename))
    file_storage.save(path)
    return path


@app.route("/tools/compare", methods=["GET"])
def compare_verify_tool():
    """Standalone tool, same reasoning as /tools/log-check — comparing two
    rendered TLF outputs (or an output against its mock shell) isn't tied
    to any otype's spec/generate/review/export state; the per-otype tab's
    disabled "Compare & verify" nav button pointed here originally but
    Phase 9 landed as this standalone page instead, once it became clear
    the two file uploads it needs don't belong in RUN_STATE at all."""
    return render_template("compare_verify.html", mode=None, findings=None, missing=None)


@app.route("/tools/compare-outputs", methods=["POST"])
def compare_verify_outputs_route():
    file_a = request.files.get("file_a")
    file_b = request.files.get("file_b")
    if not file_a or not file_a.filename or not file_b or not file_b.filename:
        return render_template("compare_verify.html", mode=None, findings=None, missing=None)

    path_a = _save_upload(file_a, "compare_a")
    path_b = _save_upload(file_b, "compare_b")
    try:
        findings = compare_outputs(path_a, path_b)
    except ValueError as e:
        return render_template("compare_verify.html", mode=None, findings=None, missing=None,
                               error=str(e))

    changed_count = sum(1 for f in findings if f["kind"] == "changed")
    only_count = len(findings) - changed_count
    return render_template("compare_verify.html", mode="outputs", findings=findings,
                           changed_count=changed_count, only_count=only_count, missing=None)


@app.route("/tools/compare-shell", methods=["POST"])
def compare_verify_shell_route():
    output_file = request.files.get("output_file")
    shell_file = request.files.get("shell_file")
    if not output_file or not output_file.filename or not shell_file or not shell_file.filename:
        return render_template("compare_verify.html", mode=None, findings=None, missing=None)

    output_path = _save_upload(output_file, "compare_output")
    shell_path = _save_upload(shell_file, "compare_shell")
    try:
        missing = validate_against_shell(output_path, shell_path)
    except ValueError as e:
        return render_template("compare_verify.html", mode=None, findings=None, missing=None,
                               error=str(e))

    return render_template("compare_verify.html", mode="shell", missing=missing, findings=None)


def _run_automap_job(raw_dir, output_path, use_api, sdtmig_version):
    """Background thread target for /tools/sdtm-automap — one model call
    per uploaded dataset, so this runs off the request thread for the same
    reason every other model-calling route in this app does (Flask's
    single-threaded dev server would otherwise stall on any other request,
    including this page's own status poll, while it ran)."""
    try:
        rows = sdtm_automapper.run_automapper(
            raw_dir, output_path, use_api=use_api, sdtmig_version=sdtmig_version,
            cancel_event=_AUTOMAP_CTRL["cancel_event"],
        )
        _AUTOMAP_STATE["rows"] = rows
        _AUTOMAP_STATE["output_path"] = output_path
        if _AUTOMAP_CTRL["cancel_event"].is_set():
            _AUTOMAP_STATE["status"] = "aborted"
            _AUTOMAP_STATE["note"] = "Mapping aborted by user — partial results below, if any completed."
        else:
            n_high = sum(1 for r in rows if r["confidence"] == "High")
            n_med = sum(1 for r in rows if r["confidence"] == "Medium")
            n_low = sum(1 for r in rows if r["confidence"] == "Low")
            _AUTOMAP_STATE["status"] = "done"
            _AUTOMAP_STATE["note"] = f"Mapped {len(rows)} variables ({n_high} High, {n_med} Medium, {n_low} Low)."
    except Exception as e:
        _AUTOMAP_STATE["status"] = "error"
        _AUTOMAP_STATE["note"] = f"Mapping failed: {e}"
    finally:
        _AUTOMAP_LOCK.release()


@app.route("/tools/sdtm-automap", methods=["GET", "POST"])
def sdtm_automap_tool():
    """Standalone tool, same reasoning as /tools/log-check and
    /tools/compare — mapping raw data to SDTM isn't tied to any otype's
    spec/generate/review/export state, it's its own one-shot "upload data,
    get a mapping proposal" workflow."""
    if request.method == "POST":
        files = request.files.getlist("raw_files")
        files = [f for f in files if f and f.filename]
        if not files:
            return render_template("sdtm_automap.html", status=_AUTOMAP_STATE["status"],
                                   note="Select at least one .sas7bdat or .csv file.",
                                   rows=None, counts=None)

        if not _AUTOMAP_LOCK.acquire(blocking=False):
            return render_template("sdtm_automap.html", status="running",
                                   note="A mapping run is already in progress.",
                                   rows=_AUTOMAP_STATE["rows"], counts=_confidence_counts(_AUTOMAP_STATE["rows"]))

        raw_dir = os.path.join(UPLOAD_DIR, "sdtm_automap", datetime.now().strftime("%Y%m%d%H%M%S%f"))
        os.makedirs(raw_dir, exist_ok=True)
        for f in files:
            f.save(os.path.join(raw_dir, secure_filename(f.filename)))

        mode = request.form.get("mode", "api")
        sdtmig_version = request.form.get("sdtmig_version") or None
        output_path = os.path.join(raw_dir, "sdtm_automap.xlsx")

        _AUTOMAP_CTRL["cancel_event"].clear()
        _AUTOMAP_STATE["status"] = "running"
        _AUTOMAP_STATE["note"] = None
        _AUTOMAP_STATE["rows"] = None
        _AUTOMAP_STATE["output_path"] = None

        threading.Thread(target=_run_automap_job,
                         args=(raw_dir, output_path, mode != "offline", sdtmig_version),
                         daemon=True).start()

    return render_template("sdtm_automap.html", status=_AUTOMAP_STATE["status"],
                           note=_AUTOMAP_STATE["note"], rows=_AUTOMAP_STATE["rows"],
                           counts=_confidence_counts(_AUTOMAP_STATE["rows"]))


def _confidence_counts(rows):
    counts = {"High": 0, "Medium": 0, "Low": 0}
    for r in rows or []:
        counts[r["confidence"]] = counts.get(r["confidence"], 0) + 1
    return counts


@app.route("/tools/sdtm-automap/abort", methods=["POST"])
def sdtm_automap_abort():
    _AUTOMAP_CTRL["cancel_event"].set()
    if _AUTOMAP_STATE["status"] == "running":
        _AUTOMAP_STATE["note"] = "Aborting — finishing up the current dataset…"
    return render_template("sdtm_automap.html", status=_AUTOMAP_STATE["status"],
                           note=_AUTOMAP_STATE["note"], rows=_AUTOMAP_STATE["rows"],
                           counts=_confidence_counts(_AUTOMAP_STATE["rows"]))


@app.route("/tools/sdtm-automap/download", methods=["GET"])
def sdtm_automap_download():
    """Serves only the file THIS tool's own last run produced — not an
    arbitrary path from the query string — same pattern as /download."""
    path = _AUTOMAP_STATE.get("output_path")
    if not path or not os.path.exists(path):
        return "No mapping result available to download.", 404
    return send_file(os.path.abspath(path), as_attachment=True, download_name="sdtm_automap.xlsx")


@app.route("/parse", methods=["POST"])
def parse_spec():
    otype = _otype_from_request()
    state = RUN_STATE["otypes"][otype]
    # Each tab's own modebar carries its own hardcoded otype, mode, lang —
    # there's no shared field for another tab's action to clobber.
    state["mode"] = request.form.get("mode", state["mode"])
    state["lang"] = request.form.get("lang", state["lang"])
    if otype == "sdtm":
        state["sdtmig_version"] = request.form.get("sdtmig_version", state["sdtmig_version"])
    elif otype == "adam":
        state["adamig_version"] = request.form.get("adamig_version", state["adamig_version"])

    uploaded = _resolve_uploads(request.files.getlist("spec_file"), otype)
    routing = {}
    available_domains = []
    if otype == "adam":
        acrf_path, adsl_spec_path = _classify_adam_uploads(uploaded)
        acrf_path = acrf_path or ACRF
        adsl_spec_path = adsl_spec_path or ADAM_SPEC
        if os.path.exists(acrf_path):
            acrf = pd.read_excel(acrf_path, sheet_name="By Domain")
            routing["ACRF domains"] = acrf["Domain"].value_counts().to_dict()
        if os.path.exists(adsl_spec_path):
            spec = pd.read_excel(adsl_spec_path, sheet_name="Variables")
            copies, derived, ex_summary, main_step = route_adsl_spec(spec)
            routing["ADSL routing"] = {
                "copies": len(copies), "derived": len(derived),
                "EX pre-step": len(ex_summary), "main step": len(main_step),
            }
        available_domains = _adam_available_datasets(acrf_path, adsl_spec_path)
    elif otype == "sdtm":
        spec_path = uploaded[0] if uploaded else SDTM_SPEC
        if os.path.exists(spec_path):
            domains = sdtm_assembler.list_domains(spec_path)
            routing["SDTM domains"] = {d: sdtm_assembler.get_domain_class(d) for d in domains}
            available_domains = domains
    else:  # tlf
        shell_table_ids = {}
        for shell in (uploaded or SHELLS):
            if os.path.exists(shell):
                meta, _ = tlf._read_shell(shell)
                shell_table_ids[os.path.basename(shell)] = meta.get("table_id", "?")
        routing["Shells"] = shell_table_ids
        available_domains = list(shell_table_ids.values())

    state["routing"] = routing
    state["available_domains"] = available_domains
    state["selected_domain"] = "all"  # reset on every fresh parse
    state["active_screen"] = "generate"

    return _render(active_otype=otype)


def _run_patch_job(diff, v2_path, writer_mode, reviewer_mode, use_macros):
    """Background thread target for /apply_patch — same non-blocking
    rationale as _run_generate_job: patch_program calls the model once per
    changed/new variable, which can take a while, and Flask's single-
    threaded dev server would otherwise be unable to serve ANY other
    request (including another tab's Generate polling) while it's in
    flight. ADaM only — spec-driven patching only exists for ADSL SAS."""
    state = RUN_STATE["otypes"]["adam"]
    try:
        new_program, _ = patch_program(state["programs"]["adsl"], state["adsl_spec_path"], v2_path,
                                       writer_mode=writer_mode, reviewer_mode=reviewer_mode,
                                       use_macros=use_macros)
        _patch_blocks(state, diff, new_program)
        state["adsl_spec_path"] = v2_path
        state["spec_diff"] = None
        state["pending_spec_v2"] = None
        state["exported_files"] = []
        state["last_commit"] = None
        state["active_screen"] = "review"
        state["job_status"] = "done"
        state["job_note"] = (f"Patched {len(diff['changed'])} changed, {len(diff['new'])} new, "
                             f"{len(diff['deleted'])} deleted variable(s) — only the touched "
                             f"blocks need re-review; everything else kept its approval.")
    except Exception as e:
        state["job_status"] = "error"
        state["job_note"] = f"Patch failed: {e}"
    finally:
        _GENERATE_LOCKS["adam"].release()


@app.route("/spec_diff", methods=["POST"])
def spec_diff():
    """Preview step: diff a newly uploaded spec (v2) against the spec ADSL
    was actually generated from (state["adsl_spec_path"], tracked in
    _run_generate_job) and show what would change, WITHOUT touching the
    program yet — /apply_patch is the separate, deliberate commit step."""
    state = RUN_STATE["otypes"]["adam"]
    if not state.get("adsl_spec_path") or "adsl" not in state.get("programs", {}):
        return _render(active_otype="adam", note_otype="adam",
                      note="Generate ADSL at least once before updating it from a new spec.")
    if state["lang"] != "sas":
        return _render(active_otype="adam", note_otype="adam",
                      note="Update from a new spec is SAS-only today.")

    files = request.files.getlist("spec_v2")
    if not files or not files[0].filename:
        return _render(active_otype="adam", note_otype="adam",
                      note="Choose a spec file to compare against the current one.")

    v2_dir = os.path.join(UPLOAD_DIR, "adam_spec_v2")
    os.makedirs(v2_dir, exist_ok=True)
    v2_path = os.path.join(v2_dir, secure_filename(files[0].filename))
    files[0].save(v2_path)

    try:
        diff = diff_specs(state["adsl_spec_path"], v2_path)
    except Exception as e:
        return _render(active_otype="adam", note_otype="adam", note=f"Could not diff specs: {e}")

    if not diff["changed"] and not diff["new"] and not diff["deleted"]:
        return _render(active_otype="adam", note_otype="adam",
                      note="No differences from the current spec — nothing to patch.")

    state["spec_diff"] = diff
    state["pending_spec_v2"] = v2_path
    return _render(active_otype="adam")


@app.route("/apply_patch", methods=["POST"])
def apply_patch():
    state = RUN_STATE["otypes"]["adam"]
    diff = state.get("spec_diff")
    v2_path = state.get("pending_spec_v2")
    if not diff or not v2_path:
        return _render(active_otype="adam", note_otype="adam", note="No pending update to apply.")

    lock = _GENERATE_LOCKS["adam"]
    if not lock.acquire(blocking=False):
        return _render(active_otype="adam", note_otype="adam",
                      note="A generation is already running on this tab — wait for it to "
                          "finish before applying this update.")

    writer_mode, reviewer_mode = MODE_MAP.get(state["mode"], (None, None))
    state["job_status"] = "running"
    state["job_kind"] = "patch"
    state["job_note"] = None

    threading.Thread(target=_run_patch_job,
                     args=(diff, v2_path, writer_mode, reviewer_mode, state["use_macros"]),
                     daemon=True).start()

    return _render(active_otype="adam")


@app.route("/cancel_patch", methods=["POST"])
def cancel_patch():
    """Discard a previewed diff without applying it."""
    state = RUN_STATE["otypes"]["adam"]
    state["spec_diff"] = None
    state["pending_spec_v2"] = None
    return _render(active_otype="adam")


def _classify_legacy_program(program, spec):
    """Best-effort heuristic ONLY — flags a variable/row as "likely
    present" if its name appears anywhere in the program (case-insensitive
    substring — not a precise assignment-target check, since ADaM's
    `VAR = ...` style, SDTM's, and TLF's `var {v};`/`tables _ARM*{v}` style
    don't share one syntactic shape, and this same heuristic has to work
    across all three). Real legacy code can also define something through
    a macro call, different casing, or not at all — this is just a
    starting point for the checkboxes' default state; the UI lets the user
    override every one of them regardless of the guess."""
    classification = []
    program_lower = program.lower()
    for _, row in spec.iterrows():
        var = str(row["Variable"])
        present = var.lower() in program_lower
        classification.append({"variable": var, "label": row["Label"], "present_guess": present})
    return classification


def _normalize_tlf_rows(rows):
    """TLF's Shell_Rows sheet has two different shapes depending on table
    type — demographics-style (adam_var/label/stat_type/decimals) or AE-
    style (row_label/condition/indent) — normalize both into Variable/Label
    columns so _classify_legacy_program and the instruction formatters can
    treat a TLF row the same way an ADaM/SDTM variable is treated."""
    out = rows.copy()
    if "adam_var" in out.columns:
        out["Variable"] = out["adam_var"]
        out["Label"] = out["label"]
    else:
        out["Variable"] = out["row_label"]
        out["Label"] = out["row_label"]
    return out


def _adam_instruction_block(var, row):
    text = f"- {var} (Label: {row['Label']}, Type: {row['Type']}, Length: {row['Length']})\n  Derivation rule: {row['Derivation']}"
    comment = str(row.get("Comment", "") or "").strip()
    if comment and comment.lower() != "nan":
        text += f"\n  Additional instructions: {comment}"
    return text


def _sdtm_instruction_block(var, row):
    text = f"- {var} (Label: {row.get('Label', '')}, Type: {row.get('Type', '')}, Origin: {row.get('Origin', '')})"
    derivation = str(row.get("Derivation", "") or "").strip()
    if derivation and derivation.lower() not in ("nan", "none"):
        text += f"\n  Derivation: {derivation}"
    codelist = str(row.get("Codelist", "") or "").strip()
    if codelist and codelist.lower() != "nan":
        text += f"\n  Codelist: {codelist}"
    comment = str(row.get("Comment", "") or "").strip()
    if comment and comment.lower() != "nan":
        text += f"\n  Additional instructions: {comment}"
    return text


def _tlf_instruction_block(var, row):
    if "stat_type" in row.index:
        text = f"- {var} (Label: {row['label']}, stat_type: {row['stat_type']}, decimals: {row['decimals']})"
    else:
        text = (f"- {var} (row_label: {row['row_label']}, "
                f"condition: {row.get('condition', '')}, indent: {row.get('indent', '')})")
    comment = str(row.get("Comment", "") or "").strip()
    if comment and comment.lower() != "nan":
        text += f"\n  Additional instructions: {comment}"
    return text


@app.route("/legacy_upload", methods=["POST"])
def legacy_upload():
    """Bring in an existing (non-SpecGen) program for any of the 3 tabs.
    Just saves the file(s) and classifies each current spec variable/shell
    row as likely-present/likely-missing — /legacy_insert (ADaM only) and
    /legacy_preview_update (all 3) are the separate action steps.

    otype-specific extra input, since one otype's "spec" isn't a single
    tracked file the way ADaM's is: SDTM also needs a domain code (one
    upload is one domain's file, not the whole spec) and optionally a spec
    file (defaults to SDTM_SPEC); TLF also needs the shell file the table
    was built from (TLF has no "current shell" tracked in state)."""
    otype = _otype_from_request()
    state = RUN_STATE["otypes"][otype]
    if state["lang"] != "sas":
        return _render(active_otype=otype, note_otype=otype,
                      note="Bringing in an existing program is SAS-only today.")

    files = request.files.getlist("legacy_program")
    if not files or not files[0].filename:
        return _render(active_otype=otype, note_otype=otype,
                      note="Choose an existing .sas program to bring in.")

    legacy_dir = os.path.join(UPLOAD_DIR, f"{otype}_legacy")
    os.makedirs(legacy_dir, exist_ok=True)
    legacy_path = os.path.join(legacy_dir, secure_filename(files[0].filename))
    files[0].save(legacy_path)

    try:
        with open(legacy_path, encoding="utf-8", errors="replace") as f:
            program = f.read()

        if otype == "adam":
            spec_path = state.get("adsl_spec_path") or ADAM_SPEC
            if not os.path.exists(spec_path):
                return _render(active_otype=otype, note_otype=otype,
                              note=f"No ADaM spec available to classify against ({spec_path} not found).")
            spec = pd.read_excel(spec_path, sheet_name="Variables")

        elif otype == "sdtm":
            domain = request.form.get("domain", "").strip().upper()
            if not domain:
                return _render(active_otype=otype, note_otype=otype,
                              note="Enter the domain code this program is for (e.g. AE, DM).")
            spec_files = request.files.getlist("legacy_spec")
            if spec_files and spec_files[0].filename:
                spec_dir = os.path.join(UPLOAD_DIR, "sdtm_legacy_spec")
                os.makedirs(spec_dir, exist_ok=True)
                spec_path = os.path.join(spec_dir, secure_filename(spec_files[0].filename))
                spec_files[0].save(spec_path)
            else:
                spec_path = SDTM_SPEC
            variables = sdtm_assembler.read_domain_spec(spec_path, domain)
            if not variables:
                return _render(active_otype=otype, note_otype=otype,
                              note=f"No variables found for domain {domain} in {spec_path}.")
            spec = pd.DataFrame(variables)
            state["legacy_domain"] = domain
            state["legacy_spec_path"] = spec_path

        else:  # tlf
            shell_files = request.files.getlist("legacy_shell")
            if not shell_files or not shell_files[0].filename:
                return _render(active_otype=otype, note_otype=otype,
                              note="Also upload the shell (.xlsx) this table was built from.")
            shell_dir = os.path.join(UPLOAD_DIR, "tlf_legacy_shell")
            os.makedirs(shell_dir, exist_ok=True)
            shell_path = os.path.join(shell_dir, secure_filename(shell_files[0].filename))
            shell_files[0].save(shell_path)
            rows = pd.read_excel(shell_path, sheet_name="Shell_Rows")
            spec = _normalize_tlf_rows(rows)
            state["legacy_shell_path"] = shell_path

    except Exception as e:
        return _render(active_otype=otype, note_otype=otype, note=f"Could not read upload or spec: {e}")

    state["legacy_upload_path"] = legacy_path
    state["legacy_classification"] = _classify_legacy_program(program, spec)
    return _render(active_otype=otype)


def _run_legacy_insert_job(selected_vars, writer_mode, reviewer_mode, use_macros):
    """Background thread target for /legacy_insert — same non-blocking
    rationale as _run_generate_job/_run_patch_job. Reuses spec_patcher's
    _build_block() directly (Comment/Derivation-aware, catalog-aware,
    QC-reviewed) — identical machinery to spec_patcher's own new-variable
    path, just appended into an uploaded program instead of one this app
    already tracked."""
    state = RUN_STATE["otypes"]["adam"]
    try:
        legacy_path = state["legacy_upload_path"]
        adsl_spec_path = state.get("adsl_spec_path") or ADAM_SPEC
        with open(legacy_path, encoding="utf-8", errors="replace") as f:
            program = f.read()
        spec = pd.read_excel(adsl_spec_path, sheet_name="Variables")
        available = known_variables(spec)

        new_blocks = {}
        for var in selected_vars:
            row = spec[spec["Variable"] == var]
            if row.empty:
                continue
            new_blocks[var] = _build_block(var, row.iloc[0], available, writer_mode, reviewer_mode, use_macros)

        if not new_blocks:
            state["job_status"] = "error"
            state["job_note"] = "No valid variables selected to insert."
            return

        insert_text = "\n\n".join(new_blocks.values())
        if "  keep " in program:
            program = program.replace("  keep ", f"{insert_text}\n\n  keep ", 1)
        else:
            # No recognizable `keep` statement — this is genuinely arbitrary
            # uploaded code, not something SpecGen wrote, so there's no safe
            # assumption about where derivation logic should end. Append at
            # the end rather than guessing wrong.
            program = program.rstrip() + "\n\n" + insert_text + "\n"

        state["programs"]["adsl"] = program

        # A previous full-update (see /legacy_apply_update) may have left a
        # single opaque "file" block for this program — now stale, since the
        # program just changed underneath it via a different mechanism.
        stale_key = "adam:adsl_legacy"
        if stale_key in state["blocks"]:
            state["blocks"].pop(stale_key, None)
            if stale_key in state["block_order"]:
                state["block_order"].remove(stale_key)

        parsed = {b["var"]: b for b in parse_adsl_blocks(program)}
        for var in new_blocks:
            b = parsed.get(var)
            if not b:
                continue
            key = f"adam:adsl:{var}"
            state["blocks"][key] = {"label": var, "code": b["code"], "qc": b["qc"],
                                    "approved": False, "kind": "adsl_var", "var": var}
            if key not in state["block_order"]:
                state["block_order"].append(key)

        _, derived, ex_summary, main_step = route_adsl_spec(spec)
        state["main_step_rows"] = {r["Variable"]: r.to_dict() for _, r in main_step.iterrows()}
        state["adsl_available"] = available
        state["adsl_spec_path"] = adsl_spec_path
        state["legacy_upload_path"] = None
        state["legacy_classification"] = None
        state["exported_files"] = []
        state["last_commit"] = None
        state["active_screen"] = "review"
        state["job_status"] = "done"
        state["job_note"] = f"Inserted {len(new_blocks)} new variable(s) into the uploaded program."
    except Exception as e:
        state["job_status"] = "error"
        state["job_note"] = f"Insert failed: {e}"
    finally:
        _GENERATE_LOCKS["adam"].release()


@app.route("/legacy_insert", methods=["POST"])
def legacy_insert():
    state = RUN_STATE["otypes"]["adam"]
    if not state.get("legacy_classification"):
        return _render(active_otype="adam", note_otype="adam", note="Upload and analyze a program first.")

    selected_vars = request.form.getlist("insert_var")
    if not selected_vars:
        return _render(active_otype="adam", note_otype="adam", note="Select at least one variable to insert.")

    lock = _GENERATE_LOCKS["adam"]
    if not lock.acquire(blocking=False):
        return _render(active_otype="adam", note_otype="adam",
                      note="A generation is already running on this tab — wait for it to finish.")

    writer_mode, reviewer_mode = MODE_MAP.get(state["mode"], (None, None))
    state["job_status"] = "running"
    state["job_kind"] = "legacy_insert"
    state["job_note"] = None

    threading.Thread(target=_run_legacy_insert_job,
                     args=(selected_vars, writer_mode, reviewer_mode, state["use_macros"]),
                     daemon=True).start()

    return _render(active_otype="adam")


def _run_legacy_update_job(otype, target_vars):
    """Background thread target for /legacy_preview_update. Calls
    spec_patcher.locate_and_update() once for every selected variable/row
    together (see that function's docstring for why batched) — a PREVIEW
    only, nothing is written to state["programs"] here.

    Which spec to read and how to format each variable/row's instruction
    differs per otype (see _adam_instruction_block/_sdtm_instruction_block/
    _tlf_instruction_block) since locate_and_update() itself is otype-
    agnostic — it just wants pre-built instruction text."""
    state = RUN_STATE["otypes"][otype]
    try:
        legacy_path = state["legacy_upload_path"]
        with open(legacy_path, encoding="utf-8", errors="replace") as f:
            program = f.read()

        if otype == "adam":
            spec_path = state.get("adsl_spec_path") or ADAM_SPEC
            spec = pd.read_excel(spec_path, sheet_name="Variables")
            fmt = _adam_instruction_block
        elif otype == "sdtm":
            variables = sdtm_assembler.read_domain_spec(state["legacy_spec_path"], state["legacy_domain"])
            spec = pd.DataFrame(variables)
            fmt = _sdtm_instruction_block
        else:  # tlf
            rows = pd.read_excel(state["legacy_shell_path"], sheet_name="Shell_Rows")
            spec = _normalize_tlf_rows(rows)
            fmt = _tlf_instruction_block

        instruction_blocks = []
        for var in target_vars:
            row = spec[spec["Variable"] == var]
            if row.empty:
                continue
            instruction_blocks.append(fmt(var, row.iloc[0]))

        new_program, diff = locate_and_update(program, instruction_blocks)

        state["legacy_update_preview"] = {
            "program": new_program,
            "diff": "".join(diff),
            "targeted_vars": target_vars,
        }
        state["job_status"] = "done"
        state["job_note"] = (f"Preview ready for {len(target_vars)} variable(s)/row(s) — review "
                             f"the diff and edit the text below before applying.")
    except Exception as e:
        state["job_status"] = "error"
        state["job_note"] = f"Preview failed: {e}"
    finally:
        _GENERATE_LOCKS[otype].release()


@app.route("/legacy_preview_update", methods=["POST"])
def legacy_preview_update():
    otype = _otype_from_request()
    state = RUN_STATE["otypes"][otype]
    if not state.get("legacy_classification"):
        return _render(active_otype=otype, note_otype=otype, note="Upload and analyze a program first.")

    target_vars = request.form.getlist("update_var")
    if not target_vars:
        return _render(active_otype=otype, note_otype=otype, note="Select at least one variable/row to update.")

    lock = _GENERATE_LOCKS[otype]
    if not lock.acquire(blocking=False):
        return _render(active_otype=otype, note_otype=otype,
                      note="A generation is already running on this tab — wait for it to finish.")

    state["job_status"] = "running"
    state["job_kind"] = "legacy_update"
    state["job_note"] = None

    threading.Thread(target=_run_legacy_update_job, args=(otype, target_vars), daemon=True).start()

    return _render(active_otype=otype)


@app.route("/legacy_apply_update", methods=["POST"])
def legacy_apply_update():
    """Commit a previewed full-update — uses whatever text is in the
    submitted textarea, NOT necessarily state["legacy_update_preview"]'s
    original proposal, since the user may have hand-edited it (the "live
    editing" step). The result becomes one opaque "file" block (the same
    kind every non-ADSL program already uses) rather than forcing per-
    variable tracking onto content that was never structured that way."""
    otype = _otype_from_request()
    state = RUN_STATE["otypes"][otype]
    preview = state.get("legacy_update_preview")
    if not preview:
        return _render(active_otype=otype, note_otype=otype, note="No pending update to apply.")

    edited_program = request.form.get("program_text", preview["program"])

    if otype == "adam":
        # A prior normal generate/insert may have left per-variable adsl
        # blocks — now stale, since this program replaces that content
        # wholesale via a different (whole-file) mechanism.
        stale_keys = [k for k in state["block_order"] if k.startswith("adam:adsl:")]
        for k in stale_keys:
            state["blocks"].pop(k, None)
            state["block_order"].remove(k)
        program_name = "adsl"
        key = "adam:adsl_legacy"
        label = "adsl.sas (uploaded program, updated)"
    elif otype == "sdtm":
        program_name = state["legacy_domain"].lower()
        key = f"sdtm:{program_name}"
        label = f"{program_name}.sas (uploaded program, updated)"
    else:  # tlf
        program_name = os.path.splitext(os.path.basename(state["legacy_upload_path"]))[0]
        key = f"tlf:{program_name}"
        label = f"{program_name}.sas (uploaded program, updated)"

    state["programs"][program_name] = edited_program
    state["blocks"][key] = {"label": label, "code": edited_program,
                            "qc": "NONE", "approved": False, "kind": "file", "var": None}
    if key not in state["block_order"]:
        state["block_order"].append(key)

    state["legacy_upload_path"] = None
    state["legacy_classification"] = None
    state["legacy_update_preview"] = None
    state["legacy_domain"] = None
    state["legacy_spec_path"] = None
    state["legacy_shell_path"] = None
    state["exported_files"] = []
    state["last_commit"] = None
    state["active_screen"] = "review"
    return _render(active_otype=otype)


@app.route("/legacy_cancel_update", methods=["POST"])
def legacy_cancel_update():
    """Discard a previewed full-update without applying it."""
    otype = _otype_from_request()
    state = RUN_STATE["otypes"][otype]
    state["legacy_update_preview"] = None
    return _render(active_otype=otype)


def _run_generate_job(otype, lang, mode, domain, uploaded, force_pending, use_macros=True, ig_version=None):
    """Background thread target for /generate. Doing the (potentially slow)
    generation work off the request thread is what makes /abort possible —
    a request handler that's blocked in subprocess.run()/assemble_adsl() for
    minutes can't also service the separate /abort POST that's supposed to
    interrupt it; a request that just starts this thread and returns can.
    Releases this otype's _GENERATE_LOCKS entry when done (acquired by the
    /generate route before starting the thread)."""
    state = RUN_STATE["otypes"][otype]
    ctrl = _JOB_CTRL[otype]
    try:
        adsl_context = None
        if otype == "adam":
            acrf_path, adsl_spec_path = _classify_adam_uploads(uploaded)
            programs, adsl_context = generate_adam(lang, mode, acrf_path, adsl_spec_path,
                                                    domain=domain, cancel_event=ctrl["cancel_event"],
                                                    use_macros=use_macros, ig_version=ig_version)
            if "adsl" in programs:
                # "Update from new spec" diffs against whatever spec ADSL was
                # actually generated from, so it has to be tracked here where
                # the resolved path (upload or ADAM_SPEC default) is known —
                # generate_adam itself is a pure function with no state access.
                state["adsl_spec_path"] = adsl_spec_path or ADAM_SPEC
        elif otype == "tlf":
            programs = generate_tlf(lang, shells=uploaded or None, domain=domain,
                                    cancel_event=ctrl["cancel_event"], use_macros=use_macros)
        else:
            programs = generate_sdtm(lang, mode, spec_path=uploaded[0] if uploaded else None,
                                     domain=domain, force_pending=force_pending, ctrl=ctrl,
                                     use_macros=use_macros, ig_version=ig_version)

        result_note = programs.pop("(note)", None) if isinstance(programs, dict) else None

        state["programs"] = programs
        state["exported_files"] = []
        state["last_commit"] = None
        _rebuild_blocks(state, otype, programs, adsl_context)
        state["active_screen"] = "review"

        if ctrl["cancel_event"].is_set():
            state["job_status"] = "aborted"
            state["job_note"] = result_note or "Generation aborted by user."
        else:
            state["job_status"] = "done"
            state["job_note"] = result_note
    except Exception as e:
        # An uploaded file can be almost anything (wrong sheet names, wrong
        # shape, corrupted) — surface that as a normal in-app note instead of
        # an unhandled exception in a background thread (which Flask would
        # never see), and leave any earlier successful run's blocks/programs
        # alone rather than partially overwriting them.
        state["job_status"] = "error"
        state["job_note"] = f"Generation failed: {e}"
    finally:
        _GENERATE_LOCKS[otype].release()


def _run_qc_generate_job(otype, lang, writer_mode, ig_version):
    """Background thread target for /qc_generate — independent double-
    programming QC (see qc_generator.py). Same reasoning as
    _run_generate_job for running off the request thread: N model calls,
    one per main-step variable."""
    state = RUN_STATE["otypes"][otype]
    try:
        spec_path = state.get("adsl_spec_path") or ADAM_SPEC
        spec = pd.read_excel(spec_path, sheet_name="Variables")

        qc_program = qc_generator.generate_qc_adsl(spec, language=lang, mode=writer_mode,
                                                    ig_version=ig_version)
        compare_program = qc_generator.generate_compare_harness(spec, language=lang)

        ext = "R" if lang == "r" else "sas"
        state["programs"]["adsl_qc"] = qc_program
        state["programs"]["adsl_compare"] = compare_program
        for name, code in (("adsl_qc", qc_program), ("adsl_compare", compare_program)):
            key = f"{otype}:{name}"
            label = f"{name}.{ext}"
            state["blocks"][key] = {"label": label, "code": code, "qc": "NONE",
                                    "approved": False, "kind": "file", "var": None}
            if key not in state["block_order"]:
                state["block_order"].append(key)

        state["job_status"] = "done"
        state["job_note"] = ("QC re-derivation and PROC COMPARE harness generated — "
                             "review adsl_qc and adsl_compare below.")
    except Exception as e:
        state["job_status"] = "error"
        state["job_note"] = f"QC generation failed: {e}"
    finally:
        _GENERATE_LOCKS[otype].release()


@app.route("/qc_generate", methods=["POST"])
def qc_generate():
    """Independent double-programming QC for ADSL (see qc_generator.py):
    re-derives every main-step variable from the same spec via its own
    model call (macros never offered — see that module's docstring), then
    a deterministic PROC COMPARE / data-frame-diff harness reconciling it
    against production adsl. Requires ADSL to have been generated already
    — there's nothing to independently re-derive or compare against
    otherwise."""
    otype = "adam"
    state = RUN_STATE["otypes"][otype]
    if "adsl" not in state.get("programs", {}):
        return _render(active_otype=otype, note_otype=otype,
                      note="Generate ADSL first — QC mode independently re-derives "
                          "it and compares against the result.")

    lock = _GENERATE_LOCKS[otype]
    if not lock.acquire(blocking=False):
        return _render(active_otype=otype, note_otype=otype,
                      note="A generation is already running on this tab — wait for it to finish.")

    writer_mode, _ = MODE_MAP.get(state["mode"], (None, None))
    state["job_status"] = "running"
    state["job_kind"] = "qc_generate"
    state["job_note"] = None
    threading.Thread(target=_run_qc_generate_job,
                     args=(otype, state["lang"], writer_mode, state["adamig_version"]),
                     daemon=True).start()
    return _render(active_otype=otype)


@app.route("/generate", methods=["POST"])
def generate():
    otype = _otype_from_request()
    state = RUN_STATE["otypes"][otype]
    lock = _GENERATE_LOCKS[otype]
    if not lock.acquire(blocking=False):
        return _render(active_otype=otype, note_otype=otype,
                      note="A generation is already running — please wait for it "
                          "to finish, or use Abort, instead of clicking Generate again.")

    mode = request.form.get("mode", state["mode"])
    lang = request.form.get("lang", state["lang"])
    domain = request.form.get("domain", "all") or "all"
    state["mode"] = mode
    state["lang"] = lang
    state["selected_domain"] = domain
    # Checkbox: present in the form only when checked, absent when not —
    # standard HTML behavior, no hidden-fallback field needed. All 3 tabs
    # have this control now (ADaM: exact-match substitution in ADSL SAS;
    # SDTM: hint offered to the Writer per domain; TLF: direct codegen
    # substitution, since TLF has no model calls at all).
    state["use_macros"] = "use_macros" in request.form
    ig_version = state["sdtmig_version"] if otype == "sdtm" else state["adamig_version"] if otype == "adam" else None

    # Uploaded files only exist on request.files for THIS request, so they
    # must be saved to disk here, synchronously, before the background
    # thread starts — the thread only gets back plain file paths.
    uploaded = _resolve_uploads(request.files.getlist("spec_file"), otype)
    force_pending = state["sdtm_force_pending"]
    state["sdtm_force_pending"] = False

    ctrl = _JOB_CTRL[otype]
    ctrl["cancel_event"].clear()
    ctrl["proc"] = None
    state["job_status"] = "running"
    state["job_kind"] = "generate"
    state["job_note"] = None

    threading.Thread(target=_run_generate_job,
                     args=(otype, lang, mode, domain, uploaded, force_pending, state["use_macros"], ig_version),
                     daemon=True).start()

    return _render(active_otype=otype)


@app.route("/abort", methods=["POST"])
def abort():
    otype = _otype_from_request()
    ctrl = _JOB_CTRL[otype]
    ctrl["cancel_event"].set()
    proc = ctrl["proc"]
    if proc is not None and proc.poll() is None:
        proc.terminate()  # SDTM only — ADaM/TLF notice cancel_event cooperatively instead

    state = RUN_STATE["otypes"][otype]
    if state["job_status"] == "running":
        state["job_note"] = "Aborting — finishing up the current step…"
    return _render(active_otype=otype)


@app.route("/job_status", methods=["GET"])
def job_status():
    """Polled by the Generate screen while a job is running, so the page can
    flip to the finished Review screen (or show the abort/error note) without
    the user needing to refresh manually."""
    otype = request.args.get("otype", "adam")
    otype = otype if otype in OTYPES else "adam"
    state = RUN_STATE["otypes"][otype]
    return jsonify(status=state["job_status"], note=state["job_note"])


@app.route("/approve", methods=["POST"])
def approve():
    key = request.form.get("block_key", "")
    otype = key.split(":", 1)[0] if ":" in key else "adam"
    otype = otype if otype in OTYPES else "adam"
    state = RUN_STATE["otypes"][otype]
    if key in state["blocks"]:
        state["blocks"][key]["approved"] = True
    return _render(active_otype=otype)


@app.route("/adsl_improve", methods=["POST"])
def adsl_improve():
    key = request.form.get("block_key", "")
    otype = key.split(":", 1)[0] if ":" in key else "adam"
    otype = otype if otype in OTYPES else "adam"
    state = RUN_STATE["otypes"][otype]
    block = state["blocks"].get(key)
    if block and block["kind"] == "adsl_var":
        improve_adsl_block(block["var"])
    return _render(active_otype=otype)


@app.route("/adsl_review", methods=["POST"])
def adsl_review():
    key = request.form.get("block_key", "")
    otype = key.split(":", 1)[0] if ":" in key else "adam"
    otype = otype if otype in OTYPES else "adam"
    state = RUN_STATE["otypes"][otype]
    block = state["blocks"].get(key)
    if block and block["kind"] == "adsl_var":
        review_adsl_block(block["var"])
    return _render(active_otype=otype)


def _strip_sdtm_qc_marker(code):
    """Remove a leading QC marker comment line (added by a previous Review),
    if present, so re-running Improve/Review doesn't compound stale marker
    text, and so Improve doesn't see a stale verdict as part of "the code"."""
    return re.sub(r'^(?:/\* QC (?:FLAG: .*?|PASS) \*/|# QC (?:FLAG: .*|PASS))\n', '', code)


def _run_sdtm_improve_job(domain, use_api, language, ig_version=None):
    """Background thread target for /sdtm_improve — same non-blocking
    rationale as every other model-calling job in this app. Writes the
    improved program back to BOTH state["programs"] AND the actual
    sdtm_programs/<domain>.<ext> file on disk: Export's SDTM branch just
    lists already-on-disk paths rather than rewriting them (unlike ADaM/
    TLF), so skipping the disk write would make Export silently ship the
    pre-improve draft."""
    state = RUN_STATE["otypes"]["sdtm"]
    try:
        spec_path = state["uploaded_paths"][0] if state["uploaded_paths"] else SDTM_SPEC
        variables = sdtm_assembler.read_domain_spec(spec_path, domain)
        domain_lower = domain.lower()
        current_code = _strip_sdtm_qc_marker(state["programs"][domain_lower])

        improved = sdtm_assembler.improve_domain_program(domain, current_code, variables,
                                                          use_api=use_api, language=language,
                                                          ig_version=ig_version)

        ext = "R" if language == "r" else "sas"
        file_path = os.path.join("sdtm_programs", f"{domain_lower}.{ext}")
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(improved)

        key = f"sdtm:{domain_lower}"
        state["programs"][domain_lower] = improved
        state["blocks"][key]["code"] = improved
        # A prior Review verdict no longer applies to code Improve just
        # changed — reset until Review runs again, same convention as ADaM.
        state["blocks"][key]["qc"] = "NONE"
        state["blocks"][key]["approved"] = False
        state["job_status"] = "done"
        state["job_note"] = f"Improved {domain}."
    except Exception as e:
        state["job_status"] = "error"
        state["job_note"] = f"Improve failed: {e}"
    finally:
        _GENERATE_LOCKS["sdtm"].release()


def _run_sdtm_review_job(domain, use_api, language, ig_version=None):
    """Background thread target for /sdtm_review. Unlike the old single-shot
    pipeline's review_sas(draft) call — which passed the raw generated CODE
    in as if it were the prompt, so it never produced a real verdict and the
    result was discarded after printing — this uses a genuine PASS/FAIL
    review prompt (sdtm_assembler.review_domain_program) and actually
    surfaces the verdict as the block's QC badge, plus prepends it as a
    comment in the code (same audit-trail-in-code convention ADaM's QC FLAG/
    QC PASS markers already use)."""
    state = RUN_STATE["otypes"]["sdtm"]
    try:
        spec_path = state["uploaded_paths"][0] if state["uploaded_paths"] else SDTM_SPEC
        variables = sdtm_assembler.read_domain_spec(spec_path, domain)
        domain_lower = domain.lower()
        current_code = _strip_sdtm_qc_marker(state["programs"][domain_lower])

        verdict = sdtm_assembler.review_domain_program(domain, current_code, variables,
                                                        use_api=use_api, language=language,
                                                        ig_version=ig_version)
        qc = "FAIL" if verdict.startswith("FAIL") else "PASS"
        comment = f"QC FLAG: {verdict}" if qc == "FAIL" else "QC PASS"
        marker = f"# {comment}\n" if language == "r" else f"/* {comment} */\n"
        new_code = marker + current_code

        ext = "R" if language == "r" else "sas"
        file_path = os.path.join("sdtm_programs", f"{domain_lower}.{ext}")
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(new_code)

        key = f"sdtm:{domain_lower}"
        state["programs"][domain_lower] = new_code
        state["blocks"][key]["code"] = new_code
        state["blocks"][key]["qc"] = qc
        state["blocks"][key]["approved"] = False
        state["job_status"] = "done"
        state["job_note"] = f"Reviewed {domain}: {verdict}"
    except Exception as e:
        state["job_status"] = "error"
        state["job_note"] = f"Review failed: {e}"
    finally:
        _GENERATE_LOCKS["sdtm"].release()


@app.route("/sdtm_improve", methods=["POST"])
def sdtm_improve():
    key = request.form.get("block_key", "")
    state = RUN_STATE["otypes"]["sdtm"]
    block = state["blocks"].get(key)
    if not block or block["kind"] != "sdtm_domain":
        return _render(active_otype="sdtm")

    lock = _GENERATE_LOCKS["sdtm"]
    if not lock.acquire(blocking=False):
        return _render(active_otype="sdtm", note_otype="sdtm",
                      note="A generation is already running on this tab — wait for it to finish.")

    domain = block["label"].upper()
    _, reviewer_mode = MODE_MAP.get(state["mode"], (None, None))
    use_api = reviewer_mode == "api"
    state["job_status"] = "running"
    state["job_kind"] = "sdtm_improve"
    state["job_note"] = None
    threading.Thread(target=_run_sdtm_improve_job,
                     args=(domain, use_api, state["lang"], state["sdtmig_version"]), daemon=True).start()
    return _render(active_otype="sdtm")


@app.route("/sdtm_review", methods=["POST"])
def sdtm_review():
    key = request.form.get("block_key", "")
    state = RUN_STATE["otypes"]["sdtm"]
    block = state["blocks"].get(key)
    if not block or block["kind"] != "sdtm_domain":
        return _render(active_otype="sdtm")

    lock = _GENERATE_LOCKS["sdtm"]
    if not lock.acquire(blocking=False):
        return _render(active_otype="sdtm", note_otype="sdtm",
                      note="A generation is already running on this tab — wait for it to finish.")

    domain = block["label"].upper()
    _, reviewer_mode = MODE_MAP.get(state["mode"], (None, None))
    use_api = reviewer_mode == "api"
    state["job_status"] = "running"
    state["job_kind"] = "sdtm_review"
    state["job_note"] = None
    threading.Thread(target=_run_sdtm_review_job,
                     args=(domain, use_api, state["lang"], state["sdtmig_version"]), daemon=True).start()
    return _render(active_otype="sdtm")


@app.route("/export", methods=["POST"])
def export():
    otype = _otype_from_request()
    state = RUN_STATE["otypes"][otype]
    approved, total = _signoff_counts(state)
    if total == 0 or approved < total:
        return _render(active_otype=otype, note_otype=otype,
                      note="Export locked: not every block is approved yet.")

    ext = "R" if state["lang"] == "r" else "sas"
    written = []
    if otype == "adam":
        for name, code in state["programs"].items():
            path = "adsl.%s" % ext if name == "adsl" else os.path.join("adam_programs", f"{name}.{ext}")
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(code)
            written.append(path)
    elif otype == "tlf":
        for name, code in state["programs"].items():
            path = os.path.join("tlf_programs", f"{name}.{ext}")
            os.makedirs("tlf_programs", exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(code)
            written.append(path)
    else:  # sdtm — sdtm_assembler.py already wrote these to disk during Generate
        written = [os.path.join("sdtm_programs", f"{name}.sas") for name in state["programs"]]

    state["exported_files"] = written
    state["active_screen"] = "export"
    return _render(active_otype=otype, note_otype=otype, note=f"Exported {len(written)} file(s).")


@app.route("/download", methods=["GET"])
def download():
    """Serve one exported file for download. otype+path must match an
    entry in that tab's OWN exported_files — an app-controlled list, not an
    arbitrary path taken from the query string — so this can't be used to
    fetch any other file on disk."""
    otype = request.args.get("otype", "adam")
    otype = otype if otype in OTYPES else "adam"
    path = request.args.get("path", "")
    state = RUN_STATE["otypes"][otype]
    if path not in state["exported_files"]:
        return "Not an exported file for this tab.", 404
    return send_file(os.path.abspath(path), as_attachment=True, download_name=os.path.basename(path))


@app.route("/commit", methods=["POST"])
def commit():
    otype = _otype_from_request()
    state = RUN_STATE["otypes"][otype]
    files = state["exported_files"]
    if not files:
        state["last_commit"] = {"ok": False, "message": "Nothing exported yet."}
        return _render(active_otype=otype)

    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    msg = (f"Generate {otype.upper()} ({state['lang'].upper()}) "
          f"via SpecGen app — mode={state['mode']}, {ts}")
    try:
        subprocess.run(["git", "add", "--"] + files, check=True, capture_output=True, text=True)
        commit_res = subprocess.run(["git", "commit", "-m", msg], capture_output=True, text=True)
        if commit_res.returncode != 0:
            state["last_commit"] = {"ok": False, "message": commit_res.stdout + commit_res.stderr}
            return _render(active_otype=otype)
        push_res = subprocess.run(["git", "push", "origin", "main"], capture_output=True, text=True)
        short_hash = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                                    capture_output=True, text=True).stdout.strip()
        ok = push_res.returncode == 0
        state["last_commit"] = {
            "ok": ok, "hash": short_hash,
            "message": msg if ok else msg + "\n\nPush failed:\n" + push_res.stdout + push_res.stderr,
        }
    except Exception as e:
        state["last_commit"] = {"ok": False, "message": str(e)}

    return _render(active_otype=otype)


if __name__ == "__main__":
    # use_reloader=False: Werkzeug's file-watcher has repeatedly misfired in
    # this environment (observed reloading mid-request over unrelated
    # filesystem noise, once even over changes it claimed were inside
    # site-packages/flask itself) — a reload kills the in-flight request's
    # worker process without ever replying, which looks exactly like the
    # browser being stuck loading forever. debug=True is kept for its error
    # pages/tracebacks; only the auto-restart-on-file-change behavior is off.
    app.run(debug=True, port=5000, use_reloader=False)
