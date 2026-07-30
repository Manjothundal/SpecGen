/*******************************************************************************
* Program:    cm.sas
* Domain:     CM (Interventions)
* Purpose:    Create SDTM CM domain dataset
* Variables:  19
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.cm (source CRF data)
* Output:     sdtm.cm (CM domain dataset)
*
* Variables:  STUDYID, CMSEQ, USUBJID, DOMAIN, CMTRT, CMDECOD, CMCAT, CMDOSE
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*==================================================================================================
  Program:        CM.sas
  Description:    Create SDTM CM (Concomitant Medications) domain
  SAS Version:    9.4 or later
  CDISC Version:  SDTM 3.2 or later
==================================================================================================*/

/*-- BEGIN CM --*/

*-------------------------------------------------------------------------------------------;
* Step 1: Read source CM data and merge with DM for subject identifiers and reference date ;
*-------------------------------------------------------------------------------------------;

proc sort data=raw.cm out=cm_raw;
    by STUDYID SITEID SUBJID;
run;

proc sort data=raw.dm(keep=STUDYID SITEID SUBJID USUBJID RFSTDTC) out=dm_ref nodupkey;
    by STUDYID SITEID SUBJID;
run;

data cm_01;
    merge cm_raw(in=a)
          dm_ref(in=b);
    by STUDYID SITEID SUBJID;
    
    if a; /* Keep all CM records */
    
    length USUBJID $40 RFSTDTC $19;
    
    /* Create USUBJID if not already available from DM */
    if missing(USUBJID) then USUBJID = catx('-', STUDYID, SITEID, SUBJID);
    
    /* Ensure reference start date is available for study day calculations */
    if missing(RFSTDTC) then put "WARN" "ING: Missing RFSTDTC for " USUBJID=;
run;

*-------------------------------------------------------------------------------------------;
* Step 2: Create CM domain variables and map source to SDTM                                 ;
*-------------------------------------------------------------------------------------------;

data cm_02;
    set cm_01;
    
    length STUDYID $20
           DOMAIN $2 
           USUBJID $40
           CMTRT $200 
           CMDECOD $200 
           CMCAT $200
           CMDOSE 8
           CMDOSU $20 
           CMDOSFRQ $20 
           CMROUTE $40 
           CMSTDTC $19 
           CMENDTC $19
           CMSTDY 8
           CMENDY 8
           EPOCH $20
           CMCLAS $100
           CMINDC $200
           CMONGO $3;
    
    /*-- Assign Domain --*/
    DOMAIN = 'CM';
    
    /*-- Map Reported Name of Treatment --*/
    CMTRT = strip(CMTRT);
    
    /*-- Map Standardized Treatment Name --*/
    CMDECOD = strip(CMDECOD);
    if missing(CMDECOD) then CMDECOD = CMTRT; /* Use reported name if no standardized name */
    
    /*-- Map Category --*/
    CMCAT = strip(CMCAT);
    
    /*-- Map Dose (numeric) --*/
    /* CMDOSE remains as numeric */
    
    /*-- Map Dose Units --*/
    CMDOSU = strip(upcase(CMDOSU));
    
    /*-- Map Dosing Frequency --*/
    CMDOSFRQ = strip(upcase(CMDOSFRQ));
    
    /*-- Map Route of Administration --*/
    CMROUTE = strip(upcase(CMROUTE));
    
    /*-- Map Start Date/Time (ISO 8601 format) --*/
    CMSTDTC = strip(CMSTDTC);
    
    /*-- Map End Date/Time (ISO 8601 format) --*/
    CMENDTC = strip(CMENDTC);
    
    /*-- Map ATC Class --*/
    CMCLAS = strip(CMCLAS);
    
    /*-- Map Indication --*/
    CMINDC = strip(CMINDC);
    
    /*-- Map Ongoing --*/
    CMONGO = strip(upcase(CMONGO));
    
run;

*-------------------------------------------------------------------------------------------;
* Step 3: Derive Study Days (CMSTDY, CMENDY) relative to RFSTDTC                          ;
*-------------------------------------------------------------------------------------------;

