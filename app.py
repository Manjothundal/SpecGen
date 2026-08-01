"""
app.py — SpecGen web app (Flask). PIECE 3: file upload.

Dropdown for output type (SDTM / ADaM / TLF) + language, generates the whole
set. Each output type now also accepts an optional upload of its own input
file(s); when none is uploaded, the sample inputs already in the project
(acrf_metadata.xlsx, sdtm_spec_draft.xlsx, sample shells) are used instead.

  ADaM : calls bds_assembler functions directly (8 datasets); input = ACRF
         metadata workbook (single file)
  TLF  : calls tlf_assembler for each shell (one table per shell file);
         input = one or more mock-shell workbooks
  SDTM : runs sdtm_assembler.py as a subprocess (it's a script that takes a
         spec-file arg and writes to sdtm_programs/), then reads the files
         back; input = SDTM spec draft workbook (single file)

Run:  python app.py   ->   http://127.0.0.1:5000
"""

import os
import glob
import shutil
import subprocess
import sys
import tempfile
import pandas as pd
from flask import Flask, render_template, request
from werkzeug.utils import secure_filename

import bds_assembler as bds
import tlf_assembler as tlf

app = Flask(__name__)

ACRF = "acrf_metadata.xlsx"
SDTM_SPEC = "sdtm_spec_draft.xlsx"
SHELLS = ["sample_shell_demographics.xlsx", "sample_shell_ae.xlsx"]


def _save_uploads(files, upload_dir):
    """Save any non-empty uploaded files to upload_dir. Returns saved paths."""
    saved = []
    for f in files:
        if f and f.filename:
            path = os.path.join(upload_dir, secure_filename(f.filename))
            f.save(path)
            saved.append(path)
    return saved


def generate_adam(lang, acrf_path=None):
    """Return dict {name: code} for all 8 ADaM datasets."""
    acrf = pd.read_excel(acrf_path or ACRF, sheet_name="By Domain")
    out = {}
    # Findings
    for dom, src, code in [("VS", "vs", "ADVS"), ("LB", "lb", "ADLB"),
                           ("EG", "eg", "ADEG"), ("TR", "tr", "ADTR")]:
        params = bds.build_param_spec_from_acrf(acrf, dom, dom + "TESTCD")
        out[code.lower()] = bds.generate_bds_domain(src, params, code, language=lang)
    # Events
    out["adae"] = bds.generate_ae_domain("ADAE", language=lang)
    out["adcm"] = bds.generate_cm_domain("ADCM", language=lang)
    # Oncology
    if lang == "r":
        out["adrs"] = bds.generate_rs_domain_r("ADRS")
        out["adtte"] = bds.generate_tte_domain_r("ADTTE")
    else:
        out["adrs"] = bds.generate_rs_domain("ADRS")
        out["adtte"] = bds.generate_tte_domain("ADTTE")
    return out


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


def generate_sdtm(lang, spec_path=None):
    """Run sdtm_assembler.py as a subprocess, then read the .sas files back.
    Note: SDTM generation is SAS-only in the current assembler; lang is ignored
    here and we tell the user.

    sdtm_assembler.py skips domains whose output file already exists unless
    --force is passed, so a hand-QC'd fix in sdtm_programs/ survives repeat
    "Generate" clicks. An explicit spec upload is a deliberate request to
    (re)generate from that spec, so it passes --force; the no-upload default
    (sample spec, just viewing current output) does not.
    """
    force = spec_path is not None
    spec_path = spec_path or SDTM_SPEC
    out = {}
    if not os.path.exists(spec_path):
        return {"(error)": f"{spec_path} not found in project folder."}
    # run the real script (offline so it doesn't need the API for a quick demo)
    cmd = [sys.executable, "sdtm_assembler.py", spec_path, "--offline"]
    if force:
        cmd.append("--force")
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=600)
    except subprocess.CalledProcessError as e:
        return {"(error)": f"sdtm_assembler failed:\n{e.stderr}"}
    for path in sorted(glob.glob(os.path.join("sdtm_programs", "*.sas"))):
        name = os.path.splitext(os.path.basename(path))[0]
        with open(path, encoding="utf-8") as f:
            out[name] = f.read()
    return out


@app.route("/", methods=["GET"])
def index():
    return render_template("index.html", programs=None, lang=None, otype=None, note=None)


@app.route("/generate", methods=["POST"])
def generate():
    lang = request.form.get("lang", "sas")
    otype = request.form.get("otype", "adam")
    note = None
    if otype == "sdtm" and lang == "r":
        note = "SDTM generation is currently SAS-only; showing SAS programs."

    upload_dir = tempfile.mkdtemp(prefix="specgen_upload_")
    try:
        uploaded = _save_uploads(request.files.getlist("spec_file"), upload_dir)
        if otype == "adam":
            programs = generate_adam(lang, acrf_path=uploaded[0] if uploaded else None)
        elif otype == "tlf":
            programs = generate_tlf(lang, shells=uploaded or None)
        else:
            programs = generate_sdtm(lang, spec_path=uploaded[0] if uploaded else None)
    finally:
        shutil.rmtree(upload_dir, ignore_errors=True)

    return render_template("index.html", programs=programs, lang=lang, otype=otype, note=note)


if __name__ == "__main__":
    app.run(debug=True, port=5000)
