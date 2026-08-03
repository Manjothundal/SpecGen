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

def _generate_demog_sas(meta, rows, use_macros=True):
    """
    SAS demographics table with full REPORT assembly.

    Strategy: each shell row appends standardized display lines (label + a
    formatted value per treatment arm) into one stacked dataset _results,
    keyed by (ord, roworder, rowlabel, colname, value). The REPORT block then
    transposes colname->columns (one per arm + Total) and renders proc report.

    use_macros: this generator is fully deterministic (no model calls), so
    "using a macro" means literally emitting the company macro CALL in place
    of the equivalent longhand PROC SQL / expression, not an LLM hint like
    SDTM's — the two substitution points (Big-N denominator, n (%) display
    formatting) are always the same regardless of the shell.
    """
    src_ds = str(meta["source_dataset"]).lower()        # adsl
    pop = meta["population"]                             # SAFFL
    colvar = meta["column_var"]                          # TRT01A
    add_total = str(meta.get("add_total_column", "YES")).upper() == "YES"
    prog = []

    prog.append(f"""{BEGIN_SAS.format(var="TABLE_SETUP")}
/* {meta.get('title1','')} */
/* {meta.get('title2','')} */
/* {meta.get('title3','')} */

/* Population: keep only {pop}='Y'. If a Total column is wanted, stack a
   copy of every record under a synthetic arm 'Total' so the same summary
   code produces the Total automatically. */
data _tab;
    set {src_ds};
    where {pop} = "Y";
run;
"""
    + ("""
data _tab;
    set _tab _tab(in=_t);
    length _ARM $40;
    if _t then _ARM = "Total";
    else _ARM = strip(""" + colvar + """);
run;
""" if add_total else """
data _tab;
    set _tab;
    length _ARM $40;
    _ARM = strip(""" + colvar + """);
run;
""")
    + f"""proc sort data=_tab; by _ARM; run;

/* denominator N per arm, for categorical percentages */
{"%tlf_bign(indata=_tab, armvar=_ARM, outdata=_bign);" if use_macros else '''proc sql noprint;
    create table _bign as
    select _ARM, count(distinct USUBJID) as bigN
    from _tab group by _ARM;
quit;'''}
{END_SAS.format(var="TABLE_SETUP")}""")

    ord_n = 0
    for _, r in rows.iterrows():
        ord_n += 1
        var = r["adam_var"]
        label = r["label"]
        stat = r["stat_type"]
        dec = int(r["decimals"])

        if stat == "contn":
            block = f"""/* {label} — continuous, formatted display rows */
proc means data=_tab noprint nway;
    class _ARM;
    var {var};
    output out=_m_{var}(drop=_type_ _freq_)
           n=n mean=mean std=std median=median min=min max=max;
run;

data _r_{var};
    set _m_{var};
    length rowlabel $40 value $20;
    ord = {ord_n};
    grouplabel = "{label}";
    roworder = 1; rowlabel = "n";            value = strip(put(n, 8.));        output;
    roworder = 2; rowlabel = "Mean (SD)";    value = strip(put(mean, 8.{dec})) || " (" || strip(put(std, 8.{dec+1})) || ")"; output;
    roworder = 3; rowlabel = "Median";       value = strip(put(median, 8.{dec})); output;
    roworder = 4; rowlabel = "Min, Max";     value = strip(put(min, 8.{dec})) || ", " || strip(put(max, 8.{dec})); output;
    keep ord grouplabel roworder rowlabel _ARM value;
run;"""
        elif stat == "catn":
            block = f"""/* {label} — categorical n (%) display rows */
proc freq data=_tab noprint;
    tables _ARM*{var} / out=_c_{var}(rename=(count=n));
run;

proc sort data=_c_{var}; by _ARM; run;
data _c_{var};
    merge _c_{var} _bign;
    by _ARM;
    length rowlabel $40 value $20;
    ord = {ord_n};
    grouplabel = "{label}";
    roworder = 100 + rank({var});   /* order categories after group label */
    rowlabel = strip(vvalue({var}));
    {"value = %tlf_pctfmt(n=n, bign=bigN, dec=1);" if use_macros else '''if bigN > 0 then value = strip(put(n, 8.)) || " (" || strip(put(100*n/bigN, 8.1)) || "%)";
    else value = strip(put(n, 8.));'''}
    keep ord grouplabel roworder rowlabel _ARM value;
run;"""
        else:
            block = f"/* {label} — unknown stat_type '{stat}', skipped */\ndata _r_{var}; stop; run;"

        prog.append(f"{BEGIN_SAS.format(var=var)}\n{block}\n{END_SAS.format(var=var)}")

    # Stack all _r_/_c_ results, transpose arms to columns, proc report
    stack_names = []
    for _, r in rows.iterrows():
        var = r["adam_var"]
        stack_names.append(f"_r_{var}" if r["stat_type"] == "contn" else (f"_c_{var}" if r["stat_type"] == "catn" else f"_r_{var}"))
    stack_list = " ".join(stack_names)
    fn1 = meta.get("footnote1", "")
    fn2 = meta.get("footnote2", "")
    t1 = meta.get("title1",""); t2 = meta.get("title2",""); t3 = meta.get("title3","")

    prog.append(f"""{BEGIN_SAS.format(var="REPORT")}
/* Stack every variable's display rows, then transpose _ARM to columns */
data _results;
    set {stack_list};
run;

proc sort data=_results; by ord roworder _ARM; run;

proc transpose data=_results out=_wide(drop=_name_) delimiter=_;
    by ord roworder grouplabel rowlabel;
    id _ARM;
    var value;
run;

proc sort data=_wide; by ord roworder; run;

title1 "{t1}";
title2 "{t2}";
title3 "{t3}";
footnote1 "{fn1}";
footnote2 "{fn2}";

proc report data=_wide nowd;
    columns ord roworder grouplabel rowlabel _all_;
    define ord      / order noprint;
    define roworder / order noprint;
    define grouplabel / order "Characteristic";
    define rowlabel  / display " ";
run;

title; footnote;
{END_SAS.format(var="REPORT")}""")

    return "\n\n".join(prog) + "\n"


