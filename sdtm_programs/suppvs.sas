/*******************************************************************************
* Program:    suppvs.sas
* Domain:     SUPPVS (SUPP)
* Purpose:    Create SDTM SUPPVS domain dataset
* Variables:  13
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.suppvs (source CRF data)
* Output:     sdtm.suppvs (SUPPVS domain dataset)
*
* Variables:  STUDYID, RDOMAIN, USUBJID, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN SUPPVS --*/

*---------------------------------------------------------------------------*
| Program Name    : suppvs.sas                                             |
| Purpose         : Create SUPPVS (Supplemental Qualifiers for VS) Domain  |
| CDISC Version   : SDTM 3.2                                              |
| Input           : raw.vs, sdtm.VS                                        |
| Output          : sdtm.SUPPVS                                            |
| Parent Domain   : VS                                                     |
*---------------------------------------------------------------------------*;

** Merge source data with parent domain to get VSSEQ **;
data work.vs_source;
    merge raw.vs(in=a)
          sdtm.vs(in=b keep=studyid usubjid vstestcd vsdtc vsseq);
    by studyid usubjid vstestcd vsdtc;
    if a and b;
run;

** Transpose qualifier variables into QNAM/QVAL structure **;
data work.suppvs_pre;
    length STUDYID $20 RDOMAIN $2 USUBJID $40 IDVAR $8 IDVARVAL $200 
           QNAM $8 QLABEL $40 QVAL $200 QORIG $8 QEVAL $40;
    set work.vs_source;
    
    ** Set common variables **;
    RDOMAIN = 'VS';
    IDVAR = 'VSSEQ';
    IDVARVAL = put(VSSEQ, best.);
    QORIG = 'CRF';
    QEVAL = '';
    
    ** VSCLSIG - Clinically Significant **;
    if not missing(VSCLSIG) then do;
        QNAM = 'VSCLSIG';
        QLABEL = 'Clinically Significant';
        QVAL = strip(VSCLSIG);
        output;
    end;
    
    ** VSFAST - Fasting **;
    if not missing(VSFAST) then do;
        QNAM = 'VSFAST';
        QLABEL = 'Fasting Status';
        QVAL = strip(VSFAST);
        output;
    end;
    
    ** VSLOC - Location of Measurement **;
    if not missing(VSLOC) then do;
        QNAM = 'VSLOC';
        QLABEL = 'Location of Vital Signs Measurement';
        QVAL = strip(VSLOC);
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

** Sort and create final dataset **;
proc sort data=work.suppvs_pre 
          out=sdtm.suppvs(label='Supplemental Qualifiers for Vital Signs');
    by STUDYID RDOMAIN USUBJID IDVARVAL QNAM;
run;

** Clean up work datasets **;
proc datasets library=work nolist;
    delete vs_source suppvs_pre;
quit;

/*-- END SUPPVS --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.suppvs;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.suppvs varnum;
run;

proc freq data=sdtm.suppvs;
  tables DOMAIN / nocum nopercent;
run;

/* End of suppvs.sas */
