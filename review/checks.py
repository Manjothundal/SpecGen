"""checks.py - deterministic review checks. Pure functions, no model calls, no I/O.

    check_x(datasets, outputs, rule, ctx) -> list[finding dict]

    datasets  {"ADSL": DataFrame, "ADAE": DataFrame, ...}   upper-case names
    outputs   list of output records from review.output_reader
    rule      a rule dict (review.rules_store shape); its "params" configure the check
    ctx       optional dict. ctx["profiles"] = {"ADPC": profile} supplies variable
              labels (only check_label_units needs it)

A check returns [] when the data agrees with the rule. It raises CheckInputError
when it cannot look - a dataset, variable or rule param is missing or misspelled
- so a broken input is never reported as a finding and never passes silently.

A finding is a dict in the spec 4.2 shape (finding_id and run_id are filled in
later by the engine) plus rule_id, which dedupe uses. Every finding carries a
source_ref and an evidence string built from counts computed here in pandas;
_finding() refuses to build one without both.

Params for each check are listed in its docstring.
"""

import re
from decimal import ROUND_HALF_UP, Decimal

import pandas as pd


class CheckInputError(Exception):
    """A check could not run: missing dataset, variable or rule param."""


_MISSING = object()

DEFAULT_POPULATIONS = {
    "safety": {"flag": "SAFFL", "trt": "TRT01A", "label": "Safety"},
    "itt": {"flag": "ITTFL", "trt": "TRT01P", "label": "Intent-to-Treat"},
    "randomised": {"flag": None, "trt": "TRT01P", "label": "Randomised"},
}
_POP_PATTERNS = [
    ("safety", re.compile(r"\bsafety\b", re.I)),
    ("itt", re.compile(r"\b(itt|intent[- ]to[- ]treat)\b", re.I)),
    ("randomised", re.compile(r"\brandomi[sz]ed\b", re.I)),
]
_HDR_N = re.compile(r"^(.*?)\s*\(\s*N\s*=\s*(\d+)\s*\)\s*$", re.I | re.S)
_PCT_CELL = re.compile(r"(\d+)\s*\(\s*(\d+(?:\.\d+)?)\s*%\s*\)")
# "25", "25 (50.0%)", "Male: 25 (50%)" - a count cell. "52.3", "51.1 (14.30)", "32, 69" are not.
_COUNT_CELL = re.compile(r"^\s*(?:[A-Za-z][A-Za-z ]*:\s*)?(\d+)\s*(?:\(\s*\d+(?:\.\d+)?\s*%\s*\))?\s*$")
_PER_UNIT = re.compile(r"(?:/\s*|\bper\s+)(kg|mg)\b", re.I)
_TOTAL_NAMES = {"total", "all", "allsubjects", "allpatients", "overall"}


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _finding(rule, output_file, what_is_wrong, evidence, severity=None):
    """Build one finding. Refuses to exist without evidence containing a real
    number, or without a source reference (design rule 2, enforced in code)."""
    evidence = (evidence or "").strip()
    if not evidence or not re.search(r"\d", evidence):
        raise ValueError(f"finding for rule {rule.get('rule_id')} has no numeric evidence")
    source_ref = (rule.get("sap_ref") or "").strip() or f"rule {rule['rule_id']}"
    return {
        "finding_id": None,
        "run_id": None,
        "rule_id": rule["rule_id"],
        "output_file": output_file,
        "what_is_wrong": what_is_wrong,
        "evidence": evidence,
        "source_ref": source_ref,
        "severity": severity or rule["severity"],
        "decision": "open",
        "decided_by": None,
        "decided_at": None,
    }


def _p(rule, key, default=_MISSING):
    params = rule.get("params") or {}
    if key in params:
        return params[key]
    if default is _MISSING:
        raise CheckInputError(f"rule {rule['rule_id']} is missing required param {key!r}")
    return default


def _need(datasets, name, cols=()):
    if name not in datasets:
        raise CheckInputError(f"dataset {name} was not supplied")
    df = datasets[name]
    missing = [c for c in cols if c not in df.columns]
    if missing:
        raise CheckInputError(f"{name} has no variable(s): {', '.join(missing)}")
    return df


def _need_outputs(outputs):
    if not outputs:
        raise CheckInputError("no outputs were supplied to check")


