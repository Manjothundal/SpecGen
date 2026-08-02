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
  Program Name    : sdtm_vs.sas
  Study           : [Study Name]
  Author          : [Author Name]
  Date Created    : [Date]
  Description     : Create SDTM VS (Vital Signs) domain from raw data
  Input Datasets  : raw.vs, sdtm.dm
  Output Dataset  : sdtm.vs
=======================================================================================*/

/*-- BEGIN VS --*/

*-----------------------------------------------------------------------------*
* Step 1: Read DM dataset for reference dates and subject identifiers
*-----------------------------------------------------------------------------*;
proc sort data=sdtm.dm(keep=studyid usubjid rfstdtc) out=dm nodupkey;
    by usubjid;
run;

*-----------------------------------------------------------------------------*
* Step 2: Read raw VS data and transpose if needed (assuming wide format)
*-----------------------------------------------------------------------------*;
data vs_raw;
    set raw.vs;
    
    * Keep relevant variables from raw data;
    * Assuming raw structure includes: STUDYID, SITEID, SUBJID, VISIT, VISITNUM, 
      VSDAT, VSTIM, VSPOS, SYSBP, DIABP, PULSE, RESP, TEMP, WEIGHT, HEIGHT, etc.;
run;

*-----------------------------------------------------------------------------*
* Step 3: Transpose wide format to vertical (one row per test per timepoint)
*-----------------------------------------------------------------------------*;
data vs_vertical;
    set vs_raw;
    
    length VSTESTCD $8 VSTEST $40 VSORRES $200 VSORRESU $40 VSPOS_FINAL $40;
    
    * Derive USUBJID if not already present;
    length USUBJID $40;
    if missing(usubjid) then usubjid = catx('-', studyid, siteid, subjid);
    
    * Create position variable;
    VSPOS_FINAL = vspos;
    
    * Systolic Blood Pressure;
    if not missing(sysbp) then do;
        VSTESTCD = 'SYSBP';
        VSTEST = 'Systolic Blood Pressure';
        VSORRES = strip(put(sysbp, best.));
        VSORRESU = 'mmHg';
        output;
    end;
    else if sysbp = . and not missing(vsreasnd) then do;
        VSTESTCD = 'SYSBP';
        VSTEST = 'Systolic Blood Pressure';
        VSORRES = '';
        VSORRESU = 'mmHg';
        output;
    end;
    
    * Diastolic Blood Pressure;
    if not missing(diabp) then do;
        VSTESTCD = 'DIABP';
        VSTEST = 'Diastolic Blood Pressure';
        VSORRES = strip(put(diabp, best.));
        VSORRESU = 'mmHg';
        output;
    end;
    else if diabp = . and not missing(vsreasnd) then do;
        VSTESTCD = 'DIABP';
        VSTEST = 'Diastolic Blood Pressure';
        VSORRES = '';
        VSORRESU = 'mmHg';
        output;
    end;
    
    * Pulse/Heart Rate;
    if not missing(pulse) then do;
        VSTESTCD = 'PULSE';
        VSTEST = 'Pulse Rate';
        VSORRES = strip(put(pulse, best.));
        VSORRESU = 'beats/min';
        output;
    end;
    else if pulse = . and not missing(vsreasnd) then do;
        VSTESTCD = 'PULSE';
        VSTEST = 'Pulse Rate';
        VSORRES = '';
        VSORRESU = 'beats/min';
        output;
    end;
    
    * Respiratory Rate;
    if not missing(resp) then do;
        VSTESTCD = 'RESP';
        VSTEST = 'Respiratory Rate';
        VSORRES = strip(put(resp, best.));
        VSORRESU = 'breaths/min';
        output;
    end;
    else if resp = . and not missing(vsreasnd) then do;
        VSTESTCD = 'RESP';
        VSTEST = 'Respiratory Rate';
        VSORRES = '';
        VSORRESU = 'breaths/min';
        output;
    end;
    
    * Temperature;
    if not missing(temp) then do;
        VSTESTCD = 'TEMP';
        VSTEST = 'Temperature';
        VSORRES = strip(put(temp, best.));
        VSORRESU = 'C';
        output;
    end;
    else if temp = . and not missing(vsreasnd) then do;
        VSTESTCD = 'TEMP';
        VSTEST = 'Temperature';
        VSORRES = '';
        VSORRESU = 'C';
        output;
    end;
    
    * Weight;
    if not missing(weight) then do;
        VSTESTCD = 'WEIGHT';
        VSTEST = 'Weight';
        VSORRES = strip(put(weight, best.));
        VSORRESU = 'kg';
        output;
    end;
    else if weight = . and not missing(vsreasnd) then do;
        VSTESTCD = 'WEIGHT';
        VSTEST = 'Weight';
        VSORRES = '';
        VSORRESU = 'kg';
        output;
    end;
    
    * Height;
    if not missing(height) then do;
        VSTESTCD = 'HEIGHT';
        VSTEST = 'Height';
        VSORRES = strip(put(height, best.));
        VSORRESU = 'cm';
        output;
    end;
    else if height = . and not missing(vsreasnd) then do;
        VSTESTCD = 'HEIGHT';
        VSTEST = 'Height';
        VSORRES = '';
        VSORRESU = 'cm';
        output;
    end;
    
    keep usubjid studyid vstestcd vstest vsorres vsorresu visitnum visit 
         vsdat vstim vspos_final vsreasnd;
