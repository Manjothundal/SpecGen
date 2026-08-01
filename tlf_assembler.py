"""
tlf_assembler.py — TLF (Tables, Listings, Figures) generator.

Reads a machine-readable mock shell (built by build_sample_shell.py) plus the
ADaM source dataset name, and generates the program that produces the table.

Difference from dataset generators: a table is summary statistics arranged
into a display. For each shell row the generator computes:
  contn (continuous)  -> n, mean, SD, median, min, max
  catn  (categorical) -> n (%) per category
across each treatment column (column_var) plus an optional Total, restricted
to the population flag (e.g. SAFFL).

Dispatches SAS or R on config.LANGUAGE (or --lang), like bds_assembler.py.
Every block wrapped in BEGIN/END markers. Writes to tlf_programs/.

SCOPE: first table type is the demographics summary (contn/catn rows from
ADSL). AE-summary and shift tables are later table types.
"""

import os
import pandas as pd
import config

BEGIN_SAS = "/*-- BEGIN {var} --*/"
END_SAS = "/*-- END {var} --*/"
BEGIN_R = "# -- BEGIN {var} -- #"
END_R = "# -- END {var} -- #"


def _read_shell(shell_path):
    """Load the two shell sheets into (meta dict, rows dataframe)."""
    meta_df = pd.read_excel(shell_path, sheet_name="Shell_Meta")
    meta = dict(zip(meta_df["Field"], meta_df["Value"]))
    rows = pd.read_excel(shell_path, sheet_name="Shell_Rows")
    return meta, rows


# ---------------------------------------------------------------------------
# SAS demographics table
# ---------------------------------------------------------------------------

def _generate_demog_sas(meta, rows):
    src = str(meta["source_dataset"]).lower()          # adsl
    pop = meta["population"]                            # SAFFL
    colvar = meta["column_var"]                         # TRT01A
    prog = []

    # Header comment
    prog.append(f"""{BEGIN_SAS.format(var="TABLE_SETUP")}
/* {meta.get('title1','')} */
/* {meta.get('title2','')} */
/* {meta.get('title3','')} */

/* Population: keep only {pop}='Y' */
data _tab;
    set {src};
    where {pop} = "Y";
run;
{END_SAS.format(var="TABLE_SETUP")}""")

    # One analysis block per shell row
    for _, r in rows.iterrows():
        var = r["adam_var"]
        label = r["label"]
        stat = r["stat_type"]
        dec = int(r["decimals"])

        if stat == "contn":
            block = f"""/* {label} — continuous summary by {colvar} */
proc means data=_tab n mean std median min max maxdec={dec} nway;
    class {colvar};
    var {var};
    output out=_c_{var}(drop=_type_ _freq_)
           n=n mean=mean std=std median=median min=min max=max;
run;"""
        elif stat == "catn":
            block = f"""/* {label} — categorical n (%) by {colvar} */
proc freq data=_tab noprint;
    tables {colvar}*{var} / outpct out=_f_{var};
run;"""
        else:
            block = f"/* {label} — unknown stat_type '{stat}', skipped */"

        prog.append(f"{BEGIN_SAS.format(var=var)}\n{block}\n{END_SAS.format(var=var)}")

    # Report assembly stub (real proc report layout is a later refinement)
    fn1 = meta.get("footnote1", "")
    fn2 = meta.get("footnote2", "")
    prog.append(f"""{BEGIN_SAS.format(var="REPORT")}
/* TODO: stack the per-variable summaries into the final display order,
   transpose to one column per {colvar} (+ Total), and render via proc report.
   Footnotes:
     {fn1}
     {fn2} */
{END_SAS.format(var="REPORT")}""")

    return "\n\n".join(prog) + "\n"


# ---------------------------------------------------------------------------
# R demographics table
# ---------------------------------------------------------------------------

def _generate_demog_r(meta, rows):
    src = str(meta["source_dataset"]).lower()
    pop = meta["population"]
    colvar = meta["column_var"]
    prog = []
    prog.append("library(dplyr)")
    prog.append("library(tidyr)")
    prog.append("")

    prog.append(f"""{BEGIN_R.format(var="TABLE_SETUP")}
# {meta.get('title1','')} — {meta.get('title2','')}
# Population: keep only {pop} == "Y"
tab <- {src} |>
  filter({pop} == "Y")
{END_R.format(var="TABLE_SETUP")}""")

    for _, r in rows.iterrows():
        var = r["adam_var"]
        label = r["label"]
        stat = r["stat_type"]

        if stat == "contn":
            block = f"""# {label} — continuous summary by {colvar}
c_{var} <- tab |>
  group_by({colvar}) |>
  summarise(
    n = sum(!is.na({var})),
    mean = mean({var}, na.rm = TRUE),
    sd = sd({var}, na.rm = TRUE),
    median = median({var}, na.rm = TRUE),
    min = min({var}, na.rm = TRUE),
    max = max({var}, na.rm = TRUE),
    .groups = "drop"
  )"""
        elif stat == "catn":
            block = f"""# {label} — categorical n (%) by {colvar}
f_{var} <- tab |>
  group_by({colvar}, {var}) |>
  summarise(n = n(), .groups = "drop") |>
  group_by({colvar}) |>
  mutate(pct = 100 * n / sum(n)) |>
  ungroup()"""
        else:
            block = f"# {label} — unknown stat_type '{stat}', skipped"

        prog.append(f"{BEGIN_R.format(var=var)}\n{block}\n{END_R.format(var=var)}")

    prog.append(f"""{BEGIN_R.format(var="REPORT")}
# TODO: bind the per-variable summaries in display order, pivot to one column
# per {colvar} (+ Total), render with gt::gt() and the shell footnotes.
{END_R.format(var="REPORT")}""")

    return "\n\n".join(prog) + "\n"


# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

def generate_table(shell_path, language=None):
    language = (language or config.LANGUAGE).lower()
    meta, rows = _read_shell(shell_path)
    if language == "r":
        return _generate_demog_r(meta, rows)
    return _generate_demog_sas(meta, rows)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Generate TLF programs (SAS or R).")
    parser.add_argument("--lang", choices=["sas", "r"], default=None)
    parser.add_argument("--shell", default="sample_shell_demographics.xlsx")
    args = parser.parse_args()

    lang = (args.lang or config.LANGUAGE).lower()
    ext = "R" if lang == "r" else "sas"
    out_dir = "tlf_programs"
    os.makedirs(out_dir, exist_ok=True)

    meta, _ = _read_shell(args.shell)
    table_id = str(meta.get("table_id", "table")).replace(".", "_")

    code = generate_table(args.shell, language=lang)
    path = os.path.join(out_dir, f"t_{table_id}.{ext}")
    with open(path, "w", encoding="utf-8") as f:
        f.write(code)
    print(f"Language: {lang}")
    print(f"Wrote {path}")
