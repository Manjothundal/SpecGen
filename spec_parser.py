import argparse
import pandas as pd
from runlog import log_run
from assembler import assemble_adsl
from config import WRITER, REVIEWER, LANGUAGE
from generator import model_name

parser = argparse.ArgumentParser(description="Generate the ADSL program (SAS or R).")
parser.add_argument("--lang", choices=["sas", "r"], default=None,
                    help="Output language. Overrides config.LANGUAGE. Omit to use config.LANGUAGE.")
args = parser.parse_args()

lang = (args.lang or LANGUAGE).lower()
ext = "R" if lang == "r" else "sas"
output_file = f"adsl.{ext}"

# Read the Variables sheet from the spec workbook
spec = pd.read_excel("adam_spec_full.xlsx", sheet_name="Variables")

# Split copies (straight from SDTM) vs derived (need logic)
copies = spec[spec["Origin"] == "Predecessor"]
derived = spec[spec["Origin"] == "Derived"]

# Route derived variables by how they must be built
ex_summary = derived[derived["Source"] == "EX_SUMMARY"]
main_step = derived[derived["Source"].isin(["DM", "DERIVED"])]

print("Language:", lang)
print(len(copies), "copies")
print(len(derived), "derived")
print(len(ex_summary), "need EX pre-step")
print(len(main_step), "go in main step")

# Build the full ADSL program
program = assemble_adsl(spec, derived, ex_summary, main_step, language=lang)

with open(output_file, "w") as f:
    f.write(program)

print(f"\nSaved {output_file}")

# Log this run in the runlog.csv file
mode = f"{WRITER}-writer/{REVIEWER}-reviewer/{lang}"
log_run(
    "adam_spec_full.xlsx",
    mode,
    model_name(WRITER),
    model_name(REVIEWER),
    model_name(REVIEWER),
    len(main_step),
    output_file,
)