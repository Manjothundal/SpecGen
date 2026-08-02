/*******************************************************************************
* Program:    eg.sas
* Domain:     EG (Findings)
* Purpose:    Create SDTM EG domain dataset
* Variables:  19
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.eg (source CRF data)
* Output:     sdtm.eg (EG domain dataset)
*
* Variables:  STUDYID, EGSEQ, USUBJID, DOMAIN, EGTESTCD, EGTEST, EGCAT, EGORRES
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*---------------------------------------------------------------------------*
 | PROGRAM NAME:    SDTM_EG.sas                                             |
 | DESCRIPTION:     Create SDTM EG (ECG Tests) domain                       |
 | DOMAIN:          EG (Findings - ECG)                                     |
 | INPUT:           raw.eg, sdtm.dm                                         |
 | OUTPUT:          sdtm.eg                                                 |
 | PROGRAMMER:      Senior CDISC SDTM Programmer                            |
 | DATE:            [Date]                                                  |
 *---------------------------------------------------------------------------*/

/*-- BEGIN EG --*/

/*---------------------------------------------------------------------------*
 | Step 1: Read in DM for reference information                            |
 *---------------------------------------------------------------------------*/
proc sort data=sdtm.dm(keep=studyid usubjid rfstdtc) out=dm nodupkey;
    by studyid usubjid;
run;

/*---------------------------------------------------------------------------*
 | Step 2: Read and transpose source EG data if in wide format             |
 | Assumes raw.eg contains variables:                                       |
 | STUDYID, SITEID, SUBJID, VISIT, VISITNUM, EGDTC, EGEVAL                 |
 | HR, HRUNIT, HRND, HRREA                                                  |
 | QT, QTUNIT, QTND, QTREA                                                  |
 | QTC, QTCUNIT, QTCND, QTCREA                                              |
 | RR, RRUNIT, RRND, RRREA                                                  |
 | PR, PRUNIT, PRND, PRREA                                                  |
 | QRS, QRSUNIT, QRSND, QRSREA                                              |
 *---------------------------------------------------------------------------*/

