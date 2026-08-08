import os
import sys

# Same fix as test_differ.py/test_patcher.py — see there for why.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import pandas as pd

from qc_generator import generate_qc_adsl, generate_compare_harness

# CI sets this to "mock" (see .github/workflows/tests.yml) — see
# test_patcher.py for why. Unset outside CI, falls back to config.WRITER.
mode = os.environ.get("SPECGEN_WRITER_MODE")

spec = pd.read_excel("adam_spec.xlsx", sheet_name="Variables")

qc_program = generate_qc_adsl(spec, language="sas", mode=mode)
with open("adsl_qc.sas", "w", encoding="utf-8") as f:
    f.write(qc_program)
print("Saved adsl_qc.sas")

compare_program = generate_compare_harness(spec, language="sas")
with open("adsl_compare.sas", "w", encoding="utf-8") as f:
    f.write(compare_program)
print("Saved adsl_compare.sas")
