import sys

# Spec derivation text (often pasted from Word-authored specs) can contain
# Unicode punctuation (em-dashes, curly quotes) that Windows' default console
# codepage (cp1252) can't encode — print_diff would otherwise crash with
# UnicodeEncodeError the moment a derivation contains one. Same fix as
# app.py/sdtm_assembler.py apply for the same reason.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from spec_differ import diff_specs, print_diff

diff = diff_specs("adam_spec.xlsx", "adam_spec_v2.xlsx")
print_diff(diff)