def _label(ctx, dataset, var):
    prof = (ctx or {}).get("profiles", {}).get(dataset)
    if prof is None:
        raise CheckInputError(f"no profile for {dataset} in ctx['profiles'] (variable labels come from it)")
    for v in prof["variables"]:
        if v["name"] == var:
            return v["label"] or ""
    raise CheckInputError(f"profile of {dataset} has no variable {var}")


def _norm(text):
    return re.sub(r"[^a-z0-9]", "", str(text).lower())


def _dates(series):
    return pd.to_datetime(series, errors="coerce")


def _fmt(v):
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def _clip(text, n=90):
    text = str(text)
    return text if len(text) <= n else text[: n - 3] + "..."


def _pct(n, total, places):
    q = Decimal(1).scaleb(-places)
    return (Decimal(100 * n) / Decimal(total)).quantize(q, rounding=ROUND_HALF_UP)


def _count_cell(text):
    m = _COUNT_CELL.match(text or "")
    return int(m.group(1)) if m else None


def _out_name(o):
    if o["table_id"]:
        return f"{o['kind'].capitalize()} {o['table_id']} ({o['source_file']})"
    return f"{o['title'] or 'untitled output'} ({o['source_file']})"


def _out_short(o):
    return f"{o['kind'].capitalize()} {o['table_id']}" if o["table_id"] else (o["title"] or o["source_file"])


def _output_key(o):
    return o["table_id"] if o["kind"] == "table" else f"{o['kind'].capitalize()} {o['table_id']}"


def _pop_of(output):
    """Population a table states for itself (subtitle first, then title)."""
    for text in (output["subtitle"], output["title"]):
        for key, pat in _POP_PATTERNS:
            if pat.search(text or ""):
                return key
    return None


def _header_ns(output):
    """[(column index, column name, printed Big N)] for headers like 'Placebo (N=19)'."""
    found = []
    for j, h in enumerate(output["column_headers"]):
        m = _HDR_N.match(h or "")
        if m and m.group(1).strip():
            found.append((j, m.group(1).strip(), int(m.group(2))))
    return found


def _is_total(name):
    return _norm(name) in _TOTAL_NAMES


def _populations(rule):
    merged = {k: dict(v) for k, v in DEFAULT_POPULATIONS.items()}
    for k, v in (_p(rule, "populations", {}) or {}).items():
        merged.setdefault(k, {}).update(v)
    return merged


def _pop_counts(datasets, rule, pop):
    """ADSL subject counts for a population: total, and per treatment arm."""
    cfg = _populations(rule)[pop]
    cols = [cfg["trt"]] + ([cfg["flag"]] if cfg["flag"] else [])
    adsl = _need(datasets, "ADSL", cols)
    sub = adsl if not cfg["flag"] else adsl[adsl[cfg["flag"]] == "Y"]
    by_arm = {}
    for arm in adsl[cfg["trt"]].dropna().unique():
        if str(arm).strip():
            by_arm[_norm(arm)] = (str(arm), int((sub[cfg["trt"]] == arm).sum()))
    desc = f"{cfg['flag']}='Y'" if cfg["flag"] else "all randomised subjects"
    return {"label": cfg["label"], "desc": desc, "total": int(len(sub)), "by_arm": by_arm}


def _column_ns(datasets, rule, out, pop):
    """For one table: [(name, printed N, ADSL count for `pop`)] over the header
    columns that can be matched to an ADSL arm (or to the Total)."""
    counts = _pop_counts(datasets, rule, pop)
    cols = []
    for _, name, n in _header_ns(out):
        if _is_total(name):
            cols.append((name, n, counts["total"]))
        elif _norm(name) in counts["by_arm"]:
            cols.append((name, n, counts["by_arm"][_norm(name)][1]))
    return counts, cols


# ---------------------------------------------------------------------------
# 1. Big N in the table header vs the population flag count in ADSL
# ---------------------------------------------------------------------------

