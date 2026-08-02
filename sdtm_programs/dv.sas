/*******************************************************************************
* Program:    dv.sas
* Domain:     DV (Events)
* Purpose:    Create SDTM DV domain dataset
* Variables:  14
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.dv (source CRF data)
* Output:     sdtm.dv (DV domain dataset)
*
* Variables:  STUDYID, DVSEQ, USUBJID, DOMAIN, DVTERM, DVDECOD, DVCAT, DVSCAT
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*==============================================================================
  Program:      DV.sas
  Purpose:      Create SDTM DV (Protocol Deviations) Domain
  SDTM Version: 3.2 (or later)
  Notes:        DV is in the Events class - one row per event per subject
==============================================================================*/

/*-- BEGIN DV --*/

%*----------------------------------------------------------------------------
  Step 1: Read source DV data and merge with DM for reference dates
------------------------------------------------------------------------------;

proc sort data=raw.dv out=dv_source;
  by studyid siteid subjid;
run;

proc sort data=raw.dm out=dm_source;
  by studyid siteid subjid;
run;

data dv_merge;
  merge dv_source (in=indv)
        dm_source (keep=studyid siteid subjid rfstdtc 
                   rename=(rfstdtc=dm_rfstdtc));
  by studyid siteid subjid;
  if indv;
run;


%*----------------------------------------------------------------------------
  Step 2: Create base DV dataset with domain assignments and derivations
------------------------------------------------------------------------------;

data dv_base;
  set dv_merge;
  
  length STUDYID $20
         DOMAIN $2
         USUBJID $40
         DVSEQ 8
         DVTERM $200
         DVDECOD $200
         DVCAT $200
         DVSCAT $200
         DVBODSYS $200
         DVSTDTC $20
         DVENDTC $20
         DVSTDY 8
         DVENDY 8
         EPOCH $20;
  
  /*-- Domain Assignment --*/
  DOMAIN = 'DV';
  
  /*-- Derive USUBJID --*/
  USUBJID = catx('-', STUDYID, SITEID, SUBJID);
  
  /*-- Map DV Term from source verbatim --*/
  if not missing(dv_verbatim) then DVTERM = strip(dv_verbatim);
  else if not missing(deviation_term) then DVTERM = strip(deviation_term);
  
  /*-- Map DV Decoded Term from source coded term --*/
  if not missing(dv_coded) then DVDECOD = strip(dv_coded);
  else if not missing(deviation_coded) then DVDECOD = strip(deviation_coded);
  else DVDECOD = DVTERM; /* Use verbatim if no coded term available */
  
  /*-- Map Category from source --*/
  if not missing(dv_cat) then DVCAT = strip(dv_cat);
  else if not missing(deviation_category) then DVCAT = strip(deviation_category);
  
  /*-- Map Subcategory from source --*/
  if not missing(dv_scat) then DVSCAT = strip(dv_scat);
  else if not missing(deviation_subcategory) then DVSCAT = strip(deviation_subcategory);
  
  /*-- Map Body System if applicable (may not be used for all DV types) --*/
  if not missing(dv_bodsys) then DVBODSYS = strip(dv_bodsys);
  else if not missing(body_system) then DVBODSYS = strip(body_system);
  
  /*-- Map Start Date/Time to ISO 8601 format --*/
  if not missing(dv_stdat) then do;
    if not missing(dv_sttim) then 
      DVSTDTC = cats(put(dv_stdat, yymmdd10.), 'T', put(dv_sttim, time8.));
    else 
      DVSTDTC = put(dv_stdat, yymmdd10.);
  end;
  else if not missing(deviation_start_date) then do;
    if not missing(deviation_start_time) then 
      DVSTDTC = cats(put(deviation_start_date, yymmdd10.), 'T', 
                     put(deviation_start_time, time8.));
    else 
      DVSTDTC = put(deviation_start_date, yymmdd10.);
  end;
  
  /*-- Map End Date/Time to ISO 8601 format --*/
  if not missing(dv_endat) then do;
    if not missing(dv_entim) then 
      DVENDTC = cats(put(dv_endat, yymmdd10.), 'T', put(dv_entim, time8.));
    else 
      DVENDTC = put(dv_endat, yymmdd10.);
  end;
  else if not missing(deviation_end_date) then do;
    if not missing(deviation_end_time) then 
      DVENDTC = cats(put(deviation_end_date, yymmdd10.), 'T', 
                     put(deviation_end_time, time8.));
    else 
      DVENDTC = put(deviation_end_date, yymmdd10.);
  end;
  
  /*-- Keep DM reference date for study day calculation --*/
  length rfstdtc_char $20;
  rfstdtc_char = dm_rfstdtc;
  
run;


%*----------------------------------------------------------------------------
  Step 3: Derive Study Days (DVSTDY, DVENDY)
------------------------------------------------------------------------------;

