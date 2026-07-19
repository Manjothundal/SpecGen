import pandas as pd
# Read the variables sheet from the spec workbook
spec = pd.read_excel("adam_spec.xlsx", sheet_name="Variables")
print(spec.shape)
print(spec[["Variable", "Origin"]])
copies = spec[spec["Origin"] == "Predecessor"]
derived = spec[spec["Origin"] == "Derived"]
print(len(copies), "copies")
print(len(derived), "derived")
print(spec["Origin"].value_counts())
print("\n--- Derived variables ---")

for i, row in derived.iterrows():
    print(row["Variable"], "|", row["Type"], "|", row["Derivation"])

from prompt_builder import build_prompt

test_row = derived.iloc[0]
print("\n--- PROMPT ---")
print(build_prompt(test_row))

from generator import generate_sas

print("\n--- GENERATED SAS ---")
print(generate_sas(build_prompt(test_row)))