def check_bign(datasets, outputs, rule, ctx=None):
    """Column header N ('Placebo (N=20)') vs the ADSL count for the population
    the table states (Safety -> SAFFL='Y' by TRT01A, ITT -> ITTFL='Y' by TRT01P).

    params (all optional): populations - override flag/trt variables per
    population, e.g. {"safety": {"flag": "SAFFL", "trt": "TRT01A"}}.
    Tables that state no recognisable population, and header columns that match
    no ADSL arm, are not compared.
    """
    _need_outputs(outputs)
    findings = []
    for out in outputs:
        pop = _pop_of(out)
        if pop is None:
            continue
        counts, cols = _column_ns(datasets, rule, out, pop)
        bad = [(name, n, actual) for name, n, actual in cols if n != actual]
        if not bad:
            continue
        evidence = (f"{_out_short(out)}: {len(bad)} of {len(cols)} column headers disagree with ADSL "
                    f"{counts['label']} population ({counts['desc']}): "
                    + "; ".join(f"{name} prints N={n}, ADSL has {a}" for name, n, a in bad) + ".")
        findings.append(_finding(
            rule, _out_name(out),
            f"Big N in the column headers of {_out_short(out)} does not match the "
            f"{counts['label']} population in ADSL.", evidence))
    return findings


# ---------------------------------------------------------------------------
# 2. Population used by a table vs the population the SAP states for it
# ---------------------------------------------------------------------------

def check_population_filter(datasets, outputs, rule, ctx=None):
    """Two ways a table can use the wrong population:
      (a) the population it states for itself differs from the SAP's, or
      (b) it states the right one but every column N that could tell the
          populations apart equals the OTHER population's ADSL count.

    params: table_populations (required) - {"14.3.1": "safety", ...} from the SAP.
            populations (optional) - as in check_bign.
    A table missing from table_populations is not checked.
    """
    _need_outputs(outputs)
    expected_by_table = _p(rule, "table_populations")
    findings = []
    for out in outputs:
        expected = expected_by_table.get(out["table_id"])
        stated = _pop_of(out)
        if expected is None or stated is None:
            continue
        exp_counts = _pop_counts(datasets, rule, expected)

        if stated != expected:
            got = _pop_counts(datasets, rule, stated)
            evidence = (f"{_out_short(out)} states the {got['label']} population "
                        f"({got['desc']}, {got['total']} subjects in ADSL) but the SAP requires the "
                        f"{exp_counts['label']} population ({exp_counts['desc']}, "
                        f"{exp_counts['total']} subjects in ADSL).")
            findings.append(_finding(
                rule, _out_name(out),
                f"{_out_short(out)} is labelled with a different population than the SAP specifies.",
                evidence))
            continue

        for other in _populations(rule):
            if other == expected:
                continue
            oth_counts, cols = _column_ns(datasets, rule, out, other)
            exp_cols = {n: a for n, _, a in _column_ns(datasets, rule, out, expected)[1]}
            tell_apart = [(n, printed, a, exp_cols[n]) for n, printed, a in cols
                          if n in exp_cols and a != exp_cols[n]]
            if tell_apart and all(printed == a for _, printed, a, _ in tell_apart):
                evidence = (f"{_out_short(out)} states the {exp_counts['label']} population, but all "
                            f"{len(tell_apart)} column(s) whose N differs between populations print the "
                            f"{oth_counts['label']} count: "
                            + "; ".join(f"{n} prints N={p}, {oth_counts['desc']} gives {a}, "
                                        f"{exp_counts['desc']} gives {e}" for n, p, a, e in tell_apart) + ".")
                findings.append(_finding(
                    rule, _out_name(out),
                    f"{_out_short(out)} appears to be built on the {oth_counts['label']} population, "
                    f"not the {exp_counts['label']} population the SAP specifies.", evidence))
                break
    return findings


# ---------------------------------------------------------------------------
# 3. Baseline flag present in some periods only
# ---------------------------------------------------------------------------

