"""qc_generator.py — independent double-programming QC for ADSL.

Real double-programming QC: a second programmer derives the same variables
from the same APPROVED SPEC, independently — not from the production
program's code — and the two outputs are reconciled by comparison. Two
pieces:

  generate_qc_adsl()       — re-derives every main-step (Origin=Derived,
                              Source in DM/DERIVED — the same rows the
                              production Writer/Improver/Reviewer pipeline
                              covers) variable via its own model call, with
                              a QC-programmer persona and the macro catalog
                              deliberately never offered (see below), into a
                              second program (adsl_qc.sas / adsl_qc.R).
  generate_compare_harness() — a deterministic PROC COMPARE (SAS) / data-
                              frame diff (R) reconciling `adsl` (production)
                              against `adsl_qc` (this module's output). No
                              model call — a diff is either found or it
                              isn't, there's nothing for a model to draft.

Scope: only main-step derivation logic is re-derived — the ten ADSL
pre-steps (EX summarize, SUPPDM transpose, SE select, DS summarize, ...)
are shared between production and QC unchanged. Those are built
deterministically by the harness, not drafted by a model (see README.md),
so double-programming them would be re-testing this app's own Python
against itself with an LLM in between, not catching the kind of natural-
language-to-code translation error double programming exists to catch.
Predecessor (straight-copy) and EX_SUMMARY-sourced variables are excluded
for the same reason: nothing was independently drafted for them in
production to disagree with.

Macros are deliberately OFF on the QC path even for a variable production
matched exactly in the catalog (macro_catalog.csv) — reusing the same
validated macro on both sides would make a bug IN that macro invisible to
a comparison that calls it twice. QC always re-derives from the raw
Derivation rule in the model's own words.
"""

from assembler import clean, known_variables, _r_add_comma
from generator import generate_code

MAIN_STEP_SOURCES = ("DM", "DERIVED")


def route_qc_rows(spec):
    """Same filter as app.py's route_adsl_spec — the main-step subset only
    (see module docstring for why copies/EX_SUMMARY rows are excluded)."""
    derived = spec[spec["Origin"] == "Derived"]
    return derived[derived["Source"].isin(MAIN_STEP_SOURCES)]


def _build_qc_prompt_sas(row, known_vars, ig_version=None):
    ig_line = f"- Follow CDISC ADaMIG v{ig_version} conventions for variable naming, controlled terminology, and core-variable expectations.\n" if ig_version else ""
    return f"""You are an independent QC programmer performing double-programming
validation. You have not seen, and must not assume anything about, any
other program written for this study — derive this variable directly and
independently from the specification below, in your own words.

Variable: {row['Variable']}
Label: {row['Label']}
Type: {row['Type']}, Length: {row['Length']}
Derivation rule: {row['Derivation']}

Rules:
- Output ONLY the derivation logic statements (length, label, format, if/then, assignments).
- Do NOT include data, set, merge, or run statements - the code will be inserted into an existing data step.
- Assume {", ".join(known_vars)} are already available in the step.
- Do NOT repeat the variable metadata as comments. Output ONE brief comment line, then the code.
- Do NOT add any explanation before or after the code.
- Output plain SAS code only, no markdown fences.
- Do NOT use or reference any company macro, even if one seems applicable —
  write the raw derivation logic yourself. Independence from any macro
  another programmer might have chosen is the point of this pass.
{ig_line}
Style rules:
- Use select/when instead of if/else chains with 3 or more branches.
- Do NOT invent format names, variable values, or codes not stated in the derivation rule.
- Reference variables by name only, never with a dataset prefix.
- For SDTM ISO 8601 date strings (--DTC variables), use `input(substr(dtc,1,10), ?? E8601DA.)`.
- CRITICAL: In SAS, missing numeric values are less than every number. Any numeric range chain MUST guard `missing(X)` first.
"""


