import sys

# Same fix as test_differ.py/test_patcher.py — see there for why.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from compare_verify import compare_outputs, print_compare_summary, validate_against_shell

print("### Output-to-output: sample_output_a.pdf vs sample_output_b.pdf (one changed cell) ###")
findings = compare_outputs("sample_output_a.pdf", "sample_output_b.pdf", log=False)
print_compare_summary(findings)

print("\n### Output-to-mock-shell: sample_output_a.pdf vs sample_shell_demographics.xlsx ###")
missing = validate_against_shell("sample_output_a.pdf", "sample_shell_demographics.xlsx", log=False)
print(f"\nMissing {len(missing)} item(s) the shell expected but the output didn't contain:")
for m in missing:
    print(f"  - {m['field']}")