# ---------------------------------------------------------------------------
# R demographics table
# ---------------------------------------------------------------------------

def _generate_demog_r(meta, rows):
    """
    R demographics table with full REPORT assembly (parity with SAS).

    Each variable builds a small tibble of display rows (grouplabel, rowlabel,
    ARM, value). A Total arm is added by duplicating rows under ARM="Total".
    REPORT binds them, pivots ARM to columns, and renders with gt.
    """
    src_ds = str(meta["source_dataset"]).lower()
    pop = meta["population"]
    colvar = meta["column_var"]
    add_total = str(meta.get("add_total_column", "YES")).upper() == "YES"
    prog = []
    prog.append("library(dplyr)")
    prog.append("library(tidyr)")
    prog.append("library(gt)")
    prog.append("")

    total_line = (f'  bind_rows(mutate(tab0, ARM = "Total"))' if add_total else "")
    prog.append(f"""{BEGIN_R.format(var="TABLE_SETUP")}
# {meta.get('title1','')} — {meta.get('title2','')}
# Population: keep only {pop} == "Y"; ARM = treatment arm, plus a Total copy.
tab0 <- {src_ds} |>
  filter({pop} == "Y") |>
  mutate(ARM = {colvar})

tab <- tab0{(' |>' + chr(10) + total_line) if add_total else ''}

# denominator N per arm (distinct subjects) for categorical percentages
bigN <- tab |> group_by(ARM) |> summarise(bigN = n_distinct(USUBJID), .groups = "drop")
{END_R.format(var="TABLE_SETUP")}""")

    ord_n = 0
    disp_names = []
    for _, r in rows.iterrows():
        ord_n += 1
        var = r["adam_var"]; label = r["label"]; stat = r["stat_type"]; dec = int(r["decimals"])
        dname = f"d_{var}"; disp_names.append(dname)

        if stat == "contn":
            block = f"""# {label} — continuous display rows
{dname} <- tab |>
  group_by(ARM) |>
  summarise(
    n = sum(!is.na({var})),
    mean = mean({var}, na.rm = TRUE),
    sd = sd({var}, na.rm = TRUE),
    median = median({var}, na.rm = TRUE),
    min = min({var}, na.rm = TRUE),
    max = max({var}, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    `n` = as.character(n),
    `Mean (SD)` = paste0(formatC(mean, format="f", digits={dec}),
                         " (", formatC(sd, format="f", digits={dec+1}), ")"),
    `Median` = formatC(median, format="f", digits={dec}),
    `Min, Max` = paste0(formatC(min, format="f", digits={dec}), ", ",
                        formatC(max, format="f", digits={dec}))
  ) |>
  select(ARM, `n`, `Mean (SD)`, `Median`, `Min, Max`) |>
  pivot_longer(-ARM, names_to = "rowlabel", values_to = "value") |>
  mutate(ord = {ord_n}, grouplabel = "{label}",
         roworder = match(rowlabel, c("n","Mean (SD)","Median","Min, Max")))"""
        elif stat == "catn":
            block = f"""# {label} — categorical n (%) display rows
{dname} <- tab |>
  group_by(ARM, {var}) |>
  summarise(n = n(), .groups = "drop") |>
  left_join(bigN, by = "ARM") |>
  mutate(
    rowlabel = as.character({var}),
    value = ifelse(bigN > 0,
                   paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"),
                   as.character(n)),
    ord = {ord_n}, grouplabel = "{label}",
    roworder = 100 + as.integer(factor({var}))
  ) |>
  select(ARM, rowlabel, value, ord, grouplabel, roworder)"""
        else:
            block = f"# {label} — unknown stat_type '{stat}', skipped\n{dname} <- tibble()"

        prog.append(f"{BEGIN_R.format(var=var)}\n{block}\n{END_R.format(var=var)}")

    bind_list = ", ".join(disp_names)
    fn1 = meta.get("footnote1",""); fn2 = meta.get("footnote2","")
    t1 = meta.get("title1",""); t2 = meta.get("title2",""); t3 = meta.get("title3","")

    prog.append(f"""{BEGIN_R.format(var="REPORT")}
# Bind all display rows, pivot ARM to columns, render with gt
report_long <- bind_rows({bind_list}) |>
  arrange(ord, roworder, ARM)

report_wide <- report_long |>
  pivot_wider(id_cols = c(ord, roworder, grouplabel, rowlabel),
              names_from = ARM, values_from = value) |>
  arrange(ord, roworder) |>
  select(-ord, -roworder)

demog_table <- report_wide |>
  gt(groupname_col = "grouplabel", rowname_col = "rowlabel") |>
  tab_header(title = "{t1}", subtitle = "{t2}") |>
  tab_source_note("{fn1}") |>
  tab_source_note("{fn2}")

demog_table
{END_R.format(var="REPORT")}""")

    return "\n\n".join(prog) + "\n"