def _build_qc_prompt_r(row, known_vars, ig_version=None):
    ig_line = f"- Follow CDISC ADaMIG v{ig_version} conventions for variable naming, controlled terminology, and core-variable expectations.\n" if ig_version else ""
    return f"""You are an independent QC programmer (tidyverse) performing double-
programming validation. You have not seen, and must not assume anything
about, any other program written for this study — derive this variable
directly and independently from the specification below, in your own words.

Variable: {row['Variable']}
Label: {row['Label']}
Type: {row['Type']}, Length: {row['Length']}
Derivation rule: {row['Derivation']}

Rules:
- Output ONLY the derivation expression(s) for this one variable, as one or
  more `NAME = <expression>` lines suitable for placing inside an existing
  mutate() on a data frame already piped in.
- Do NOT include library(), read/load, the data frame name, the pipe `|>`,
  the surrounding mutate() call, or any I/O.
- Assume {", ".join(known_vars)} are already columns in the data frame.
- Do NOT repeat the variable metadata as comments. Output ONE brief comment line, then the code.
- Do NOT add any explanation before or after the code.
- Output plain R code only, no markdown fences.
{ig_line}
Style rules:
- Use case_when() for 3+ branches, if_else() (never base ifelse) for two-way conditions.
- Do NOT invent variable values or codes not stated in the derivation rule.
- Reference columns by bare name.
- For SDTM ISO 8601 date strings, parse with `as.Date(substr(dtc, 1, 10))`.
- Guard NA explicitly before any numeric-range comparison (R's NA is not ordered below numbers, unlike SAS missing).
"""


def build_qc_prompt(row, known_vars, language="sas", ig_version=None):
    language = (language or "sas").lower()
    if language == "sas":
        return _build_qc_prompt_sas(row, known_vars, ig_version)
    elif language == "r":
        return _build_qc_prompt_r(row, known_vars, ig_version)
    raise ValueError(f"Unknown language: {language!r} (expected 'sas' or 'r')")


def generate_qc_block(row, known_vars, language="sas", mode=None, ig_version=None):
    code = generate_code(build_qc_prompt(row, known_vars, language=language, ig_version=ig_version),
                         mode=mode, language=language)
    return clean(code)


def generate_qc_adsl(spec, language="sas", mode=None, ig_version=None, cancel_event=None):
    """Independently re-derive every main-step variable and assemble
    adsl_qc.sas / adsl_qc.R. `spec` is the same Variables-sheet DataFrame
    production ADSL was generated from. Writer-only (no Improve/Review) —
    the PROC COMPARE reconciliation against production IS this pass's QC
    mechanism, the same way it would be for a human double-programmer.

    Joins the exact same pre-step datasets/frames production's own main
    step does (dm, ex_dates, ex_first, suppdm_w, se_epoch, ds_summary,
    ds_trtdisc, vs_summary, cm_summary, mh_summary) — those are shared,
    deterministic inputs (see module docstring), so this program is meant
    to run in the same session/library as adsl.sas, after it, reusing the
    intermediate datasets adsl.sas's own pre-steps already built."""
    language = (language or "sas").lower()
    qc_rows = route_qc_rows(spec)
    available = known_variables(spec)

    if language == "r":
        parts = []
        parts.append("# ********************************")
        parts.append("# Program: adsl_qc.R")
        parts.append("# Independent double-programming QC re-derivation of adsl.R")
        parts.append("# Generated by SpecGen (target = r)")
        parts.append("# ********************************")
        parts.append("library(dplyr)")
        parts.append("")
        parts.append("# Same pre-step frames adsl.R's own main step joins — see module docstring")
        parts.append("adsl_qc <- dm |>")
        parts.append("  left_join(ex_dates,   by = \"USUBJID\") |>")
        parts.append("  left_join(ex_first,   by = \"USUBJID\") |>")
        parts.append("  left_join(suppdm_w,   by = \"USUBJID\") |>")
        parts.append("  left_join(se_epoch,   by = \"USUBJID\") |>")
        parts.append("  left_join(ds_summary, by = \"USUBJID\") |>")
        parts.append("  left_join(ds_trtdisc, by = \"USUBJID\") |>")
        parts.append("  left_join(vs_summary, by = \"USUBJID\") |>")
        parts.append("  left_join(cm_summary, by = \"USUBJID\") |>")
        parts.append("  left_join(mh_summary, by = \"USUBJID\") |>")
        parts.append("  mutate(")
        for _, row in qc_rows.sort_values("Order").iterrows():
            if cancel_event is not None and cancel_event.is_set():
                parts.append(f"    # -- generation aborted by user before variable {row['Variable']} -- #")
                break
            var = row["Variable"]
            code = generate_qc_block(row, available, language="r", mode=mode, ig_version=ig_version)
            raw_lines = code.splitlines()
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
            parts.append("\n".join(indented))
        parts.append("  )")
        return "\n".join(parts)

    parts = []
    parts.append("/* Program: adsl_qc.sas */")
    parts.append("/* Independent double-programming QC re-derivation of adsl.sas */")
    parts.append("/* Generated by SpecGen */")
    parts.append("")
    parts.append("/* Same pre-step datasets adsl.sas's own main step merges — see module docstring */")
    parts.append("data adsl_qc;")
    parts.append("  merge dm ex_dates ex_first suppdm_w se_epoch ds_summary ds_trtdisc vs_summary cm_summary mh_summary;")
    parts.append("  by usubjid;")
    parts.append("")
    for _, row in qc_rows.sort_values("Order").iterrows():
        if cancel_event is not None and cancel_event.is_set():
            parts.append(f"/* -- generation aborted by user before variable {row['Variable']} -- */")
            break
        code = generate_qc_block(row, available, language="sas", mode=mode, ig_version=ig_version)
        parts.append(code)
        parts.append("")
    parts.append("run;")
    return "\n".join(parts)


