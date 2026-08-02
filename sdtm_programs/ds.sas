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

/*==============================================================================
Program:        sdtm_ds.sas
Purpose:        Create SDTM DS (Disposition) Domain
SDTM Version:   3.2
Inputs:         raw.ds, raw.dm
Outputs:        sdtm.ds
================================================================================*/

/*-- BEGIN DS --*/

*-----------------------------------------------------------------------------*
* Step 1: Read in raw disposition data and merge with DM for study day calc  *
*-----------------------------------------------------------------------------*;

proc sort data=raw.ds out=ds_raw;
    by studyid siteid subjid;
run;

proc sort data=raw.dm out=dm_ref;
    by studyid siteid subjid;
run;

data ds_01;
    length usubjid $40;
    
    merge ds_raw (in=a)
          dm_ref (keep=studyid siteid subjid usubjid rfstdtc rfendtc);
    by studyid siteid subjid;
    if a;
    
    *-----------------------------------------------------------------------------*
    * Step 2: Derive USUBJID if not already present                               *
    *-----------------------------------------------------------------------------*;
    if missing(usubjid) then do;
        usubjid = catx('-', studyid, siteid, subjid);
    end;
run;

*-----------------------------------------------------------------------------*
* Step 3: Set domain and map source variables                                 *
*-----------------------------------------------------------------------------*;

data ds_02;
    length studyid $20
           domain $2
           usubjid $40
           dsterm $200
           dsdecod $200
           dscat $200
           dsscat $200
           dsbodsys $200
           dsstdtc $20
           dsendtc $20
           epoch $20;
    
    set ds_01;
    
    * Set Domain *;
    domain = 'DS';
    
    * Map Reported and Coded Terms *;
    if not missing(dsterm_raw) then dsterm = strip(dsterm_raw);
    else if not missing(dsterm) then dsterm = strip(dsterm);
    
    if not missing(dsdecod_raw) then dsdecod = strip(dsdecod_raw);
    else if not missing(dsdecod) then dsdecod = strip(dsdecod);
    else if not missing(dsterm) then dsdecod = strip(dsterm);
    
    * Map Category and Subcategory *;
    if not missing(dscat_raw) then dscat = strip(dscat_raw);
    else if not missing(dscat) then dscat = strip(dscat);
    
    if not missing(dsscat_raw) then dsscat = strip(dsscat_raw);
    else if not missing(dsscat) then dsscat = strip(dsscat);
    
    * Map Body System *;
    if not missing(dsbodsys_raw) then dsbodsys = strip(dsbodsys_raw);
    else if not missing(dsbodsys) then dsbodsys = strip(dsbodsys);
run;

*-----------------------------------------------------------------------------*
* Step 4: Derive ISO 8601 date/time character variables                       *
*-----------------------------------------------------------------------------*;

data ds_03;
    set ds_02;
    
    * Derive DSSTDTC in ISO 8601 format *;
    if not missing(dsstdat) then do;
        if not missing(dssttim) then 
            dsstdtc = strip(put(dsstdat, is8601da.)) || 'T' || 
                     put(dssttim, tod8.);
        else 
            dsstdtc = put(dsstdat, is8601da.);
    end;
    else if not missing(dsstdtc_raw) then 
        dsstdtc = strip(dsstdtc_raw);
    
    * Derive DSENDTC in ISO 8601 format *;
    if not missing(dsendat) then do;
        if not missing(dsentim) then 
            dsendtc = strip(put(dsendat, is8601da.)) || 'T' || 
                     put(dsentim, tod8.);
        else 
            dsendtc = put(dsendat, is8601da.);
    end;
    else if not missing(dsendtc_raw) then 
        dsendtc = strip(dsendtc_raw);
run;

*-----------------------------------------------------------------------------*
* Step 5: Derive study day variables (--STDY, --ENDY)                         *
*-----------------------------------------------------------------------------*;