def check_baseline_per_period(datasets, outputs, rule, ctx=None):
    """When the SAP defines baseline per period, a subject/parameter with records
    in more than one period needs ABLFL='Y' in EACH of those periods. Flags
    subject-parameter pairs that have it in some periods but not all.

    params: dataset (default "ADVS"), period_var ("APERIOD"), flag_var ("ABLFL"),
            param_var ("PARAMCD"), subject_var ("USUBJID").
    """
    name = _p(rule, "dataset", "ADVS")
    period, flag = _p(rule, "period_var", "APERIOD"), _p(rule, "flag_var", "ABLFL")
    param, subj = _p(rule, "param_var", "PARAMCD"), _p(rule, "subject_var", "USUBJID")
    df = _need(datasets, name, [subj, period, flag, param])
    keys = [subj, param]

    recs = df.groupby(keys + [period]).size().rename("n").reset_index()
    flagged = df[df[flag] == "Y"].groupby(keys + [period]).size().rename("f").reset_index()
    m = recs.merge(flagged, on=keys + [period], how="left").fillna({"f": 0})
    m = m[m.groupby(keys)[period].transform("nunique") > 1]
    if m.empty:
        return []

    g = m.groupby(keys)
    pairs = int(g.ngroups)
    n_flagged_periods = g["f"].apply(lambda s: int((s > 0).sum()))
    n_periods = g[period].nunique()
    partial = n_flagged_periods[(n_flagged_periods > 0) & (n_flagged_periods < n_periods)].index
    if len(partial) == 0:
        return []

    lacking = m[(m["f"] == 0) & m.set_index(keys).index.isin(partial)]
    by_period = lacking[period].value_counts().sort_index()
    breakdown = ", ".join(f"Period {_fmt(p)}: {int(c)}" for p, c in by_period.items())
    evidence = (f"{name}: {len(partial)} of {pairs} subject-{param} pairs with records in more than "
                f"one period have {flag}='Y' in some periods but not all. Periods with no baseline "
                f"record ({breakdown}).")
    return [_finding(
        rule, name,
        f"{flag} is present in only some periods although the SAP defines baseline per period.",
        evidence)]


# ---------------------------------------------------------------------------
# 4. TEAE flag vs first dose and last dose + window
# ---------------------------------------------------------------------------

def check_teae_window(datasets, outputs, rule, ctx=None):
    """TRTEMFL vs the SAP window: start on or after first dose, and on or before
    last dose + window_days (no upper bound while the last dose date is missing).

    params: window_days (required). ae_dataset ("ADAE"), flag_var ("TRTEMFL"),
            start_var ("ASTDT"), subject_var ("USUBJID"), first_dose_var ("TRTSDT"),
            last_dose_var ("TRTEDT") - ADSL dose dates; trt_var ("TRT01A") - if ADSL
            has it, the evidence adds subjects with any TEAE per arm, current vs SAP.
    Records with no start date cannot be assessed and are counted, not judged.
    """
    window = int(_p(rule, "window_days"))
    ae_name = _p(rule, "ae_dataset", "ADAE")
    flag, start = _p(rule, "flag_var", "TRTEMFL"), _p(rule, "start_var", "ASTDT")
    subj = _p(rule, "subject_var", "USUBJID")
    first_v, last_v = _p(rule, "first_dose_var", "TRTSDT"), _p(rule, "last_dose_var", "TRTEDT")
    trt = _p(rule, "trt_var", "TRT01A")

    ae = _need(datasets, ae_name, [subj, start, flag])
    adsl = _need(datasets, "ADSL", [subj, first_v, last_v])
    if not adsl[subj].is_unique:
        raise CheckInputError(f"ADSL has more than one row per {subj}")
    # ADSL columns get a prefix so a same-named column already in the AE
    # dataset (some studies carry TRTSDT there) can never shadow ADSL's.
    keep = [first_v, last_v] + ([trt] if trt in adsl.columns else [])
    adsl_part = adsl[[subj] + keep].rename(columns={c: f"_adsl_{c}" for c in keep})
    m = ae.merge(adsl_part, on=subj, how="left")
    trt_col = f"_adsl_{trt}"

    s = _dates(m[start])
    first, last = _dates(m[f"_adsl_{first_v}"]), _dates(m[f"_adsl_{last_v}"])
    assessable = s.notna()
    inside = assessable & first.notna() & (s >= first) & (last.isna() | (s <= last + pd.Timedelta(days=window)))
    flagged = m[flag] == "Y"
    over = flagged & assessable & ~inside
    under = ~flagged & inside
    if not over.any() and not under.any():
        return []

    after = over & last.notna() & (s > last + pd.Timedelta(days=window))
    before = over & first.notna() & (s < first)
    no_dose = over & first.isna()
    parts = []
    if after.any():
        parts.append(f"{int(after.sum())} of {int(flagged.sum())} records with {flag}='Y' start more "
                     f"than {window} days after last dose")
    if before.any():
        parts.append(f"{int(before.sum())} of {int(flagged.sum())} records with {flag}='Y' start "
                     f"before first dose")
    if no_dose.any():
        parts.append(f"{int(no_dose.sum())} of {int(flagged.sum())} records with {flag}='Y' belong to "
                     f"subjects with no first dose date")
    if under.any():
        parts.append(f"{int(under.sum())} of {int((~flagged & assessable).sum())} records with "
                     f"{flag}!='Y' start inside the window")
    evidence = f"{ae_name}: " + "; ".join(parts) + "."

    if trt_col in m.columns:
        arms = [str(a) for a in adsl[trt].dropna().unique() if str(a).strip()]
        per_arm = [f"{a} {m.loc[flagged & (m[trt_col] == a), subj].nunique()} current vs "
                   f"{m.loc[inside & (m[trt_col] == a), subj].nunique()} under SAP rule" for a in arms]
        evidence += " Subjects with any TEAE: " + "; ".join(per_arm) + "."
    if (~assessable).any():
        evidence += f" {int((~assessable).sum())} records have no start date and were not assessed."

    return [_finding(
        rule, ae_name,
        f"{flag} in {ae_name} does not follow the SAP window (first dose to last dose + {window} days).",
        evidence)]


