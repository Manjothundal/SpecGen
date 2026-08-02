/*******************************************************************************
* Program:    ts.sas
* Domain:     TS (General)
* Purpose:    Create SDTM TS domain dataset
* Variables:  10
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.ts (source CRF data)
* Output:     sdtm.ts (TS domain dataset)
*
* Variables:  STUDYID, DOMAIN, TSSEQ, TSGRPID, TSPARMCD, TSPARM, TSVAL, TSVALCD
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-----------------------------------------------------------------------------
  Program Name:     sdtm_ts.sas
  Description:      Create SDTM TS (Trial Summary) Domain
  SDTM Version:     3.2
  Input:            raw.ts
  Output:           sdtm.ts
  -----------------------------------------------------------------------------
  Modification History:
  Date        Programmer    Description
  ----------  ------------  ---------------------------------------------------
  DDMMMYYYY   CDISC Team    Initial version
-----------------------------------------------------------------------------*/

/*-- BEGIN TS --*/

/*-----------------------------------------------------------------------------
  Step 1: Read source data and prepare base dataset
-----------------------------------------------------------------------------*/
data ts_raw;
    set raw.ts;
    
    /* Keep only non-missing records */
    if not missing(tsparmcd);
run;

/*-----------------------------------------------------------------------------
  Step 2: Derive standard TS variables
-----------------------------------------------------------------------------*/
data ts_prep;
    set ts_raw;
    
    /* Ensure proper variable lengths per SDTM IG */
    length STUDYID $20
           DOMAIN $2
           TSGRPID $20
           TSPARMCD $8
           TSPARM $100
           TSVAL $200
           TSVALCD $20
           TSVCDREF $50
           TSVCDVER $20;
    
    /* Set required domain variable */
    DOMAIN = 'TS';
    
    /* Map variables from source - adjust source variable names as needed */
    STUDYID = strip(studyid);
    
    /* Map trial summary parameters */
    TSGRPID = strip(tsgrpid);
    TSPARMCD = strip(upcase(tsparmcd));
    TSPARM = strip(tsparm);
    TSVAL = strip(tsval);
    TSVALCD = strip(tsvalcd);
    TSVCDREF = strip(tsvcdref);
    TSVCDVER = strip(tsvcdver);
run;

/*-----------------------------------------------------------------------------
  Step 3: Sort and derive sequence number
-----------------------------------------------------------------------------*/
proc sort data=ts_prep;
    by STUDYID TSGRPID TSPARMCD;
run;

data ts_seq;
    set ts_prep;
    by STUDYID TSGRPID TSPARMCD;
    
    /* Derive sequence number */
    length TSSEQ 8;
    retain TSSEQ;
    
    if first.STUDYID then TSSEQ = 0;
    TSSEQ + 1;
run;

/*-----------------------------------------------------------------------------
  Step 4: Apply labels and create final dataset
-----------------------------------------------------------------------------*/
data sdtm.ts;
    retain STUDYID DOMAIN TSSEQ TSGRPID TSPARMCD TSPARM TSVAL TSVALCD 
           TSVCDREF TSVCDVER;
    set ts_seq;
    
    /* Apply variable labels per SDTM specification */
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        TSSEQ    = "Sequence Number"
        TSGRPID  = "Group ID"
        TSPARMCD = "Trial Summary Parameter Short Name"
        TSPARM   = "Trial Summary Parameter"
        TSVAL    = "Parameter Value"
        TSVALCD  = "Parameter Value Code"
        TSVCDREF = "Name of the Reference Terminology"
        TSVCDVER = "Version of the Reference Terminology"
    ;
    
    /* Keep only specified variables in correct order */
    keep STUDYID DOMAIN TSSEQ TSGRPID TSPARMCD TSPARM TSVAL TSVALCD 
         TSVCDREF TSVCDVER;
run;

/*-----------------------------------------------------------------------------
  Step 5: Sort final dataset
-----------------------------------------------------------------------------*/
proc sort data=sdtm.ts;
    by STUDYID TSSEQ;
run;

/*-----------------------------------------------------------------------------
  Step 6: Generate summary report
-----------------------------------------------------------------------------*/
proc freq data=sdtm.ts;
    tables TSPARMCD * TSPARM / list missing;
    title "TS Domain - Parameter Frequency";
run;

proc print data=sdtm.ts(obs=20);
    title "TS Domain - First 20 Records";
run;

title;

/*-- END TS --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.ts;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.ts varnum;
run;

proc freq data=sdtm.ts;
  tables DOMAIN / nocum nopercent;
run;

/* End of ts.sas */
