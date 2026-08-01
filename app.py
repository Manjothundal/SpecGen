import os
from flask import Flask, render_template, request
import pandas as pd
import bds_assembler as bds

app = Flask(__name__)

@app.route("/", methods=["GET"])
def index():
    return render_template("index.html", code=None, lang=None)

@app.route("/generate", methods=["POST"])
def generate():
    lang = request.form.get("lang", "sas")
    acrf = pd.read_excel("acrf_metadata.xlsx", sheet_name="By Domain")
    vs_params = bds.build_param_spec_from_acrf(acrf, "VS", "VSTESTCD")
    code = bds.generate_bds_domain("vs", vs_params, "ADVS", language=lang)
    return render_template("index.html", code=code, lang=lang)

if __name__ == "__main__":
    app.run(debug=True, port=5000)