data ds_04;
    set ds_03;
    
    length dsstdy dsendy 8;
    
    * Convert character dates to numeric for calculation *;
    if not missing(dsstdtc) then 
        dsstdat_num = input(substr(dsstdtc, 1, 10), yymmdd10.);
    if not missing(dsendtc) then 
        dsendat_num = input(substr(dsendtc, 1, 10), yymmdd10.);
    if not missing(rfstdtc) then 
        rfstdat_num = input(substr(rfstdtc, 1, 10), yymmdd10.);
    
    * Derive DSSTDY *;
    if not missing(dsstdat_num) and not missing(rfstdat_num) then do;
        if dsstdat_num >= rfstdat_num then 
            dsstdy = dsstdat_num - rfstdat_num + 1;
        else 
            dsstdy = dsstdat_num - rfstdat_num;
    end;
    
    * Derive DSENDY *;
    if not missing(dsendat_num) and not missing(rfstdat_num) then do;
        if dsendat_num >= rfstdat_num then 
            dsendy = dsendat_num - rfstdat_num + 1;
        else 
            dsendy = dsendat_num - rfstdat_num;
    end;
    
    drop dsstdat_num dsendat_num rfstdat_num;
run;

*-----------------------------------------------------------------------------*
* Step 6: Derive EPOCH based on date relative to treatment periods            *
*-----------------------------------------------------------------------------*;

data ds_05;
    set ds_04;
    
    * Basic EPOCH derivation - customize based on study design *;
    if not missing(epoch_raw) then 
        epoch = strip(epoch_raw);
    else if not missing(dsstdtc) then do;
        dsstdat_num = input(substr(dsstdtc, 1, 10), yymmdd10.);
        if not missing(rfstdtc) then 
            rfstdat_num = input(substr(rfstdtc, 1, 10), yymmdd10.);
        if not missing(rfendtc) then 
            rfendat_num = input(substr(rfendtc, 1, 10), yymmdd10.);
        
        if not missing(rfstdat_num) then do;
            if dsstdat_num < rfstdat_num then 
                epoch = 'SCREENING';
            else if not missing(rfendat_num) and dsstdat_num > rfendat_num then 
                epoch = 'FOLLOW-UP';
            else 
                epoch = 'TREATMENT';
        end;
        
        drop dsstdat_num rfstdat_num rfendat_num;
    end;
run;

*-----------------------------------------------------------------------------*
* Step 7: Derive DSSEQ (sequence number within subject)                       *
*-----------------------------------------------------------------------------*;

proc sort data=ds_05;
    by usubjid dsstdtc dsterm;
run;

data ds_06;
    set ds_05;
    by usubjid;
    
    length dsseq 8;
    
    retain dsseq;
    
    if first.usubjid then dsseq = 0;
    dsseq + 1;
run;

*-----------------------------------------------------------------------------*
* Step 8: Apply labels and final formatting                                   *
*-----------------------------------------------------------------------------*;

data ds_final;
    set ds_06;
    
    label
        studyid   = "Study Identifier"
        domain    = "Domain Abbreviation"
        usubjid   = "Unique Subject Identifier"
        dsseq     = "Sequence Number"
        dsterm    = "Reported Term for the Disposition Event"
        dsdecod   = "Standardized Disposition Term"
        dscat     = "Category for Disposition Event"
        dsscat    = "Subcategory for Disposition Event"
        dsbodsys  = "Body System or Organ Class"
        dsstdtc   = "Start Date/Time of Disposition Event"
        dsendtc   = "End Date/Time of Disposition Event"
        dsstdy    = "Study Day of Start of Disposition Event"
        dsendy    = "Study Day of End of Disposition Event"
        epoch     = "Epoch"
    ;
run;

*-----------------------------------------------------------------------------*
* Step 9: Final sort and output to SDTM library                               *
*-----------------------------------------------------------------------------*;

proc sort data=ds_final 
          out=sdtm.ds (keep=studyid domain usubjid dsseq dsterm dsdecod 
                            dscat dsscat dsbodsys dsstdtc dsendtc 
                            dsstdy dsendy epoch);
    by studyid usubjid dsseq;
run;

*-----------------------------------------------------------------------------*
* Step 10: Generate summary report                                            *
*-----------------------------------------------------------------------------*;

proc sql;
    title "DS Domain Summary";
    select count(distinct usubjid) as Subjects,
           count(*) as Records,
           count(distinct dsterm) as Unique_Terms
    from sdtm.ds;
quit;

proc freq data=sdtm.ds;
    tables dscat dsdecod epoch / missing;
    title "DS Domain Frequency Counts";
run;

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