# ---------------------------------------------------------------------------
# 5. Printed percentages vs n/N
# ---------------------------------------------------------------------------

def check_percentages(datasets, outputs, rule, ctx=None):
    """In every 'n (xx.x%)' cell of a column whose header prints N, the percentage
    must equal n/N at the precision it is printed with (round half up).
    No params. datasets are not used.
    """
    _need_outputs(outputs)
    findings = []
    for out in outputs:
        ns = {j: (name, n) for j, name, n in _header_ns(out)}
        checked, bad = 0, []
        for row in out["rows"]:
            for j, cell in enumerate(row):
                m = _PCT_CELL.search(cell or "") if j in ns else None
                if not m:
                    continue
                checked += 1
                n, printed = int(m.group(1)), m.group(2)
                total = ns[j][1]
                places = len(printed.split(".")[1]) if "." in printed else 0
                recomputed = _pct(n, total, places) if total else None
                if recomputed is None or Decimal(printed) != recomputed:
                    calc = f"{n}/{total} = {recomputed}%" if recomputed is not None else f"N=0 but n={n}"
                    bad.append(f"'{row[0]}' / {out['column_headers'][j]}: printed {cell.strip()}, {calc}")
        if bad:
            shown = "; ".join(bad[:3]) + (f"; and {len(bad) - 3} more" if len(bad) > 3 else "")
            evidence = (f"{_out_short(out)}: {len(bad)} of {checked} n (%) cells print a percentage that "
                        f"does not equal n/N. {shown}.")
            findings.append(_finding(
                rule, _out_name(out),
                f"Printed percentages in {_out_short(out)} do not match n divided by the column N.", evidence))
    return findings


# ---------------------------------------------------------------------------
# 6. Total column = sum of the arms
# ---------------------------------------------------------------------------

def check_totals(datasets, outputs, rule, ctx=None):
    """In a table with a Total column, every row whose cells are all counts
    ('n' or 'n (%)') must have Total equal to the sum of the arm columns.
    Header Ns are not summed here (check_bign / check_cross_table_n cover them).
    No params. datasets are not used.
    """
    _need_outputs(outputs)
    findings = []
    for out in outputs:
        hdr = out["column_headers"]
        total_cols = [j for j, h in enumerate(hdr) if j > 0 and _is_total((_HDR_N.match(h) or [None, h])[1])]
        if not total_cols:
            continue
        tj = total_cols[0]
        arms = [j for j in range(1, len(hdr)) if j != tj]
        if len(arms) < 2:
            continue
        checked, bad = 0, []
        for row in out["rows"]:
            if len(row) <= max(arms + [tj]):
                continue
            vals = [_count_cell(row[j]) for j in arms]
            tot = _count_cell(row[tj])
            if tot is None or any(v is None for v in vals):
                continue
            checked += 1
            if sum(vals) != tot:
                bad.append(f"'{row[0]}': {' + '.join(str(v) for v in vals)} = {sum(vals)}, Total prints {tot}")
        if bad:
            evidence = (f"{_out_short(out)}: {len(bad)} of {checked} count rows have a Total column that is "
                        f"not the sum of the arms. " + "; ".join(bad[:3]) + ".")
            findings.append(_finding(
                rule, _out_name(out),
                f"The Total column in {_out_short(out)} does not equal the sum of the treatment arms.", evidence))
    return findings


# ---------------------------------------------------------------------------
# 7. SOC count not lower than its largest PT
# ---------------------------------------------------------------------------

