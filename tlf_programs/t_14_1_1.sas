/*-- BEGIN TABLE_SETUP --*/
/* Table 14.1.1 */
/* Summary of Demographic and Baseline Characteristics */
/* Safety Population */

/* Population: keep only SAFFL='Y'. If a Total column is wanted, stack a
   copy of every record under a synthetic arm 'Total' so the same summary
   code produces the Total automatically. */
data _tab;
    set adsl;
    where SAFFL = "Y";
run;

data _tab;
    set _tab _tab(in=_t);
    length _ARM $40;
    if _t then _ARM = "Total";
    else _ARM = strip(TRT01A);
run;
proc sort data=_tab; by _ARM; run;

/* denominator N per arm, for categorical percentages */
proc sql noprint;
    create table _bign as
    select _ARM, count(distinct USUBJID) as bigN
    from _tab group by _ARM;
quit;
/*-- END TABLE_SETUP --*/

/*-- BEGIN AGE --*/
/* Age (years) — continuous, formatted display rows */
proc means data=_tab noprint nway;
    class _ARM;
    var AGE;
    output out=_m_AGE(drop=_type_ _freq_)
           n=n mean=mean std=std median=median min=min max=max;
run;

data _r_AGE;
    set _m_AGE;
    length rowlabel $40 value $20;
    ord = 1;
    grouplabel = "Age (years)";
    roworder = 1; rowlabel = "n";            value = strip(put(n, 8.));        output;
    roworder = 2; rowlabel = "Mean (SD)";    value = strip(put(mean, 8.1)) || " (" || strip(put(std, 8.2)) || ")"; output;
    roworder = 3; rowlabel = "Median";       value = strip(put(median, 8.1)); output;
    roworder = 4; rowlabel = "Min, Max";     value = strip(put(min, 8.1)) || ", " || strip(put(max, 8.1)); output;
    keep ord grouplabel roworder rowlabel _ARM value;
run;
/*-- END AGE --*/

/*-- BEGIN AGEGR1 --*/
/* Age Group, n (%) — categorical n (%) display rows */
proc freq data=_tab noprint;
    tables _ARM*AGEGR1 / out=_c_AGEGR1(rename=(count=n));
run;

proc sort data=_c_AGEGR1; by _ARM; run;
data _c_AGEGR1;
    merge _c_AGEGR1 _bign;
    by _ARM;
    length rowlabel $40 value $20;
    ord = 2;
    grouplabel = "Age Group, n (%)";
    roworder = 100 + rank(AGEGR1);   /* order categories after group label */
    rowlabel = strip(vvalue(AGEGR1));
    if bigN > 0 then value = strip(put(n, 8.)) || " (" || strip(put(100*n/bigN, 8.1)) || "%)";
    else value = strip(put(n, 8.));
    keep ord grouplabel roworder rowlabel _ARM value;
run;
/*-- END AGEGR1 --*/

/*-- BEGIN SEX --*/
/* Sex, n (%) — categorical n (%) display rows */
proc freq data=_tab noprint;
    tables _ARM*SEX / out=_c_SEX(rename=(count=n));
run;

proc sort data=_c_SEX; by _ARM; run;
data _c_SEX;
    merge _c_SEX _bign;
    by _ARM;
    length rowlabel $40 value $20;
    ord = 3;
    grouplabel = "Sex, n (%)";
    roworder = 100 + rank(SEX);   /* order categories after group label */
    rowlabel = strip(vvalue(SEX));
    if bigN > 0 then value = strip(put(n, 8.)) || " (" || strip(put(100*n/bigN, 8.1)) || "%)";
    else value = strip(put(n, 8.));
    keep ord grouplabel roworder rowlabel _ARM value;
run;
/*-- END SEX --*/

/*-- BEGIN RACE --*/
/* Race, n (%) — categorical n (%) display rows */
proc freq data=_tab noprint;
    tables _ARM*RACE / out=_c_RACE(rename=(count=n));
run;

proc sort data=_c_RACE; by _ARM; run;
data _c_RACE;
    merge _c_RACE _bign;
    by _ARM;
    length rowlabel $40 value $20;
    ord = 4;
    grouplabel = "Race, n (%)";
    roworder = 100 + rank(RACE);   /* order categories after group label */
    rowlabel = strip(vvalue(RACE));
    if bigN > 0 then value = strip(put(n, 8.)) || " (" || strip(put(100*n/bigN, 8.1)) || "%)";
    else value = strip(put(n, 8.));
    keep ord grouplabel roworder rowlabel _ARM value;
run;
/*-- END RACE --*/

/*-- BEGIN BMIBL --*/
/* Baseline BMI (kg/m2) — continuous, formatted display rows */
proc means data=_tab noprint nway;
    class _ARM;
    var BMIBL;
    output out=_m_BMIBL(drop=_type_ _freq_)
           n=n mean=mean std=std median=median min=min max=max;
run;

data _r_BMIBL;
    set _m_BMIBL;
    length rowlabel $40 value $20;
    ord = 5;
    grouplabel = "Baseline BMI (kg/m2)";
    roworder = 1; rowlabel = "n";            value = strip(put(n, 8.));        output;
    roworder = 2; rowlabel = "Mean (SD)";    value = strip(put(mean, 8.1)) || " (" || strip(put(std, 8.2)) || ")"; output;
    roworder = 3; rowlabel = "Median";       value = strip(put(median, 8.1)); output;
    roworder = 4; rowlabel = "Min, Max";     value = strip(put(min, 8.1)) || ", " || strip(put(max, 8.1)); output;
    keep ord grouplabel roworder rowlabel _ARM value;
run;
/*-- END BMIBL --*/

/*-- BEGIN REPORT --*/
/* Stack every variable's display rows, then transpose _ARM to columns */
data _results;
    set _r_AGE _c_AGEGR1 _c_SEX _c_RACE _r_BMIBL;
run;

proc sort data=_results; by ord roworder _ARM; run;

proc transpose data=_results out=_wide(drop=_name_) delimiter=_;
    by ord roworder grouplabel rowlabel;
    id _ARM;
    var value;
run;

proc sort data=_wide; by ord roworder; run;

title1 "Table 14.1.1";
title2 "Summary of Demographic and Baseline Characteristics";
title3 "Safety Population";
footnote1 "N = number of subjects in the safety population.";
footnote2 "Percentages are based on N within each treatment group.";

proc report data=_wide nowd;
    columns ord roworder grouplabel rowlabel _all_;
    define ord      / order noprint;
    define roworder / order noprint;
    define grouplabel / order "Characteristic";
    define rowlabel  / display " ";
run;

title; footnote;
/*-- END REPORT --*/
