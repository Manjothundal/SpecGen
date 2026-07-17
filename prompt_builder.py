def build_prompt(row):
    """Turn one spec row into an instruction for the AI."""
    prompt = f"""You are a senior clinical SAS programmer.
Write SAS 9.4 code to derive one ADaM variable.

Variable: {row['Variable']}
Label: {row['Label']}
Type: {row['Type']}, Length: {row['Length']}
Derivation rule: {row['Derivation']}

Rules:
- Assume input SDTM datasets (DM, EX, etc.) are already available in WORK.
- Output ONLY the SAS code, no explanation.
- Add a comment above the code stating the variable name and rule.
"""
    return prompt