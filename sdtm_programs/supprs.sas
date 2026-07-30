/*******************************************************************************
* Program:    supprs.sas
* Domain:     SUPPRS (SUPP)
* Purpose:    Create SDTM SUPPRS domain dataset
* Variables:  13
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.supprs (source CRF data)
* Output:     sdtm.supprs (SUPPRS domain dataset)
*
* Variables:  STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN SUPPRS --*/
******************************************************************************;
* Program:      SUPPRS.sas                                                   *;
* Description:  Create SUPPRS supplemental qualifiers domain for RS          *;
* RDOMAIN:      RS                                                           *;
* IDVAR:        RSSEQ                                                        *;
******************************************************************************;

******************************************************************************;
* Step 1: Read source data and merge with SDTM RS to get RSSEQ              *;
******************************************************************************;
proc sort data=raw.rs out=raw_rs_sort;
    by studyid usubjid rstestcd rsdtc;
run;

proc sort data=sdtm.rs(keep=studyid usubjid rsseq rstestcd rsdtc) out=sdtm_rs_sort;
    by studyid usubjid rstestcd rsdtc;
run;

data rs_with_seq;
    merge raw_rs_sort(in=a)
          sdtm_rs_sort(in=b);
    by studyid usubjid rstestcd rsdtc;
    if a and b;
run;

******************************************************************************;
* Step 2: Transpose qualifier variables into QNAM/QVAL structure            *;
******************************************************************************;
data supprs_pre;
    length STUDYID $20 RDOMAIN $2 USUBJID $40 IDVAR $8 IDVARVAL $200 
           QNAM $200 QLABEL $200 QVAL $200 QORIG $8 QEVAL $40;
    
    set rs_with_seq;
    
    RDOMAIN = 'RS';
    IDVAR = 'RSSEQ';
    IDVARVAL = put(RSSEQ, best.);
    QORIG = 'CRF';
    QEVAL = '';
    
    * Qualifier 1: RSBORRESP;
    if not missing(RSBORRESP) then do;
        QNAM = 'RSBORRESP';
        QLABEL = 'Best Overall Response: CR PR SD PD';
        QVAL = strip(RSBORRESP);
        output;
    end;
    
    * Qualifier 2: RSCONFDTC;
    if not missing(RSCONFDTC) then do;
        QNAM = 'RSCONFDTC';
        QLABEL = 'Date of Confirmation';
        QVAL = strip(put(RSCONFDTC, is8601da.));
        output;
    end;
    
    * Qualifier 3: RSCONFYN;
    if not missing(RSCONFYN) then do;
        QNAM = 'RSCONFYN';
        QLABEL = 'Confirmed Response?: Yes No';
        QVAL = strip(RSCONFYN);
        output;
    end;
    
    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
run;

******************************************************************************;
* Step 3: Apply labels and sort by required variables                        *;
******************************************************************************;
proc sort data=supprs_pre 
          out=sdtm.supprs(label="Supplemental Qualifiers for RS");
    by STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM;
run;

data sdtm.supprs;
    set sdtm.supprs;
    
    label
        STUDYID  = "Study Identifier"
        RDOMAIN  = "Related Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        IDVAR    = "Identifying Variable"
        IDVARVAL = "Identifying Variable Value"
        QNAM     = "Qualifier Variable Name"
        QLABEL   = "Qualifier Variable Label"
        QVAL     = "Data Value"
        QORIG    = "Origin"
        QEVAL    = "Evaluator"
    ;
run;

******************************************************************************;
* Step 4: Generate summary report                                            *;
******************************************************************************;
proc freq data=sdtm.supprs;
    tables QNAM*QORIG / list missing;
    title "SUPPRS: Frequency of Qualifier Variables";
run;

proc contents data=sdtm.supprs varnum;
    title "SUPPRS: Dataset Contents";
run;

title;

/*-- END SUPPRS --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.supprs;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.supprs varnum;
run;

proc freq data=sdtm.supprs;
  tables DOMAIN / nocum nopercent;
run;

/* End of supprs.sas */