def check_soc_pt(datasets, outputs, rule, ctx=None):
    """In an SOC / PT table, a subject counted under a PT is also counted under
    its SOC, so SOC n >= the largest PT n in every column. Row indentation is
    lost in the grid, so rows are classed as SOC or PT by looking their label up
    in the AE dataset (soc_var / pt_var values).

    params: ae_dataset ("ADAE"), soc_var ("AEBODSYS"), pt_var ("AEDECOD").
    Tables with no SOC row are skipped.
    """
    _need_outputs(outputs)
    ae_name = _p(rule, "ae_dataset", "ADAE")
    soc_v, pt_v = _p(rule, "soc_var", "AEBODSYS"), _p(rule, "pt_var", "AEDECOD")
    ae = _need(datasets, ae_name, [soc_v, pt_v])
    socs = {_norm(x) for x in ae[soc_v].dropna().unique()}
    pts = {_norm(x) for x in ae[pt_v].dropna().unique()}

    findings = []
    for out in outputs:
        groups, current = [], None
        for row in out["rows"]:
            key = _norm(row[0]) if row else ""
            if key in socs:
                current = {"soc": row, "pts": []}
                groups.append(current)
            elif key in pts and current is not None:
                current["pts"].append(row)
            else:
                current = None
        if not groups:
            continue
        hdr = out["column_headers"]
        checked, bad = 0, []
        for g in groups:
            for j in range(1, len(hdr)):
                soc_n = _count_cell(g["soc"][j]) if j < len(g["soc"]) else None
                pt_ns = [(p[0], _count_cell(p[j])) for p in g["pts"] if j < len(p)]
                pt_ns = [(label, n) for label, n in pt_ns if n is not None]
                if soc_n is None or not pt_ns:
                    continue
                checked += 1
                label, top = max(pt_ns, key=lambda t: t[1])
                if soc_n < top:
                    bad.append(f"'{g['soc'][0]}' / {hdr[j]}: SOC n={soc_n} but PT '{label}' n={top}")
        if bad:
            evidence = (f"{_out_short(out)}: {len(bad)} of {checked} SOC/column combinations have a SOC count "
                        f"lower than its largest PT. " + "; ".join(bad[:3]) + ".")
            findings.append(_finding(
                rule, _out_name(out),
                f"In {_out_short(out)} a System Organ Class count is lower than one of its Preferred Terms.",
                evidence))
    return findings


# ---------------------------------------------------------------------------
# 8. Variable label claims per-mg / per-kg but the values are not normalised
# ---------------------------------------------------------------------------

def check_label_units(datasets, outputs, rule, ctx=None):
    """If the label of value_var says 'per kg', 'per mg', '/kg' or '/mg', the
    values must equal source_var divided by the matching denominator variable.
    Records where the denominator is missing, zero or exactly 1 cannot tell
    normalised from raw and are not counted.

    params: dataset, value_var, source_var (all required).
            denominators (optional) - {"kg": "WEIGHT", "mg": "DOSE"}.
            tolerance (optional) - relative, default 0.05.
    Needs ctx["profiles"][dataset] for the label. A label with no per-unit claim
    yields no finding.
    """
    name, value_v, source_v = _p(rule, "dataset"), _p(rule, "value_var"), _p(rule, "source_var")
    denoms = _p(rule, "denominators", {"kg": "WEIGHT", "mg": "DOSE"})
    tol = float(_p(rule, "tolerance", 0.05))
    df = _need(datasets, name, [value_v, source_v])
    label = _label(ctx, name, value_v)
    m = _PER_UNIT.search(label)
    if not m:
        return []
    unit = m.group(1).lower()
    if unit not in denoms:
        raise CheckInputError(f"rule {rule['rule_id']} names no denominator variable for per-{unit}")
    den_v = denoms[unit]
    _need(datasets, name, [den_v])

    val, src, den = (pd.to_numeric(df[c], errors="coerce") for c in (value_v, source_v, den_v))
    ok = val.notna() & src.notna() & den.notna() & (den > 0) & (den != 1)
    if not ok.any():
        return []
    expected = src / den
    normalised = (val - expected).abs() <= tol * expected.abs()
    not_norm = ok & ~normalised
    if not not_norm.any():
        return []
    unchanged = not_norm & ((val - src).abs() <= tol * src.abs())
    evidence = (f"{name}.{value_v} is labelled '{label}' but {int(not_norm.sum())} of {int(ok.sum())} "
                f"assessable records do not equal {source_v} / {den_v}; {int(unchanged.sum())} of those "
                f"equal {source_v} unchanged.")
    return [_finding(
        rule, f"{name}.{value_v}",
        f"The label of {value_v} says per-{unit} but the values are not divided by {den_v}.", evidence)]


