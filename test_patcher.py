import os
import sys

# Spec derivation text (often pasted from Word-authored specs) can contain
# Unicode punctuation (em-dashes, curly quotes) that Windows' default console
# codepage (cp1252) can't encode — patch_program's own diff printout would
# otherwise crash with UnicodeEncodeError. Same fix as app.py/sdtm_assembler.py
# apply for the same reason.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from spec_patcher import patch_program

# CI sets these to "mock" (see .github/workflows/tests.yml) so this smoke
# test runs deterministically with no Ollama server and no paid Anthropic
# API call. Unset (None) outside CI — same as before, falls back to
# config.WRITER/REVIEWER.
writer_mode = os.environ.get("SPECGEN_WRITER_MODE")
reviewer_mode = os.environ.get("SPECGEN_REVIEWER_MODE")

with open("adsl.sas", encoding="utf-8", errors="replace") as f:
    original = f.read()

program, diff = patch_program(
    original,
    spec_v1="adam_spec.xlsx",
    spec_v2="adam_spec_v2.xlsx",
    writer_mode=writer_mode,
    reviewer_mode=reviewer_mode,
)

with open("adsl_v2.sas", "w", encoding="utf-8") as f:
    f.write(program)

print("\nSaved adsl_v2.sas")