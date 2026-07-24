from spec_differ import diff_specs, print_diff

diff = diff_specs("adam_spec.xlsx", "adam_spec_v2.xlsx")
print_diff(diff)