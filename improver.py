from generator import generate_code
import config


def build_improve_prompt(code, row, known_vars, language=None):
    """Ask a principal programmer to rewrite a draft block correctly.

    language: "sas" or "r" (defaults to config.LANGUAGE). Selects the persona
        and the rewrite checklist — both are language-specific.
    """
    language = (language or config.LANGUAGE).lower()
    if language == "sas":
        return _build_sas_improve_prompt(code, row, known_vars)
    elif language == "r":
        return _build_r_improve_prompt(code, row, known_vars)
    else:
        raise ValueError(f"Unknown language: {language!r} (expected 'sas' or 'r')")


# ---------------------------------------------------------------------------
# SAS improve prompt — unchanged from the original
# ---------------------------------------------------------------------------

def _build_sas_improve_prompt(code, row, known_vars):
    return f"""You are a principal clinical SAS programmer with 15+ years of experience.
A junior programmer produced the draft below. Rewrite it correctly.

SPECIFICATION
Variable: {row['Variable']}
Label: {row['Label']}
Type: {row['Type']}, Length: {row['Length']}
Derivation rule: {row['Derivation']}

DRAFT CODE
{code}

Variables available in this data step:
{", ".join(known_vars)}

Rewrite the code so that it:
- Correctly implements the derivation rule and nothing more
- Uses only variables from the available list, with no dataset prefixes
- Declares length and label; adds a format ONLY if the spec gives one
- Never invents values, codes, treatment names, or format names
- Uses `select;` with full conditions, or `select (VAR);` only for exact value matching
- Compares character variables to character values, never to numeric missing
- Is code a senior programmer would sign off on

Output ONLY the corrected SAS code with one brief comment line.
No explanation, no markdown fences.
"""


# ---------------------------------------------------------------------------
# R improve prompt — plain tidyverse (dplyr) parallel
# ---------------------------------------------------------------------------

def _build_r_improve_prompt(code, row, known_vars):
    return f"""You are a principal clinical R programmer (tidyverse) with 15+ years of experience.
A junior programmer produced the draft below. Rewrite it correctly.

SPECIFICATION
Variable: {row['Variable']}
Label: {row['Label']}
Type: {row['Type']}, Length: {row['Length']}
Derivation rule: {row['Derivation']}

DRAFT CODE
{code}

Columns available in this data frame:
{", ".join(known_vars)}

The code is the inner derivation expression(s) for ONE variable, to be placed
inside an existing mutate() on a data frame already piped in.

Rewrite the code so that it:
- Correctly implements the derivation rule and nothing more
- Is only the bare `NAME = <expression>` line(s) — no library(), no data frame
  name, no pipe |>, no wrapping mutate(), no I/O
- Uses only columns from the available list, referenced by bare name (no df$ or
  DM$ prefixes)
- Uses case_when() for 3+ branches (each `condition ~ value`, ending `TRUE ~ ...`)
  and if_else() for a single two-way condition; never base ifelse()
- Uses typed missing values (NA_character_ / NA_real_) and typed literals
  (strings for character results, numeric for numeric)
- Guards NA explicitly before any numeric-range comparison, since in R a
  comparison with NA yields NA (unlike SAS, NA is not ordered below numbers)
- Never invents values, codes, treatment names, or column names
- Does NOT emit length/label/format statements — R has none
- Is code a senior programmer would sign off on

Output ONLY the corrected R code with one brief comment line.
No explanation, no markdown fences.
"""


def improve_block(code, row, known_vars, language=None):
    """Return an improved version of a generated code block."""
    return generate_code(build_improve_prompt(code, row, known_vars, language=language)).strip()
