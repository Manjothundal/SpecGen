from macro_lookup import load_catalog, find_macro
import config

catalog = load_catalog()


def build_prompt(row, skip_macro=False, context_vars=None, language=None):
    """Turn one spec row into an instruction for the AI.

    context_vars: override the "already available" variable description.
        Default assumes SDTM source (DM, EX). Pass a BDS-specific string for
        ADaM BDS domains (ADVS, ADLB, etc.) where the available columns are
        PARAMCD/AVAL/BASE, not SDTM domain vars.

    language: "sas" or "r". Defaults to config.LANGUAGE. Selects which
        language-specific prompt body is built. The variable metadata header
        is identical for both; only the code-style body differs.

    NOTE: in R mode the SAS macro catalog is always skipped — those macros
    (adsl_agegr, etc.) are SAS-only and have no R equivalent, so offering
    them to an R Writer would tell it to emit a SAS macro call.
    """
    language = (language or config.LANGUAGE).lower()

    format_line = ""
    fmt = str(row["Format"]).strip()
    if fmt and fmt.lower() != "nan":
        format_line = f"Format: {fmt}\n"

    # Macro catalog is SAS-only. Force-skip in R mode regardless of caller.
    if language == "r":
        skip_macro = True

    match = None if skip_macro else find_macro(row["Variable"], catalog)
    if match:
        macro_section = f"""
VALIDATED MACRO AVAILABLE — use it instead of writing raw code:
Macro: {match['macro']}
Purpose: {match['purpose']}
Call: {match['call']}
NOTE: This macro is validated and handles missing values. Adapt the call for this specific variable if needed. Do NOT write raw derivation logic — output ONLY the macro call.
"""
    else:
        macro_section = ""

    if language == "sas":
        return _build_sas_prompt(row, format_line, macro_section, context_vars)
    elif language == "r":
        return _build_r_prompt(row, format_line, context_vars)
    else:
        raise ValueError(f"Unknown language: {language!r} (expected 'sas' or 'r')")


# ---------------------------------------------------------------------------
# SAS prompt body — unchanged from the original build_prompt
# ---------------------------------------------------------------------------

def _build_sas_prompt(row, format_line, macro_section, context_vars):
    available_vars = context_vars or "all needed SDTM variables (from DM, EX, etc.)"

    prompt = f"""You are a senior clinical SAS programmer.
Write SAS 9.4 code to derive one ADaM variable.

Variable: {row['Variable']}
Label: {row['Label']}
Type: {row['Type']}, Length: {row['Length']}
{format_line}Derivation rule: {row['Derivation']}
{macro_section}
Rules:
- Output ONLY the derivation logic statements (length, label, format, if/then, assignments).
- Do NOT include data, set, merge, or run statements - the code will be inserted into an existing data step.
- Assume {available_vars} are already available in the step.
- Do NOT repeat the variable metadata (name, label, type, format, derivation rule) as comments. Output ONE brief comment line, then the code.
- Do NOT add any explanation before or after the code.
- Output plain SAS code only, no markdown fences.

Style rules:
- Use select/when instead of if/else chains with 3 or more branches.
- For conditions, use a bare `select;` with full conditions in each when, e.g. `select; when (AGE < 65) X = 1; ... end;`
- Use `select (VAR);` ONLY when matching exact values, e.g. `select (SEX); when ("M") ...`
- Never use range operators or bare comparisons inside `when ()` after `select (VAR);`
- Do NOT invent format names. Use only formats given in the spec or standard SAS formats.
- Do NOT invent variable values or codes that are not stated in the derivation rule.
- Use ONLY variables named in the derivation rule or standard SDTM variables from DM or EX. NEVER invent helper variables or flags that are not defined in this step.
- Reference variables by name only, never with a dataset prefix (write ARM, not DM.ARM).
- SUPPDM qualifiers are already transposed into columns named after each QNAM (e.g. COMPLT). Reference those column names directly; NEVER reference QNAM or QVAL.
- For SDTM ISO 8601 date strings (--DTC variables like RFICDTC, DTHDTC), use `input(substr(dtc,1,10), ?? E8601DA.)` consistently. Never use yymmdd10. on --DTC variables.
- CRITICAL: In SAS, missing numeric values are less than every number. Any numeric range chain (if X < a; else if ...) MUST start with `if missing(X) then do; call missing(RESULT); end; else` before any comparison. Never compare a numeric variable without guarding missing first.
"""
    return prompt


