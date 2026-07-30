/*******************************************************************************
* Program:    ae.sas
* Domain:     AE (Events)
* Purpose:    Create SDTM AE domain dataset
* Variables:  19
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.ae (source CRF data)
* Output:     sdtm.ae (AE domain dataset)
*
* Variables:  STUDYID, AESEQ, USUBJID, DOMAIN, AETERM, AEDECOD, AECAT, AESCAT
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*====================================================================================
  Program:        sdtm_ae.sas
  Description:    Generate SDTM AE (Adverse Events) domain
  CDISC Version:  SDTMIG v3.4
  SAS Version:    9.4 or higher
====================================================================================*/

/*-- BEGIN AE --*/

%let domain = AE;

/*----------------------------------------------------------------------------------
  Step 1: Read source data and merge with DM for subject-level info
----------------------------------------------------------------------------------*/
proc sql;
    create table work.ae_base as
    select 
        dm.STUDYID,
        dm.USUBJID,
        dm.SITEID,
        dm.SUBJID,
        dm.RFSTDTC,
        dm.RFENDTC,
        ae.*
    from raw.ae as ae
    left join raw.dm as dm
    on ae.STUDYID = dm.STUDYID and 
       ae.SITEID = dm.SITEID and 
       ae.SUBJID = dm.SUBJID
    order by dm.USUBJID, ae.AESTDAT, ae.AETERM;
quit;

/*----------------------------------------------------------------------------------
  Step 2: Derive USUBJID if not available from merge
----------------------------------------------------------------------------------*/
data work.ae_usubjid;
    length STUDYID $20 DOMAIN $2 USUBJID $40;
    set work.ae_base;
    
    /* Derive USUBJID if missing */
    if missing(USUBJID) then do;
        USUBJID = catx('-', STUDYID, SITEID, SUBJID);
    end;
    
    /* Set DOMAIN */
    DOMAIN = "&domain";
run;

/*----------------------------------------------------------------------------------
  Step 3: Map AE-specific variables from source
----------------------------------------------------------------------------------*/
data work.ae_mapped;
    length STUDYID $20
           DOMAIN $2
           USUBJID $40
           AETERM $200
           AEDECOD $200
           AEBODSYS $200
           AECAT $200
           AESCAT $200
           AESTDTC $19
           AEENDTC $19
           AEACN $40
           AEOUT $30
           AEREL $5
           AESER $1
           AESEV $8
           EPOCH $20;
    set work.ae_usubjid;
    
    /* Map reported term */
    AETERM = strip(AEVERBAT);
    
    /* Map dictionary-derived term */
    if not missing(AEDECOD) then AEDECOD = strip(AEDECOD);
    else AEDECOD = strip(AETERM);
    
    /* Map body system/organ class */
    if not missing(AEBODSYS) then AEBODSYS = strip(AEBODSYS);
    else if not missing(AESOC) then AEBODSYS = strip(AESOC);
    
    /* Map start date/time to ISO 8601 format */
    if not missing(AESTDAT) then do;
        if not missing(AESTTIM) then 
            AESTDTC = strip(put(AESTDAT, yymmdd10.)) || 'T' || 
                     put(input(put(AESTTIM, time8.), time.), time8.);
        else 
            AESTDTC = strip(put(AESTDAT, yymmdd10.));
    end;
    
    /* Map end date/time to ISO 8601 format */
    if not missing(AEENDAT) then do;
        if not missing(AEENTIM) then 
            AEENDTC = strip(put(AEENDAT, yymmdd10.)) || 'T' || 
                     put(input(put(AEENTIM, time8.), time.), time8.);
        else 
            AEENDTC = strip(put(AEENDAT, yymmdd10.));
    end;
    
    /* Map Category and Subcategory */
    if not missing(AECAT) then AECAT = strip(AECAT);
    if not missing(AESCAT) then AESCAT = strip(AESCAT);
    
    /* Map Action Taken with Study Treatment */
    AEACN = strip(upcase(AEACNOTH));
    if AEACN in ('DOSE NOT CHANGED' 'NONE') then AEACN = 'DOSE NOT CHANGED';
    else if AEACN = 'DOSE REDUCED' then AEACN = 'DOSE REDUCED';
    else if AEACN in ('DRUG WITHDRAWN' 'WITHDRAWN') then AEACN = 'DRUG WITHDRAWN';
    else if AEACN = 'DRUG INTERRUPTED' then AEACN = 'DRUG INTERRUPTED';
    else if AEACN = 'DOSE INCREASED' then AEACN = 'DOSE INCREASED';
    else if AEACN = 'NOT APPLICABLE' then AEACN = 'NOT APPLICABLE';
    else if AEACN = 'UNKNOWN' then AEACN = 'UNKNOWN';
    
    /* Map Outcome */
    AEOUT = strip(upcase(AEOUT));
    if AEOUT in ('RECOVERED' 'RECOVERED/RESOLVED') then AEOUT = 'RECOVERED/RESOLVED';
    else if AEOUT in ('RECOVERING' 'RECOVERING/RESOLVING') then AEOUT = 'RECOVERING/RESOLVING';
    else if AEOUT = 'NOT RECOVERED/NOT RESOLVED' then AEOUT = 'NOT RECOVERED/NOT RESOLVED';
    else if AEOUT in ('RECOVERED/RESOLVED WITH SEQUELAE' 'RECOVERED WITH SEQUELAE') then AEOUT = 'RECOVERED WITH SEQUELAE';
    else if AEOUT = 'FATAL' then AEOUT = 'FATAL';
    else if AEOUT = 'UNKNOWN' then AEOUT = 'UNKNOWN';
    
    /* Map Relationship to Study Drug */
    AEREL = strip(upcase(AEREL));
    if AEREL in ('Y' 'YES' 'RELATED' 'PROBABLY RELATED' 'POSSIBLY RELATED') then AEREL = 'Y';
    else if AEREL in ('N' 'NO' 'NOT RELATED') then AEREL = 'N';
    
    /* Map Serious Event Flag */
    AESER = strip(upcase(AESER));
    if AESER in ('Y' 'YES' '1') then AESER = 'Y';
    else if AESER in ('N' 'NO' '0') then AESER = 'N';
    
    /* Map Severity/Intensity */
    AESEV = strip(upcase(AESEV));
    if AESEV in ('MILD' '1') then AESEV = 'MILD';
    else if AESEV in ('MODERATE' '2') then AESEV = 'MODERATE';
    else if AESEV in ('SEVERE' '3') then AESEV = 'SEVERE';
