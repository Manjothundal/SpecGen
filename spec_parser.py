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