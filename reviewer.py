from generator import review_sas

def build_review_prompt(code, known_vars):
    """Ask the model to check generated code against the known variable list."""
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

def review_block(code, known_vars):
    """Return the model's one-line verdict on a code block."""
    verdict = review_sas(build_review_prompt(code, known_vars)).strip()
    return verdict