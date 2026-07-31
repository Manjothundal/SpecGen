/*-- BEGIN ADEG_PARAMCD --*/
data adeg_paramcd;
    set eg;
    length PARAMCD $8 PARAM $40;
    if EGTESTCD = "HR" then do; PARAMCD = "HR"; PARAM = "Heart Rate (bpm)"; end;
    if EGTESTCD = "PRINTR" then do; PARAMCD = "PRINTR"; PARAM = "PR Interval (msec)"; end;
    if EGTESTCD = "QRSDUR" then do; PARAMCD = "QRSDUR"; PARAM = "QRS Duration (msec)"; end;
    if EGTESTCD = "QTINT" then do; PARAMCD = "QTINT"; PARAM = "QT Interval (msec)"; end;
    if EGTESTCD = "QTCF" then do; PARAMCD = "QTCF"; PARAM = "QTcF (msec)"; end;
    AVAL = EGSTRESN;  /* standardized numeric result */
run;
/*-- END ADEG_PARAMCD --*/
/*-- BEGIN ADEG_BASELINE --*/
proc sort data=adeg_paramcd;
    by USUBJID PARAMCD VISITNUM;
run;

data adeg_base;
    set adeg_paramcd;
    by USUBJID PARAMCD;
    retain BASE;
    if VISIT = "BASELINE" then BASE = AVAL;
    if first.PARAMCD then if VISIT ne "BASELINE" then BASE = .;
    CHG = AVAL - BASE;
    if BASE ne 0 and not missing(BASE) then PCHG = 100 * (CHG / BASE);
    else PCHG = .;
run;
/*-- END ADEG_BASELINE --*/
/*-- BEGIN AWLO_AWHI --*/
data adeg_windows;
    set adeg_base;
    length AWLO AWHI 8;
    select (VISITNUM);
        when (1) do; AWLO = -28; AWHI = -1; end;
        when (2) do; AWLO = -14; AWHI = -1; end;
        when (4) do; AWLO = 12; AWHI = 18; end;
        when (5) do; AWLO = 26; AWHI = 32; end;
        when (6) do; AWLO = 54; AWHI = 60; end;
        when (7) do; AWLO = 82; AWHI = 88; end;
        when (8) do; AWLO = 110; AWHI = 116; end;
        when (9) do; AWLO = 166; AWHI = 172; end;
        when (10) do; AWLO = 250; AWHI = 256; end;
        when (11) do; AWLO = 362; AWHI = 368; end;
        when (12) do; AWLO = 370; AWHI = 375; end;
        when (13) do; AWLO = 377; AWHI = 382; end;
        when (14) do; AWLO = 390; AWHI = 400; end;
        otherwise do; call missing(AWLO, AWHI); end;
    end;
run;
/*-- END AWLO_AWHI --*/
/*-- BEGIN ANL01FL --*/
    /* Analysis flag: within visit window and non-missing AVAL */
    length ANL01FL $1;
    label ANL01FL = "Analysis Flag 01";
    if not missing(AVAL) and AWLO <= VISITNUM <= AWHI then ANL01FL = 'Y';
    else call missing(ANL01FL);
/*-- END ANL01FL --*/
