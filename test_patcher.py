from spec_patcher import patch_program

with open("adsl.sas", encoding="utf-8", errors="replace") as f:
    original = f.read()

program, diff = patch_program(
    original,
    spec_v1="adam_spec.xlsx",
    spec_v2="adam_spec_v2.xlsx"
)

with open("adsl_v2.sas", "w", encoding="utf-8") as f:
    f.write(program)

print("\nSaved adsl_v2.sas")