/*******************************************************************************
* Program:    suppcm.sas
* Domain:     SUPPCM (SUPP)
* Purpose:    Create SDTM SUPPCM domain dataset
* Variables:  12
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.suppcm (source CRF data)
* Output:     sdtm.suppcm (SUPPCM domain dataset)
*
* Variables:  STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN SUPPCM --*/
/*====================================================================================
  Program Name: suppcm.sas
  Description:  Create SUPPCM supplemental qualifiers for CM domain
  RDOMAIN:      CM
  IDVAR:        CMSEQ
====================================================================================*/

*-----------------------------------------------------------------------------------;
* Merge source data with SDTM CM to get CMSEQ values;
*-----------------------------------------------------------------------------------;
proc sort data=raw.cm out=work.cm_raw;
    by studyid usubjid cmtrt cmdecod;
run;

proc sort data=sdtm.cm out=work.cm_sdtm;
    by studyid usubjid cmtrt cmdecod;
run;

data work.cm_merge;
    merge work.cm_raw (in=a)
          work.cm_sdtm (in=b keep=studyid usubjid cmtrt cmdecod cmseq);
    by studyid usubjid cmtrt cmdecod;
    if a and b;
run;

*-----------------------------------------------------------------------------------;
* Transpose qualifier variables into QNAM/QVAL rows;
*-----------------------------------------------------------------------------------;
data work.suppcm_base;
    length STUDYID $20 
           RDOMAIN $2 
           USUBJID $40 
           IDVAR $8 
           IDVARVAL $200 
           QNAM $8 
           QLABEL $40 
           QVAL $200 
           QORIG $8 
           QEVAL $40;
    
    set work.cm_merge;
    
    RDOMAIN = 'CM';
    IDVAR = 'CMSEQ';
    IDVARVAL = put(CMSEQ, best.);
    QORIG = 'CRF';
    QEVAL = '';
    
    * CMINDOTH - Other Indication;
    if not missing(CMINDOTH) then do;
        QNAM = 'CMINDOTH';
        QLABEL = 'Other Indication';
        QVAL = strip(CMINDOTH);
        output;
    end;
    
    * CMPREVFL - Prior Medication Flag;
    if not missing(CMPREVFL) then do;
        QNAM = 'CMPREVFL';
        QLABEL = 'Prior Medication Flag';
        QVAL = strip(CMPREVFL);
        output;
    end;
    
    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
    
    label STUDYID  = 'Study Identifier'
          RDOMAIN  = 'Related Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          IDVAR    = 'Identifying Variable'
          IDVARVAL = 'Identifying Variable Value'
          QNAM     = 'Qualifier Variable Name'
          QLABEL   = 'Qualifier Variable Label'
          QVAL     = 'Data Value'
          QORIG    = 'Origin'
          QEVAL    = 'Evaluator';
run;

*-----------------------------------------------------------------------------------;
* Sort by required ordering variables;
*-----------------------------------------------------------------------------------;
proc sort data=work.suppcm_base
          out=sdtm.suppcm;
    by STUDYID RDOMAIN USUBJID IDVARVAL QNAM;
run;

*-----------------------------------------------------------------------------------;
* Clean up work datasets;
*-----------------------------------------------------------------------------------;
proc datasets library=work nolist;
    delete cm_raw cm_sdtm cm_merge suppcm_base;
quit;

/*-- END SUPPCM --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.suppcm;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.suppcm varnum;
run;

proc freq data=sdtm.suppcm;
  tables DOMAIN / nocum nopercent;
run;

/* End of suppcm.sas */
