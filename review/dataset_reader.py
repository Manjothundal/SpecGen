"""dataset_reader.py - read SDTM/ADaM datasets (.xpt / .sas7bdat) into pandas
plus a metadata profile.

The profile holds names, labels, types, counts and value COUNTS only - never
subject-level rows - so it is safe to hand to a model later (design rule:
no subject-level data in any model prompt). The dataframe itself stays in
Python for the deterministic checks.

    df, profile = read_dataset("data/sample_datasets/adae.xpt")
    datasets = read_datasets("data/sample_datasets")   # {"ADAE": (df, profile), ...}
"""

import os

import pandas as pd
import pyreadstat

SUPPORTED = (".xpt", ".sas7bdat")

# A variable with this few distinct values gets its value counts listed in
# the profile (flags, severity, arm, sex, ...). Anything wider is left out.
VALUES_MAX_DISTINCT = 12

# SAS formats that mean "this numeric column is really a date / datetime".
_DATE_FORMATS = ("DATE", "DDMMYY", "MMDDYY", "YYMMDD", "E8601DA", "IS8601DA")
_DATETIME_FORMATS = ("DATETIME", "E8601DT", "IS8601DT")


def _format_kind(fmt):
    f = (fmt or "").upper().lstrip("$")
    if f.startswith(_DATETIME_FORMATS):
        return "datetime"
    if f.startswith(_DATE_FORMATS):
        return "date"
    return None


def _missing_mask(series):
    """SAS convention: a blank character value counts as missing."""
    if pd.api.types.is_object_dtype(series) or pd.api.types.is_string_dtype(series):
        return series.isna() | (series.astype(str).str.strip() == "")
    return series.isna()


def _to_datetime(series, kind):
    """SAS dates are days since 1960-01-01, datetimes are seconds. pyreadstat
    sometimes has already turned a date-formatted column into date objects
    (object dtype) - that case just needs parsing."""
    if pd.api.types.is_numeric_dtype(series):
        unit = "s" if kind == "datetime" else "D"
        return pd.to_datetime(series, unit=unit, origin="1960-01-01")
    return pd.to_datetime(series, errors="coerce")


def _num_text(x):
    """5.0 -> '5' so integer-valued numerics read naturally in the profile."""
    if isinstance(x, float) and x.is_integer():
        return str(int(x))
    return str(x)


def profile_dataframe(df, name, labels=None, formats=None, dataset_label="", path=""):
    """Metadata profile for one dataframe (see module docstring)."""
    labels = labels or {}
    formats = formats or {}
    variables = []
    for col in df.columns:
        s = df[col]
        missing = _missing_mask(s)
        present = s[~missing]
        is_date = pd.api.types.is_datetime64_any_dtype(s)
        if is_date:
            vtype = "date"
        elif pd.api.types.is_numeric_dtype(s):
            vtype = "num"
        else:
            vtype = "char"

        entry = {
            "name": col,
            "label": labels.get(col) or "",
            "type": vtype,
            "format": formats.get(col) or "",
            "n_missing": int(missing.sum()),
            "n_distinct": int(present.nunique()),
        }
        if vtype in ("num", "date") and len(present):
            entry["min"] = _num_text(present.min())
            entry["max"] = _num_text(present.max())
        if vtype != "date" and 0 < entry["n_distinct"] <= VALUES_MAX_DISTINCT:
            counts = present.value_counts()
            entry["values"] = {_num_text(k): int(v) for k, v in counts.items()}
        variables.append(entry)

    return {
        "name": name,
        "path": path,
        "label": dataset_label or "",
        "n_records": int(len(df)),
        "n_vars": int(len(df.columns)),
        "variables": variables,
    }


def read_dataset(path):
    """Read one .xpt or .sas7bdat file. Returns (dataframe, profile).

    Numeric columns carrying a SAS date/datetime format come back as
    datetime64 so the checks can do date arithmetic directly.
    """
    ext = os.path.splitext(path)[1].lower()
    if ext not in SUPPORTED:
        raise ValueError(f"Unsupported dataset type {ext!r} (supported: {', '.join(SUPPORTED)})")

    if ext == ".xpt":
        df, meta = pyreadstat.read_xport(path)
    else:
        df, meta = pyreadstat.read_sas7bdat(path)

    formats = dict(getattr(meta, "original_variable_types", None) or {})
    for col in df.columns:
        kind = _format_kind(formats.get(col))
        if kind and not pd.api.types.is_datetime64_any_dtype(df[col]):
            df[col] = _to_datetime(df[col], kind)

    labels = dict(zip(meta.column_names, meta.column_labels))
    name = os.path.splitext(os.path.basename(path))[0].upper()
    profile = profile_dataframe(
        df, name, labels=labels, formats=formats,
        dataset_label=getattr(meta, "file_label", "") or "", path=path,
    )
    return df, profile


def read_datasets(folder):
    """Read every supported dataset in a folder. Returns {NAME: (df, profile)}
    keyed by upper-case file stem (ADAE.xpt -> "ADAE"), sorted by name."""
    found = {}
    for fname in sorted(os.listdir(folder)):
        if os.path.splitext(fname)[1].lower() not in SUPPORTED:
            continue
        name = os.path.splitext(fname)[0].upper()
        if name in found:
            raise ValueError(f"Two files claim dataset {name} in {folder} - keep one")
        found[name] = read_dataset(os.path.join(folder, fname))
    return found