run;

*-----------------------------------------------------------------------------*
* Step 4: Merge with DM for reference start date
*-----------------------------------------------------------------------------*;
proc sort data=vs_vertical;
    by usubjid;
run;

data vs_merged;
    merge vs_vertical(in=a)
          dm(in=b);
    by usubjid;
    if a;
    
    length DOMAIN $2 VSCAT $40 VSSTRESC $200 VSSTRESU $40 
           VSDTC $20 VSSTAT $8;
    
    * Set domain;
    DOMAIN = 'VS';
    
    * Set category;
    VSCAT = 'VITAL SIGNS';
    
    * Create date/time of collection in ISO 8601 format;
    if not missing(vsdat) then do;
        if not missing(vstim) then 
            VSDTC = put(vsdat, yymmdd10.) || 'T' || put(vstim, time5.);
        else 
            VSDTC = put(vsdat, yymmdd10.);
    end;
    else VSDTC = '';
    
    * Derive completion status and handle not done;
    if missing(vsorres) and not missing(vsreasnd) then do;
        VSSTAT = 'NOT DONE';
    end;
    else do;
        VSSTAT = '';
    end;
    
    * Derive standardized character result;
    if VSSTAT ne 'NOT DONE' then VSSTRESC = vsorres;
    else VSSTRESC = '';
    
    * Derive standard units (same as original for this example);
    VSSTRESU = vsorresu;
    
    * Derive numeric result;
    VSSTRESN = .;
    if not missing(vsorres) and VSSTAT ne 'NOT DONE' then do;
        VSSTRESN = input(vsorres, ?? best.);
    end;
    
    * Apply unit conversions if needed;
    * Example: Convert temperature from F to C if needed;
    if vstestcd = 'TEMP' and upcase(vsorresu) = 'F' and not missing(VSSTRESN) then do;
        VSSTRESN = (VSSTRESN - 32) * 5/9;
        VSSTRESU = 'C';
        VSSTRESC = strip(put(VSSTRESN, 8.1));
    end;
    
    * Derive study day;
    VSDY = .;
    if not missing(vsdat) and not missing(rfstdtc) then do;
        _rfstdt = input(scan(rfstdtc,1,'T'), ?? yymmdd10.);
        if not missing(_rfstdt) then do;
            if vsdat >= _rfstdt then
                VSDY = vsdat - _rfstdt + 1;
            else
                VSDY = vsdat - _rfstdt;
        end;
    end;
    
    * Rename position variable;
    VSPOS = vspos_final;
    
    drop rfstdtc vsdat vstim vspos_final _rfstdt;
run;

*-----------------------------------------------------------------------------*
* Step 5: Derive sequence number
*-----------------------------------------------------------------------------*;
proc sort data=vs_merged;
    by studyid usubjid vstestcd visitnum vsdtc;
run;

data vs_seq;
    set vs_merged;
    by studyid usubjid;
    
    retain VSSEQ;
    
    if first.usubjid then VSSEQ = 0;
    VSSEQ + 1;
run;

*-----------------------------------------------------------------------------*
* Step 6: Final dataset with proper attributes and sort order
*-----------------------------------------------------------------------------*;
data sdtm.vs;
    retain
        STUDYID
        DOMAIN
        USUBJID
        VSSEQ
        VSTESTCD
        VSTEST
        VSCAT
        VSORRES
        VSORRESU
        VSSTRESC
        VSSTRESN
        VSSTRESU
        VSSTAT
        VSREASND
        VISITNUM
        VISIT
        VSDTC
        VSDY
        VSPOS;
    
    * Set variable lengths explicitly;
    length
        STUDYID  $20
        DOMAIN   $2
        USUBJID  $40
        VSSEQ    8
        VSTESTCD $8
        VSTEST   $40
        VSCAT    $40
        VSORRES  $200
        VSORRESU $40
        VSSTRESC $200
        VSSTRESN 8
        VSSTRESU $40
        VSSTAT   $8
        VSREASND $200
        VISITNUM 8
        VISIT    $40
        VSDTC    $20
        VSDY     8
        VSPOS    $40
    ;
    
    set vs_seq;
    
    * Apply labels;
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        VSSEQ    = "Sequence Number"
        VSTESTCD = "Vital Signs Test Short Name"
        VSTEST   = "Vital Signs Test Name"
        VSCAT    = "Category for Vital Signs"
        VSORRES  = "Result or Finding in Original Units"
        VSORRESU = "Original Units"
        VSSTRESC = "Character Result/Finding in Std Format"
        VSSTRESN = "Numeric Result/Finding in Standard Units"
        VSSTRESU = "Standard Units"
        VSSTAT   = "Completion Status"
        VSREASND = "Reason Not Done"
        VISITNUM = "Visit Number"
        VISIT    = "Visit Name"
        VSDTC    = "Date/Time of Vital Signs"
        VSDY     = "Study Day of Vital Signs"
        VSPOS    = "Vital Signs Position of Subject"
    ;
    
    * Keep only required variables;
    keep
        STUDYID
        DOMAIN
        USUBJID
        VSSEQ
        VSTESTCD
        VSTEST
        VSCAT
        VSORRES
        VSORRESU
        VSSTRESC
        VSSTRESN
        VSSTRESU
        VSSTAT
        VSREASND
        VISITNUM
        VISIT
        VSDTC
        VSDY
        VSPOS
    ;
