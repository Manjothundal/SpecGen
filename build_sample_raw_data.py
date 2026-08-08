"""
build_sample_raw_data.py - generate sample raw clinical datasets (CSV) for
sdtm_automapper.py to read — deliberately EDC/vendor-export-style column
names (SUBJECT_ID, AE_TERM, SYSBP_VALUE, ...), not already SDTM-shaped, so
mapping them is a real exercise for the tool, not a no-op. Mirrors the
existing build_sample_acrf.py / build_sample_protocol.py / build_sample_shell.py
pattern: generate once, commit the output as a fixture.

Usage:
  python build_sample_raw_data.py [--output-dir raw_data]
"""

import argparse
import os

import pandas as pd


def build_demog(out_dir):
    df = pd.DataFrame({
        "SUBJECT_ID": ["STUDY01-001", "STUDY01-002", "STUDY01-003", "STUDY01-004"],
        "SITE_NUM": ["101", "101", "102", "102"],
        "DOB": ["1975-03-12", "1968-11-02", "1982-07-19", "1990-01-30"],
        "GENDER": ["M", "F", "F", "M"],
        "RACE_DESC": ["WHITE", "BLACK OR AFRICAN AMERICAN", "ASIAN", "WHITE"],
        "RANDOM_DATE": ["2023-01-15", "2023-01-18", "2023-01-20", "2023-01-22"],
        "ARM_DESC": ["Placebo", "Drug A 50mg", "Drug A 100mg", "Placebo"],
    })
    df.to_csv(os.path.join(out_dir, "demog.csv"), index=False)


def build_adverse_events(out_dir):
    df = pd.DataFrame({
        "SUBJECT_ID": ["STUDY01-001", "STUDY01-001", "STUDY01-002"],
        "AE_TERM": ["Headache", "Nausea", "Fatigue"],
        "AE_START": ["2023-02-01", "2023-02-10", "2023-02-05"],
        "AE_STOP": ["2023-02-03", "2023-02-11", "2023-02-08"],
        "AE_SEVERITY": ["MILD", "MODERATE", "MILD"],
        "AE_SERIOUS": ["N", "N", "N"],
        "AE_RELATED": ["UNLIKELY", "POSSIBLE", "UNLIKELY"],
    })
    df.to_csv(os.path.join(out_dir, "adverse_events.csv"), index=False)


def build_vitals(out_dir):
    df = pd.DataFrame({
        "SUBJECT_ID": ["STUDY01-001", "STUDY01-001", "STUDY01-002", "STUDY01-002"],
        "VISIT_NAME": ["Baseline", "Week 4", "Baseline", "Week 4"],
        "VISIT_DATE": ["2023-01-20", "2023-02-17", "2023-01-21", "2023-02-18"],
        "SYSBP_VALUE": [122, 118, 130, 128],
        "DIABP_VALUE": [80, 76, 84, 82],
        "PULSE_VALUE": [72, 70, 76, 74],
    })
    df.to_csv(os.path.join(out_dir, "vitals.csv"), index=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate sample raw clinical datasets.")
    parser.add_argument("--output-dir", "-o", default="raw_data")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)
    build_demog(args.output_dir)
    build_adverse_events(args.output_dir)
    build_vitals(args.output_dir)
    print(f"Wrote demog.csv, adverse_events.csv, vitals.csv to {args.output_dir}/")