data eg_trans;
    set raw.eg;
    
    /*-- Derive USUBJID --*/
    length USUBJID $40;
    USUBJID = catx('-', STUDYID, SITEID, SUBJID);
    
    /*-- Define array for test names and parameters --*/
    length EGTESTCD $8 EGTEST $40 EGORRES $200 EGORRESU $40 
           EGSTAT $12 EGREASND $200 EGCAT $40;
    
    /*-- HR: Heart Rate --*/
    EGTESTCD = 'HR';
    EGTEST = 'Heart Rate';
    EGCAT = 'ECG';
    if upcase(strip(HRND)) = 'Y' then do;
        EGSTAT = 'NOT DONE';
        EGREASND = strip(HRREA);
        EGORRES = '';
        EGORRESU = '';
    end;
    else do;
        EGSTAT = '';
        EGREASND = '';
        if HR ne . then EGORRES = strip(put(HR, best.));
        else EGORRES = '';
        EGORRESU = strip(HRUNIT);
    end;
    output;
    
    /*-- QT Interval --*/
    EGTESTCD = 'QT';
    EGTEST = 'QT Duration';
    EGCAT = 'ECG';
    if upcase(strip(QTND)) = 'Y' then do;
        EGSTAT = 'NOT DONE';
        EGREASND = strip(QTREA);
        EGORRES = '';
        EGORRESU = '';
    end;
    else do;
        EGSTAT = '';
        EGREASND = '';
        if QT ne . then EGORRES = strip(put(QT, best.));
        else EGORRES = '';
        EGORRESU = strip(QTUNIT);
    end;
    output;
    
    /*-- QTc: QT Corrected --*/
    EGTESTCD = 'QTC';
    EGTEST = 'QT Corrected';
    EGCAT = 'ECG';
    if upcase(strip(QTCND)) = 'Y' then do;
        EGSTAT = 'NOT DONE';
        EGREASND = strip(QTCREA);
        EGORRES = '';
        EGORRESU = '';
    end;
    else do;
        EGSTAT = '';
        EGREASND = '';
        if QTC ne . then EGORRES = strip(put(QTC, best.));
        else EGORRES = '';
        EGORRESU = strip(QTCUNIT);
    end;
    output;
    
    /*-- RR Interval --*/
    EGTESTCD = 'RR';
    EGTEST = 'RR Duration';
    EGCAT = 'ECG';
    if upcase(strip(RRND)) = 'Y' then do;
        EGSTAT = 'NOT DONE';
        EGREASND = strip(RRREA);
        EGORRES = '';
        EGORRESU = '';
    end;
    else do;
        EGSTAT = '';
        EGREASND = '';
        if RR ne . then EGORRES = strip(put(RR, best.));
        else EGORRES = '';
        EGORRESU = strip(RRUNIT);
    end;
    output;
    
    /*-- PR Interval --*/
    EGTESTCD = 'PR';
    EGTEST = 'PR Duration';
    EGCAT = 'ECG';
    if upcase(strip(PRND)) = 'Y' then do;
        EGSTAT = 'NOT DONE';
        EGREASND = strip(PRREA);
        EGORRES = '';
        EGORRESU = '';
    end;
    else do;
        EGSTAT = '';
        EGREASND = '';
        if PR ne . then EGORRES = strip(put(PR, best.));
        else EGORRES = '';
        EGORRESU = strip(PRUNIT);
    end;
    output;
    
    /*-- QRS Duration --*/
    EGTESTCD = 'QRS';
    EGTEST = 'QRS Duration';
    EGCAT = 'ECG';
    if upcase(strip(QRSND)) = 'Y' then do;
        EGSTAT = 'NOT DONE';
        EGREASND = strip(QRSREA);
        EGORRES = '';
        EGORRESU = '';
    end;
    else do;
        EGSTAT = '';
        EGREASND = '';
        if QRS ne . then EGORRES = strip(put(QRS, best.));
        else EGORRES = '';
        EGORRESU = strip(QRSUNIT);
    end;
    output;
    
    keep STUDYID USUBJID EGTESTCD EGTEST EGCAT EGORRES EGORRESU 
         EGSTAT EGREASND VISIT VISITNUM EGDTC EGEVAL;
run;

/*---------------------------------------------------------------------------*
 | Step 3: Merge with DM and derive standard variables                     |
 *---------------------------------------------------------------------------*/

data eg_derived;
    merge eg_trans(in=a)
          dm;
    by studyid usubjid;
    if a;
    
    length DOMAIN $2 EGSTRESC $200 EGSTRESU $40;
    
    /*-- Set DOMAIN --*/
    DOMAIN = 'EG';
    
    /*-- Derive EGSTRESC (standardized character result) --*/
    EGSTRESC = '';
    
    /*-- Derive EGSTRESN (numeric result in standard units) --*/
    EGSTRESN = .;
    
    /*-- Derive EGSTRESU (standard units) --*/
    EGSTRESU = '';
    
    /*-- Apply unit conversions if needed --*/
    if EGSTAT ne 'NOT DONE' and EGORRES ne '' then do;
        if EGTESTCD = 'HR' then do;
            if upcase(EGORRESU) in ('BEATS/MIN' 'BPM' '/MIN') then do;
                EGSTRESU = 'beats/min';
                EGSTRESN = input(EGORRES, ?best.);
                EGSTRESC = strip(EGORRES);
            end;
            else do;
                EGSTRESU = strip(EGORRESU);
                EGSTRESN = input(EGORRES, ?best.);
                EGSTRESC = strip(EGORRES);
            end;
        end;
        else if EGTESTCD in ('QT' 'QTC' 'RR' 'PR' 'QRS') then do;
            if upcase(EGORRESU) = 'MSEC' then do;
                EGSTRESU = 'msec';
                EGSTRESN = input(EGORRES, ?best.);
                EGSTRESC = strip(EGORRES);
            end;
            else if upcase(EGORRESU) = 'SEC' then do;
                EGSTRESU = 'msec';
                EGSTRESN = input(EGORRES, ?best.) * 1000;
                EGSTRESC = strip(put(EGSTRESN, best.));
            end;
            else do;
                EGSTRESU = strip(EGORRESU);
                EGSTRESN = input(EGORRES, ?best.);
                EGSTRESC = strip(EGORRES);
            end;
        end;
        else do;
            EGSTRESU = strip(EGORRESU);
            EGSTRESN = input(EGORRES, ?best.);
            EGSTRESC = strip(EGORRES);
        end;
    end;
    
    /*-- Derive EGDY (Study Day) --*/
    EGDY = .;
    if EGDTC ne '' and RFSTDTC ne '' then do;
        if input(substr(EGDTC,1,10), ??yymmdd10.) ne . and 
           input(substr(RFSTDTC,1,10), ??yymmdd10.) ne . then do;
            if input(substr(EGDTC,1,10), yymmdd10.) >= input(substr(RFSTDTC,1,10), yymmdd10.) then
                EGDY = input(substr(EGDTC,1,10), yymmdd10.) - input(substr(RFSTDTC,1,10), yymmdd10.) + 1;
            else
                EGDY = input(substr(EGDTC,1,10), yymmdd10.) - input(substr(RFSTDTC,1,10), yymmdd10.);
        end;
    end;
