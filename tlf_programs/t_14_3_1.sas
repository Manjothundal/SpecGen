/*-- BEGIN TABLE_SETUP --*/
/* Table 14.3.1 */
/* Overall Summary of Treatment-Emergent Adverse Events */
/* Safety Population */

/* Denominator: safety-population subjects (one row per subject) */
data _den;
    set adsl;
    where SAFFL = "Y";
    length _ARM $40;
    keep USUBJID TRT01A _ARM;
run;

/* Numerator source: treatment-emergent AEs only */
data _num;
    set adae;
    where TRTEMFL = "Y";
    length _ARM $40;
run;

data _den;
    set _den _den(in=_t);
    if _t then _ARM = "Total"; else _ARM = strip(TRT01A);
run;
data _num;
    set _num _num(in=_t);
    if _t then _ARM = "Total"; else _ARM = strip(TRT01A);
run;

proc sql noprint;
    create table _bign as
    select _ARM, count(distinct USUBJID) as bigN
    from _den group by _ARM;
quit;
/*-- END TABLE_SETUP --*/

/*-- BEGIN ROW1 --*/
/* Subjects with any TEAE — distinct subjects with TEAE */
proc sql noprint;
    create table _n_1 as
    select _ARM, count(distinct USUBJID) as n
    from _num
    where 1
    group by _ARM;
quit;

proc sort data=_n_1; by _ARM; run;
data _ae_1;
    merge _n_1 _bign;
    by _ARM;
    length grouplabel rowlabel $80 value $20;
    ord = 1; roworder = 1; indent = 0;
    rowlabel = "Subjects with any TEAE";
    if n = . then n = 0;
    if bigN > 0 then value = strip(put(n,8.)) || " (" || strip(put(100*n/bigN,8.1)) || "%)";
    else value = strip(put(n,8.));
    keep ord roworder indent rowlabel _ARM value;
run;
/*-- END ROW1 --*/

/*-- BEGIN ROW2 --*/
/* Subjects with any serious TEAE — distinct subjects with TEAE meeting: AESER = "Y" */
proc sql noprint;
    create table _n_2 as
    select _ARM, count(distinct USUBJID) as n
    from _num
    where 1 and AESER = "Y"
    group by _ARM;
quit;

proc sort data=_n_2; by _ARM; run;
data _ae_2;
    merge _n_2 _bign;
    by _ARM;
    length grouplabel rowlabel $80 value $20;
    ord = 2; roworder = 1; indent = 0;
    rowlabel = "Subjects with any serious TEAE";
    if n = . then n = 0;
    if bigN > 0 then value = strip(put(n,8.)) || " (" || strip(put(100*n/bigN,8.1)) || "%)";
    else value = strip(put(n,8.));
    keep ord roworder indent rowlabel _ARM value;
run;
/*-- END ROW2 --*/

/*-- BEGIN ROW3 --*/
/* Subjects with any drug-related TEAE — distinct subjects with TEAE meeting: AEREL = "Y" */
proc sql noprint;
    create table _n_3 as
    select _ARM, count(distinct USUBJID) as n
    from _num
    where 1 and AEREL = "Y"
    group by _ARM;
quit;

proc sort data=_n_3; by _ARM; run;
data _ae_3;
    merge _n_3 _bign;
    by _ARM;
    length grouplabel rowlabel $80 value $20;
    ord = 3; roworder = 1; indent = 0;
    rowlabel = "Subjects with any drug-related TEAE";
    if n = . then n = 0;
    if bigN > 0 then value = strip(put(n,8.)) || " (" || strip(put(100*n/bigN,8.1)) || "%)";
    else value = strip(put(n,8.));
    keep ord roworder indent rowlabel _ARM value;
run;
/*-- END ROW3 --*/

/*-- BEGIN ROW4 --*/
/* Subjects with any TEAE leading to discontinuation — distinct subjects with TEAE meeting: AEACN = "DRUG WITHDRAWN" */
proc sql noprint;
    create table _n_4 as
    select _ARM, count(distinct USUBJID) as n
    from _num
    where 1 and AEACN = "DRUG WITHDRAWN"
    group by _ARM;
quit;

proc sort data=_n_4; by _ARM; run;
data _ae_4;
    merge _n_4 _bign;
    by _ARM;
    length grouplabel rowlabel $80 value $20;
    ord = 4; roworder = 1; indent = 0;
    rowlabel = "Subjects with any TEAE leading to discontinuation";
    if n = . then n = 0;
    if bigN > 0 then value = strip(put(n,8.)) || " (" || strip(put(100*n/bigN,8.1)) || "%)";
    else value = strip(put(n,8.));
    keep ord roworder indent rowlabel _ARM value;
