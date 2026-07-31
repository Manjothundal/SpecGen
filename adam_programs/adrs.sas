/*-- BEGIN ADRS_PARAMCD --*/
data adrs_ovr;
    set rs;
    where RSTESTCD = "OVRLRESP";
    length PARAMCD $8 PARAM $40 AVALC $20;
    PARAMCD = "OVRLRESP";
    PARAM = "Overall Response";
    AVALC = strip(RSORRES);
    /* response ranking: lower = better (CR best) */
    select (upcase(AVALC));
        when ("CR") AVAL = 1;
        when ("PR") AVAL = 2;
        when ("SD") AVAL = 3;
        when ("PD") AVAL = 4;
        when ("NE") AVAL = 5;
        otherwise AVAL = .;
    end;
run;
/*-- END ADRS_PARAMCD --*/
/*-- BEGIN ANL01FL_BOR --*/
proc sort data=adrs_ovr;
    by USUBJID AVAL;
run;

data adrs;
    set adrs_ovr;
    by USUBJID;
    length ANL01FL $1;
    /* flag the best (lowest-rank) response record per subject */
    if first.USUBJID then ANL01FL = 'Y';
    else call missing(ANL01FL);
run;
/*-- END ANL01FL_BOR --*/
