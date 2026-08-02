/*******************************************************************************
* Program:    cm.sas
* Domain:     CM (Interventions)
* Purpose:    Create SDTM CM domain dataset
* Variables:  28
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.cm (source CRF data)
* Output:     sdtm.cm (CM domain dataset)
*
* Variables:  STUDYID, DOMAIN, USUBJID, CMCAT, CMSEQ, CMGRPID, CMSPID, CMTRT
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*==========================================================================================*
 | Program Name:    CM.sas                                                                  |
 | Program Purpose: Create SDTM CM (Concomitant Medications) Domain                        |
 | SAS Version:     9.4 or higher                                                           |
 | CDISC Version:   SDTM 3.2 or higher                                                      |
 |==========================================================================================*/

/*-- BEGIN CM --*/

*-----------------------------------------------------------------------------------------*
| Step 1: Read source data and merge with DM for reference dates                          |
*-----------------------------------------------------------------------------------------*;

proc sort data=raw.cm out=cm_raw;
    by studyid siteid subjid;
run;

proc sort data=raw.dm(keep=studyid siteid subjid usubjid rfstdtc rfendtc) out=dm;
    by studyid siteid subjid;
run;

data cm_merged;
    merge cm_raw(in=a)
          dm(in=b);
    by studyid siteid subjid;
    if a;
    
    if not b then do;
        put "WARNING: Subject not found in DM: " studyid= siteid= subjid=;
    end;
run;

*-----------------------------------------------------------------------------------------*
| Step 2: Create CM domain with derivations                                               |
*-----------------------------------------------------------------------------------------*;

data cm_1;
    set cm_merged;
    by studyid siteid subjid;
    
    length STUDYID $20
           DOMAIN $2 
           USUBJID $40
           CMCAT $200
           CMGRPID $20
           CMSPID $20
           CMTRT $200
           CMDECOD $200
           CMINDC $200
           CMDOSTXT $200
           CMDOSU $20
           CMDOSFRQ $20
           CMROUTE $20
           CMSTDTC $20
           CMENDTC $20
           CMENRF $20
           ATC4CD $10
           ATC4 $200
           ATC3CD $10
           ATC3 $200
           ATC2CD $10
           ATC2 $200
           ATC1CD $10
           ATC1 $200;
    
    /* Domain Assignment */
    DOMAIN = 'CM';
    
    /* Study Identifier */
    STUDYID = strip(put(studyid, best.));
    
    /* USUBJID Derivation */
    if missing(USUBJID) then do;
        USUBJID = catx('-', strip(put(studyid, best.)), strip(put(siteid, best.)), strip(put(subjid, best.)));
    end;
    
    /* Map source variables to SDTM variables */
    
    /* Category for Medication */
    if not missing(cmcat_raw) then CMCAT = strip(cmcat_raw);
    
    /* Group ID */
    if not missing(cmgrpid_raw) then CMGRPID = strip(cmgrpid_raw);
    
    /* Sponsor-Defined Identifier */
    if not missing(cmspid_raw) then CMSPID = strip(cmspid_raw);
    
    /* Reported Name of Drug */
    if not missing(cmtrt_raw) then CMTRT = strip(cmtrt_raw);
    
    /* Standardized Medication Name */
    if not missing(cmdecod_raw) then CMDECOD = strip(cmdecod_raw);
    
    /* Indication */
    if not missing(cmindc_raw) then CMINDC = strip(cmindc_raw);
    
    /* Dose per Administration */
    if not missing(cmdose_raw) then do;
        if notdigit(strip(cmdose_raw)) = 0 then CMDOSE = input(cmdose_raw, ?? best.);
    end;
    
    /* Dose Description */
    if not missing(cmdostxt_raw) then CMDOSTXT = strip(cmdostxt_raw);
    
    /* Dose Units */
    if not missing(cmdosu_raw) then CMDOSU = strip(cmdosu_raw);
    
    /* Dosing Frequency */
    if not missing(cmdosfrq_raw) then CMDOSFRQ = strip(cmdosfrq_raw);
    
    /* Route of Administration */
    if not missing(cmroute_raw) then CMROUTE = strip(cmroute_raw);
    
    /* Start Date/Time - Convert to ISO 8601 */
    if not missing(cmstdat_raw) then do;
        _cmstdat_chk = strip(cmstdat_raw);
        if indexc(_cmstdat_chk, '-') > 0 and length(_cmstdat_chk) >= 10 then
            CMSTDTC = substr(_cmstdat_chk, 1, 10);
        else if missing(CMSTDTC) then do;
            _cmstdt = input(cmstdat_raw, ?? yymmdd10.);
            if not missing(_cmstdt) then CMSTDTC = put(_cmstdt, is8601da.);
        end;
    end;
    
    /* End Date/Time - Convert to ISO 8601 */
    if not missing(cmendat_raw) then do;
        _cmendat_chk = strip(cmendat_raw);
        if indexc(_cmendat_chk, '-') > 0 and length(_cmendat_chk) >= 10 then
            CMENDTC = substr(_cmendat_chk, 1, 10);
        else if missing(CMENDTC) then do;
            _cmendt = input(cmendat_raw, ?? yymmdd10.);
            if not missing(_cmendt) then CMENDTC = put(_cmendt, is8601da.);
        end;
    end;
    
    /* ATC Level 4 Code and Term */
    if not missing(atc4cd_raw) then ATC4CD = strip(atc4cd_raw);
    if not missing(atc4_raw) then ATC4 = strip(atc4_raw);
    
    /* ATC Level 3 Code and Term */
    if not missing(atc3cd_raw) then ATC3CD = strip(atc3cd_raw);
    if not missing(atc3_raw) then ATC3 = strip(atc3_raw);
    
    /* ATC Level 2 Code and Term */
    if not missing(atc2cd_raw) then ATC2CD = strip(atc2cd_raw);
    if not missing(atc2_raw) then ATC2 = strip(atc2_raw);
    
    /* ATC Level 1 Code and Term */
    if not missing(atc1cd_raw) then ATC1CD = strip(atc1cd_raw);
    if not missing(atc1_raw) then ATC1 = strip(atc1_raw);
    
    drop _cmstdat_chk _cmendat_chk _cmstdt _cmendt;
