from generator import review_code
import config


def build_review_prompt(code, known_vars, language=None):
    """Ask the model to check generated code against the known variable list.

    language: "sas" or "r" (defaults to config.LANGUAGE). Selects the QC
        persona and the language-specific checks. Check #1 (hallucinated
        variables) is shared; checks #2/#3 differ because "what would fail"
        is language-specific — a SAS data-step violation is not an R concept,
        and vice versa.
    """
    language = (language or config.LANGUAGE).lower()

    if language == "sas":
        return _build_sas_review_prompt(code, known_vars)
    elif language == "r":
        return _build_r_review_prompt(code, known_vars)
    else:
        raise ValueError(f"Unknown language: {language!r} (expected 'sas' or 'r')")


# ---------------------------------------------------------------------------
# SAS review prompt — unchanged from the original
# ---------------------------------------------------------------------------

def _build_sas_review_prompt(code, known_vars):
    return f"""You are a senior clinical SAS programmer performing QC.

Review this generated SAS code block:

{code}

Variables available in this data step:
{", ".join(known_vars)}

Check ONLY for these issues:
1. References to variables NOT in the available list (hallucinated variables)
2. Statements that would fail in a data step (data/set/merge/run statements)
3. Character values assigned to numeric variables or vice versa

Reply with exactly one line:
PASS
or
FAIL: <short reason>

No other text.
"""


# ---------------------------------------------------------------------------
# R review prompt — parallel checks for plain tidyverse (dplyr)
# ---------------------------------------------------------------------------

def _build_r_review_prompt(code, known_vars):
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

Do NOT flag valid R for not looking like SAS (no run;, no length/label/format,
no semicolons — these are correct in R).

Reply with exactly one line:
PASS
or
FAIL: <short reason>

No other text.
"""


def review_block(code, known_vars, language=None, mode=None):
    """Return the model's one-line verdict on a code block."""
    verdict = review_code(build_review_prompt(code, known_vars, language=language), mode=mode).strip()
    return verdict