run;

/*----------------------------------------------------------------------------------
  Step 4: Derive study days (AESTDY, AEENDY)
----------------------------------------------------------------------------------*/
data work.ae_studyday;
    set work.ae_mapped;
    
    length AESTDY AEENDY 8;
    
    /* Convert RFSTDTC to SAS date for calculation */
    if not missing(RFSTDTC) then do;
        rfstdt = input(scan(RFSTDTC, 1, 'T'), yymmdd10.);
        
        /* Derive start study day */
        if not missing(AESTDAT) then do;
            if AESTDAT >= rfstdt then 
                AESTDY = AESTDAT - rfstdt + 1;
            else 
                AESTDY = AESTDAT - rfstdt;
        end;
        
        /* Derive end study day */
        if not missing(AEENDAT) then do;
            if AEENDAT >= rfstdt then 
                AEENDY = AEENDAT - rfstdt + 1;
            else 
                AEENDY = AEENDAT - rfstdt;
        end;
    end;
    
    drop rfstdt;
run;

/*----------------------------------------------------------------------------------
  Step 5: Derive EPOCH based on timing relative to treatment
----------------------------------------------------------------------------------*/
data work.ae_epoch;
    set work.ae_studyday;
    
    /* Derive EPOCH based on study day */
    if not missing(AESTDY) then do;
        if AESTDY < 1 then EPOCH = 'SCREENING';
        else EPOCH = 'TREATMENT';
        
        /* Check against reference end date if available */
        if not missing(RFENDTC) and not missing(AESTDAT) then do;
            rfendt = input(scan(RFENDTC, 1, 'T'), yymmdd10.);
            if AESTDAT > rfendt then EPOCH = 'FOLLOW-UP';
            drop rfendt;
        end;
    end;
run;

/*----------------------------------------------------------------------------------
  Step 6: Assign sequence numbers (AESEQ)
----------------------------------------------------------------------------------*/
proc sort data=work.ae_epoch;
    by USUBJID AESTDTC AETERM;
run;

data work.ae_seq;
    length AESEQ 8;
    set work.ae_epoch;
    by USUBJID;
    
    /* Assign sequence number within subject */
    if first.USUBJID then AESEQ = 1;
    else AESEQ + 1;
run;

/*----------------------------------------------------------------------------------
  Step 7: Apply variable labels and create final dataset
----------------------------------------------------------------------------------*/
data work.ae_final;
    set work.ae_seq;
    
    /* Apply labels */
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        AESEQ    = "Sequence Number"
        AETERM   = "Reported Term for the Adverse Event"
        AEDECOD  = "Dictionary-Derived Term"
        AECAT    = "Category for Adverse Event"
        AESCAT   = "Subcategory for Adverse Event"
        AEBODSYS = "Body System or Organ Class"
        AESTDTC  = "Start Date/Time of Adverse Event"
        AEENDTC  = "End Date/Time of Adverse Event"
        AESTDY   = "Study Day of Start of Adverse Event"
        AEENDY   = "Study Day of End of Adverse Event"
        EPOCH    = "Epoch"
        AEACN    = "Action Taken with Study Treatment"
        AEOUT    = "Outcome of Adverse Event"
        AEREL    = "Causality"
        AESER    = "Serious Event"
        AESEV    = "Severity/Intensity"
    ;
run;

/*----------------------------------------------------------------------------------
  Step 8: Final sort and output to SDTM library
----------------------------------------------------------------------------------*/
proc sort data=work.ae_final 
          out=sdtm.ae (keep=STUDYID DOMAIN USUBJID AESEQ AETERM AEDECOD AECAT AESCAT 
                            AEBODSYS AESTDTC AEENDTC AESTDY AEENDY EPOCH AEACN 
                            AEOUT AEREL AESER AESEV);
    by STUDYID USUBJID AESEQ;
run;

/*----------------------------------------------------------------------------------
  Step 9: Generate summary report
----------------------------------------------------------------------------------*/
proc sql noprint;
    select count(distinct USUBJID) into :nsubj trimmed
    from sdtm.ae;
    
    select count(*) into :nae trimmed
    from sdtm.ae;
quit;

%put NOTE: AE domain created successfully;
%put NOTE: Total subjects with AEs: &nsubj;
%put NOTE: Total AE records: &nae;

/*-- END AE --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.ae;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.ae varnum;
run;

proc freq data=sdtm.ae;
  tables DOMAIN / nocum nopercent;
run;

/* End of ae.sas */