run;
/*-- END ROW4 --*/

/*-- BEGIN ROW5 --*/
/* TEAE by maximum severity — heading row (no count) */
data _ae_5;
    length grouplabel rowlabel $80 value $20;
    ord = 5; roworder = 0; indent = 0;
    rowlabel = "TEAE by maximum severity"; _ARM = ""; value = "";
    /* emit one placeholder per arm so the row spans columns */
    stop;
run;
/*-- END ROW5 --*/

/*-- BEGIN ROW6 --*/
/* Mild — distinct subjects with TEAE meeting: AESEV = "MILD" */
proc sql noprint;
    create table _n_6 as
    select _ARM, count(distinct USUBJID) as n
    from _num
    where 1 and AESEV = "MILD"
    group by _ARM;
quit;

proc sort data=_n_6; by _ARM; run;
data _ae_6;
    merge _n_6 _bign;
    by _ARM;
    length grouplabel rowlabel $80 value $20;
    ord = 6; roworder = 1; indent = 1;
    rowlabel = "Mild";
    if n = . then n = 0;
    if bigN > 0 then value = strip(put(n,8.)) || " (" || strip(put(100*n/bigN,8.1)) || "%)";
    else value = strip(put(n,8.));
    keep ord roworder indent rowlabel _ARM value;
run;
/*-- END ROW6 --*/

/*-- BEGIN ROW7 --*/
/* Moderate — distinct subjects with TEAE meeting: AESEV = "MODERATE" */
proc sql noprint;
    create table _n_7 as
    select _ARM, count(distinct USUBJID) as n
    from _num
    where 1 and AESEV = "MODERATE"
    group by _ARM;
quit;

proc sort data=_n_7; by _ARM; run;
data _ae_7;
    merge _n_7 _bign;
    by _ARM;
    length grouplabel rowlabel $80 value $20;
    ord = 7; roworder = 1; indent = 1;
    rowlabel = "Moderate";
    if n = . then n = 0;
    if bigN > 0 then value = strip(put(n,8.)) || " (" || strip(put(100*n/bigN,8.1)) || "%)";
    else value = strip(put(n,8.));
    keep ord roworder indent rowlabel _ARM value;
run;
/*-- END ROW7 --*/

/*-- BEGIN ROW8 --*/
/* Severe — distinct subjects with TEAE meeting: AESEV = "SEVERE" */
proc sql noprint;
    create table _n_8 as
    select _ARM, count(distinct USUBJID) as n
    from _num
    where 1 and AESEV = "SEVERE"
    group by _ARM;
quit;

proc sort data=_n_8; by _ARM; run;
data _ae_8;
    merge _n_8 _bign;
    by _ARM;
    length grouplabel rowlabel $80 value $20;
    ord = 8; roworder = 1; indent = 1;
    rowlabel = "Severe";
    if n = . then n = 0;
    if bigN > 0 then value = strip(put(n,8.)) || " (" || strip(put(100*n/bigN,8.1)) || "%)";
    else value = strip(put(n,8.));
    keep ord roworder indent rowlabel _ARM value;
run;
/*-- END ROW8 --*/

/*-- BEGIN REPORT --*/
data _results; set _ae_1 _ae_2 _ae_3 _ae_4 _ae_5 _ae_6 _ae_7 _ae_8; run;
proc sort data=_results; by ord roworder _ARM; run;

proc transpose data=_results out=_wide(drop=_name_) delimiter=_;
    by ord roworder indent rowlabel;
    id _ARM;
    var value;
run;
proc sort data=_wide; by ord roworder; run;

title1 "Table 14.3.1"; title2 "Overall Summary of Treatment-Emergent Adverse Events"; title3 "Safety Population";
footnote1 "TEAE = treatment-emergent adverse event.";
footnote2 "A subject is counted once within each row, regardless of the number of events.";
footnote3 "Percentages use the number of safety-population subjects per arm as denominator.";

proc report data=_wide nowd;
    columns ord roworder indent rowlabel _all_;
    define ord / order noprint;
    define roworder / order noprint;
    define indent / display noprint;
    define rowlabel / display "Adverse Event Category";
run;
title; footnote;
/*-- END REPORT --*/
