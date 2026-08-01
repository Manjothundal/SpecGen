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
