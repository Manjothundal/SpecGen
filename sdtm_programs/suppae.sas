/*******************************************************************************
* Program:    suppae.sas
* Domain:     SUPPAE (SUPP)
* Purpose:    Create SDTM SUPPAE domain dataset
* Variables:  14
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.suppae (source CRF data)
* Output:     sdtm.suppae (SUPPAE domain dataset)
*
* Variables:  STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*==============================================================================
  Program:      SUPPAE.sas
  Description:  Create SUPPAE Supplemental Qualifiers for AE Domain
  Input:        raw.ae (source data)
                sdtm.ae (parent domain)
  Output:       sdtm.suppae
==============================================================================*/

/*-- BEGIN SUPPAE --*/

* Read source data and merge with parent domain to get AESEQ;
proc sort data=raw.ae out=raw_ae_sort;
    by USUBJID AESTDTC AETERM;
run;

proc sort data=sdtm.ae out=ae_sort;
    by USUBJID AESTDTC AETERM;
run;

* Create lookup dataset with AESEQ from parent domain;
data ae_lookup;
    merge raw_ae_sort (in=a)
          ae_sort (in=b keep=STUDYID USUBJID AESEQ AESTDTC AETERM);
    by USUBJID AESTDTC AETERM;
    if a and b;
run;

* Transpose qualifier variables into QNAM/QVAL structure;
data suppae_01;
    set ae_lookup;
    
    length STUDYID $20
           RDOMAIN $8
           USUBJID $40
           IDVAR $8 
           IDVARVAL $200 
           QNAM $8 
           QLABEL $40 
           QVAL $200 
           QORIG $8 
           QEVAL $40;
    
    RDOMAIN = 'AE';
    IDVAR = 'AESEQ';
    IDVARVAL = put(AESEQ, best.);
    QORIG = 'CRF';
    QEVAL = '';
    
    * AEACNOTH - Other Action Taken;
    if not missing(AEACNOTH) then do;
        QNAM = 'AEACNOTH';
        QLABEL = 'Other Action Taken';
        QVAL = strip(AEACNOTH);
        output;
    end;
    
    * AESDTH - Led to Death;
    if not missing(AESDTH) then do;
        QNAM = 'AESDTH';
        QLABEL = 'Results in Death';
        QVAL = strip(AESDTH);
        output;
    end;
    
    * AESHOSP - Led to Hospitalization;
    if not missing(AESHOSP) then do;
        QNAM = 'AESHOSP';
        QLABEL = 'Requires or Prolongs Hospitalization';
        QVAL = strip(AESHOSP);
        output;
    end;
    
    * AETRTEM - Treatment Emergent;
    if not missing(AETRTEM) then do;
        QNAM = 'AETRTEM';
        QLABEL = 'Treatment Emergent Flag';
        QVAL = strip(AETRTEM);
        output;
    end;
    
    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
run;

* Sort by key variables;
proc sort data=suppae_01 out=sdtm.suppae;
    by STUDYID RDOMAIN USUBJID IDVARVAL QNAM;
run;

* Apply variable labels and attributes;
data sdtm.suppae;
    set sdtm.suppae;
    
    label STUDYID = 'Study Identifier'
          RDOMAIN = 'Related Domain Abbreviation'
          USUBJID = 'Unique Subject Identifier'
          IDVAR = 'Identifying Variable'
          IDVARVAL = 'Identifying Variable Value'
          QNAM = 'Qualifier Variable Name'
          QLABEL = 'Qualifier Variable Label'
          QVAL = 'Data Value'
          QORIG = 'Origin'
          QEVAL = 'Evaluator';
run;

* Clean up temporary datasets;
proc datasets library=work nolist;
    delete raw_ae_sort ae_sort ae_lookup suppae_01;
quit;

/*-- END SUPPAE --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.suppae;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.suppae varnum;
run;

proc freq data=sdtm.suppae;
  tables DOMAIN / nocum nopercent;
run;

/* End of suppae.sas */