run;

*-----------------------------------------------------------------------------------------*
| Step 3: Derive Study Days (--STDY, --ENDY) relative to RFSTDTC                         |
*-----------------------------------------------------------------------------------------*;

data cm_2;
    set cm_1;
    
    /* Convert ISO 8601 dates to SAS dates for calculation */
    length rfstdt cmstdt cmendt 8;
    
    /* Reference Start Date */
    if not missing(rfstdtc) then rfstdt = input(substr(rfstdtc, 1, 10), ?? yymmdd10.);
    
    /* CM Start Date */
    if not missing(CMSTDTC) then cmstdt = input(substr(CMSTDTC, 1, 10), ?? yymmdd10.);
    
    /* CM End Date */
    if not missing(CMENDTC) then cmendt = input(substr(CMENDTC, 1, 10), ?? yymmdd10.);
    
    /* Study Day of Start of Medication */
    if not missing(cmstdt) and not missing(rfstdt) then do;
        if cmstdt >= rfstdt then 
            CMSTDY = cmstdt - rfstdt + 1;
        else 
            CMSTDY = cmstdt - rfstdt;
    end;
    
    /* Study Day of End of Medication */
    if not missing(cmendt) and not missing(rfstdt) then do;
        if cmendt >= rfstdt then 
            CMENDY = cmendt - rfstdt + 1;
        else 
            CMENDY = cmendt - rfstdt;
    end;
    
    drop rfstdt cmstdt cmendt;
run;

*-----------------------------------------------------------------------------------------*
| Step 4: Derive End Relative to Reference Period (CMENRF)                               |
*-----------------------------------------------------------------------------------------*;

