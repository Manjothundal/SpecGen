/*******************************************************************************
* Program:    ex.sas
* Domain:     EX (Interventions)
* Purpose:    Create SDTM EX domain dataset
* Variables:  16
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.ex (source CRF data)
* Output:     sdtm.ex (EX domain dataset)
*
* Variables:  STUDYID, EXSEQ, USUBJID, DOMAIN, EXTRT, EXDECOD, EXCAT, EXDOSE
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*=============================================================================
  PROGRAM:      SDTM_EX.sas
  DESCRIPTION:  Create SDTM EX (Exposure) Domain
  DOMAIN:       EX (Interventions Class)
=============================================================================*/

/*-- BEGIN EX --*/

/*-----------------------------------------------------------------------------
  Step 1: Read DM domain for subject-level information
-----------------------------------------------------------------------------*/
proc sort data=sdtm.dm(keep=studyid usubjid rfstdtc) out=dm nodupkey;
    by studyid usubjid;
run;

/*-----------------------------------------------------------------------------
  Step 2: Read source EX data and merge with DM
-----------------------------------------------------------------------------*/
data ex_raw;
    merge raw.ex(in=a)
          dm(in=b);
    by studyid usubjid;
    
    if a;
    
    /* Ensure required variables exist */
    if missing(usubjid) then delete;
run;

/*-----------------------------------------------------------------------------
  Step 3: Create EX domain with derivations
-----------------------------------------------------------------------------*/
data ex_1;
    set ex_raw;
    
    /* Set domain constant */
    length STUDYID $20 DOMAIN $2 USUBJID $40;
    DOMAIN = 'EX';
    
    /* Map treatment variables */
    length EXTRT $200 EXDECOD $200;
    EXTRT = strip(EXTRT);
    
    /* Derive standardized treatment name */
    if not missing(EXTRT) then EXDECOD = strip(upcase(EXTRT));
    else EXDECOD = '';
    
    /* Map category */
    length EXCAT $200;
    EXCAT = strip(EXCAT);
    
    /* Map dose and units */
    length EXDOSU $200;
    if not missing(EXDOSE) then EXDOSE = EXDOSE;
    EXDOSU = strip(EXDOSU);
    
    /* Map dosing frequency */
    length EXDOSFRQ $200;
    EXDOSFRQ = strip(EXDOSFRQ);
    
    /* Map route of administration */
    length EXROUTE $200;
    EXROUTE = strip(EXROUTE);
    
    /* Format start and end dates to ISO 8601 */
    length EXSTDTC EXENDTC $20;
    
    /* Convert dates to ISO 8601 format if needed */
    if not missing(EXSTDTC) then do;
        _exstdtc_temp = strip(EXSTDTC);
        if length(_exstdtc_temp) <= 11 and verify(_exstdtc_temp, '0123456789/-:T ') = 0 then do;
            _exstdt_num = input(_exstdtc_temp, ?? yymmdd10.);
            if not missing(_exstdt_num) then EXSTDTC = put(_exstdt_num, is8601da.);
            else EXSTDTC = strip(EXSTDTC);
        end;
        else EXSTDTC = strip(EXSTDTC);
    end;
    
    if not missing(EXENDTC) then do;
        _exendtc_temp = strip(EXENDTC);
        if length(_exendtc_temp) <= 11 and verify(_exendtc_temp, '0123456789/-:T ') = 0 then do;
            _exendt_num = input(_exendtc_temp, ?? yymmdd10.);
            if not missing(_exendt_num) then EXENDTC = put(_exendt_num, is8601da.);
            else EXENDTC = strip(EXENDTC);
        end;
        else EXENDTC = strip(EXENDTC);
    end;
    
    /* Derive study day variables */
    if not missing(RFSTDTC) and not missing(EXSTDTC) and length(strip(EXSTDTC)) >= 10 then do;
        _rfstdt = input(substr(strip(RFSTDTC), 1, 10), ?? yymmdd10.);
        _exstdt = input(substr(strip(EXSTDTC), 1, 10), ?? yymmdd10.);
        
        if not missing(_rfstdt) and not missing(_exstdt) then do;
            if _exstdt >= _rfstdt then EXSTDY = _exstdt - _rfstdt + 1;
            else EXSTDY = _exstdt - _rfstdt;
        end;
    end;
    
    if not missing(RFSTDTC) and not missing(EXENDTC) and length(strip(EXENDTC)) >= 10 then do;
        _rfstdt = input(substr(strip(RFSTDTC), 1, 10), ?? yymmdd10.);
        _exendt = input(substr(strip(EXENDTC), 1, 10), ?? yymmdd10.);
        
        if not missing(_rfstdt) and not missing(_exendt) then do;
            if _exendt >= _rfstdt then EXENDY = _exendt - _rfstdt + 1;
            else EXENDY = _exendt - _rfstdt;
        end;
    end;
    
    /* Derive EPOCH based on study day */
    length EPOCH $20;
    if not missing(EXSTDY) then do;
        if EXSTDY < 1 then EPOCH = 'SCREENING';
        else if EXSTDY >= 1 then EPOCH = 'TREATMENT';
    end;
    else if not missing(EXSTDTC) then EPOCH = 'TREATMENT';
    
    /* Drop temporary variables */
    drop _rfstdt _exstdt _exendt _exstdtc_temp _exendtc_temp _exstdt_num _exendt_num RFSTDTC;
