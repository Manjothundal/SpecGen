def build_prompt(row):
    """Turn one spec row into an instruction for the AI."""
    prompt = f"""You are a senior clinical SAS programmer.
Write SAS 9.4 code to derive one ADaM variable.

Variable: {row['Variable']}
Label: {row['Label']}
Type: {row['Type']}, Length: {row['Length']}
Derivation rule: {row['Derivation']}

Rules:
- Output ONLY the derivation logic statements (length, label, if/then, assignments).
- Do NOT include data, set, merge, or run statements - the code will be inserted into an existing data step.
- Assume all needed SDTM variables (from DM, EX, etc.) are already available in the step.
- Add a comment above the logic stating the variable name and rule.
- Output plain SAS code only, no explanation, no markdown fences.
"""
    return prompt