/*-- BEGIN TABLE_SETUP --*/
/* Table 14.1.1 */
/* Summary of Demographic and Baseline Characteristics */
/* Safety Population */

/* Population: keep only SAFFL='Y' */
data _tab;
    set adsl;
    where SAFFL = "Y";
run;
/*-- END TABLE_SETUP --*/

/*-- BEGIN AGE --*/
/* Age (years) — continuous summary by TRT01A */
proc means data=_tab n mean std median min max maxdec=1 nway;
    class TRT01A;
    var AGE;
    output out=_c_AGE(drop=_type_ _freq_)
           n=n mean=mean std=std median=median min=min max=max;
run;
/*-- END AGE --*/

/*-- BEGIN AGEGR1 --*/
/* Age Group, n (%) — categorical n (%) by TRT01A */
proc freq data=_tab noprint;
    tables TRT01A*AGEGR1 / outpct out=_f_AGEGR1;
run;
/*-- END AGEGR1 --*/

/*-- BEGIN SEX --*/
/* Sex, n (%) — categorical n (%) by TRT01A */
proc freq data=_tab noprint;
    tables TRT01A*SEX / outpct out=_f_SEX;
run;
/*-- END SEX --*/

/*-- BEGIN RACE --*/
/* Race, n (%) — categorical n (%) by TRT01A */
proc freq data=_tab noprint;
    tables TRT01A*RACE / outpct out=_f_RACE;
run;
/*-- END RACE --*/

/*-- BEGIN BMIBL --*/
/* Baseline BMI (kg/m2) — continuous summary by TRT01A */
proc means data=_tab n mean std median min max maxdec=1 nway;
    class TRT01A;
    var BMIBL;
    output out=_c_BMIBL(drop=_type_ _freq_)
           n=n mean=mean std=std median=median min=min max=max;
run;
/*-- END BMIBL --*/

/*-- BEGIN REPORT --*/
/* TODO: stack the per-variable summaries into the final display order,
   transpose to one column per TRT01A (+ Total), and render via proc report.
   Footnotes:
     N = number of subjects in the safety population.
     Percentages are based on N within each treatment group. */
/*-- END REPORT --*/
