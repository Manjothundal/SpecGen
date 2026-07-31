/*-- BEGIN ADTTE_SETUP --*/
proc sort data=adsl(keep=USUBJID TRTSDT) out=adtte_adsl; by USUBJID; run;

data adtte;
    set adtte_adsl;
    length PARAMCD $8 PARAM $40 CNSR 8 AVAL 8 STARTDT ADT 8;
    format STARTDT ADT date9.;
    STARTDT = TRTSDT;

/*-- END ADTTE_SETUP --*/
/*-- BEGIN PFS --*/
    /* --- PFS: progression-free survival --- */
    PARAMCD = "PFS";
    PARAM = "Progression-Free Survival (days)";
    /* TODO: set ADT = earliest of (progression date from ADRS PD),
       (death date from DS/DM); CNSR=0 if event, else ADT = last
       assessment date and CNSR=1 */
    if not missing(ADT) and not missing(STARTDT) then AVAL = ADT - STARTDT + 1;
    output;
/*-- END PFS --*/
/*-- BEGIN OS --*/
    /* --- OS: overall survival --- */
    PARAMCD = "OS";
    PARAM = "Overall Survival (days)";
    /* TODO: set ADT = death date (CNSR=0) or last-known-alive date (CNSR=1) */
    if not missing(ADT) and not missing(STARTDT) then AVAL = ADT - STARTDT + 1;
    output;
run;
/*-- END OS --*/