run;

/*---------------------------------------------------------------------------*
 | Step 4: Sort and assign EGSEQ                                           |
 *---------------------------------------------------------------------------*/

proc sort data=eg_derived;
    by STUDYID USUBJID VISITNUM EGDTC EGTESTCD;
run;

data eg_seq;
    set eg_derived;
    by STUDYID USUBJID;
    
    /*-- Derive EGSEQ --*/
    retain EGSEQ;
    if first.USUBJID then EGSEQ = 0;
    EGSEQ + 1;
    
    /*-- Apply labels --*/
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        EGSEQ    = "Sequence Number"
        EGTESTCD = "ECG Test or Examination Short Name"
        EGTEST   = "ECG Test or Examination Name"
        EGCAT    = "Category for ECG"
        EGORRES  = "Result or Finding in Original Units"
        EGORRESU = "Original Units"
        EGSTRESC = "Character Result/Finding in Std Format"
        EGSTRESN = "Numeric Result/Finding in Standard Units"
        EGSTRESU = "Standard Units"
        EGSTAT   = "Completion Status"
        EGREASND = "Reason Not Done"
        VISITNUM = "Visit Number"
        VISIT    = "Visit Name"
        EGDTC    = "Date/Time of ECG"
        EGDY     = "Study Day of ECG"
        EGEVAL   = "Evaluator"
    ;
    
    /*-- Apply formats --*/
    format EGSTRESN EGSEQ VISITNUM EGDY 8.;
run;

/*---------------------------------------------------------------------------*
 | Step 5: Create final SDTM EG dataset                                    |
 *---------------------------------------------------------------------------*/

data sdtm.eg;
    retain STUDYID DOMAIN USUBJID EGSEQ EGTESTCD EGTEST EGCAT 
           EGORRES EGORRESU EGSTRESC EGSTRESN EGSTRESU 
           EGSTAT EGREASND VISITNUM VISIT EGDTC EGDY EGEVAL;
    set eg_seq;
    
    keep STUDYID DOMAIN USUBJID EGSEQ EGTESTCD EGTEST EGCAT 
         EGORRES EGORRESU EGSTRESC EGSTRESN EGSTRESU 
         EGSTAT EGREASND VISITNUM VISIT EGDTC EGDY EGEVAL;
run;

/*---------------------------------------------------------------------------*
 | Step 6: Final sort by key variables                                     |
 *---------------------------------------------------------------------------*/

proc sort data=sdtm.eg;
    by STUDYID USUBJID EGSEQ;
run;

/*---------------------------------------------------------------------------*
 | Step 7: Generate summary report                                         |
 *---------------------------------------------------------------------------*/

