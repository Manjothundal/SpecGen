import os

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