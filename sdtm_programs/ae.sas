/*******************************************************************************
* Program:    ae.sas
* Domain:     AE (Events)
* Purpose:    Create SDTM AE domain dataset
* Variables:  19
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.ae (source CRF data)
* Output:     sdtm.ae (AE domain dataset)
*
* Variables:  STUDYID, AESEQ, USUBJID, DOMAIN, AETERM, AEDECOD, AECAT, AESCAT
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN AE --*/

data sdtm.ae;
    merge raw.ae (in=ae) raw.dm (in=dm keep=studyid siteid subjid rfstdtc);
    by studyid siteid subjid;

    /* Set DOMAIN = 'AE' */
    domain = 'AE';

    /* Derive USUBJID if not already available in AE dataset */
    if ae.usubjid eq '' then usubjid = catx('-', studyid, siteid, subjid);

    /* Map AETERM, AEDECOD, AESTDTC, AEENDTC from source */
    aeterm = term;
    aedecod = decod;
    aestdtc = stdtc;
    aeendtc = endtc;

    /* Derive AESTDY and AEENDY as study day relative to RFSTDTC from DM */
    if rfstdtc ne '' then do;
        aestdy = (input(stdtc, anydtdte.) - input(rfstdtc, anydtdte.)) + 1;
        aeendy = (input(endtc, anydtdte.) - input(rfstdtc, anydtdte.)) + 1;
    end;

    /* Derive EPOCH based on date relative to treatment period */
    if rfstdtc ne '' and stdtc ne '' then do;
        if input(stdtc, anydtdte.) < input(rfstdtc, anydtdte.) then epoch = 'SCREENING';
        else epoch = 'TREATMENT';
    end;

    /* Apply --CAT, --SCAT from source categories */
    aecat = cat;
    aescat = scat;

    /* Domain-specific variables mapped from source */
    aesev = sev;
    aeacn = acn;
    aeout = out;
    aerel = rel;
    aeser = ser;

    /* AEBODSYS: no MedDRA/WHO coding source available yet */
    aebodsys = ' ';

    /* Derive AESEQ as a sequence number within each subject */
    retain aeseq;
    if first.subjid then aeseq = 0;
    aeseq + 1;

    /* KEEP statement listing all spec variables in order */
    keep studyid aeseq usubjid domain aeterm aedecod aecat aescat aebodsys aestdtc aeendtc aestdy aeendy epoch aeacn aeout aerel aeser aesev;

    /* Label statement with variable labels */
    label
        studyid = 'Study Identifier'
        aeseq = 'Sequence Number'
        usubjid = 'Unique Subject Identifier'
        domain = 'Domain Abbreviation'
        aeterm = 'Reported Term for the Event'
        aedecod = 'Dictionary-Derived Term'
        aecat = 'Category for Event'
        aescat = 'Subcategory for Event'
        aebodsys = 'Body System or Organ Class'
        aestdtc = 'Start Date/Time of Event'
        aeendtc = 'End Date/Time of Event'
        aestdy = 'Study Day of Start of Event'
        aeendy = 'Study Day of End of Event'
        epoch = 'Epoch'
        aeacn = 'Action Taken: None Dose Reduced Drug Withdraw Char NY'
        aeout = 'Outcome: Recovered Ongoing Fatal Char NY'
        aerel = 'Related to Study Drug?: Yes No'
        aeser = 'Serious?: Yes No'
        aesev = 'Severity: Mild Moderate Severe';
run;

/*-- END AE --*/


/*-- BEGIN SUPPAE --*/
/*====================================================================================
  Program:      suppae.sas
  Description:  Create SUPPAE (Supplemental Qualifiers for AE) domain
  Input:        raw.ae (source data)
                sdtm.ae (parent domain with AESEQ)
  Output:       sdtm.suppae
====================================================================================*/

%let studyid = STUDY123;

* Read parent domain to get AESEQ for matching;
proc sort data=sdtm.ae(keep=studyid usubjid aeseq) 
          out=ae_parent nodupkey;
    by studyid usubjid aeseq;
run;

* Read source AE data;
proc sort data=raw.ae out=raw_ae_sort;
    by studyid usubjid;
run;

* Merge source with parent to get AESEQ;
proc sort data=ae_parent out=ae_parent_sort;
    by studyid usubjid;
run;

data ae_with_seq;
    merge raw_ae_sort(in=a)
          ae_parent_sort(in=b);
    by studyid usubjid;
    if a and b;
run;

* Transpose qualifier variables into QNAM/QVAL structure;
data suppae_01;
    length STUDYID $20 
           RDOMAIN $2 
           USUBJID $40 
           IDVAR $8 
           IDVARVAL $200 
           QNAM $8 
           QLABEL $200 
           QVAL $200 
           QORIG $8 
           QEVAL $40;
    
    set ae_with_seq;
    
    RDOMAIN = 'AE';
    IDVAR = 'AESEQ';
    IDVARVAL = put(AESEQ, 8.);
    QORIG = 'CRF';
    QEVAL = '';
    
    * AEACNOTH - Other Action Taken;
    if not missing(AEACNOTH) then do;
        QNAM = 'AEACNOTH';
        QLABEL = 'Other Action Taken';
        QVAL = strip(AEACNOTH);
        output;
    end;
    
    * AESDTH - Results in Death;
    if not missing(AESDTH) then do;
        QNAM = 'AESDTH';
        QLABEL = 'Results in Death';
        QVAL = strip(AESDTH);
        output;
    end;
    
    * AESHOSP - Requires or Prolongs Hospitalization;
    if not missing(AESHOSP) then do;
        QNAM = 'AESHOSP';
        QLABEL = 'Requires or Prolongs Hospitalization';
        QVAL = strip(AESHOSP);
        output;
    end;
    
    * AETRTEM - Treatment Emergent Flag;
    if not missing(AETRTEM) then do;
        QNAM = 'AETRTEM';
        QLABEL = 'Treatment Emergent Flag';
        QVAL = strip(AETRTEM);
        output;
    end;
    
    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
run;

* Sort SUPPAE by key variables;
proc sort data=suppae_01 
          out=sdtm.suppae;
    by STUDYID RDOMAIN USUBJID IDVARVAL QNAM;
run;

* Apply variable labels;
data sdtm.suppae;
    set sdtm.suppae;
    
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

* Summary report;
proc freq data=sdtm.suppae;
    tables QNAM / nocum;
    title "SUPPAE: Summary of Qualifier Variables";
run;

proc sql;
    select count(distinct catx('|', studyid, usubjid, idvarval)) as Total_Parent_Records,
           count(*) as Total_SUPPAE_Records
    from sdtm.suppae;
quit;

title;

/*-- END SUPPAE --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.ae;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.ae varnum;
run;

proc freq data=sdtm.ae;
  tables DOMAIN / nocum nopercent;
run;

/* End of ae.sas */
