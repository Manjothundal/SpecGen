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

/*=======================================================================================
  Program:      EX.sas
  Description:  SDTM EX (Exposure) Domain - Interventions Class
  Date:         [Current Date]
  Programmer:   [Name]
  Study:        [Study Number]
  Notes:        Production-quality SDTM EX domain program
=========================================================================================*/

/*-- BEGIN EX --*/

%let keepvars = STUDYID DOMAIN USUBJID EXSEQ EXTRT EXDECOD EXCAT EXDOSE EXDOSU 
                EXDOSFRQ EXROUTE EXSTDTC EXENDTC EXSTDY EXENDY EPOCH;

/*---------------------------------------------------------------------------------------
  STEP 1: Read in DM domain for reference variables (STUDYID, USUBJID, RFSTDTC)
---------------------------------------------------------------------------------------*/
proc sort data=sdtm.dm(keep=studyid usubjid rfstdtc siteid subjid) out=dm nodupkey;
    by studyid usubjid;
run;

/*---------------------------------------------------------------------------------------
  STEP 2: Read and prepare raw EX source data
---------------------------------------------------------------------------------------*/
data ex_raw;
    set raw.ex;
    
    /* Keep only non-missing records */
    if not missing(subjid);
    
    /* Derive USUBJID if not already in source */
    length usubjid $40;
    if missing(usubjid) then usubjid = catx('-', studyid, siteid, subjid);
    
run;

/*---------------------------------------------------------------------------------------
  STEP 3: Merge EX raw data with DM to get reference date (RFSTDTC)
---------------------------------------------------------------------------------------*/
proc sort data=ex_raw;
    by studyid usubjid;
run;

data ex_merge;
    merge ex_raw(in=a)
          dm(in=b keep=studyid usubjid rfstdtc);
    by studyid usubjid;
    if a;
    
    /* Flag if subject not in DM */
    if not b then put "WARNING: Subject not found in DM - " usubjid=;
run;