# ---------------------------------------------------------------------------
# AE summary table (Table 14.3.x) — counts DISTINCT SUBJECTS per condition.
# Two datasets: numerator from ADAE (TEAE flag + condition), denominator
# (big-N) from ADSL population. One subject counted once per row.
# ---------------------------------------------------------------------------

def _generate_ae_sas(meta, rows, use_macros=True):
    denom = str(meta["denom_dataset"]).lower()      # adsl
    numer = str(meta["numer_dataset"]).lower()      # adae
    pop = meta["population"]                          # SAFFL
    teae = meta["teae_flag"]                          # TRTEMFL
    colvar = meta["column_var"]                       # TRT01A
    add_total = str(meta.get("add_total_column", "YES")).upper() == "YES"
    prog = []

    total_sas = ("""
data _den;
    set _den _den(in=_t);
    if _t then _ARM = "Total"; else _ARM = strip(""" + colvar + """);
run;
data _num;
    set _num _num(in=_t);
    if _t then _ARM = "Total"; else _ARM = strip(""" + colvar + """);
run;""" if add_total else """
data _den; set _den; _ARM = strip(""" + colvar + """); run;
data _num; set _num; _ARM = strip(""" + colvar + """); run;""")

    prog.append(f"""{BEGIN_SAS.format(var="TABLE_SETUP")}
/* {meta.get('title1','')} */
/* {meta.get('title2','')} */
/* {meta.get('title3','')} */

/* Denominator: safety-population subjects (one row per subject) */
data _den;
    set {denom};
    where {pop} = "Y";
    length _ARM $40;
    keep USUBJID {colvar} _ARM;
run;

/* Numerator source: treatment-emergent AEs only */
data _num;
    set {numer};
    where {teae} = "Y";
    length _ARM $40;
run;
{total_sas}

{"%tlf_bign(indata=_den, armvar=_ARM, outdata=_bign);" if use_macros else '''proc sql noprint;
    create table _bign as
    select _ARM, count(distinct USUBJID) as bigN
    from _den group by _ARM;
quit;'''}
{END_SAS.format(var="TABLE_SETUP")}""")

    for _, r in rows.iterrows():
        order = int(r["order"])
        label = r["row_label"]
        cond = str(r["condition"]).strip()
        indent = int(r["indent"]) if not pd.isna(r["indent"]) else 0
        is_heading = (cond == "" or cond.lower() == "nan") and indent == 0 and order == 5  # "by max severity" heading

        # A heading row (no condition, not the baseline) prints label only.
        if (cond == "" or cond.lower() == "nan") and label.lower().startswith("teae by"):
            block = f"""/* {label} — heading row (no count) */
data _ae_{order};
    length grouplabel rowlabel $80 value $20;
    ord = {order}; roworder = 0; indent = {indent};
    rowlabel = "{label}"; _ARM = ""; value = "";
    /* emit one placeholder per arm so the row spans columns */
    stop;
run;"""
        else:
            where_extra = "" if (cond == "" or cond.lower() == "nan") else f" and {cond}"
            block = f"""/* {label} — distinct subjects with TEAE{(' meeting: ' + cond) if where_extra else ''} */
proc sql noprint;
    create table _n_{order} as
    select _ARM, count(distinct USUBJID) as n
    from _num
    where 1{where_extra}
    group by _ARM;
quit;

proc sort data=_n_{order}; by _ARM; run;
data _ae_{order};
    merge _n_{order} _bign;
    by _ARM;
    length grouplabel rowlabel $80 value $20;
    ord = {order}; roworder = 1; indent = {indent};
    rowlabel = "{label}";
    if n = . then n = 0;
    {"value = %tlf_pctfmt(n=n, bign=bigN, dec=1);" if use_macros else '''if bigN > 0 then value = strip(put(n,8.)) || " (" || strip(put(100*n/bigN,8.1)) || "%)";
    else value = strip(put(n,8.));'''}
    keep ord roworder indent rowlabel _ARM value;
run;"""
        prog.append(f"{BEGIN_SAS.format(var='ROW'+str(order))}\n{block}\n{END_SAS.format(var='ROW'+str(order))}")

    stack = " ".join(f"_ae_{int(r['order'])}" for _, r in rows.iterrows())
    t1=meta.get("title1",""); t2=meta.get("title2",""); t3=meta.get("title3","")
    fns = [meta.get(k,"") for k in ("footnote1","footnote2","footnote3") if meta.get(k,"")]
    fn_stmts = "\n".join(f'footnote{i+1} "{f}";' for i,f in enumerate(fns))

    prog.append(f"""{BEGIN_SAS.format(var="REPORT")}
data _results; set {stack}; run;
proc sort data=_results; by ord roworder _ARM; run;

proc transpose data=_results out=_wide(drop=_name_) delimiter=_;
    by ord roworder indent rowlabel;
    id _ARM;
    var value;
run;
proc sort data=_wide; by ord roworder; run;

title1 "{t1}"; title2 "{t2}"; title3 "{t3}";
{fn_stmts}

proc report data=_wide nowd;
    columns ord roworder indent rowlabel _all_;
    define ord / order noprint;
    define roworder / order noprint;
    define indent / display noprint;
    define rowlabel / display "Adverse Event Category";
run;
title; footnote;
{END_SAS.format(var="REPORT")}""")

    return "\n\n".join(prog) + "\n"


