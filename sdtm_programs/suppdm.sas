/*******************************************************************************
* Program:    suppdm.sas
* Domain:     SUPPDM (SUPP)
* Purpose:    Create SDTM SUPPDM domain dataset
* Variables:  13
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.suppdm (source CRF data)
* Output:     sdtm.suppdm (SUPPDM domain dataset)
*
* Variables:  STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN SUPPDM --*/

**********************************************************************;
* Program:      SUPPDM.sas                                            ;
* Description:  Create SUPPDM (Supplemental Qualifiers for DM)        ;
* Study:        [STUDY NAME]                                          ;
* Domain:       SUPPDM                                                ;
* Parent:       DM                                                    ;
**********************************************************************;

**********************************************************************;
* Step 1: Merge source data with SDTM DM to get USUBJID              ;
**********************************************************************;
proc sort data=raw.dm out=raw_dm_sort;
    by USUBJID;
run;

proc sort data=sdtm.dm out=dm_key;
    by USUBJID;
run;

data dm_with_qual;
    merge raw_dm_sort (in=a)
          dm_key (in=b keep=STUDYID USUBJID);
    by USUBJID;
    if a and b;
    
    * Keep only qualifier variables needed for SUPPDM;
    keep STUDYID USUBJID COMPLT DCSREAS EDUYRN;
run;

**********************************************************************;
* Step 2: Transpose qualifier variables into SUPPDM structure        ;
**********************************************************************;
data suppdm_prelim;
    length STUDYID $20 RDOMAIN $8 USUBJID $40 IDVAR $8 IDVARVAL $200
           QNAM $200 QLABEL $200 QVAL $200 QORIG $8 QEVAL $40;
    set dm_with_qual;
    
    RDOMAIN = 'DM';
    IDVAR = 'USUBJID';
    IDVARVAL = strip(USUBJID);
    QORIG = 'CRF';
    QEVAL = '';
    
    * Transpose COMPLT;
    if not missing(COMPLT) then do;
        QNAM = 'COMPLT';
        QLABEL = 'Completed Study?';
        QVAL = strip(COMPLT);
        output;
    end;
    
    * Transpose DCSREAS;
    if not missing(DCSREAS) then do;
        QNAM = 'DCSREAS';
        QLABEL = 'Reason for Discontinuation';
        QVAL = strip(DCSREAS);
        output;
    end;
    
    * Transpose EDUYRN;
    if not missing(EDUYRN) then do;
        QNAM = 'EDUYRN';
        QLABEL = 'Years of Education';
        if compress(EDUYRN, '0123456789.') = '' then
            QVAL = strip(put(input(EDUYRN, best.), best.));
        else
            QVAL = strip(EDUYRN);
        output;
    end;
    
    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
run;

**********************************************************************;
* Step 3: Sort and create final SUPPDM dataset                       ;
**********************************************************************;
proc sort data=suppdm_prelim 
          out=sdtm.suppdm (label="Supplemental Qualifiers for DM");
    by STUDYID RDOMAIN USUBJID IDVARVAL QNAM;
run;

**********************************************************************;
* Step 4: Apply variable labels                                      ;
**********************************************************************;
data sdtm.suppdm;
    set sdtm.suppdm;
    
    label STUDYID  = "Study Identifier"
          RDOMAIN  = "Related Domain Abbreviation"
          USUBJID  = "Unique Subject Identifier"
          IDVAR    = "Identifying Variable"
          IDVARVAL = "Identifying Variable Value"
          QNAM     = "Qualifier Variable Name"
          QLABEL   = "Qualifier Variable Label"
          QVAL     = "Data Value"
          QORIG    = "Origin"
          QEVAL    = "Evaluator";
run;

**********************************************************************;
* Step 5: Generate summary report                                    ;
**********************************************************************;
proc freq data=sdtm.suppdm;
    tables QNAM / nocum;
    title "SUPPDM: Frequency of Qualifier Variables";
run;

proc contents data=sdtm.suppdm varnum;
    title "SUPPDM: Dataset Contents";
run;

title;

/*-- END SUPPDM --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.suppdm;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.suppdm varnum;
run;

proc freq data=sdtm.suppdm;
  tables DOMAIN / nocum nopercent;
run;

/* End of suppdm.sas */
