/*******************************************************************************
* Program:    ds.sas
* Domain:     DS (Events)
* Purpose:    Create SDTM DS domain dataset
* Variables:  14
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.ds (source CRF data)
* Output:     sdtm.ds (DS domain dataset)
*
* Variables:  STUDYID, DSSEQ, USUBJID, DOMAIN, DSTERM, DSDECOD, DSCAT, DSSCAT
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*=======================================================================================
  Program:      ds.sas
  Description:  Create SDTM DS (Disposition) domain
  CDISC SDTM:   Version 3.2 or later
  Input:        raw.ds, sdtm.dm
  Output:       sdtm.ds
=======================================================================================*/

/*-- BEGIN DS --*/

%let keepvars = STUDYID DOMAIN USUBJID DSSEQ DSTERM DSDECOD DSCAT DSSCAT DSBODSYS 
                DSSTDTC DSENDTC DSSTDY DSENDY EPOCH;

*--------------------------------------------------------------------------------------;
* Read source DS data and merge with DM for reference dates and subject identifiers   ;
*--------------------------------------------------------------------------------------;
proc sort data=raw.ds out=ds_raw;
    by studyid siteid subjid;
run;

proc sort data=sdtm.dm(keep=studyid usubjid siteid subjid rfstdtc) out=dm_ref;
    by studyid siteid subjid;
run;

data ds_merged;
    merge ds_raw(in=a)
          dm_ref(in=b);
    by studyid siteid subjid;
    
    if a;
    
    * Issue warning if subject not found in DM;
    if not b then do;
        put "WARNING: Subject not found in DM - " studyid= siteid= subjid=;
    end;
run;