def _generate_ae_r(meta, rows):
    denom = str(meta["denom_dataset"]).lower()
    numer = str(meta["numer_dataset"]).lower()
    pop = meta["population"]; teae = meta["teae_flag"]; colvar = meta["column_var"]
    add_total = str(meta.get("add_total_column","YES")).upper() == "YES"
    prog = ["library(dplyr)", "library(tidyr)", "library(gt)", ""]

    prog.append(f"""{BEGIN_R.format(var="TABLE_SETUP")}
# {meta.get('title1','')} — {meta.get('title2','')}
den0 <- {denom} |> filter({pop} == "Y") |> mutate(ARM = {colvar})
num0 <- {numer} |> filter({teae} == "Y") |> mutate(ARM = {colvar})
den <- den0{' |> bind_rows(mutate(den0, ARM = "Total"))' if add_total else ''}
num <- num0{' |> bind_rows(mutate(num0, ARM = "Total"))' if add_total else ''}
bigN <- den |> group_by(ARM) |> summarise(bigN = n_distinct(USUBJID), .groups="drop")
{END_R.format(var="TABLE_SETUP")}""")

    dnames = []
    for _, r in rows.iterrows():
        order = int(r["order"]); label = r["row_label"]
        cond = str(r["condition"]).strip(); indent = int(r["indent"]) if not pd.isna(r["indent"]) else 0
        dn = f"ae_{order}"; dnames.append(dn)
        if (cond == "" or cond.lower()=="nan") and label.lower().startswith("teae by"):
            block = f"""# {label} — heading row
{dn} <- tibble(ARM = character(), rowlabel = character(), value = character(),
              ord = integer(), roworder = integer(), indent = integer())
{dn} <- bind_rows({dn}, tibble(ARM = NA_character_, rowlabel = "{label}",
              value = NA_character_, ord = {order}L, roworder = 0L, indent = {indent}L))"""
        else:
            filt = "" if (cond=="" or cond.lower()=="nan") else f" |> filter({cond.replace('=','==').replace('====','==')})"
            block = f"""# {label} — distinct subjects
{dn} <- num{filt} |>
  group_by(ARM) |>
  summarise(n = n_distinct(USUBJID), .groups = "drop") |>
  right_join(bigN, by = "ARM") |>
  mutate(
    n = ifelse(is.na(n), 0, n),
    rowlabel = "{label}",
    value = ifelse(bigN > 0, paste0(n, " (", formatC(100*n/bigN, format="f", digits=1), "%)"), as.character(n)),
    ord = {order}L, roworder = 1L, indent = {indent}L
  ) |>
  select(ARM, rowlabel, value, ord, roworder, indent)"""
        prog.append(f"{BEGIN_R.format(var='ROW'+str(order))}\n{block}\n{END_R.format(var='ROW'+str(order))}")

    fns = [meta.get(k,"") for k in ("footnote1","footnote2","footnote3") if meta.get(k,"")]
    src_notes = "\n".join(f'  tab_source_note("{f}") |>' for f in fns)
    src_notes = src_notes.rstrip(" |>")
    t1=meta.get("title1",""); t2=meta.get("title2","")

    prog.append(f"""{BEGIN_R.format(var="REPORT")}
report_long <- bind_rows({", ".join(dnames)}) |> arrange(ord, roworder, ARM)
report_wide <- report_long |>
  pivot_wider(id_cols = c(ord, roworder, indent, rowlabel),
              names_from = ARM, values_from = value) |>
  arrange(ord, roworder) |>
  select(-ord, -roworder, -indent, -`NA`)

ae_table <- report_wide |>
  gt(rowname_col = "rowlabel") |>
  tab_header(title = "{t1}", subtitle = "{t2}") |>
{src_notes}

ae_table
{END_R.format(var="REPORT")}""")

    return "\n\n".join(prog) + "\n"


# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

def generate_table(shell_path, language=None, use_macros=True):
    """use_macros: SAS only — there's no R macro catalog (same as ADaM/SDTM),
    so the R builders don't take this param at all; it's a no-op in R mode."""
    language = (language or config.LANGUAGE).lower()
    meta, rows = _read_shell(shell_path)
    # Table type is inferred from the shell: an AE-style shell names a
    # numerator dataset + TEAE flag; a demographics shell does not.
    is_ae = "numer_dataset" in meta and "teae_flag" in meta
    if is_ae:
        return _generate_ae_r(meta, rows) if language == "r" else _generate_ae_sas(meta, rows, use_macros)
    return _generate_demog_r(meta, rows) if language == "r" else _generate_demog_sas(meta, rows, use_macros)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Generate TLF programs (SAS or R).")
    parser.add_argument("--lang", choices=["sas", "r"], default=None)
    parser.add_argument("--shell", default="sample_shell_demographics.xlsx")
    parser.add_argument("--no-macros", action="store_true",
                        help="Don't use the company macro catalog (%%tlf_bign/%%tlf_pctfmt) "
                             "in generated SAS — emit the equivalent longhand code instead "
                             "(default: use the macros). No effect in R mode.")
    args = parser.parse_args()

    lang = (args.lang or config.LANGUAGE).lower()
    ext = "R" if lang == "r" else "sas"
    out_dir = "tlf_programs"
    os.makedirs(out_dir, exist_ok=True)

    meta, _ = _read_shell(args.shell)
    table_id = str(meta.get("table_id", "table")).replace(".", "_")

    code = generate_table(args.shell, language=lang, use_macros=not args.no_macros)
    path = os.path.join(out_dir, f"t_{table_id}.{ext}")
    with open(path, "w", encoding="utf-8") as f:
        f.write(code)
    print(f"Language: {lang}")
    print(f"Wrote {path}")
