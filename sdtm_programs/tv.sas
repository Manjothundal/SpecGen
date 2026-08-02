/*******************************************************************************
* Program:    tv.sas
* Domain:     TV (General)
* Purpose:    Create SDTM TV domain dataset
* Variables:  9
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.tv (source CRF data)
* Output:     sdtm.tv (TV domain dataset)
*
* Variables:  STUDYID, DOMAIN, VISITNUM, VISIT, VISITDY, ARMCD, TVSTRL, TVENRL
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*=======================================================================================
  Program Name: TV.sas
  Description:  Create SDTM TV (Trial Visits) domain
  Domain:       TV (Events class - one row per visit per planned arm)
  Input:        raw.tv
  Output:       sdtm.tv
=======================================================================================*/

/*-- BEGIN TV --*/

%let keepvars = STUDYID DOMAIN VISITNUM VISIT VISITDY ARMCD ARM TVSTRL TVENRL;

/*---------------------------------------------------------------------------------------
  Step 1: Create TV domain
---------------------------------------------------------------------------------------*/
data tv_01;
    length STUDYID $20
           DOMAIN $2
           VISITNUM 8
           VISIT $200
           VISITDY 8
           ARMCD $20
           ARM $200
           TVSTRL $200
           TVENRL $200;
    
    set raw.tv;
    
    /*-- Assign DOMAIN --*/
    DOMAIN = 'TV';
    
    /*-- Assign STUDYID (preserve from source) --*/
    STUDYID = strip(STUDYID);
    
    /*-- Assign Visit Number --*/
    VISITNUM = visitnum;
    
    /*-- Assign Visit Name --*/
    VISIT = strip(visit);
    
    /*-- Assign Planned Study Day of Visit --*/
    VISITDY = visitdy;
    
    /*-- Assign Planned Arm Code --*/
    ARMCD = strip(armcd);
    
    /*-- Assign Description of Planned Arm --*/
    ARM = strip(arm);
    
    /*-- Assign Visit Start Rule --*/
    TVSTRL = strip(tvstrl);
    
    /*-- Assign Visit End Rule --*/
    TVENRL = strip(tvenrl);
    
    /*-- Apply Labels --*/
    label STUDYID  = "Study Identifier"
          DOMAIN   = "Domain Abbreviation"
          VISITNUM = "Visit Number"
          VISIT    = "Visit Name"
          VISITDY  = "Planned Study Day of Visit"
          ARMCD    = "Planned Arm Code"
          ARM      = "Description of Planned Arm"
          TVSTRL   = "Visit Start Rule"
          TVENRL   = "Visit End Rule";
run;

/*---------------------------------------------------------------------------------------
  Step 2: Remove duplicate records if any
---------------------------------------------------------------------------------------*/
proc sort data=tv_01 nodupkey;
    by STUDYID ARMCD VISITNUM VISIT;
run;

/*---------------------------------------------------------------------------------------
  Step 3: Sort final dataset and create final TV domain
---------------------------------------------------------------------------------------*/
proc sort data=tv_01 out=sdtm.tv(label="Trial Visits");
    by STUDYID ARMCD VISITNUM;
run;

/*---------------------------------------------------------------------------------------
  Step 4: Generate summary report
---------------------------------------------------------------------------------------*/
proc sql;
    title "TV Domain - Record Count Summary";
    select count(*) as Total_Records,
           count(distinct STUDYID) as Unique_Studies,
           count(distinct ARMCD) as Unique_Arms,
           count(distinct VISITNUM) as Unique_Visits
    from sdtm.tv;
quit;

proc freq data=sdtm.tv;
    title "TV Domain - Frequency Summary";
    tables ARMCD*VISITNUM / list missing;
run;

title;

/*-- END TV --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.tv;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.tv varnum;
run;

proc freq data=sdtm.tv;
  tables DOMAIN / nocum nopercent;
run;

/* End of tv.sas */
