/*******************************************************************************
* Program:    vs.sas
* Domain:     VS (Findings)
* Purpose:    Create SDTM VS domain dataset
* Variables:  19
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.vs (source CRF data)
* Output:     sdtm.vs (VS domain dataset)
*
* Variables:  STUDYID, VSSEQ, USUBJID, DOMAIN, VSTESTCD, VSTEST, VSCAT, VSORRES
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*=======================================================================================
  Program:      VS_SDTM.sas
  Description:  Create SDTM VS (Vital Signs) domain
  Input:        raw.vs, raw.dm
  Output:       sdtm.vs
=======================================================================================*/

/*-- BEGIN VS --*/

*-- Read in DM data for USUBJID, STUDYID, and RFSTDTC --;
proc sort data=raw.dm out=dm_for_vs;
    by STUDYID SITEID SUBJID;
run;

data dm_for_vs;
    set dm_for_vs;
    keep STUDYID SITEID SUBJID USUBJID RFSTDTC;
run;

*-- Read and transpose source VS data to vertical format --;
data vs_raw;
    set raw.vs;
run;

*-- Check if data is in wide format and transpose if needed --;
*-- Assume raw.vs contains: STUDYID, SITEID, SUBJID, VISITNUM, VISIT, VSDTC, VSPOS,
   and vital signs parameters (SYSBP, DIABP, PULSE, TEMP, RESP, WEIGHT, HEIGHT) --;

proc transpose data=vs_raw out=vs_vert(rename=(col1=VSORRES _NAME_=VSTESTCD));
    by STUDYID SITEID SUBJID VISITNUM VISIT VSDTC VSPOS;
    var SYSBP DIABP PULSE TEMP RESP WEIGHT HEIGHT;
run;

*-- Merge with DM to get USUBJID and RFSTDTC --;
proc sort data=vs_vert;
    by STUDYID SITEID SUBJID;
run;

data vs_merge;
    length STUDYID $20 DOMAIN $2 USUBJID $40 VSTESTCD $8 VSTEST $40 VSCAT $40
           VSORRES $200 VSORRESU $40 VSSTRESC $200 VSSTRESN 8 VSSTRESU $40
           VSSTAT $8 VSREASND $200 VISITNUM 8 VISIT $40 VSDTC $20 VSDY 8 VSPOS $40;
    
    merge vs_vert(in=a)
          dm_for_vs(in=b);
    by STUDYID SITEID SUBJID;
    if a;
    
    *-- If USUBJID is not in source data, derive it --;
    if missing(USUBJID) then USUBJID = catx('-', STUDYID, SITEID, SUBJID);
    
    *-- Set DOMAIN --;
    DOMAIN = 'VS';
    
    *-- Set VSCAT --;
    VSCAT = 'VITAL SIGNS';
    
    *-- Map VSTESTCD to VSTEST --;
    select (upcase(VSTESTCD));
        when ('SYSBP')   VSTEST = 'Systolic Blood Pressure';
        when ('DIABP')   VSTEST = 'Diastolic Blood Pressure';
        when ('PULSE')   VSTEST = 'Pulse Rate';
        when ('TEMP')    VSTEST = 'Temperature';
        when ('RESP')    VSTEST = 'Respiratory Rate';
        when ('WEIGHT')  VSTEST = 'Weight';
        when ('HEIGHT')  VSTEST = 'Height';
        otherwise        VSTEST = VSTESTCD;
    end;
    
    *-- Derive original units --;
    select (upcase(VSTESTCD));
        when ('SYSBP', 'DIABP') VSORRESU = 'mmHg';
        when ('PULSE')          VSORRESU = 'beats/min';
        when ('TEMP')           VSORRESU = 'C';
        when ('RESP')           VSORRESU = 'breaths/min';
        when ('WEIGHT')         VSORRESU = 'kg';
        when ('HEIGHT')         VSORRESU = 'cm';
        otherwise               VSORRESU = '';
    end;
    
    *-- Handle NOT DONE status and reason not done --;
    if missing(VSORRES) or upcase(strip(VSORRES)) in ('ND' 'NOT DONE' 'NOT PERFORMED') then do;
        VSSTAT = 'NOT DONE';
        if upcase(strip(VSORRES)) in ('ND' 'NOT DONE' 'NOT PERFORMED') then VSREASND = strip(VSORRES);
        VSORRES = '';
    end;
    
    *-- Derive VSSTRESC (character result in standard format) --;
    if VSSTAT ne 'NOT DONE' then do;
        VSSTRESC = strip(VSORRES);
    end;
    else VSSTRESC = '';
    
    *-- Derive VSSTRESN (numeric result) --;
    if VSSTAT ne 'NOT DONE' and not missing(VSSTRESC) then do;
        VSSTRESN = input(VSSTRESC, ?? best.);
    end;
    
    *-- Derive standard units (same as original for this example) --;
    if VSSTAT ne 'NOT DONE' then do;
        VSSTRESU = VSORRESU;
    end;
    
    *-- Derive study day (VSDY) --;
    if not missing(VSDTC) and not missing(RFSTDTC) then do;
        if length(strip(VSDTC)) >= 10 and length(strip(RFSTDTC)) >= 10 then do;
            _vsdate = input(substr(VSDTC,1,10), yymmdd10.);
            _rfstdate = input(substr(RFSTDTC,1,10), yymmdd10.);
            if not missing(_vsdate) and not missing(_rfstdate) then do;
                if _vsdate >= _rfstdate then 
                    VSDY = _vsdate - _rfstdate + 1;
                else 
                    VSDY = _vsdate - _rfstdate;
            end;
        end;
    end;
    
    drop SITEID SUBJID RFSTDTC _vsdate _rfstdate;
