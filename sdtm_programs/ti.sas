/*******************************************************************************
* Program:    ti.sas
* Domain:     TI (General)
* Purpose:    Create SDTM TI domain dataset
* Variables:  8
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.ti (source CRF data)
* Output:     sdtm.ti (TI domain dataset)
*
* Variables:  STUDYID, DOMAIN, IETESTCD, IETEST  , IECAT, IESCAT, TIRL, TIVERS
*             
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-----------------------------------------------------------------------------
  Program Name    : sdtm_ti.sas
  Program Purpose : Create SDTM TI (Trial Inclusion/Exclusion) Domain
  SAS Version     : 9.4 or higher
  Created By      : CDISC SDTM Programmer
  Date Created    : [Date]
  Input           : raw.ti
  Output          : sdtm.ti
-----------------------------------------------------------------------------*/

/*-- BEGIN TI --*/

*-----------------------------------------------------------------------------;
* Read source TI data                                                         ;
*-----------------------------------------------------------------------------;
proc sort data=raw.ti out=ti_source;
    by STUDYID CRITERION_CD;
run;

*-----------------------------------------------------------------------------;
* Create TI domain with proper derivations                                   ;
*-----------------------------------------------------------------------------;
data sdtm.ti;
    set ti_source;
    
    *-- Set DOMAIN --*;
    length STUDYID $20
           DOMAIN $2
           IETESTCD $8
           IETEST $200
           IECAT $200
           IESCAT $200
           TIRL $2000
           TIVERS $20;
    
    *-- Set DOMAIN --*;
    DOMAIN = 'TI';
    
    *-- Map IETESTCD and IETEST --*;
    IETESTCD = strip(upcase(CRITERION_CD));
    IETEST = strip(CRITERION_TEXT);
    
    *-- Map IECAT and IESCAT --*;
    IECAT = strip(CATEGORY);
    if not missing(SUBCATEGORY) then IESCAT = strip(SUBCATEGORY);
    
    *-- Map TIRL (Inclusion/Exclusion Criterion Rule) --*;
    TIRL = strip(RULE_TEXT);
    
    *-- Map TIVERS (Protocol Criteria Versions) --*;
    TIVERS = strip(PROTOCOL_VERSION);
    
    *-- Apply variable labels --*;
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        IETESTCD = "Incl/Excl Criterion Short Name"
        IETEST   = "Inclusion/Exclusion Criterion"
        IECAT    = "Inclusion/Exclusion Category"
        IESCAT   = "Inclusion/Exclusion Subcategory"
        TIRL     = "Inclusion/Exclusion Criterion Rule"
        TIVERS   = "Trial Inclusion/Exclusion Criteria Version"
    ;
    
    *-- Keep only required variables --*;
    keep STUDYID DOMAIN IETESTCD IETEST IECAT IESCAT TIRL TIVERS;
run;

*-----------------------------------------------------------------------------;
* Final sort for TI domain                                                   ;
*-----------------------------------------------------------------------------;
proc sort data=sdtm.ti;
    by STUDYID IETESTCD;
run;

*-----------------------------------------------------------------------------;
* Generate summary report                                                     ;
*-----------------------------------------------------------------------------;
proc freq data=sdtm.ti;
    tables IETESTCD*IETEST IECAT IESCAT / list missing;
    title "TI Domain - Frequency Counts";
run;

proc contents data=sdtm.ti varnum;
    title "TI Domain - Contents";
run;

title;

/*-- END TI --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.ti;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.ti varnum;
run;

proc freq data=sdtm.ti;
  tables DOMAIN / nocum nopercent;
run;

/* End of ti.sas */