run;

*-----------------------------------------------------------------------------*
* Step 7: Final sort by STUDYID USUBJID VSTESTCD VISITNUM VSDTC VSSEQ
*-----------------------------------------------------------------------------*;
proc sort data=sdtm.vs;
    by studyid usubjid vstestcd visitnum vsdtc vsseq;
run;

*-----------------------------------------------------------------------------*
* Step 8: Create summary report
*-----------------------------------------------------------------------------*;
proc freq data=sdtm.vs;
    tables vstestcd*vstest / list missing;
    tables vsstat / missing;
    title "VS Domain - Frequency of Tests and Completion Status";
run;

proc means data=sdtm.vs n nmiss min max mean std;
    var vsstresn vsdy;
    class vstestcd;
    title "VS Domain - Numeric Results Summary";
run;

title;

/*-- END VS --*/


/*-- BEGIN SUPPVS --*/

*----------------------------------------------------------------*
* Program: suppvs.sas
* Purpose: Create SUPPVS supplemental qualifiers domain
* Domain:  SUPPVS (Supplemental Qualifiers for VS)
*----------------------------------------------------------------*;

*----------------------------------------------------------------*
* Step 1: Merge parent VS source with SDTM VS to get VSSEQ
*----------------------------------------------------------------*;
proc sort data=raw.vs out=vs_raw;
    by studyid usubjid vstestcd visitnum vstptnum;
run;

proc sort data=sdtm.vs out=vs_sdtm(keep=studyid usubjid vstestcd visitnum vstptnum vsseq);
    by studyid usubjid vstestcd visitnum vstptnum;
run;

data vs_combined;
    merge vs_raw(in=a)
          vs_sdtm(in=b);
    by studyid usubjid vstestcd visitnum vstptnum;
    if a and b;
run;

*----------------------------------------------------------------*
* Step 2: Transpose qualifier variables into QNAM/QVAL structure
*----------------------------------------------------------------*;
data suppvs_all;
    set vs_combined;
    
    length STUDYID $200
           RDOMAIN $8
           USUBJID $200
           IDVAR $8
           IDVARVAL $200
           QNAM $8
           QLABEL $200
           QVAL $200
           QORIG $8
           QEVAL $200;
    
    RDOMAIN = 'VS';
    IDVAR = 'VSSEQ';
    IDVARVAL = put(vsseq, best.);
    
    * VSCLSIG - Clinically Significant *;
    if not missing(vsclsig) then do;
        QNAM = 'VSCLSIG';
        QLABEL = 'Clinically Significant';
        QVAL = strip(vsclsig);
        QORIG = 'CRF';
        QEVAL = '';
        output;
    end;
    
    * VSFAST - Fasting Status *;
    if not missing(vsfast) then do;
        QNAM = 'VSFAST';
        QLABEL = 'Fasting Status';
        QVAL = strip(vsfast);
        QORIG = 'CRF';
        QEVAL = '';
        output;
    end;
    
    * VSLOC - Location of Measurement *;
    if not missing(vsloc) then do;
        QNAM = 'VSLOC';
        QLABEL = 'Location of Vital Signs Measurement';
        QVAL = strip(vsloc);
        QORIG = 'CRF';
        QEVAL = '';
        output;
    end;
    
    keep studyid rdomain usubjid idvar idvarval qnam qlabel qval qorig qeval;
run;

*----------------------------------------------------------------*
* Step 3: Apply variable attributes and sort
*----------------------------------------------------------------*;
data sdtm.suppvs;
    retain STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
    
    length STUDYID $200
           RDOMAIN $8
           USUBJID $200
           IDVAR $8
           IDVARVAL $200
           QNAM $8
           QLABEL $200
           QVAL $200
           QORIG $8
           QEVAL $200;
    
    set suppvs_all;
    
    * Ensure QVAL is non-missing *;
    if not missing(qval);
    
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

proc sort data=sdtm.suppvs;
    by studyid rdomain usubjid idvarval qnam;
run;

*----------------------------------------------------------------*
* Step 4: Cleanup temporary datasets
*----------------------------------------------------------------*;
proc datasets library=work nolist;
    delete vs_raw vs_sdtm vs_combined suppvs_all;
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