# ---------------------------------------------------------------------------
# R prompt body — plain tidyverse (dplyr), mirrors the SAS derivation logic
# ---------------------------------------------------------------------------

def _build_r_prompt(row, format_line, context_vars):
    available_vars = context_vars or "all needed SDTM variables (from DM, EX, etc.)"

    prompt = f"""You are a senior clinical R programmer working in the tidyverse.
Write plain R (dplyr) code to derive one ADaM variable.

Variable: {row['Variable']}
Label: {row['Label']}
Type: {row['Type']}, Length: {row['Length']}
{format_line}Derivation rule: {row['Derivation']}

Rules:
- Output ONLY the derivation expression(s) for this one variable — the
  right-hand side(s) that assign it. The code will be inserted inside an
  existing `mutate()` on a data frame already piped in. Write it as one or
  more `NAME = <expression>` lines suitable for placing inside mutate().
- Do NOT include library(), read/load, the data frame name, the pipe `|>`,
  the surrounding `mutate(` call, or any I/O — only the assignment(s).
- Assume {available_vars} are already columns in the data frame.
- Do NOT repeat the variable metadata (name, label, type, format, derivation
  rule) as comments. Output ONE brief comment line, then the code.
- Do NOT add any explanation before or after the code.
- Output plain R code only, no markdown fences.

Style rules:
- Use dplyr::case_when() instead of nested if/else for 3 or more branches.
  Each arm is `condition ~ value`; end with `TRUE ~ <default>`.
- Use if_else() (not base ifelse) for a single two-way condition.
- Match the label with a comment; R has no `label`/`length`/`format`
  statement — do NOT emit those. Store character results as strings and
  numeric as numeric; use NA_character_ / NA_real_ for typed missing.
- Do NOT invent variable values or codes that are not stated in the
  derivation rule.
- Use ONLY variables named in the derivation rule or standard SDTM variables
  from DM or EX. NEVER invent helper columns or flags not defined here.
- Reference columns by bare name (ARM, not df$ARM or DM$ARM).
- SUPPDM qualifiers are already pivoted into columns named after each QNAM
  (e.g. COMPLT). Reference those column names directly; NEVER reference QNAM
  or QVAL.
- For SDTM ISO 8601 date strings (--DTC variables like RFICDTC, DTHDTC), parse
  with `as.Date(substr(dtc, 1, 10))`. Do not invent date formats.
- Missing handling: unlike SAS, R's NA is NOT ordered below numbers — a
  comparison with NA yields NA, not TRUE/FALSE. In case_when, guard missing
  explicitly (e.g. `is.na(X) ~ NA_real_` as the first arm) so an NA input
  never falls through to a numeric-range arm.
"""
    return prompt


# --- ANL01FL row for ADVS, since no hand-authored BDS spec exists ---
ANL01FL_ROW = {
    "Variable": "ANL01FL",
    "Label": "Analysis Flag 01",
    "Type": "Char",
    "Length": "1",
    "Format": "",
    "Derivation": (
        "Set to 'Y' if the record falls within the protocol-defined analysis "
        "visit window and AVAL is not missing. Otherwise leave null."
    ),
}

# Call it like this (SAS):
#   prompt = build_prompt(
#       ANL01FL_ROW,
#       skip_macro=True,
#       context_vars="PARAMCD, PARAM, AVAL, BASE, CHG, PCHG, VISIT, VISITNUM, USUBJID (from the ADVS reshape step)"
#   )
# For R, add language="r" (skip_macro is forced True in R mode anyway):
#   prompt = build_prompt(ANL01FL_ROW, context_vars="...", language="r")
