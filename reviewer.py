from generator import review_code
import config


def build_review_prompt(code, known_vars, language=None, ig_version=None):
    """Ask the model to check generated code against the known variable list.

    language: "sas" or "r" (defaults to config.LANGUAGE). Selects the QC
        persona and the language-specific checks. Check #1 (hallucinated
        variables) is shared; checks #2/#3 differ because "what would fail"
        is language-specific — a SAS data-step violation is not an R concept,
        and vice versa.

    ig_version: CDISC ADaMIG version (e.g. "1.3") — when given, adds a 4th
        checklist item so this doubles as the "Verify against ADaMIG
        v{version}" action (same Review button, one extra check).
    """
    language = (language or config.LANGUAGE).lower()

    if language == "sas":
        return _build_sas_review_prompt(code, known_vars, ig_version)
    elif language == "r":
        return _build_r_review_prompt(code, known_vars, ig_version)
    else:
        raise ValueError(f"Unknown language: {language!r} (expected 'sas' or 'r')")


# ---------------------------------------------------------------------------
# SAS review prompt — unchanged from the original
# ---------------------------------------------------------------------------

def _build_sas_review_prompt(code, known_vars, ig_version=None):
    ig_check = f"\n5. Non-compliance with CDISC ADaMIG v{ig_version} conventions for this variable (naming, controlled terminology)" if ig_version else ""
    return f"""You are a senior clinical SAS programmer performing QC.

Review this generated SAS code block:

{code}

Variables available in this data step:
{", ".join(known_vars)}

Check ONLY for these issues:
1. References to variables NOT in the available list (hallucinated variables)
2. Statements that would fail in a data step (data/set/merge/run statements)
3. Character values assigned to numeric variables or vice versa
4. Common Pinnacle 21 findings: a label exceeding 40 characters; leading or
   trailing whitespace on a character value; non-ASCII/special characters
   (curly quotes, em-dashes) in a label or character value{ig_check}

Reply with exactly one line:
PASS
or
FAIL: <short reason>

No other text.
"""


# ---------------------------------------------------------------------------
# R review prompt — parallel checks for plain tidyverse (dplyr)
# ---------------------------------------------------------------------------

def _build_r_review_prompt(code, known_vars, ig_version=None):
    ig_check = f"\n5. Non-compliance with CDISC ADaMIG v{ig_version} conventions for this variable (naming, controlled terminology)" if ig_version else ""
    return f"""You are a senior clinical R programmer (tidyverse) performing QC.

Review this generated R code block. It is meant to be the inner derivation
expression(s) placed inside an existing mutate() on a data frame already
piped in — NOT a standalone script.

{code}

Columns available in this data frame:
{", ".join(known_vars)}

Check ONLY for these issues:
1. References to columns NOT in the available list (hallucinated variables)
2. Code that does NOT belong in an inner mutate() expression: library() calls,
   read/load or other I/O, the data frame name, the pipe |>, or the wrapping
   mutate( ... ) itself. Only the bare NAME = <expression> line(s) are valid.
3. Type errors: a character result (string / NA_character_) assigned where a
   numeric is expected or vice versa; a number written in quotes; base ifelse
   used where typed if_else()/case_when() is required for NA safety.
4. Common Pinnacle 21 findings: leading or trailing whitespace on a character
   value; non-ASCII/special characters (curly quotes, em-dashes) in a
   character value{ig_check}

Do NOT flag valid R for not looking like SAS (no run;, no length/label/format,
no semicolons — these are correct in R).

Reply with exactly one line:
PASS
or
FAIL: <short reason>

No other text.
"""


def review_block(code, known_vars, language=None, mode=None, ig_version=None):
    """Return the model's one-line verdict on a code block."""
    verdict = review_code(build_review_prompt(code, known_vars, language=language,
                                              ig_version=ig_version), mode=mode, language=language).strip()
    return verdict
