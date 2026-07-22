def build_prompt(row):
    """Turn one spec row into an instruction for the AI."""
    prompt = f"""You are a senior clinical SAS programmer.
Write SAS 9.4 code to derive one ADaM variable.

Variable: {row['Variable']}
Label: {row['Label']}
Type: {row['Type']}, Length: {row['Length']}
Format: {row['Format']}
Derivation rule: {row['Derivation']}

Rules:
- Output ONLY the derivation logic statements (length, label, format, if/then, assignments).
- Do NOT include data, set, merge, or run statements - the code will be inserted into an existing data step.
- Assume all needed SDTM variables (from DM, EX, etc.) are already available in the step.
- If Format is not 'nan', apply it with a format statement.
- Add a comment above the logic stating the variable name and rule.
- Output plain SAS code only, no explanation, no markdown fences.
- SUPPDM qualifiers are already transposed into columns named after each QNAM (e.g. COMPLT). Reference those column names directly; NEVER reference QNAM or QVAL.

Style rules:
- Use select/when instead of if/else chains with 3 or more branches.
- Write concise, professional code as a senior programmer would.
- Use ONLY variables named in the derivation rule or standard SDTM variables from DM or EX. NEVER invent helper variables or flags that are not defined in this step.
"""
    return prompt