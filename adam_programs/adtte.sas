/*-- BEGIN ADTTE_SETUP --*/
proc sql noprint;
    create table adtte_prog as
        select USUBJID, min(input(substr(RSDTC,1,10), ?? yymmdd10.)) as PROGDT format=date9.
        from rs
        where RSTESTCD = "OVRLRESP" and upcase(RSORRES) = "PD"
        group by USUBJID;

    create table adtte_lastrs as
        select USUBJID, max(input(substr(RSDTC,1,10), ?? yymmdd10.)) as LASTRSDT format=date9.
        from rs
        where RSTESTCD = "OVRLRESP" and RSORRES is not missing
        group by USUBJID;
quit;

proc sort data=adsl(keep=USUBJID TRTSDT) out=adtte_adsl; by USUBJID; run;
proc sort data=dm(keep=USUBJID DTHFL DTHDTC) out=adtte_dm; by USUBJID; run;

data adtte;
    merge adtte_adsl(in=in_adsl) adtte_dm adtte_prog adtte_lastrs;
    by USUBJID;
    if in_adsl;
    length PARAMCD $8 PARAM $40 CNSR 8 AVAL 8 STARTDT ADT DTHDT 8;
    format STARTDT ADT DTHDT date9.;
    STARTDT = TRTSDT;
    if DTHFL = "Y" and not missing(DTHDTC) then DTHDT = input(substr(DTHDTC,1,10), ?? yymmdd10.);

/*-- END ADTTE_SETUP --*/
/*-- BEGIN PFS --*/
    /* --- PFS: progression-free survival --- */
    PARAMCD = "PFS";
    PARAM = "Progression-Free Survival (days)";
    /* event = earliest of RS-assessed progression or death; else censor at
       the last tumor assessment */
    if not missing(PROGDT) or not missing(DTHDT) then do;
        ADT = min(PROGDT, DTHDT);
        CNSR = 0;
    end;
    else do;
        ADT = LASTRSDT;
        CNSR = 1;
    end;
    if not missing(ADT) and not missing(STARTDT) then AVAL = ADT - STARTDT + 1;
    output;
/*-- END PFS --*/
/*-- BEGIN OS --*/
    /* --- OS: overall survival --- */
    PARAMCD = "OS";
    PARAM = "Overall Survival (days)";
    /* event = death; else censor at the last tumor assessment (proxy for
       last-known-alive) */
    if not missing(DTHDT) then do;
        ADT = DTHDT;
        CNSR = 0;
    end;
    else do;
        ADT = LASTRSDT;
        CNSR = 1;
    end;
    if not missing(ADT) and not missing(STARTDT) then AVAL = ADT - STARTDT + 1;
    output;
run;
/*-- END OS --*/
