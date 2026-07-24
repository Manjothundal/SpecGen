from macro_lookup import load_catalog, find_macro

catalog = load_catalog()

def build_prompt(row, skip_macro=False):
    """Turn one spec row into an instruction for the AI."""

    format_line = ""
    fmt = str(row["Format"]).strip()
    if fmt and fmt.lower() != "nan":
        format_line = f"Format: {fmt}\n"

    # Check if a validated macro exists for this variable
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
- Assume all needed SDTM variables (from DM, EX, etc.) are already available in the step.
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