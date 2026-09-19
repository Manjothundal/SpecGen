"""Piece A tests: dataset_reader, output_reader, and the planted problems.

Run from the repo root:  pytest tests/test_readers.py -v
Needs the fixtures: python build_sample_sap.py; python build_sample_review_data.py
"""

import json
import os

import pandas as pd
import pdfplumber
import pytest

from review.dataset_reader import read_dataset, read_datasets
from review.output_reader import read_output, read_outputs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DS_DIR = os.path.join(ROOT, "data", "sample_datasets")
OUT_DIR = os.path.join(ROOT, "data", "sample_outputs")
SAP = os.path.join(ROOT, "data", "sample_sap.pdf")
MANIFEST = os.path.join(ROOT, "data", "sample_planted.json")

TITLE_1411 = "Table 14.1.1 Summary of Demographic and Baseline Characteristics"
HEADERS_OLD = ["Parameter", "Placebo (N=50)", "Drug A 50mg (N=50)"]


def _planted(pid):
    with open(MANIFEST, encoding="utf-8") as f:
        return next(p for p in json.load(f)["planted"] if p["id"] == pid)


# --- output_reader on the existing generated TLFs (RTF text, DOCX, PDF) ------

@pytest.mark.parametrize("fname", ["sample_output.rtf", "sample_output.docx", "sample_output_a.pdf"])
def test_existing_sample_outputs_same_shape(fname):
    recs = read_output(os.path.join(ROOT, fname))
    assert len(recs) == 1
    r = recs[0]
    assert r["table_id"] == "14.1.1" and r["kind"] == "table"
    assert r["title"] == TITLE_1411
    assert r["column_headers"] == HEADERS_OLD
    assert len(r["rows"]) == 2 and all(len(row) == 3 for row in r["rows"])
    assert r["rows"][0] == ["Age (years)", "Mean: 52.3", "Mean: 54.0"]
    assert r["page"] == 1 and r["source_file"] == fname


def test_rtf_text_layout_keeps_population_subtitle():
    r = read_output(os.path.join(ROOT, "sample_output.rtf"))[0]
    assert r["subtitle"] == "Safety Population"


def test_pdf_pair_differs_in_exactly_one_cell():
    a = read_output(os.path.join(ROOT, "sample_output_a.pdf"))[0]["rows"]
    b = read_output(os.path.join(ROOT, "sample_output_b.pdf"))[0]["rows"]
    diffs = [(x, y) for ra, rb in zip(a, b) for x, y in zip(ra, rb) if x != y]
    assert diffs == [("Mean: 52.3", "Mean: 53.8")]


def test_unsupported_output_type_raises():
    with pytest.raises(ValueError):
        read_output(os.path.join(ROOT, "README.md"))


# --- output_reader on the review fixtures (real RTF table, DOCX) --------------

def test_fixture_outputs_grid_shape_and_footnotes():
    recs = {r["table_id"]: r for r in read_outputs(OUT_DIR)}
    assert sorted(recs) == ["14.1.1", "14.3.1"]

    demog = recs["14.1.1"]
    assert demog["source_file"] == "t_14_1_1.rtf"
    assert demog["column_headers"] == [
        "Parameter", "Placebo (N=20)", "Drug A 50mg (N=20)", "Drug A 100mg (N=20)", "Total (N=59)"]
    assert len(demog["rows"]) == 12 and all(len(r) == 5 for r in demog["rows"])
    assert demog["subtitle"] == "Safety Population"
    assert demog["footnotes"][-1] == "Source: ADSL. Program: t_14_1_1.sas"

    ae = recs["14.3.1"]
    assert ae["source_file"] == "t_14_3_1.docx"
    assert ae["title"] == "Table 14.3.1 Overview of Treatment-Emergent Adverse Events"
    assert len(ae["rows"]) == 6 and all(len(r) == 5 for r in ae["rows"])
    assert len(ae["footnotes"]) == 3


# --- dataset_reader ------------------------------------------------------------

def test_read_datasets_shapes_and_labels():
    ds = read_datasets(DS_DIR)
    assert sorted(ds) == ["ADAE", "ADSL"]
    adsl, p = ds["ADSL"]
    assert p["n_records"] == len(adsl) == 60
    by_name = {v["name"]: v for v in p["variables"]}
    assert by_name["SAFFL"]["label"] == "Safety Population Flag"
    assert by_name["SAFFL"]["values"] == {"Y": 59, "N": 1}
    assert by_name["TRT01A"]["n_missing"] == 1          # blank char counts as missing
    assert by_name["AGE"]["type"] == "num" and "values" not in by_name["AGE"]


