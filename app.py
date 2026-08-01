"""
app.py — SpecGen web app (Flask).

A 4-screen flow modeled on docs/specgen_ui_mockup (1).html: Spec -> Generate ->
Review & sign off -> Export & audit. (Compare & verify is not implemented —
it's Phase 9, a from-scratch RTF/Word/PDF diff engine that doesn't exist yet.)

State lives in one in-memory dict (RUN_STATE) — this is a single-operator
local tool running on Flask's synchronous dev server, so there is only ever
one run in flight; no session/DB layer is needed.

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
from flask import Flask, render_template, request
from werkzeug.utils import secure_filename

import bds_assembler as bds
import tlf_assembler as tlf
import sdtm_assembler
import config
from assembler import assemble_adsl, gen_block, clean, known_variables, _r_add_comma
from improver import improve_block
from reviewer import review_block

app = Flask(__name__)

ACRF = "acrf_metadata.xlsx"
ADAM_SPEC = "adam_spec_full.xlsx"
SDTM_SPEC = "sdtm_spec_draft.xlsx"
SHELLS = ["sample_shell_demographics.xlsx", "sample_shell_ae.xlsx"]

# Mode switcher (Offline/Hybrid/API) -> (writer_mode, reviewer_mode). Only
# affects ADSL and SDTM generation — BDS datasets are deterministic string
# templates with no model calls either way.
MODE_MAP = {
    "offline": ("local", "local"),
    "hybrid": ("local", "api"),
    "api": ("api", "api"),
}

RUN_STATE = {
    "otype": None,
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
    "uploaded_for_otype": None,  # which otype uploaded_paths belongs to
}

# Uploads are saved here once per run and reused across the Spec -> Generate
# requests (the Spec screen's upload should still apply when you later click
# Generate, without re-uploading) — cleared only when a new upload replaces it.
UPLOAD_DIR = tempfile.mkdtemp(prefix="specgen_run_")

# Generation (especially SDTM with --force, or ADSL) can legitimately take
# minutes with zero progress feedback in the UI — indistinguishable from
# "stuck" to someone waiting on it. Without this, re-clicking Generate during
# a slow run spawns ANOTHER overlapping sdtm_assembler.py/assemble_adsl call
# on top of the first instead of just waiting for it.
_GENERATE_LOCK = threading.Lock()


# ---------------------------------------------------------------------------
# Upload handling
# ---------------------------------------------------------------------------

def _save_uploads(files):
    """Save any non-empty uploaded files into UPLOAD_DIR. Returns saved paths,
    or [] if no files were submitted (caller should then fall back to
    RUN_STATE["uploaded_paths"] from a prior request in this run)."""
    saved = []
    for f in files:
        if f and f.filename:
            path = os.path.join(UPLOAD_DIR, secure_filename(f.filename))
            f.save(path)
            saved.append(path)
    return saved


def _resolve_uploads(files, otype):
    """New files this request replace any previously uploaded ones; otherwise
    reuse what's already stored in RUN_STATE from an earlier step — but ONLY
    if it was uploaded for the SAME otype. Without this, uploading a file for
    one otype (e.g. an SDTM spec) then switching to another (e.g. TLF) would
    silently hand that same file to the new otype's generator, which expects
    a completely different sheet structure and crashes instead of falling
    back to the sample defaults.
    """
    new_uploads = _save_uploads(files)
    if new_uploads:
        RUN_STATE["uploaded_paths"] = new_uploads
        RUN_STATE["uploaded_for_otype"] = otype
    elif RUN_STATE.get("uploaded_for_otype") != otype:
        return []
    return RUN_STATE["uploaded_paths"]


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


# ---------------------------------------------------------------------------
# Generators
# ---------------------------------------------------------------------------

def generate_adam(lang, mode, acrf_path=None, adsl_spec_path=None):
    """Return (programs, adsl_context). programs: {name: code}. adsl_context
    is {"main_step_rows": {...}, "available": [...]} when ADSL was generated,
    else None (used later for "send back to Improver")."""
    writer_mode, reviewer_mode = MODE_MAP.get(mode, (None, None))
    out = {}
    adsl_context = None

    acrf_path = acrf_path or ACRF
    if os.path.exists(acrf_path):
        acrf = pd.read_excel(acrf_path, sheet_name="By Domain")
        present = set(acrf["Domain"].unique())

        for dom, src, code in [("VS", "vs", "ADVS"), ("LB", "lb", "ADLB"),
                               ("EG", "eg", "ADEG"), ("TR", "tr", "ADTR")]:
            if dom not in present:
                continue
            try:
                params = bds.build_param_spec_from_acrf(acrf, dom, dom + "TESTCD")
            except ValueError:
                continue
            out[code.lower()] = bds.generate_bds_domain(src, params, code, language=lang)

        if "AE" in present:
            out["adae"] = bds.generate_ae_domain("ADAE", language=lang)
        if "CM" in present:
            out["adcm"] = bds.generate_cm_domain("ADCM", language=lang)
        if "RS" in present:
            if lang == "r":
                out["adrs"] = bds.generate_rs_domain_r("ADRS")
                out["adtte"] = bds.generate_tte_domain_r("ADTTE")
            else:
                out["adrs"] = bds.generate_rs_domain("ADRS")
                out["adtte"] = bds.generate_tte_domain("ADTTE")

    adsl_spec_path = adsl_spec_path or ADAM_SPEC
    if os.path.exists(adsl_spec_path):
        spec = pd.read_excel(adsl_spec_path, sheet_name="Variables")
        _, derived, ex_summary, main_step = route_adsl_spec(spec)
        out["adsl"] = assemble_adsl(spec, derived, ex_summary, main_step,
                                    language=lang, writer_mode=writer_mode,
                                    reviewer_mode=reviewer_mode)
        adsl_context = {
            "main_step_rows": {row["Variable"]: row.to_dict()
                              for _, row in main_step.iterrows()},
            "available": known_variables(spec),
        }

    return out, adsl_context


def generate_tlf(lang, shells=None):
    """Return dict {name: code} for each shell (uploaded, or the sample shells)."""
    out = {}
    for shell in (shells or SHELLS):
        if not os.path.exists(shell):
            continue
        meta, _ = tlf._read_shell(shell)
        tid = str(meta.get("table_id", "table")).replace(".", "_")
        out[f"t_{tid}"] = tlf.generate_table(shell, language=lang)
    return out


def generate_sdtm(lang, mode, spec_path=None):
    """Run sdtm_assembler.py as a subprocess, then read the .sas files back.
    Note: SDTM generation is SAS-only in the current assembler; lang is ignored
    here and we tell the user.

    sdtm_assembler.py skips domains whose output file already exists unless
    --force is passed, so a hand-QC'd fix in sdtm_programs/ survives repeat
    "Generate" clicks. An explicit spec upload is a deliberate request to
    (re)generate from that spec, so it passes --force; the no-upload default
    (sample spec, just viewing current output) does not.

    SDTM's pipeline only has a binary use_api flag today (no true Hybrid, this
    is a known asymmetry with ADSL) — Offline stays local-only; Hybrid and API
    both map to use_api=True since that's the only "reviewed" option SDTM has.
    """
    force = spec_path is not None
    spec_path = spec_path or SDTM_SPEC
    out = {}
    if not os.path.exists(spec_path):
        return {"(error)": f"{spec_path} not found in project folder."}

    # Only read back domains actually defined in THIS spec — sdtm_programs/
    # is a shared output folder reused across whichever spec was last run
    # (sample or an uploaded one), so glob("*.sas") would mix in unrelated
    # leftover files from a different spec's earlier run. SUPP-- domains
    # don't have their own file (append_supp_domain merges them into their
    # parent's), so only list the non-SUPP domains here.
    domains = [d for d in sdtm_assembler.list_domains(spec_path) if not d.startswith("SUPP")]

    cmd = [sys.executable, "sdtm_assembler.py", spec_path]
    if mode == "offline":
        cmd.append("--offline")
    if force:
        cmd.append("--force")
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=600)
    except subprocess.CalledProcessError as e:
        return {"(error)": f"sdtm_assembler failed:\n{e.stderr}"}

    for domain in domains:
        path = os.path.join("sdtm_programs", f"{domain.lower()}.sas")
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                out[domain.lower()] = f.read()
    return out


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
    though earlier edits changed the surrounding text's length)."""
    lang = RUN_STATE["lang"]
    writer_mode, reviewer_mode = MODE_MAP.get(RUN_STATE["mode"], (None, None))
    row = RUN_STATE["main_step_rows"][var]
    available = RUN_STATE["adsl_available"]

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

    program = RUN_STATE["programs"]["adsl"]
    m = pattern.search(program)
    if m:
        program = program[:m.start(1)] + new_body + program[m.end(1):]
        RUN_STATE["programs"]["adsl"] = program

    key = "adam:adsl:" + var
    RUN_STATE["blocks"][key]["code"] = new_body
    RUN_STATE["blocks"][key]["qc"] = qc
    RUN_STATE["blocks"][key]["approved"] = False