proc freq data=sdtm.eg;
    tables EGTESTCD*EGTEST EGSTAT VISITNUM / missing;
    title "SDTM EG Domain - Frequency Counts";
run;

proc means data=sdtm.eg n nmiss min max mean median;
    var EGSTRESN EGDY;
    class EGTESTCD;
    title "SDTM EG Domain - Numeric Summary Statistics";
run;

title;

/*-- END EG --*/


/*-- BEGIN SUPPEG --*/
/*====================================================================================*/
/* Program Name:     SUPPEG.sas                                                       */
/* Description:      Create SUPPEG (Supplemental Qualifiers for EG) domain           */
/* RDOMAIN:          EG                                                               */
/* IDVAR:            EGSEQ                                                            */
/*====================================================================================*/

/*------------------------------------------------------------------------------------*/
/* Step 1: Merge source EG data with SDTM EG to get EGSEQ                            */
/*------------------------------------------------------------------------------------*/
proc sort data=raw.eg out=raw_eg_sorted;
    by USUBJID EGDTC EGTPTNUM;
run;

proc sort data=sdtm.EG out=sdtm_eg;
    by USUBJID EGDTC EGTPTNUM;
run;

data eg_with_seq;
    merge raw_eg_sorted (in=a)
          sdtm_eg (in=b keep=STUDYID USUBJID EGSEQ EGDTC EGTPTNUM);
    by USUBJID EGDTC EGTPTNUM;
    if a and b;
    
    keep STUDYID USUBJID EGSEQ EGCLSIG;
run;

/*------------------------------------------------------------------------------------*/
/* Step 2: Transpose qualifier variables into SUPPEG structure                       */
/*------------------------------------------------------------------------------------*/
data suppeg_base;
    set eg_with_seq;
    
    length STUDYID $20 
           RDOMAIN $8 
           USUBJID $40 
           IDVAR $8 
           IDVARVAL $200
           QNAM $8 
           QLABEL $200 
           QVAL $200 
           QORIG $8 
           QEVAL $40;
    
    RDOMAIN = 'EG';
    IDVAR = 'EGSEQ';
    IDVARVAL = strip(put(EGSEQ, best.));
    QORIG = 'CRF';
    QEVAL = '';
    
    /* EGCLSIG */
    if not missing(EGCLSIG) then do;
        QNAM = 'EGCLSIG';
        QLABEL = 'Clinically Significant';
        QVAL = strip(EGCLSIG);
        output;
    end;
    
    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
run;

/*------------------------------------------------------------------------------------*/
/* Step 3: Sort and apply labels                                                     */
/*------------------------------------------------------------------------------------*/
proc sort data=suppeg_base out=suppeg_sorted;
    by STUDYID RDOMAIN USUBJID IDVARVAL QNAM;
run;

data sdtm.SUPPEG;
    set suppeg_sorted;
    
    label
        STUDYID  = 'Study Identifier'
        RDOMAIN  = 'Related Domain Abbreviation'
        USUBJID  = 'Unique Subject Identifier'
        IDVAR    = 'Identifying Variable'
        IDVARVAL = 'Identifying Variable Value'
        QNAM     = 'Qualifier Variable Name'
        QLABEL   = 'Qualifier Variable Label'
        QVAL     = 'Data Value'
        QORIG    = 'Origin'
        QEVAL    = 'Evaluator'
    ;
run;

/*------------------------------------------------------------------------------------*/
/* Step 4: Create summary report                                                     */
/*------------------------------------------------------------------------------------*/
proc freq data=sdtm.SUPPEG;
    tables QNAM / missing;
    title "SUPPEG: Frequency of Qualifier Variables";
run;

proc sql;
    select count(*) as Total_Records,
           count(distinct USUBJID) as Unique_Subjects,
           count(distinct IDVARVAL) as Unique_Parent_Records
    from sdtm.SUPPEG;
    title "SUPPEG: Summary Counts";
quit;

title;

/*-- END SUPPEG --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.eg;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.eg varnum;
run;

proc freq data=sdtm.eg;
  tables DOMAIN / nocum nopercent;
run;

/* End of eg.sas */
