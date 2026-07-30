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

/*====================================================================================
  Program:        cm.sas
  Description:    Create SDTM CM (Concomitant Medications) Domain
  CDISC Version:  SDTM 3.2
  Input:          raw.cm, raw.dm
  Output:         sdtm.cm
  Date:           YYYY-MM-DD
  Programmer:     [Name]
====================================================================================*/

/*-- BEGIN CM --*/

*-- Read Demographics for USUBJID and RFSTDTC --;
proc sort data=raw.dm out=dm;
    by studyid siteid subjid;
run;

data dm_keep;
    set dm;
    by studyid siteid subjid;
    keep studyid siteid subjid usubjid rfstdtc;
run;

*-- Read raw concomitant medications data --;
proc sort data=raw.cm out=cm_raw;
    by studyid siteid subjid;
run;

*-- Merge CM with DM to get USUBJID and RFSTDTC --;
data cm_merge;
    merge cm_raw (in=a)
          dm_keep (in=b);
    by studyid siteid subjid;
    if a;
    
    *-- Create USUBJID if not present --;
    if missing(usubjid) then do;
        usubjid = catx('-', studyid, siteid, subjid);
    end;
    
    *-- Verify RFSTDTC is available --;
    if missing(rfstdtc) then do;
        put "WARNING: Missing RFSTDTC for " usubjid=;
    end;
run;

