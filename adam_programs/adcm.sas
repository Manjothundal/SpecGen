/*-- BEGIN ADCM_MERGE --*/
proc sort data=cm out=adcm_src; by USUBJID; run;
proc sort data=adsl(keep=USUBJID TRTSDT TRTEDT) out=adcm_adsl; by USUBJID; run;

data adcm_merged;
    merge adcm_src(in=a) adcm_adsl;
    by USUBJID;
    if a;  /* keep only CM records */
run;
/*-- END ADCM_MERGE --*/
/*-- BEGIN ASTDT_AENDT --*/
    /* CM start/end as numeric analysis dates */
    length ASTDT AENDT 8;
    format ASTDT AENDT date9.;
    ASTDT = input(substr(CMSTDTC,1,10), ?? E8601DA.);
    AENDT = input(substr(CMENDTC,1,10), ?? E8601DA.);
/*-- END ASTDT_AENDT --*/
/*-- BEGIN ONTRTFL --*/
    /* On/after first dose */
    length ONTRTFL $1;
    if not missing(ASTDT) and not missing(TRTSDT) and ASTDT >= TRTSDT
        then ONTRTFL = 'Y';
    else call missing(ONTRTFL);
/*-- END ONTRTFL --*/
/*-- BEGIN AOCCFL --*/
proc sort data=adcm_merged;
    by USUBJID CMDECOD ASTDT;
run;

data adcm;
    set adcm_merged;
    by USUBJID CMDECOD;
    length AOCCFL $1;
    /* flag the first record per subject per coded term */
    if first.CMDECOD then AOCCFL = 'Y';
    else call missing(AOCCFL);
run;
/*-- END AOCCFL --*/