data cm_3;
    set cm_2;
    
    length rfstdt rfendt cmendt 8;
    
    /* Reference Start Date */
    if not missing(rfstdtc) then rfstdt = input(substr(rfstdtc, 1, 10), ?? yymmdd10.);
    
    /* Reference End Date */
    if not missing(rfendtc) then rfendt = input(substr(rfendtc, 1, 10), ?? yymmdd10.);
    
    /* CM End Date */
    if not missing(CMENDTC) then cmendt = input(substr(CMENDTC, 1, 10), ?? yymmdd10.);
    
    /* Derive CMENRF */
    if missing(CMENDTC) then do;
        CMENRF = 'ONGOING';
    end;
    else if not missing(rfendtc) and not missing(rfstdt) and not missing(cmendt) then do;
        if cmendt > rfendt then 
            CMENRF = 'AFTER';
        else if cmendt < rfstdt then 
            CMENRF = 'BEFORE';
        else 
            CMENRF = 'DURING';
    end;
    
    drop rfstdt rfendt cmendt;
run;

*-----------------------------------------------------------------------------------------*
| Step 5: Assign CMSEQ and finalize                                                       |
*-----------------------------------------------------------------------------------------*;

proc sort data=cm_3;
    by STUDYID USUBJID CMSTDTC CMTRT CMDECOD;
run;

data cm_final;
    set cm_3;
    by STUDYID USUBJID;
    
    /* Sequence Number */
    if first.USUBJID then CMSEQ = 0;
    CMSEQ + 1;
    
    /* Apply Labels */
    label 
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        CMCAT    = "Category for Medication"
        CMSEQ    = "Sequence Number"
        CMGRPID  = "Group ID"
        CMSPID   = "Sponsor-Defined Identifier"
        CMTRT    = "Reported Name of Drug, Med, or Therapy"
        CMDECOD  = "Standardized Medication Name"
        CMINDC   = "Indication"
        CMDOSE   = "Dose per Administration"
        CMDOSTXT = "Dose Description"
        CMDOSU   = "Dose Units"
        CMDOSFRQ = "Dosing Frequency per Interval"
        CMROUTE  = "Route of Administration"
        CMSTDTC  = "Start Date/Time of Medication"
        CMENDTC  = "End Date/Time of Medication"
        CMSTDY   = "Study Day of Start of Medication"
        CMENDY   = "Study Day of End of Medication"
        CMENRF   = "End Relative to Reference Period"
        ATC4CD   = "ATC Level 4 Code"
        ATC4     = "ATC Level 4 Term"
        ATC3CD   = "ATC Level 3 Code"
        ATC3     = "ATC Level 3 Term"
        ATC2CD   = "ATC Level 2 Code"
        ATC2     = "ATC Level 2 Term"
        ATC1CD   = "ATC Level 1 Code"
        ATC1     = "ATC Level 1 Term";
run;

*-----------------------------------------------------------------------------------------*
| Step 6: Final sort and output to SDTM library                                           |
*-----------------------------------------------------------------------------------------*;

proc sort data=cm_final 
          out=sdtm.cm(keep=STUDYID 
                           DOMAIN 
                           USUBJID 
                           CMCAT 
                           CMSEQ 
                           CMGRPID 
                           CMSPID 
                           CMTRT 
                           CMDECOD 
                           CMINDC 
                           CMDOSE 
                           CMDOSTXT 
                           CMDOSU 
                           CMDOSFRQ 
                           CMROUTE 
                           CMSTDTC 
                           CMENDTC 
                           CMSTDY 
                           CMENDY 
                           CMENRF 
                           ATC4CD 
                           ATC4 
                           ATC3CD 
                           ATC3 
                           ATC2CD 
                           ATC2 
                           ATC1CD 
                           ATC1);
    by STUDYID USUBJID CMSEQ;
run;

*-----------------------------------------------------------------------------------------*
| Step 7: Summary report                                                                   |
*-----------------------------------------------------------------------------------------*;

proc freq data=sdtm.cm;
    tables CMCAT CMDOSFRQ CMROUTE CMENRF / missing;
    title "CM Domain Frequency Counts";
run;

proc means data=sdtm.cm n nmiss min max;
    var CMSEQ CMDOSE CMSTDY CMENDY;
    title "CM Domain Numeric Variable Summary";
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