/*---------------------------------------------------------------------------------------
  STEP 4: Create SDTM EX domain with all derivations
---------------------------------------------------------------------------------------*/
data ex_pre;
    set ex_merge;
    
    /* Set required variable lengths */
    length STUDYID $20
           DOMAIN $2
           USUBJID $40
           EXTRT $200
           EXDECOD $200
           EXCAT $200
           EXDOSE 8
           EXDOSU $200
           EXDOSFRQ $200
           EXROUTE $200
           EXSTDTC $20
           EXENDTC $20
           EXSTDY 8
           EXENDY 8
           EPOCH $20;
    
    /*-----------------------------------------------------------------------------------
      Domain and Basic Variables
    -----------------------------------------------------------------------------------*/
    DOMAIN = 'EX';
    
    /* STUDYID should come from source or DM */
    STUDYID = strip(studyid);
    USUBJID = strip(usubjid);
    
    /*-----------------------------------------------------------------------------------
      Treatment Variables - Map from source variables
      Adjust source variable names as needed for actual data
    -----------------------------------------------------------------------------------*/
    /* Reported treatment name from CRF */
    EXTRT = strip(trt);  /* Adjust source variable name as needed */
    
    /* Standardized treatment name - derive from reported name or dictionary */
    if upcase(strip(EXTRT)) in ('DRUG A' 'ACTIVE') then EXDECOD = 'DRUG A';
    else if upcase(strip(EXTRT)) in ('PLACEBO' 'PBO') then EXDECOD = 'PLACEBO';
    else EXDECOD = strip(upcase(EXTRT));
    
    /* Category for intervention */
    if not missing(excat) then EXCAT = strip(excat);  
    else EXCAT = 'STUDY TREATMENT';
    
    /*-----------------------------------------------------------------------------------
      Dose Variables - Map from source
    -----------------------------------------------------------------------------------*/
    /* Dose per administration */
    if not missing(dose) then EXDOSE = dose;  
    
    /* Dose units */
    if not missing(dosu) then EXDOSU = strip(dosu);  
    
    /* Dosing frequency */
    if not missing(dosfrq) then EXDOSFRQ = strip(dosfrq);  
    
    /* Route of administration */
    if not missing(route) then EXROUTE = strip(route);  
    
    /*-----------------------------------------------------------------------------------
      Date/Time Variables - Convert to ISO 8601 format
    -----------------------------------------------------------------------------------*/
    /* Start date/time of intervention */
    if not missing(exstdt) then do;
        if not missing(exsttm) then 
            EXSTDTC = strip(put(exstdt, yymmdd10.)) || 'T' || put(exsttm, time8.);
        else 
            EXSTDTC = strip(put(exstdt, yymmdd10.));
    end;
    
    /* End date/time of intervention */
    if not missing(exendt) then do;
        if not missing(exentm) then 
            EXENDTC = strip(put(exendt, yymmdd10.)) || 'T' || put(exentm, time8.);
        else 
            EXENDTC = strip(put(exendt, yymmdd10.));
    end;
    
    /*-----------------------------------------------------------------------------------
      Study Day Derivations - Relative to RFSTDTC
    -----------------------------------------------------------------------------------*/
    /* Derive EXSTDY - Study day of start of intervention */
    if not missing(exstdt) and not missing(rfstdtc) then do;
        rfstdt = input(scan(rfstdtc, 1, 'T'), yymmdd10.);
        if not missing(rfstdt) then do;
            if exstdt >= rfstdt then 
                EXSTDY = exstdt - rfstdt + 1;
            else 
                EXSTDY = exstdt - rfstdt;
        end;
    end;
    
    /* Derive EXENDY - Study day of end of intervention */
    if not missing(exendt) and not missing(rfstdtc) then do;
        rfstdt = input(scan(rfstdtc, 1, 'T'), yymmdd10.);
        if not missing(rfstdt) then do;
            if exendt >= rfstdt then 
                EXENDY = exendt - rfstdt + 1;
            else 
                EXENDY = exendt - rfstdt;
        end;
    end;
    
    /*-----------------------------------------------------------------------------------
      EPOCH Derivation - Based on date relative to treatment periods
      Adjust logic based on protocol-specific epochs
    -----------------------------------------------------------------------------------*/
    if not missing(epoch_source) then EPOCH = strip(epoch_source);
    else if not missing(EXSTDY) then do;
        if EXSTDY >= 1 then EPOCH = 'TREATMENT';
        else if EXSTDY < 1 then EPOCH = 'SCREENING';
    end;
    
    /* Drop temporary and source variables */
    drop trt dose dosu dosfrq route exstdt exsttm exendt exentm 
         rfstdt rfstdtc siteid subjid epoch_source excat;
         
run;

/*---------------------------------------------------------------------------------------
  STEP 5: Derive EXSEQ as sequence number within each subject
---------------------------------------------------------------------------------------*/
proc sort data=ex_pre;
    by studyid usubjid exstdtc exendtc extrt;
run;

data ex_seq;
    set ex_pre;
    by studyid usubjid;
    
    /* Sequence number within subject */
    length EXSEQ 8;
    if first.usubjid then EXSEQ = 0;
    EXSEQ + 1;
    
run;

/*---------------------------------------------------------------------------------------
  STEP 6: Apply labels and final dataset
---------------------------------------------------------------------------------------*/
data sdtm.ex(label="Exposure");
    set ex_seq;
    
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        EXSEQ    = "Sequence Number"
        EXTRT    = "Name of Actual Treatment"
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
    
    /* Keep only specified variables in order */
    keep &keepvars;
    
run;

/*---------------------------------------------------------------------------------------
  STEP 7: Final sort by STUDYID USUBJID EXSEQ
---------------------------------------------------------------------------------------*/
proc sort data=sdtm.ex;
    by studyid usubjid exseq;
run;

/*---------------------------------------------------------------------------------------
  STEP 8: Generate summary report
---------------------------------------------------------------------------------------*/
proc freq data=sdtm.ex;
    tables extrt*exdecod excat exdosfrq exroute epoch / missing list;
    title "EX Domain Frequency Summary";
run;

proc means data=sdtm.ex n nmiss min max mean median;
    var exseq exdose exstdy exendy;
    title "EX Domain Numeric Variable Summary";
run;

title;

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
