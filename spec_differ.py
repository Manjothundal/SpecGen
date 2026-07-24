import pandas as pd

def load_spec(path):
    """Load Variables sheet from a spec workbook."""
    return pd.read_excel(path, sheet_name="Variables").set_index("Variable")

def diff_specs(path_v1, path_v2):
    """Compare two spec versions. Returns a dict of change lists."""
    v1 = load_spec(path_v1)
    v2 = load_spec(path_v2)

    v1_vars = set(v1.index)
    v2_vars = set(v2.index)

    new_vars     = sorted(v2_vars - v1_vars)
    deleted_vars = sorted(v1_vars - v2_vars)
    common_vars  = v1_vars & v2_vars

    changed_vars = []
    unchanged_vars = []

    for var in sorted(common_vars):
        v1_deriv = str(v1.loc[var, "Derivation"]).strip()
        v2_deriv = str(v2.loc[var, "Derivation"]).strip()
        if v1_deriv != v2_deriv:
            changed_vars.append({
                "variable": var,
                "old_derivation": v1_deriv,
                "new_derivation": v2_deriv,
            })
        else:
            unchanged_vars.append(var)

    return {
        "new":       new_vars,
        "changed":   changed_vars,
        "deleted":   deleted_vars,
        "unchanged": unchanged_vars,
    }

def print_diff(diff):
    """Print a human-readable diff summary."""
    print(f"\n{'='*50}")
    print(f"SPEC DIFF SUMMARY")
    print(f"{'='*50}")
    print(f"New variables    : {len(diff['new'])}")
    print(f"Changed          : {len(diff['changed'])}")
    print(f"Deleted          : {len(diff['deleted'])}")
    print(f"Unchanged        : {len(diff['unchanged'])}")
    if diff['new']:
        print(f"\nNEW: {', '.join(diff['new'])}")
    if diff['changed']:
        print(f"\nCHANGED:")
        for c in diff['changed']:
            print(f"  {c['variable']}")
            print(f"    WAS: {c['old_derivation'][:80]}")
            print(f"    NOW: {c['new_derivation'][:80]}")
    if diff['deleted']:
        print(f"\nDELETED: {', '.join(diff['deleted'])}")