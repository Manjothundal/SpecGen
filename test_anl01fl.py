from prompt_builder import build_prompt, ANL01FL_ROW
from generator import generate_api  # use whatever your API generate function is named

prompt = build_prompt(
    ANL01FL_ROW,
    skip_macro=True,
    context_vars="PARAMCD, PARAM, AVAL, BASE, CHG, PCHG, VISIT, VISITNUM, USUBJID (from the ADVS reshape step)"
)

print("=== PROMPT ===")
print(prompt)
print("\n=== SAS OUTPUT ===")
print(generate_api(prompt))