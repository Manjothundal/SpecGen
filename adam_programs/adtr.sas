/*-- BEGIN ADTR_PARAMCD --*/
data adtr_paramcd;
    set tr;
    length PARAMCD $8 PARAM $40;
    if TRTESTCD = "LDIAM" then do; PARAMCD = "LDIAM"; PARAM = "Longest Diameter (mm)"; end;
    if TRTESTCD = "SAXIS" then do; PARAMCD = "SAXIS"; PARAM = "Short Axis Diameter (mm)"; end;
    if TRTESTCD = "SUMDIAM" then do; PARAMCD = "SUMDIAM"; PARAM = "Sum of Diameters (mm)"; end;
    AVAL = TRSTRESN;  /* standardized numeric result */
run;
/*-- END ADTR_PARAMCD --*/
/*-- BEGIN ADTR_BASELINE --*/
proc sort data=adtr_paramcd;
    by USUBJID PARAMCD VISITNUM;
run;

data adtr_base;
    set adtr_paramcd;
    by USUBJID PARAMCD;
    retain BASE;
    if VISIT = "BASELINE" then BASE = AVAL;
    if first.PARAMCD then if VISIT ne "BASELINE" then BASE = .;
    CHG = AVAL - BASE;
    if BASE ne 0 and not missing(BASE) then PCHG = 100 * (CHG / BASE);
    else PCHG = .;
run;
/*-- END ADTR_BASELINE --*/
/*-- BEGIN AWLO_AWHI --*/
data adtr_windows;
    set adtr_base;
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
