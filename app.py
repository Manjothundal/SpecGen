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
from flask import Flask, jsonify, render_template, request
from werkzeug.utils import secure_filename

import bds_assembler as bds
import tlf_assembler as tlf
import sdtm_assembler
import config
from assembler import assemble_adsl, gen_block, clean, known_variables, _r_add_comma
from improver import improve_block
from reviewer import review_block
from spec_differ import diff_specs
from spec_patcher import patch_program

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
        "spec_diff": None,           # ADaM only: pending diff preview, set by /spec_diff
        "pending_spec_v2": None,     # ADaM only: uploaded v2 spec path awaiting /apply_patch
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
                  use_macros=True):
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
                                    use_macros=use_macros)
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


def generate_sdtm(lang, mode, spec_path=None, domain="all", force_pending=False, ctrl=None, use_macros=True):
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

    SDTM's pipeline only has a binary use_api flag today (no true Hybrid, this
    is a known asymmetry with ADSL) — Offline stays local-only; Hybrid and API
    both map to use_api=True since that's the only "reviewed" option SDTM has.

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
    if mode == "offline":
        cmd.append("--offline")
    if force:
        cmd.append("--force")
    if single_domain_forced:
        cmd.extend(["--domain", domain])
    if not use_macros:
        cmd.append("--no-macros")
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
    markers. Returns [{"var":..., "code":..., "qc": "PASS"|"FAIL"}, ...]."""
    sas_pattern = re.compile(r'/\*-- BEGIN (\w+) --\*/\n(.*?)\n/\*-- END \1 --\*/', re.DOTALL)
    r_pattern = re.compile(r'# -- BEGIN (\w+) -- #\n(.*?)\n(?: {4})?# -- END \1 -- #', re.DOTALL)
    matches = list(sas_pattern.finditer(code)) or list(r_pattern.finditer(code))
    blocks = []
    for m in matches:
        var, body = m.group(1), m.group(2).strip("\n")
        qc = "FAIL" if "QC FLAG" in body else "PASS"
        blocks.append({"var": var, "code": body, "qc": qc})
    return blocks


def _sas_block_pattern(var):
    return re.compile(rf'/\*-- BEGIN {re.escape(var)} --\*/\n(.*?)\n/\*-- END {re.escape(var)} --\*/', re.DOTALL)


def _r_block_pattern(var):
    return re.compile(rf'# -- BEGIN {re.escape(var)} -- #\n(.*?)\n(?: {{4}})?# -- END {re.escape(var)} -- #', re.DOTALL)


def regenerate_adsl_block(var):
    """Re-run Writer -> Improver -> Reviewer for ONE ADSL variable and splice
    the result back into the stored adsl program text (fresh offsets each
    time, so repeated re-generation of different blocks stays correct even
    though earlier edits changed the surrounding text's length). ADSL only
    ever lives under the ADaM tab, so this always operates on that tab's
    own state."""
    state = RUN_STATE["otypes"]["adam"]
    lang = state["lang"]
    writer_mode, reviewer_mode = MODE_MAP.get(state["mode"], (None, None))
    row = state["main_step_rows"][var]
    available = state["adsl_available"]

    block = gen_block(row, language=lang, writer_mode=writer_mode)
    block = clean(improve_block(block, row, available, language=lang, mode=reviewer_mode))
    verdict = review_block(block, available, language=lang, mode=reviewer_mode)
    qc = "FAIL" if verdict.startswith("FAIL") else "PASS"

    if lang == "sas":
        if qc == "FAIL":
            block = f"/* QC FLAG: {verdict} */\n" + block
        new_body = block
        pattern = _sas_block_pattern(var)
    else:
        raw_lines = block.splitlines()
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
        if qc == "FAIL":
            new_body = f"    # QC FLAG: {verdict}\n" + new_body
        pattern = _r_block_pattern(var)

    program = state["programs"]["adsl"]
    m = pattern.search(program)
    if m:
        program = program[:m.start(1)] + new_body + program[m.end(1):]
        state["programs"]["adsl"] = program

    key = "adam:adsl:" + var
    state["blocks"][key]["code"] = new_body
    state["blocks"][key]["qc"] = qc
    state["blocks"][key]["approved"] = False


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
        blocks[key] = {"label": name, "code": code, "qc": "NONE",
                      "approved": False, "kind": "file", "var": None}
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
        )

    return render_template(
        "index.html",
        active_otype=RUN_STATE["active_otype"],
        tabs=tabs,
        runlog_rows=_read_runlog_tail(),
    )


def _read_runlog_tail(n=8):
    if not os.path.exists("runlog.csv"):
        return []
    with open("runlog.csv", encoding="utf-8") as f:
        lines = [l.strip() for l in f if l.strip()]
    if len(lines) < 2:
        return []
    header = lines[0].split(",")
    rows = [dict(zip(header, l.split(","))) for l in lines[1:][-n:]]
    rows.reverse()
    return rows


def _otype_from_request(default="adam"):
    otype = request.form.get("otype", default)
    return otype if otype in OTYPES else default


@app.route("/", methods=["GET"])
def index():
    return _render()


@app.route("/parse", methods=["POST"])
def parse_spec():
    otype = _otype_from_request()
    state = RUN_STATE["otypes"][otype]
    # Each tab's own modebar carries its own hardcoded otype, mode, lang —
    # there's no shared field for another tab's action to clobber.
    state["mode"] = request.form.get("mode", state["mode"])
    state["lang"] = request.form.get("lang", state["lang"])

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


def _run_generate_job(otype, lang, mode, domain, uploaded, force_pending, use_macros=True):
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
                                                    use_macros=use_macros)
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
                                     use_macros=use_macros)

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
                     args=(otype, lang, mode, domain, uploaded, force_pending, state["use_macros"]),
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


@app.route("/send_back", methods=["POST"])
def send_back():
    key = request.form.get("block_key", "")
    otype = key.split(":", 1)[0] if ":" in key else "adam"
    otype = otype if otype in OTYPES else "adam"
    state = RUN_STATE["otypes"][otype]
    block = state["blocks"].get(key)
    if block and block["kind"] == "adsl_var":
        regenerate_adsl_block(block["var"])
    return _render(active_otype=otype)


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
