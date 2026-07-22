from generator import review_sas

def build_improve_prompt(code, row, known_vars):
    """Ask a principal programmer to rewrite a draft block correctly."""
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

def improve_block(code, row, known_vars):
    """Return an improved version of a generated code block."""
    return review_sas(build_improve_prompt(code, row, known_vars)).strip()