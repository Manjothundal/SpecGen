from generator import review_code
import config


def build_improve_prompt(code, row, known_vars, language=None, ig_version=None):
    """Ask a principal programmer to rewrite a draft block correctly.

    language: "sas" or "r" (defaults to config.LANGUAGE). Selects the persona
        and the rewrite checklist — both are language-specific.

    ig_version: CDISC ADaMIG version (e.g. "1.3") — when given, adds a
        rewrite bullet targeting that version's conventions.
    """
    language = (language or config.LANGUAGE).lower()
    if language == "sas":
        return _build_sas_improve_prompt(code, row, known_vars, ig_version)
    elif language == "r":
        return _build_r_improve_prompt(code, row, known_vars, ig_version)
    else:
        raise ValueError(f"Unknown language: {language!r} (expected 'sas' or 'r')")


# ---------------------------------------------------------------------------
# SAS improve prompt — unchanged from the original
# ---------------------------------------------------------------------------

def _build_sas_improve_prompt(code, row, known_vars, ig_version=None):
    ig_line = f"- Follows CDISC ADaMIG v{ig_version} conventions for this variable (naming, controlled terminology)\n" if ig_version else ""
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
- Avoids common Pinnacle 21 findings: keep labels to 40 characters or fewer,
  strip leading/trailing whitespace from character values, and use plain
  ASCII punctuation (no curly quotes or em-dashes) in labels and character
  values
- Is code a senior programmer would sign off on
{ig_line}
Output ONLY the corrected SAS code with one brief comment line.
No explanation, no markdown fences.
"""


# ---------------------------------------------------------------------------
# R improve prompt — plain tidyverse (dplyr) parallel
# ---------------------------------------------------------------------------

def _build_r_improve_prompt(code, row, known_vars, ig_version=None):
    ig_line = f"- Follows CDISC ADaMIG v{ig_version} conventions for this variable (naming, controlled terminology)\n" if ig_version else ""
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
- Avoids common Pinnacle 21 findings: strip leading/trailing whitespace from
  character values, and use plain ASCII punctuation (no curly quotes or
  em-dashes) in character values
- Is code a senior programmer would sign off on
{ig_line}
Output ONLY the corrected R code with one brief comment line.
No explanation, no markdown fences.
"""


def improve_block(code, row, known_vars, language=None, mode=None, ig_version=None):
    """Return an improved version of a generated code block.

    Improve and Review share the REVIEWER-role model (config.REVIEWER, or the
    explicit mode override) — Draft is the only step that uses WRITER. This
    matches the documented three-mode architecture (Offline/Hybrid/API): in
    Hybrid, Improve and Review both go to the API even though the Draft was
    local.
    """
    return review_code(build_improve_prompt(code, row, known_vars, language=language,
                                            ig_version=ig_version), mode=mode, language=language).strip()