run;

/*-----------------------------------------------------------------------------
  Step 4: Sort and assign sequence number
-----------------------------------------------------------------------------*/
proc sort data=ex_1;
    by STUDYID USUBJID EXSTDTC EXTRT;
run;

data ex_2;
    set ex_1;
    by STUDYID USUBJID;
    
    /* Derive sequence number */
    if first.USUBJID then EXSEQ = 1;
    else EXSEQ + 1;
    
    /* Apply variable labels */
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        EXSEQ    = "Sequence Number"
        EXTRT    = "Name of Treatment"
        EXDECOD  = "Standardized Treatment Name"
        EXCAT    = "Category for Treatment"
        EXDOSE   = "Dose per Administration"
        EXDOSU   = "Dose Units"
        EXDOSFRQ = "Dosing Frequency per Interval"
        EXROUTE  = "Route of Administration"
        EXSTDTC  = "Start Date/Time of Treatment"
        EXENDTC  = "End Date/Time of Treatment"
        EXSTDY   = "Study Day of Start of Treatment"
        EXENDY   = "Study Day of End of Treatment"
        EPOCH    = "Epoch"
    ;
run;

/*-----------------------------------------------------------------------------
  Step 5: Final sort and output
-----------------------------------------------------------------------------*/
proc sort data=ex_2 out=sdtm.ex;
    by STUDYID USUBJID EXSEQ;
run;

/*-----------------------------------------------------------------------------
  Step 6: Create final EX dataset with specified variable order
-----------------------------------------------------------------------------*/
data sdtm.ex;
    retain
        STUDYID
        DOMAIN
        USUBJID
        EXSEQ
        EXTRT
        EXDECOD
        EXCAT
        EXDOSE
        EXDOSU
        EXDOSFRQ
        EXROUTE
        EXSTDTC
        EXENDTC
        EXSTDY
        EXENDY
        EPOCH
    ;
    set sdtm.ex;
    
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        EXSEQ    = "Sequence Number"
        EXTRT    = "Name of Treatment"
        EXDECOD  = "Standardized Treatment Name"
        EXCAT    = "Category for Treatment"
        EXDOSE   = "Dose per Administration"
        EXDOSU   = "Dose Units"
        EXDOSFRQ = "Dosing Frequency per Interval"
        EXROUTE  = "Route of Administration"
        EXSTDTC  = "Start Date/Time of Treatment"
        EXENDTC  = "End Date/Time of Treatment"
        EXSTDY   = "Study Day of Start of Treatment"
        EXENDY   = "Study Day of End of Treatment"
        EPOCH    = "Epoch"
    ;
run;

/*-----------------------------------------------------------------------------
  Step 7: Generate summary report
-----------------------------------------------------------------------------*/
proc contents data=sdtm.ex varnum;
    title "SDTM EX Domain - Contents";
run;

proc freq data=sdtm.ex;
    tables EXTRT*EXDECOD EXCAT EXDOSFRQ EXROUTE EPOCH / missing nocum nopercent;
    title "SDTM EX Domain - Frequency Counts";
run;

/*-- END EX --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.ex;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.ex varnum;
run;

proc freq data=sdtm.ex;
  tables DOMAIN / nocum nopercent;
run;

/* End of ex.sas */