# ---------------------------------------------------------------------------
# 9. Visit windows vs the SAP / protocol
# ---------------------------------------------------------------------------

def check_visit_windows(datasets, outputs, rule, ctx=None):
    """For each visit named in the SAP windows: AWLO/AWHI must equal the SAP
    bounds, and (if day_var is given) each record's study day must fall inside
    them. A bound of null means open-ended.

    params: dataset (required, e.g. "ADVS"),
            windows (required) - {"Week 4": [22, 35], "Baseline": [null, 1]},
            visit_var ("AVISIT"), lo_var ("AWLO"), hi_var ("AWHI"),
            day_var (default none; e.g. "ADY").
    Visits in the data but not in `windows` are not checked.
    """
    name, windows = _p(rule, "dataset"), _p(rule, "windows")
    visit_v, lo_v, hi_v = _p(rule, "visit_var", "AVISIT"), _p(rule, "lo_var", "AWLO"), _p(rule, "hi_var", "AWHI")
    day_v = _p(rule, "day_var", None)
    df = _need(datasets, name, [visit_v, lo_v, hi_v] + ([day_v] if day_v else []))

    def same(series, bound):
        num = pd.to_numeric(series, errors="coerce")
        return num.isna() if bound is None else num == bound

    parts, bad_visits, seen = [], 0, 0
    for visit, (lo, hi) in windows.items():
        sub = df[df[visit_v] == visit]
        if sub.empty:
            continue
        seen += 1
        sap = f"{_fmt(lo) if lo is not None else 'open'}/{_fmt(hi) if hi is not None else 'open'}"
        wrong = ~(same(sub[lo_v], lo) & same(sub[hi_v], hi))
        visit_parts = []
        if wrong.any():
            combos = sub[wrong].groupby([lo_v, hi_v], dropna=False).size()
            found = ", ".join(f"{_fmt(a) if pd.notna(a) else 'open'}/{_fmt(b) if pd.notna(b) else 'open'} "
                              f"({int(c)})" for (a, b), c in combos.items())
            visit_parts.append(f"{int(wrong.sum())} of {len(sub)} records have {lo_v}/{hi_v} = {found} "
                               f"but the SAP window is {sap}")
        if day_v:
            days = pd.to_numeric(sub[day_v], errors="coerce")
            outside = days.notna() & (((days < lo) if lo is not None else False) |
                                      ((days > hi) if hi is not None else False))
            if outside.any():
                visit_parts.append(f"{int(outside.sum())} of {len(sub)} records have {day_v} outside the "
                                   f"SAP window {sap}")
        if visit_parts:
            bad_visits += 1
            parts.append(f"'{visit}': " + "; ".join(visit_parts))
    if not parts:
        return []
    evidence = f"{name}: {bad_visits} of {seen} SAP-windowed visits disagree. " + ". ".join(parts) + "."
    return [_finding(
        rule, name, f"Visit windows in {name} ({lo_v}/{hi_v}) do not match the SAP visit windows.", evidence)]


# ---------------------------------------------------------------------------
# 10. Tables listed in the SAP vs tables delivered
# ---------------------------------------------------------------------------

def check_tlf_inventory(datasets, outputs, rule, ctx=None):
    """SAP inventory vs delivered outputs, matched on table number. Two findings
    at most: outputs the SAP lists but nobody delivered (rule severity), and
    outputs delivered that the SAP does not list (minor).

    params: tables (required) - ["14.1.1", {"id": "14.3.2", "title": "..."},
            "Listing 16.2.1"]. Tables are keyed by number; listings and figures
            as "Listing 16.2.1" / "Figure 14.4.1".
    An empty outputs list is allowed: it means nothing was delivered.
    """
    listed = []
    for t in _p(rule, "tables"):
        listed.append((t, "") if isinstance(t, str) else (t["id"], t.get("title", "")))
    delivered = {_output_key(o): o for o in outputs if o["table_id"]}

    findings = []
    missing = [(i, t) for i, t in listed if i not in delivered]
    if missing:
        names = "; ".join(f"{i} ({t})" if t else i for i, t in missing)
        evidence = (f"SAP lists {len(listed)} outputs; {len(listed) - len(missing)} delivered, "
                    f"{len(missing)} missing: {names}.")
        findings.append(_finding(
            rule, "Output inventory (SAP vs delivered)",
            f"{len(missing)} output(s) required by the SAP were not delivered.", evidence))

    listed_ids = {i for i, _ in listed}
    extra = sorted(k for k in delivered if k not in listed_ids)
    if extra:
        evidence = (f"{len(delivered)} outputs delivered; {len(extra)} not listed in the SAP inventory "
                    f"({len(listed)} listed): {', '.join(extra)}.")
        findings.append(_finding(
            rule, "Output inventory (delivered vs SAP)",
            f"{len(extra)} delivered output(s) are not in the SAP inventory.", evidence, severity="minor"))
    return findings


