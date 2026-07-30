/*******************************************************************************
* Program:    suppeg.sas
* Domain:     SUPPEG (SUPP)
* Purpose:    Create SDTM SUPPEG domain dataset
* Variables:  11
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.suppeg (source CRF data)
* Output:     sdtm.suppeg (SUPPEG domain dataset)
*
* Variables:  STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN SUPPEG --*/
*******************************************************************************;
* Program:       suppeg.sas                                                   *;
* Description:   Create SUPPEG (Supplemental Qualifiers for EG) domain       *;
* Parent Domain: EG                                                           *;
*******************************************************************************;

* Merge source data with SDTM EG to get EGSEQ;
proc sort data=raw.eg out=raw_eg_sort;
    by usubjid egdtc egtpt;
run;

proc sort data=sdtm.eg out=eg_seq;
    by usubjid egdtc egtpt;
run;

data eg_with_seq;
    merge raw_eg_sort (in=a)
          eg_seq (in=b keep=studyid usubjid egdtc egtpt egseq);
    by usubjid egdtc egtpt;
    if a and b;
run;

* Create SUPPEG records for each qualifier variable;
data suppeg;
    length STUDYID $20 RDOMAIN $8 USUBJID $40 IDVAR $8 IDVARVAL $200
           QNAM $8 QLABEL $40 QVAL $200 QORIG $8 QEVAL $40;
    
    set eg_with_seq;
    
    RDOMAIN = 'EG';
    IDVAR = 'EGSEQ';
    IDVARVAL = put(EGSEQ, 8.);
    QORIG = 'CRF';
    QEVAL = '';
    
    * EGCLSIG qualifier;
    if not missing(egclsig) then do;
        QNAM = 'EGCLSIG';
        QLABEL = 'Clinical Significance';
        QVAL = strip(egclsig);
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

* Sort final dataset;
proc sort data=suppeg out=sdtm.suppeg;
    by STUDYID USUBJID IDVARVAL QNAM;
run;

* Clean up temporary datasets;
proc datasets library=work nolist;
    delete raw_eg_sort eg_seq eg_with_seq suppeg;
quit;

/*-- END SUPPEG --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.suppeg;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.suppeg varnum;
run;

proc freq data=sdtm.suppeg;
  tables DOMAIN / nocum nopercent;
run;

/* End of suppeg.sas */