# ---------------------------------------------------------------------------
# Block bookkeeping shared by the Generate / Review screens
# ---------------------------------------------------------------------------

def _rebuild_blocks(otype, programs, adsl_context):
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

    RUN_STATE["blocks"] = blocks
    RUN_STATE["block_order"] = order
    RUN_STATE["main_step_rows"] = (adsl_context or {}).get("main_step_rows", {})
    RUN_STATE["adsl_available"] = (adsl_context or {}).get("available", [])


def _signoff_counts():
    total = len(RUN_STATE["blocks"])
    approved = sum(1 for b in RUN_STATE["blocks"].values() if b["approved"])
    return approved, total


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

def _render(active_screen="spec", note=None):
    approved, total = _signoff_counts()
    return render_template(
        "index.html",
        otype=RUN_STATE["otype"], lang=RUN_STATE["lang"], mode=RUN_STATE["mode"],
        routing=RUN_STATE["routing"],
        block_order=RUN_STATE["block_order"], blocks=RUN_STATE["blocks"],
        approved=approved, total_blocks=total,
        exported_files=RUN_STATE["exported_files"], last_commit=RUN_STATE["last_commit"],
        runlog_rows=_read_runlog_tail(),
        writer_model=config.LOCAL_MODEL if RUN_STATE["mode"] == "offline" else
                    (config.LOCAL_MODEL if RUN_STATE["mode"] == "hybrid" else config.API_MODEL),
        reviewer_model=config.API_MODEL if RUN_STATE["mode"] in ("hybrid", "api") else config.LOCAL_MODEL,
        active_screen=active_screen, note=note,
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


@app.route("/", methods=["GET"])
def index():
    return _render("spec")


@app.route("/parse", methods=["POST"])
def parse_spec():
    # Fall back to whatever was already selected (RUN_STATE), not a hardcoded
    # default — the Spec screen's own "Parse spec" form doesn't carry lang/mode
    # fields, so defaulting to "sas"/"hybrid" here would silently wipe out a
    # Language/Mode choice made via the modebar just before parsing.
    otype = request.form.get("otype", RUN_STATE["otype"] or "adam")
    lang = request.form.get("lang", RUN_STATE["lang"])
    mode = request.form.get("mode", RUN_STATE["mode"])
    RUN_STATE.update(otype=otype, lang=lang, mode=mode)

    uploaded = _resolve_uploads(request.files.getlist("spec_file"), otype)
    routing = {}
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
    elif otype == "sdtm":
        spec_path = uploaded[0] if uploaded else SDTM_SPEC
        if os.path.exists(spec_path):
            domains = sdtm_assembler.list_domains(spec_path)
            routing["SDTM domains"] = {d: sdtm_assembler.get_domain_class(d) for d in domains}
    else:  # tlf
        shell_table_ids = {}
        for shell in (uploaded or SHELLS):
            if os.path.exists(shell):
                meta, _ = tlf._read_shell(shell)
                shell_table_ids[os.path.basename(shell)] = meta.get("table_id", "?")
        routing["Shells"] = shell_table_ids
    RUN_STATE["routing"] = routing

    return _render("generate")


@app.route("/generate", methods=["POST"])
def generate():
    if not _GENERATE_LOCK.acquire(blocking=False):
        return _render("generate", note="A generation is already running — please wait for it "
                                        "to finish instead of clicking Generate again. Large specs "
                                        "with --force (an uploaded spec) can legitimately take "
                                        "several minutes with no progress shown.")
    try:
        otype = request.form.get("otype", RUN_STATE["otype"] or "adam")
        lang = request.form.get("lang", RUN_STATE["lang"])
        mode = request.form.get("mode", RUN_STATE["mode"])
        RUN_STATE.update(otype=otype, lang=lang, mode=mode)
        note = None
        if otype == "sdtm" and lang == "r":
            note = "SDTM generation is currently SAS-only; showing SAS programs."

        uploaded = _resolve_uploads(request.files.getlist("spec_file"), otype)
        adsl_context = None
        try:
            if otype == "adam":
                acrf_path, adsl_spec_path = _classify_adam_uploads(uploaded)
                programs, adsl_context = generate_adam(lang, mode, acrf_path, adsl_spec_path)
            elif otype == "tlf":
                programs = generate_tlf(lang, shells=uploaded or None)
            else:
                programs = generate_sdtm(lang, mode, spec_path=uploaded[0] if uploaded else None)
        except Exception as e:
            # An uploaded file can be almost anything (wrong sheet names, wrong
            # shape, corrupted) — surface that as a normal in-app error instead
            # of a raw Flask traceback page, and leave any earlier successful
            # run's blocks/programs alone rather than partially overwriting them.
            return _render("generate", note=f"Generation failed: {e}")

        RUN_STATE["programs"] = programs
        RUN_STATE["exported_files"] = []
        RUN_STATE["last_commit"] = None
        _rebuild_blocks(otype, programs, adsl_context)
    finally:
        _GENERATE_LOCK.release()

    return _render("review", note=note)


@app.route("/approve", methods=["POST"])
def approve():
    key = request.form.get("block_key")
    if key in RUN_STATE["blocks"]:
        RUN_STATE["blocks"][key]["approved"] = True
    return _render("review")


@app.route("/send_back", methods=["POST"])
def send_back():
    key = request.form.get("block_key")
    block = RUN_STATE["blocks"].get(key)
    if block and block["kind"] == "adsl_var":
        regenerate_adsl_block(block["var"])
    return _render("review")


@app.route("/export", methods=["POST"])
def export():
    approved, total = _signoff_counts()
    if total == 0 or approved < total:
        return _render("export", note="Export locked: not every block is approved yet.")

    ext = "R" if RUN_STATE["lang"] == "r" else "sas"
    otype = RUN_STATE["otype"]
    written = []
    if otype == "adam":
        for name, code in RUN_STATE["programs"].items():
            path = "adsl.%s" % ext if name == "adsl" else os.path.join("adam_programs", f"{name}.{ext}")
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(code)
            written.append(path)
    elif otype == "tlf":
        for name, code in RUN_STATE["programs"].items():
            path = os.path.join("tlf_programs", f"{name}.{ext}")
            os.makedirs("tlf_programs", exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(code)
            written.append(path)
    else:  # sdtm — sdtm_assembler.py already wrote these to disk during Generate
        written = [os.path.join("sdtm_programs", f"{name}.sas") for name in RUN_STATE["programs"]]

    RUN_STATE["exported_files"] = written
    return _render("export", note=f"Exported {len(written)} file(s).")


@app.route("/commit", methods=["POST"])
def commit():
    files = RUN_STATE["exported_files"]
    if not files:
        RUN_STATE["last_commit"] = {"ok": False, "message": "Nothing exported yet."}
        return _render("export")

    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    msg = (f"Generate {RUN_STATE['otype'].upper()} ({RUN_STATE['lang'].upper()}) "
          f"via SpecGen app — mode={RUN_STATE['mode']}, {ts}")
    try:
        subprocess.run(["git", "add", "--"] + files, check=True, capture_output=True, text=True)
        commit_res = subprocess.run(["git", "commit", "-m", msg], capture_output=True, text=True)
        if commit_res.returncode != 0:
            RUN_STATE["last_commit"] = {"ok": False, "message": commit_res.stdout + commit_res.stderr}
            return _render("export")
        push_res = subprocess.run(["git", "push", "origin", "main"], capture_output=True, text=True)
        short_hash = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                                    capture_output=True, text=True).stdout.strip()
        ok = push_res.returncode == 0
        RUN_STATE["last_commit"] = {
            "ok": ok, "hash": short_hash,
            "message": msg if ok else msg + "\n\nPush failed:\n" + push_res.stdout + push_res.stderr,
        }
    except Exception as e:
        RUN_STATE["last_commit"] = {"ok": False, "message": str(e)}

    return _render("export")


if __name__ == "__main__":
    # use_reloader=False: Werkzeug's file-watcher has repeatedly misfired in
    # this environment (observed reloading mid-request over unrelated
    # filesystem noise, once even over changes it claimed were inside
    # site-packages/flask itself) — a reload kills the in-flight request's
    # worker process without ever replying, which looks exactly like the
    # browser being stuck loading forever. debug=True is kept for its error
    # pages/tracebacks; only the auto-restart-on-file-change behavior is off.
    app.run(debug=True, port=5000, use_reloader=False)