data cm_03;
    set cm_02;
    
    length RFSTDT CMSTDT CMENDT 8;
    
    /*-- Convert ISO 8601 dates to SAS dates for calculation --*/
    if not missing(RFSTDTC) and length(strip(RFSTDTC)) >= 10 then 
        RFSTDT = input(substr(RFSTDTC,1,10), ??yymmdd10.);
    
    if not missing(CMSTDTC) and length(strip(CMSTDTC)) >= 10 then 
        CMSTDT = input(substr(CMSTDTC,1,10), ??yymmdd10.);
    
    if not missing(CMENDTC) and length(strip(CMENDTC)) >= 10 then 
        CMENDT = input(substr(CMENDTC,1,10), ??yymmdd10.);
    
    /*-- Derive Study Day of Start --*/
    if not missing(CMSTDT) and not missing(RFSTDT) then do;
        if CMSTDT >= RFSTDT then 
            CMSTDY = CMSTDT - RFSTDT + 1;
        else 
            CMSTDY = CMSTDT - RFSTDT;
    end;
    
    /*-- Derive Study Day of End --*/
    if not missing(CMENDT) and not missing(RFSTDT) then do;
        if CMENDT >= RFSTDT then 
            CMENDY = CMENDT - RFSTDT + 1;
        else 
            CMENDY = CMENDT - RFSTDT;
    end;
    
    drop RFSTDT CMSTDT CMENDT SITEID SUBJID RFSTDTC;
    
run;

*-------------------------------------------------------------------------------------------;
* Step 4: Derive EPOCH based on treatment period dates                                     ;
*-------------------------------------------------------------------------------------------;

data cm_04;
    set cm_03;
    
    /*-- Derive EPOCH based on study day or date relative to treatment periods --*/
    if not missing(CMSTDY) then do;
        if CMSTDY < 1 then EPOCH = 'SCREENING';
        else EPOCH = 'TREATMENT';
        /* Add additional EPOCH logic based on protocol-specific periods */
    end;
    else if not missing(CMONGO) and upcase(CMONGO) = 'YES' then do;
        EPOCH = 'SCREENING';
    end;
    else do;
        EPOCH = '';
    end;
    
run;

*-------------------------------------------------------------------------------------------;
* Step 5: Derive CMSEQ (sequence number within subject)                                    ;
*-------------------------------------------------------------------------------------------;

proc sort data=cm_04;
    by USUBJID CMSTDTC CMTRT CMDECOD;
run;

data cm_05;
    set cm_04;
    by USUBJID;
    
    /*-- Derive Sequence Number --*/
    if first.USUBJID then CMSEQ = 0;
    CMSEQ + 1;
    
    retain CMSEQ;
    
run;

*-------------------------------------------------------------------------------------------;
* Step 6: Apply labels and create final CM domain dataset                                  ;
*-------------------------------------------------------------------------------------------;

data cm_final;
    set cm_05;
    
    label 
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        CMSEQ    = "Sequence Number"
        CMTRT    = "Reported Name of Drug, Med, or Therapy"
        CMDECOD  = "Standardized Medication Name"
        CMCAT    = "Category for Medication"
        CMDOSE   = "Dose per Administration"
        CMDOSU   = "Dose Units"
        CMDOSFRQ = "Dosing Frequency per Interval"
        CMROUTE  = "Route of Administration"
        CMSTDTC  = "Start Date/Time of Medication"
        CMENDTC  = "End Date/Time of Medication"
        CMSTDY   = "Study Day of Start of Medication"
        CMENDY   = "Study Day of End of Medication"
        EPOCH    = "Epoch"
        CMCLAS   = "Medication Class"
        CMINDC   = "Indication"
        CMONGO   = "Ongoing Medication"
    ;
    
run;

*-------------------------------------------------------------------------------------------;
* Step 7: Sort and output final CM domain                                                  ;
*-------------------------------------------------------------------------------------------;

proc sort data=cm_final 
          out=sdtm.cm(keep=STUDYID DOMAIN USUBJID CMSEQ CMTRT CMDECOD CMCAT CMDOSE CMDOSU 
                           CMDOSFRQ CMROUTE CMSTDTC CMENDTC CMSTDY CMENDY EPOCH CMCLAS 
                           CMINDC CMONGO);
    by STUDYID USUBJID CMSEQ;
run;

*-------------------------------------------------------------------------------------------;
* Step 8: Generate data summary report                                                     ;
*-------------------------------------------------------------------------------------------;

proc contents data=sdtm.cm varnum;
    title "Contents of SDTM.CM Domain";
run;

proc freq data=sdtm.cm;
    tables CMCAT CMDOSU CMDOSFRQ CMROUTE EPOCH CMONGO / missing;
    title "Frequency Summary of CM Domain";
run;

/*-- END CM --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.cm;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.cm varnum;
run;

proc freq data=sdtm.cm;
  tables DOMAIN / nocum nopercent;
run;

/* End of cm.sas */
