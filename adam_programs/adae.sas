/*-- BEGIN ADAE_MERGE --*/
proc sort data=ae out=adae_src; by USUBJID; run;
proc sort data=adsl(keep=USUBJID TRTSDT TRTEDT) out=adae_adsl; by USUBJID; run;

data adae_merged;
    merge adae_src(in=a) adae_adsl;
    by USUBJID;
    if a;  /* keep only AE records */
run;
/*-- END ADAE_MERGE --*/
/*-- BEGIN ASTDT_AENDT --*/
    /* AE start/end as numeric analysis dates */
    length ASTDT AENDT 8;
    format ASTDT AENDT date9.;
    ASTDT = input(substr(AESTDTC,1,10), ?? E8601DA.);
    AENDT = input(substr(AEENDTC,1,10), ?? E8601DA.);
/*-- END ASTDT_AENDT --*/
/*-- BEGIN TRTEMFL --*/
    /* On/after first dose */
    length TRTEMFL $1;
    if not missing(ASTDT) and not missing(TRTSDT) and ASTDT >= TRTSDT
        then TRTEMFL = 'Y';
    else call missing(TRTEMFL);
/*-- END TRTEMFL --*/
/*-- BEGIN AOCCFL --*/
proc sort data=adae_merged;
    by USUBJID AEDECOD ASTDT;
run;

data adae;
    set adae_merged;
    by USUBJID AEDECOD;
    length AOCCFL $1;
    /* flag the first record per subject per coded term */
    if first.AEDECOD then AOCCFL = 'Y';
    else call missing(AOCCFL);
run;
/*-- END AOCCFL --*/