def test_sas_dates_come_back_as_datetimes():
    adae, p = read_dataset(os.path.join(DS_DIR, "adae.xpt"))
    assert pd.api.types.is_datetime64_any_dtype(adae["ASTDT"])
    by_name = {v["name"]: v for v in p["variables"]}
    assert by_name["ASTDT"]["type"] == "date" and by_name["ASTDT"]["format"] == "DATE9"


def test_profile_has_no_subject_level_rows():
    for _, (_, p) in read_datasets(DS_DIR).items():
        text = json.dumps(p)
        assert "STUDY01-0" not in text                   # no USUBJID values leak into a profile
        for v in p["variables"]:
            assert len(v.get("values", {})) <= 12


def test_unsupported_dataset_type_raises():
    with pytest.raises(ValueError):
        read_dataset(os.path.join(ROOT, "adam_spec.xlsx"))


# --- the SAP fixture must actually contain what the checks will hold data to ---

def test_sap_text_states_the_rules_the_data_breaks():
    with pdfplumber.open(SAP) as pdf:
        text = " ".join((pg.extract_text() or "") for pg in pdf.pages)
        text = " ".join(text.split())
    assert "last dose of study treatment + 7 days" in text                  # P1, section 6.2
    assert "count of SAFFL = 'Y' subjects in ADSL by TRT01A" in text        # P2, section 4.5
    assert "14.3.2 Treatment-Emergent Adverse Events by System Organ Class" in text   # P3, section 9
    assert "Baseline is defined per treatment period" in text               # section 5.1
    assert "Week 4 29 22 to 35" in text                                     # section 5.2 windows


# --- planted problems: recomputed independently of the manifest ----------------

def test_planted_p1_teae_window():
    adsl, _ = read_dataset(os.path.join(DS_DIR, "adsl.xpt"))
    adae, _ = read_dataset(os.path.join(DS_DIR, "adae.xpt"))
    ae = adae.merge(adsl[["USUBJID", "TRTSDT", "TRTEDT"]], on="USUBJID")
    sap = (ae["ASTDT"] >= ae["TRTSDT"]) & (ae["ASTDT"] <= ae["TRTEDT"] + pd.Timedelta(days=7))
    flagged = ae["TRTEMFL"] == "Y"
    exp = _planted("P1")["expected"]
    assert int(flagged.sum()) == exp["records_flagged_Y"]
    assert int((flagged & ~sap).sum()) == exp["flagged_Y_outside_sap_window"] == 9
    assert int((~flagged & sap).sum()) == 0              # the bug only over-flags, never under-flags


def test_planted_p2_bign():
    adsl, _ = read_dataset(os.path.join(DS_DIR, "adsl.xpt"))
    saf = adsl[adsl["SAFFL"] == "Y"].groupby("TRT01A").size().to_dict()
    r = next(x for x in read_outputs(OUT_DIR) if x["table_id"] == "14.1.1")
    printed = {h.split(" (N=")[0]: int(h.split("N=")[1].rstrip(")")) for h in r["column_headers"][1:]}
    assert [a for a in saf if printed[a] != saf[a]] == ["Placebo"]
    assert (printed["Placebo"], saf["Placebo"]) == (20, 19)
    assert _planted("P2")["expected"]["adsl_saffl_n"] == saf


def test_planted_p3_inventory():
    delivered = sorted(r["table_id"] for r in read_outputs(OUT_DIR))
    assert delivered == ["14.1.1", "14.3.1"]
    assert _planted("P3")["expected"]["missing"] == ["14.3.2"]


def test_clean_parts_of_the_package_agree_with_each_other():
    """14.3.1 headers use the true Safety N - so 14.1.1's Placebo N=20 is the odd one out."""
    recs = {r["table_id"]: r for r in read_outputs(OUT_DIR)}
    assert recs["14.3.1"]["column_headers"][1] == "Placebo (N=19)"
    assert recs["14.1.1"]["column_headers"][1] == "Placebo (N=20)"
    assert recs["14.1.1"]["column_headers"][2:] == recs["14.3.1"]["column_headers"][2:]
