import sys

# See test_differ.py/test_patcher.py for why: printed log text can contain
# Unicode punctuation that Windows' default console codepage (cp1252) can't
# encode.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from log_checker import check_log, print_log_check

with open("sample_sas.log", encoding="utf-8", errors="replace") as f:
    log_text = f.read()

findings = check_log(log_text)
print_log_check(findings)
