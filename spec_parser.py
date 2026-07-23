import pandas as pd
from runlog import log_run
from assembler import assemble_adsl
from config import WRITER, REVIEWER
from generator import model_name

# Read the Variables sheet from the spec workbook
spec = pd.read_excel("adam_spec_full.xlsx", sheet_name="Variables")

# Split copies (straight from SDTM) vs derived (need logic)
copies = spec[spec["Origin"] == "Predecessor"]
derived = spec[spec["Origin"] == "Derived"]

# Route derived variables by how they must be built
ex_summary = derived[derived["Source"] == "EX_SUMMARY"]
main_step = derived[derived["Source"].isin(["DM", "DERIVED"])]

print(len(copies), "copies")
print(len(derived), "derived")
print(len(ex_summary), "need EX pre-step")
print(len(main_step), "go in main step")

# Build the full ADSL program
program = assemble_adsl(spec, derived, ex_summary, main_step)

with open("adsl.sas", "w") as f:
    f.write(program)

print("\nSaved adsl.sas")

# Log this run in the runlog.csv file
mode = f"{WRITER}-writer/{REVIEWER}-reviewer"
log_run(
    "adam_spec_full.xlsx",
    mode,
    model_name(WRITER),
    model_name(REVIEWER),
    model_name(REVIEWER),
    len(main_step),
    "adsl.sas",
)