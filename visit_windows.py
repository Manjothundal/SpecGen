"""
visit_windows.py — derive AWLO/AWHI analysis visit windows from protocol TV.

The protocol_metadata.xlsx TV sheet's WINDOW column is noisy (offline-regex
artifacts like "15 12 to 18" or "/ EOT 365 362 to 368"). This module pulls
only the clean "<low> to <high>" pattern out of each WINDOW value and skips
rows where it can't. Junk visit rows (parsing noise) get no window and are
simply left out of the lookup.

Output: a SAS format/lookup that maps VISITNUM -> AWLO, AWHI, so an ADVS
step can merge them in for the ANL01FL window check.
"""

import re
import pandas as pd

WINDOW_RE = re.compile(r"(-?\d+)\s+to\s+(-?\d+)")


def build_visit_windows(protocol_path="protocol_metadata.xlsx"):
    """Return list of dicts: {visitnum, awlo, awhi} for rows with a clean window."""
    tv = pd.read_excel(protocol_path, sheet_name="TV")
    windows = []
    for _, row in tv.iterrows():
        m = WINDOW_RE.search(str(row["WINDOW"]))
        if not m:
            continue  # skip noisy/junk rows
        try:
            visitnum = int(row["VISITNUM"])
        except (ValueError, TypeError):
            continue
        awlo, awhi = int(m.group(1)), int(m.group(2))
        if awlo > awhi:
            continue  # guard against mis-parsed pairs
        windows.append({"visitnum": visitnum, "awlo": awlo, "awhi": awhi})
    return windows


def generate_awlo_awhi_sas(windows):
    """Emit a SAS step that assigns AWLO/AWHI per VISITNUM via select/when."""
    when_lines = "\n".join(
        f'        when ({w["visitnum"]}) do; AWLO = {w["awlo"]}; AWHI = {w["awhi"]}; end;'
        for w in windows
    )
    code = f"""data advs_windows;
    set advs_base;
    length AWLO AWHI 8;
    select (VISITNUM);
{when_lines}
        otherwise do; call missing(AWLO, AWHI); end;
    end;
run;"""
    return code


if __name__ == "__main__":
    w = build_visit_windows()
    print(f"Parsed {len(w)} clean visit windows:")
    for row in w:
        print(f"  VISITNUM {row['visitnum']}: {row['awlo']} to {row['awhi']}")
    print("\n=== SAS ===")
    print(generate_awlo_awhi_sas(w))
