/*******************************************************************************
* Program:    te.sas
* Domain:     TE (General)
* Purpose:    Create SDTM TE domain dataset
* Variables:  7
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.te (source CRF data)
* Output:     sdtm.te (TE domain dataset)
*
* Variables:  STUDYID, DOMAIN, ETCD, ELEMENT, TESTRL, TEENRL, TEDUR
*             
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-----------------------------------------------------------------------------
  Program Name:    TE.sas
  Description:     Create SDTM TE (Trial Elements) Domain
  SDTM Version:    3.2
  Input:           raw.te
  Output:          sdtm.TE
  -----------------------------------------------------------------------------*/

/*-- BEGIN TE --*/

/*-----------------------------------------------------------------------------
  Step 1: Read source TE data and perform initial derivations
  -----------------------------------------------------------------------------*/
data te_1;
    set raw.te;
    
    /*-- Set required variable lengths --*/
    length STUDYID $20
           DOMAIN $2
           ETCD $8
           ELEMENT $200
           TESTRL $200
           TEENRL $200
           TEDUR $20;
    
    /*-- Set STUDYID --*/
    STUDYID = "&STUDYID";
    
    /*-- Set DOMAIN --*/
    DOMAIN = 'TE';
    
    /*-- Map variables from source --*/
    ETCD = SRC_ETCD;
    ELEMENT = SRC_ELEMENT;
    TESTRL = SRC_TESTRL;
    TEENRL = SRC_TEENRL;
    TEDUR = SRC_TEDUR;
    
run;

/*-----------------------------------------------------------------------------
  Step 2: Sort by STUDYID and ETCD
  -----------------------------------------------------------------------------*/
proc sort data=te_1;
    by STUDYID ETCD;
run;

/*-----------------------------------------------------------------------------
  Step 3: Assign TESEQ
  -----------------------------------------------------------------------------*/
data te_2;
    set te_1;
    by STUDYID ETCD;
    
    /*-- Derive TESEQ as sequential number --*/
    length TESEQ 8;
    retain TESEQ 0;
    
    if first.STUDYID then TESEQ = 0;
    TESEQ + 1;
    
run;

/*-----------------------------------------------------------------------------
  Step 4: Apply Labels and Create Final Dataset
  -----------------------------------------------------------------------------*/
data sdtm.TE;
    set te_2;
    
    /*-- Apply Labels --*/
    label
        STUDYID  = 'Study Identifier'
        DOMAIN   = 'Domain Abbreviation'
        ETCD     = 'Element Code'
        ELEMENT  = 'Description of Element'
        TESTRL   = 'Rule for Start of Element'
        TEENRL   = 'Rule for End of Element'
        TEDUR    = 'Planned Duration of Element'
        TESEQ    = 'Sequence Number'
    ;
    
    /*-- Keep only required variables in specified order --*/
    keep 
        STUDYID
        DOMAIN
        ETCD
        ELEMENT
        TESTRL
        TEENRL
        TEDUR
        TESEQ
    ;
run;

/*-----------------------------------------------------------------------------
  Step 5: Final Sort
  -----------------------------------------------------------------------------*/
proc sort data=sdtm.TE;
    by STUDYID TESEQ;
run;

/*-----------------------------------------------------------------------------
  Step 6: QC Check - Generate Summary Report
  -----------------------------------------------------------------------------*/
proc sql;
    title "TE Domain Summary - Record Count by Element";
    select ETCD, ELEMENT, count(*) as COUNT
    from sdtm.TE
    group by ETCD, ELEMENT
    order by ETCD;
quit;

proc contents data=sdtm.TE varnum;
    title "TE Domain - Variable Attributes";
run;

title;

/*-- END TE --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.te;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.te varnum;
run;

proc freq data=sdtm.te;
  tables DOMAIN / nocum nopercent;
run;

/* End of te.sas */