*--------------------------------------------------------------------------------------;
* Create DS domain with derivations                                                   ;
*--------------------------------------------------------------------------------------;
data ds_temp;
    set ds_merged;
    
    length STUDYID $20
           DOMAIN $2
           USUBJID $40
           DSSEQ 8
           DSTERM $200
           DSDECOD $200
           DSCAT $40
           DSSCAT $40
           DSBODSYS $200
           DSSTDTC $20
           DSENDTC $20
           DSSTDY 8
           DSENDY 8
           EPOCH $20;
    
    *--------------------------------------------------------------------------------------;
    * Assign domain constant                                                              ;
    *--------------------------------------------------------------------------------------;
    DOMAIN = 'DS';
    
    *--------------------------------------------------------------------------------------;
    * STUDYID should be retained from source                                              ;
    *--------------------------------------------------------------------------------------;
    STUDYID = strip(STUDYID);
    
    *--------------------------------------------------------------------------------------;
    * Derive USUBJID if not already available from merge                                  ;
    *--------------------------------------------------------------------------------------;
    if missing(USUBJID) then do;
        USUBJID = catx('-', strip(STUDYID), strip(SITEID), strip(SUBJID));
    end;
    
    *--------------------------------------------------------------------------------------;
    * Map disposition terms from source                                                   ;
    * DSTERM: Reported term from CRF                                                      ;
    * DSDECOD: Standardized/dictionary-derived term                                       ;
    *--------------------------------------------------------------------------------------;
    DSTERM = strip(dterm);
    
    * Map to standardized disposition decode values;
    if not missing(ddecod) then DSDECOD = strip(ddecod);
    else if upcase(strip(dterm)) = 'COMPLETED' then DSDECOD = 'COMPLETED';
    else if upcase(strip(dterm)) = 'SCREEN FAILURE' then DSDECOD = 'SCREEN FAILURE';
    else if upcase(strip(dterm)) in ('WITHDREW CONSENT', 'WITHDRAWAL BY SUBJECT') then 
        DSDECOD = 'WITHDRAWAL BY SUBJECT';
    else if upcase(strip(dterm)) in ('ADVERSE EVENT', 'AE') then DSDECOD = 'ADVERSE EVENT';
    else if upcase(strip(dterm)) = 'LOST TO FOLLOW-UP' then DSDECOD = 'LOST TO FOLLOW-UP';
    else if upcase(strip(dterm)) = 'PHYSICIAN DECISION' then DSDECOD = 'PHYSICIAN DECISION';
    else if upcase(strip(dterm)) = 'PROTOCOL DEVIATION' then DSDECOD = 'PROTOCOL DEVIATION';
    else if upcase(strip(dterm)) = 'DEATH' then DSDECOD = 'DEATH';
    else DSDECOD = strip(dterm);
    
    *--------------------------------------------------------------------------------------;
    * Map categories and subcategories                                                     ;
    *--------------------------------------------------------------------------------------;
    if not missing(dcat) then DSCAT = strip(dcat);
    if not missing(dscat) then DSSCAT = strip(dscat);
    
    *--------------------------------------------------------------------------------------;
    * Map body system - typically not applicable for DS domain                            ;
    *--------------------------------------------------------------------------------------;
    if not missing(dbodsys) then DSBODSYS = strip(dbodsys);
    
    *--------------------------------------------------------------------------------------;
    * Map start and end dates to ISO 8601 format                                          ;
    *--------------------------------------------------------------------------------------;
    * Handle source date variables - adjust variable names as needed;
    if not missing(dstdtc_char) then do;
        DSSTDTC = strip(dstdtc_char);
    end;
    else if not missing(dstdat) then do;
        if dstdat > 0 then 
            DSSTDTC = put(dstdat, is8601da.);
    end;
    
    if not missing(dendtc_char) then do;
        DSENDTC = strip(dendtc_char);
    end;
    else if not missing(dendat) then do;
        if dendat > 0 then 
            DSENDTC = put(dendat, is8601da.);
    end;
    
    *--------------------------------------------------------------------------------------;
    * Derive study days relative to RFSTDTC                                               ;
    *--------------------------------------------------------------------------------------;
    if not missing(DSSTDTC) and not missing(RFSTDTC) and length(strip(DSSTDTC)) >= 10 
       and length(strip(RFSTDTC)) >= 10 then do;
        _dsstdt = input(substr(DSSTDTC, 1, 10), yymmdd10.);
        _rfstdt = input(substr(RFSTDTC, 1, 10), yymmdd10.);
        
        if not missing(_dsstdt) and not missing(_rfstdt) then do;
            if _dsstdt >= _rfstdt then 
                DSSTDY = _dsstdt - _rfstdt + 1;
            else 
                DSSTDY = _dsstdt - _rfstdt;
        end;
    end;
    
    if not missing(DSENDTC) and not missing(RFSTDTC) and length(strip(DSENDTC)) >= 10 
       and length(strip(RFSTDTC)) >= 10 then do;
        _dsendt = input(substr(DSENDTC, 1, 10), yymmdd10.);
        _rfstdt = input(substr(RFSTDTC, 1, 10), yymmdd10.);
        
        if not missing(_dsendt) and not missing(_rfstdt) then do;
            if _dsendt >= _rfstdt then 
                DSENDY = _dsendt - _rfstdt + 1;
            else 
                DSENDY = _dsendt - _rfstdt;
        end;
    end;
    
    *--------------------------------------------------------------------------------------;
    * Derive EPOCH based on disposition date and treatment phase                          ;
    *--------------------------------------------------------------------------------------;
    if not missing(epoch_src) then EPOCH = strip(epoch_src);
    else if not missing(DSSTDTC) then do;
        if not missing(DSSTDY) and DSSTDY < 1 then EPOCH = 'SCREENING';
        else if upcase(strip(DSDECOD)) = 'SCREEN FAILURE' then EPOCH = 'SCREENING';
        else if upcase(strip(DSCAT)) = 'DISPOSITION EVENT' then do;
            if upcase(strip(DSDECOD)) in ('COMPLETED' 'EARLY TERMINATION') then 
                EPOCH = 'TREATMENT';
            else EPOCH = 'TREATMENT';
        end;
        else EPOCH = 'TREATMENT';
    end;
    
    * Clean up temporary variables;
    drop _dsstdt _dsendt _rfstdt 
         dterm ddecod dcat dscat dbodsys 
         dstdat dendat dstdtc_char dendtc_char epoch_src
         siteid subjid rfstdtc;
    
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        DSSEQ    = "Sequence Number"
        DSTERM   = "Reported Term for the Disposition Event"
        DSDECOD  = "Standardized Disposition Term"
        DSCAT    = "Category for Disposition Event"
        DSSCAT   = "Subcategory for Disposition Event"
        DSBODSYS = "Body System or Organ Class"
        DSSTDTC  = "Start Date/Time of Disposition Event"
        DSENDTC  = "End Date/Time of Disposition Event"
        DSSTDY   = "Study Day of Start of Disposition Event"
        DSENDY   = "Study Day of End of Disposition Event"
        EPOCH    = "Epoch"
    ;
run;

*--------------------------------------------------------------------------------------;
* Sort and derive DSSEQ as sequence number within subject                             ;
*--------------------------------------------------------------------------------------;
proc sort data=ds_temp;
    by STUDYID USUBJID DSSTDTC DSTERM;
run;

data ds_temp;
    set ds_temp;
    by STUDYID USUBJID;
    
    * Derive sequence counter;
    if first.USUBJID then DSSEQ = 0;
    DSSEQ + 1;
run;

*--------------------------------------------------------------------------------------;
* Final sort and output with specified variable order                                  ;
*--------------------------------------------------------------------------------------;
proc sort data=ds_temp;
    by STUDYID USUBJID DSSEQ;
run;

data sdtm.ds(keep=&keepvars label="Disposition");
    retain &keepvars;
    set ds_temp;
run;

*--------------------------------------------------------------------------------------;
* Generate summary report                                                              ;
*--------------------------------------------------------------------------------------;
proc freq data=sdtm.ds;
    tables DSDECOD*DSCAT / missing list;
    title "DS Domain: Disposition Events Summary";
run;

proc sql;
    select count(distinct USUBJID) as Subjects,
           count(*) as Records
    from sdtm.ds;
quit;

title;

/*-- END DS --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.ds;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.ds varnum;
run;

proc freq data=sdtm.ds;
  tables DOMAIN / nocum nopercent;
run;

/* End of ds.sas */