*-- Derive CM domain --;
data sdtm.cm;
    length STUDYID $20 
           DOMAIN $2 
           USUBJID $40 
           CMSEQ 8
           CMTRT $200 
           CMDECOD $200 
           CMCAT $200 
           CMDOSE 8 
           CMDOSU $20 
           CMDOSFRQ $20 
           CMROUTE $200 
           CMSTDTC $20 
           CMENDTC $20 
           CMSTDY 8 
           CMENDY 8 
           EPOCH $20 
           CMCLAS $200 
           CMINDC $200 
           CMONGO $20;
    
    set cm_merge;
    by studyid usubjid;
    
    *-- Assign DOMAIN --;
    DOMAIN = 'CM';
    
    *-- Derive CMSEQ as sequence number within subject --;
    retain CMSEQ;
    if first.usubjid then CMSEQ = 0;
    CMSEQ + 1;
    
    *-- Map reported and standardized treatment names --;
    CMTRT = strip(cmtrt_raw);
    if not missing(cmdecod_raw) then CMDECOD = strip(cmdecod_raw);
    else CMDECOD = strip(cmtrt_raw);
    
    *-- Map category --;
    if not missing(cmcat_raw) then CMCAT = strip(cmcat_raw);
    
    *-- Map dose information --;
    if not missing(cmdose_raw) then CMDOSE = input(cmdose_raw, best.);
    if not missing(cmdosu_raw) then CMDOSU = strip(upcase(cmdosu_raw));
    if not missing(cmdosfrq_raw) then CMDOSFRQ = strip(upcase(cmdosfrq_raw));
    
    *-- Map route of administration --;
    if not missing(cmroute_raw) then CMROUTE = strip(upcase(cmroute_raw));
    
    *-- Convert dates to ISO 8601 format --;
    if not missing(cmstdt_raw) then do;
        if lengthn(compress(cmstdt_raw)) >= 8 then do;
            cmstdt_num = input(cmstdt_raw, ?? yymmdd10.);
            if not missing(cmstdt_num) then
                CMSTDTC = put(cmstdt_num, is8601da.);
            else
                CMSTDTC = strip(cmstdt_raw);
        end;
    end;
    
    if not missing(cmendt_raw) then do;
        if lengthn(compress(cmendt_raw)) >= 8 then do;
            cmendt_num = input(cmendt_raw, ?? yymmdd10.);
            if not missing(cmendt_num) then
                CMENDTC = put(cmendt_num, is8601da.);
            else
                CMENDTC = strip(cmendt_raw);
        end;
    end;
    
    *-- Derive study day for start date --;
    if not missing(CMSTDTC) and not missing(rfstdtc) and lengthn(CMSTDTC) >= 10 and lengthn(rfstdtc) >= 10 then do;
        rfstdt_num = input(substr(rfstdtc, 1, 10), ?? yymmdd10.);
        cmstdt_num = input(substr(CMSTDTC, 1, 10), ?? yymmdd10.);
        
        if not missing(cmstdt_num) and not missing(rfstdt_num) then do;
            if cmstdt_num >= rfstdt_num then 
                CMSTDY = cmstdt_num - rfstdt_num + 1;
            else 
                CMSTDY = cmstdt_num - rfstdt_num;
        end;
    end;
    
    *-- Derive study day for end date --;
    if not missing(CMENDTC) and not missing(rfstdtc) and lengthn(CMENDTC) >= 10 and lengthn(rfstdtc) >= 10 then do;
        rfstdt_num = input(substr(rfstdtc, 1, 10), ?? yymmdd10.);
        cmendt_num = input(substr(CMENDTC, 1, 10), ?? yymmdd10.);
        
        if not missing(cmendt_num) and not missing(rfstdt_num) then do;
            if cmendt_num >= rfstdt_num then 
                CMENDY = cmendt_num - rfstdt_num + 1;
            else 
                CMENDY = cmendt_num - rfstdt_num;
        end;
    end;
    
    *-- Derive EPOCH based on timing --;
    if not missing(CMSTDY) then do;
        if CMSTDY < 1 then EPOCH = 'SCREENING';
        else EPOCH = 'TREATMENT';
    end;
    else if not missing(cmongo_raw) and upcase(strip(cmongo_raw)) = 'Y' then do;
        EPOCH = 'SCREENING';
    end;
    
    *-- Map ATC class --;
    if not missing(cmclas_raw) then CMCLAS = strip(cmclas_raw);
    
    *-- Map indication --;
    if not missing(cmindc_raw) then CMINDC = strip(cmindc_raw);
    
    *-- Map ongoing flag --;
    if not missing(cmongo_raw) then CMONGO = strip(upcase(cmongo_raw));
    
    *-- Apply labels --;
    label STUDYID  = 'Study Identifier'
          DOMAIN   = 'Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          CMSEQ    = 'Sequence Number'
          CMTRT    = 'Reported Name of Drug, Med, or Therapy'
          CMDECOD  = 'Standardized Medication Name'
          CMCAT    = 'Category for Medication'
          CMDOSE   = 'Dose per Administration'
          CMDOSU   = 'Dose Units'
          CMDOSFRQ = 'Dosing Frequency per Interval'
          CMROUTE  = 'Route of Administration'
          CMSTDTC  = 'Start Date/Time of Medication'
          CMENDTC  = 'End Date/Time of Medication'
          CMSTDY   = 'Study Day of Start of Medication'
          CMENDY   = 'Study Day of End of Medication'
          EPOCH    = 'Epoch'
          CMCLAS   = 'Medication Class'
          CMINDC   = 'Indication'
          CMONGO   = 'Ongoing Event';
    
    *-- Drop temporary and raw variables --;
    drop cmtrt_raw cmdecod_raw cmcat_raw cmdose_raw cmdosu_raw cmdosfrq_raw 
         cmroute_raw cmstdt_raw cmendt_raw cmclas_raw cmindc_raw cmongo_raw
         siteid subjid rfstdtc rfstdt_num cmstdt_num cmendt_num;
    
    *-- Retain and keep specified variables in order --;
    retain STUDYID DOMAIN USUBJID CMSEQ CMTRT CMDECOD CMCAT CMDOSE CMDOSU 
           CMDOSFRQ CMROUTE CMSTDTC CMENDTC CMSTDY CMENDY EPOCH CMCLAS 
           CMINDC CMONGO;
    
    keep STUDYID DOMAIN USUBJID CMSEQ CMTRT CMDECOD CMCAT CMDOSE CMDOSU 
         CMDOSFRQ CMROUTE CMSTDTC CMENDTC CMSTDY CMENDY EPOCH CMCLAS 
         CMINDC CMONGO;
run;

*-- Sort by STUDYID USUBJID CMSEQ --;
proc sort data=sdtm.cm;
    by studyid usubjid cmseq;
run;

*-- Generate summary report --;
proc freq data=sdtm.cm;
    tables CMCAT CMDOSFRQ CMROUTE EPOCH CMONGO / missing;
    title "CM Domain - Frequency Distributions";
run;

proc means data=sdtm.cm n nmiss min max;
    var CMSEQ CMDOSE CMSTDY CMENDY;
    title "CM Domain - Continuous Variables Summary";
run;

title;

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