# ---------------------------------------------------------------------------
# 11. Same population, same N, in every table
# ---------------------------------------------------------------------------

def check_cross_table_n(datasets, outputs, rule, ctx=None):
    """Tables that state the same population must print the same N for the same
    arm (and Total). Compares tables with each other, so no dataset is needed.
    Tables that state no recognisable population are skipped.
    No params. datasets are not used.
    """
    _need_outputs(outputs)
    by_pop = {}
    for out in outputs:
        pop = _pop_of(out)
        if pop is None:
            continue
        for _, name, n in _header_ns(out):
            key = "total" if _is_total(name) else _norm(name)
            by_pop.setdefault(pop, {}).setdefault(key, {"name": name, "seen": {}})["seen"][_out_short(out)] = n

    findings = []
    for pop, cols in by_pop.items():
        comparable = {k: v for k, v in cols.items() if len(v["seen"]) > 1}
        bad = {k: v for k, v in comparable.items() if len(set(v["seen"].values())) > 1}
        if not bad:
            continue
        label = DEFAULT_POPULATIONS[pop]["label"]
        detail = "; ".join(f"{v['name']}: " + " vs ".join(f"N={n} in {t}" for t, n in v["seen"].items())
                           for v in bad.values())
        tables = sorted({t for v in bad.values() for t in v["seen"]})
        evidence = (f"{label} population: {len(bad)} of {len(comparable)} columns shared by more than one "
                    f"table print different N. {detail}.")
        findings.append(_finding(
            rule, "; ".join(tables),
            f"Tables on the {label} population print different Ns for the same treatment group.", evidence))
    return findings


# ---------------------------------------------------------------------------
# 12. TS domain vs the protocol
# ---------------------------------------------------------------------------

def check_ts_vs_protocol(datasets, outputs, rule, ctx=None):
    """TS parameter values vs what the protocol says. Values are compared
    ignoring case, punctuation and extra spaces; a parameter with several TS rows
    passes if any row matches.

    params: expected (required) - {"TITLE": "...", "TPHASE": "Phase III", ...},
            keyed by TSPARMCD, values taken from the protocol.
    Set the rule's sap_ref to the protocol section (e.g. "Protocol 1.1").
    """
    expected = _p(rule, "expected")
    ts = _need(datasets, "TS", ["TSPARMCD", "TSVAL"])

    def norm_text(s):
        return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()

    wrong, missing = [], []
    for code, want in expected.items():
        vals = [str(v) for v in ts.loc[ts["TSPARMCD"] == code, "TSVAL"].dropna()]
        if not vals:
            missing.append(code)
        elif norm_text(want) not in {norm_text(v) for v in vals}:
            wrong.append(f"{code} - TS has '{_clip(' | '.join(vals))}', protocol says '{_clip(want)}'")
    if not wrong and not missing:
        return []
    parts = wrong + ([f"not in TS at all: {', '.join(missing)}"] if missing else [])
    evidence = (f"TS: {len(wrong) + len(missing)} of {len(expected)} checked parameters disagree with the "
                f"protocol. " + "; ".join(parts) + ".")
    return [_finding(
        rule, "TS",
        "Trial Summary values do not match the protocol title and design.", evidence)]


CHECKS = {
    "check_bign": check_bign,
    "check_population_filter": check_population_filter,
    "check_baseline_per_period": check_baseline_per_period,
    "check_teae_window": check_teae_window,
    "check_percentages": check_percentages,
    "check_totals": check_totals,
    "check_soc_pt": check_soc_pt,
    "check_label_units": check_label_units,
    "check_visit_windows": check_visit_windows,
    "check_tlf_inventory": check_tlf_inventory,
    "check_cross_table_n": check_cross_table_n,
    "check_ts_vs_protocol": check_ts_vs_protocol,
}