def generate_compare_harness(spec, language="sas"):
    """Deterministic reconciliation of `adsl` (production) against
    `adsl_qc` (this module's independent re-derivation) — no model call.
    Compares only the main-step variables QC actually re-derived (see
    module docstring), plus USUBJID as the ID."""
    qc_vars = [v for v in route_qc_rows(spec)["Variable"].tolist()]

    if (language or "sas").lower() == "r":
        var_list = ", ".join(qc_vars)
        return f"""# Program: adsl_compare.R
# Reconciles adsl (production) against adsl_qc (independent QC re-derivation)
# Generated by SpecGen — deterministic, no model call
library(dplyr)

qc_vars <- c({", ".join(repr(v) for v in qc_vars)})

adsl_compare <- adsl |>
  select(USUBJID, all_of(qc_vars)) |>
  rename_with(~ paste0(.x, "_PROD"), all_of(qc_vars)) |>
  inner_join(
    adsl_qc |> select(USUBJID, all_of(qc_vars)) |>
      rename_with(~ paste0(.x, "_QC"), all_of(qc_vars)),
    by = "USUBJID"
  ) |>
  rowwise() |>
  mutate(
    MISMATCH = paste(
      Filter(function(v) !identical(get(paste0(v, "_PROD")), get(paste0(v, "_QC"))), c({", ".join(repr(v) for v in qc_vars)})),
      collapse = ", "
    )
  ) |>
  ungroup() |>
  filter(MISMATCH != "")

# adsl_compare has one row per subject with at least one mismatching
# variable, and a MISMATCH column listing which ones. Zero rows = the two
# independent derivations agree for every subject and every variable in
# qc_vars ({var_list}).
"""

    keep_vars = " ".join(qc_vars)
    return f"""/* Program: adsl_compare.sas */
/* Reconciles adsl (production) against adsl_qc (independent QC re-derivation) */
/* Generated by SpecGen — deterministic, no model call */

proc sort data=adsl(keep=USUBJID {keep_vars}) out=_prod; by USUBJID; run;
proc sort data=adsl_qc(keep=USUBJID {keep_vars}) out=_qc; by USUBJID; run;

proc compare base=_prod compare=_qc listall method=exact out=_compare_diffs outnoequal;
  id USUBJID;
  var {keep_vars};
run;

/* _compare_diffs has one observation per subject/variable that disagreed
   between production and QC; the LISTING output above also prints a full
   PROC COMPARE report. No rows in _compare_diffs (and "NOTE: No unequal
   values were found" in the log) means the two independent derivations
   agree for every subject and every variable checked ({keep_vars}). */
"""