run;

*-- Sort by subject and visit --;
proc sort data=vs_merge;
    by USUBJID VSTESTCD VISITNUM VSDTC;
run;

*-- Derive VSSEQ --;
data vs_seq;
    set vs_merge;
    by USUBJID;
    
    retain VSSEQ;
    
    if first.USUBJID then VSSEQ = 1;
    else VSSEQ + 1;
run;

*-- Sort final dataset --;
proc sort data=vs_seq;
    by STUDYID USUBJID VSSEQ;
run;

*-- Create final VS domain with proper variable order and attributes --;
data sdtm.vs;
    attrib
        STUDYID  length=$20   label='Study Identifier'
        DOMAIN   length=$2    label='Domain Abbreviation'
        USUBJID  length=$40   label='Unique Subject Identifier'
        VSSEQ    length=8     label='Sequence Number'
        VSTESTCD length=$8    label='Vital Signs Test Short Name'
        VSTEST   length=$40   label='Vital Signs Test Name'
        VSCAT    length=$40   label='Category for Vital Signs'
        VSORRES  length=$200  label='Result or Finding in Original Units'
        VSORRESU length=$40   label='Original Units'
        VSSTRESC length=$200  label='Character Result/Finding in Std Format'
        VSSTRESN length=8     label='Numeric Result/Finding in Standard Units'
        VSSTRESU length=$40   label='Standard Units'
        VSSTAT   length=$8    label='Completion Status'
        VSREASND length=$200  label='Reason Not Done'
        VISITNUM length=8     label='Visit Number'
        VISIT    length=$40   label='Visit Name'
        VSDTC    length=$20   label='Date/Time of Measurements'
        VSDY     length=8     label='Study Day of Vital Signs'
        VSPOS    length=$40   label='Vital Signs Position of Subject'
    ;
    
    set vs_seq;
    
    keep STUDYID DOMAIN USUBJID VSSEQ VSTESTCD VSTEST VSCAT VSORRES VSORRESU 
         VSSTRESC VSSTRESN VSSTRESU VSSTAT VSREASND VISITNUM VISIT VSDTC VSDY VSPOS;
run;

*-- Generate summary report --;
proc freq data=sdtm.vs;
    tables VSTESTCD*VSTEST / list missing;
    tables VSSTAT / missing;
    title 'VS Domain: Frequency of Tests and Completion Status';
run;

proc means data=sdtm.vs n nmiss min max mean median;
    var VSSTRESN VSDY;
    class VSTESTCD;
    title 'VS Domain: Summary Statistics for Numeric Results';
run;

title;

/*-- END VS --*/


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
proc sort data=sdtm.vs;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.vs varnum;
run;

proc freq data=sdtm.vs;
  tables DOMAIN / nocum nopercent;
run;

/* End of vs.sas */