data dv_stdy;
  set dv_base;
  
  length rfstdt dvstdt dvendt 8;
  
  /*-- Convert character dates to numeric for calculation --*/
  if not missing(rfstdtc_char) then 
    rfstdt = input(scan(rfstdtc_char, 1, 'T'), yymmdd10.);
  
  if not missing(DVSTDTC) then 
    dvstdt = input(scan(DVSTDTC, 1, 'T'), yymmdd10.);
  
  if not missing(DVENDTC) then 
    dvendt = input(scan(DVENDTC, 1, 'T'), yymmdd10.);
  
  /*-- Calculate Study Day for Start Date --*/
  /*-- Study day cannot be zero, add 1 if >= RFSTDTC --*/
  if not missing(dvstdt) and not missing(rfstdt) then do;
    if dvstdt >= rfstdt then 
      DVSTDY = dvstdt - rfstdt + 1;
    else 
      DVSTDY = dvstdt - rfstdt;
  end;
  
  /*-- Calculate Study Day for End Date --*/
  if not missing(dvendt) and not missing(rfstdt) then do;
    if dvendt >= rfstdt then 
      DVENDY = dvendt - rfstdt + 1;
    else 
      DVENDY = dvendt - rfstdt;
  end;
  
  drop rfstdt dvstdt dvendt rfstdtc_char;
  
run;


%*----------------------------------------------------------------------------
  Step 4: Derive EPOCH based on date relative to treatment period
------------------------------------------------------------------------------;

data dv_epoch;
  set dv_stdy;
  
  /*-- Assign EPOCH based on start date and study phase --*/
  /*-- This logic should be customized based on study design --*/
  if not missing(epoch_source) then 
    EPOCH = strip(epoch_source);
  else if not missing(DVSTDY) then do;
    if DVSTDY < 1 then 
      EPOCH = 'SCREENING';
    else if DVSTDY >= 1 then 
      EPOCH = 'TREATMENT';
    /* Add additional epoch logic as needed */
  end;
  
  /*-- Alternative: Use visit-based epoch mapping if available --*/
  else if not missing(visit) then do;
    if visit in ('SCREENING', 'SCREEN') then 
      EPOCH = 'SCREENING';
    else if visit =: 'TREAT' or visit =: 'WEEK' or visit =: 'DAY' then 
      EPOCH = 'TREATMENT';
    else if visit in ('FOLLOWUP', 'FOLLOW-UP', 'FOLLOW UP') then 
      EPOCH = 'FOLLOW-UP';
  end;
  
run;


%*----------------------------------------------------------------------------
  Step 5: Assign DVSEQ (sequence number within subject)
------------------------------------------------------------------------------;

proc sort data=dv_epoch;
  by USUBJID DVSTDTC DVTERM;
run;

data dv_seq;
  set dv_epoch;
  by USUBJID;
  
  /*-- Generate sequence number --*/
  retain DVSEQ;
  if first.USUBJID then DVSEQ = 0;
  DVSEQ + 1;
  
run;


%*----------------------------------------------------------------------------
  Step 6: Apply variable labels and create final dataset
------------------------------------------------------------------------------;

data dv_final;
  set dv_seq;
  
  label
    STUDYID  = "Study Identifier"
    DOMAIN   = "Domain Abbreviation"
    USUBJID  = "Unique Subject Identifier"
    DVSEQ    = "Sequence Number"
    DVTERM   = "Reported Term for the Protocol Deviation"
    DVDECOD  = "Standardized Protocol Deviation Term"
    DVCAT    = "Category for Protocol Deviation"
    DVSCAT   = "Subcategory for Protocol Deviation"
    DVBODSYS = "Body System or Organ Class"
    DVSTDTC  = "Start Date/Time of Protocol Deviation"
    DVENDTC  = "End Date/Time of Protocol Deviation"
    DVSTDY   = "Study Day of Start of Protocol Deviation"
    DVENDY   = "Study Day of End of Protocol Deviation"
    EPOCH    = "Epoch"
  ;
  
  format DVSEQ DVSTDY DVENDY 8.;
  
run;


%*----------------------------------------------------------------------------
  Step 7: Sort and output final DV dataset
------------------------------------------------------------------------------;

proc sort data=dv_final out=sdtm.dv (label="Protocol Deviations");
  by STUDYID USUBJID DVSEQ;
run;

/*-- Keep only SDTM variables in specified order --*/
data sdtm.dv (label="Protocol Deviations");
  retain 
    STUDYID
    DOMAIN
    USUBJID
    DVSEQ
    DVTERM
    DVDECOD
    DVCAT
    DVSCAT
    DVBODSYS
    DVSTDTC
    DVENDTC
    DVSTDY
    DVENDY
    EPOCH
  ;
  set sdtm.dv;
  keep
    STUDYID
    DOMAIN
    USUBJID
    DVSEQ
    DVTERM
    DVDECOD
    DVCAT
    DVSCAT
    DVBODSYS
    DVSTDTC
    DVENDTC
    DVSTDY
    DVENDY
    EPOCH
  ;
run;

/*-- END DV --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.dv;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.dv varnum;
run;

proc freq data=sdtm.dv;
  tables DOMAIN / nocum nopercent;
run;

/* End of dv.sas */
