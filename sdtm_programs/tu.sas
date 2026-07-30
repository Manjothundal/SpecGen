/*******************************************************************************
* Program:    tu.sas
* Domain:     TU (Findings About Events)
* Purpose:    Create SDTM TU domain dataset
* Variables:  20
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.tu (source CRF data)
* Output:     sdtm.tu (TU domain dataset)
*
* Variables:  STUDYID, TUSEQ, USUBJID, DOMAIN, TUTESTCD, TUTEST, TUCAT, TUORRES
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN TU --*/
******************************************************************************;
* Program:      sdtm_tu.sas
* Description:  Create SDTM TU (Tumor/Lesion Identification) Domain
* Study:        [STUDY]
* Programmer:   [PROGRAMMER]
* Date:         [DATE]
******************************************************************************;

%let keepvars = STUDYID DOMAIN USUBJID TUSEQ TUTESTCD TUTEST TUCAT TUORRES 
                TUSTRESC TUSTRESN TUSTRESU TUEVAL TULNKID VISITNUM VISIT 
                TUDTC TUDY TULAT TULOC TUMETHOD;

* Read DM for STUDYID, USUBJID, RFSTDTC;
proc sort data=raw.dm out=dm(keep=STUDYID USUBJID RFSTDTC);
    by USUBJID;
run;

* Read raw TU data;
proc sort data=raw.tu out=tu_raw;
    by USUBJID;
run;

* Merge with DM to get reference start date;
data tu_pre;
    merge tu_raw(in=a)
          dm(in=b keep=STUDYID USUBJID RFSTDTC);
    by USUBJID;
    if a;
    
    length STUDYID $20
           DOMAIN $2 
           USUBJID $40
           TUTESTCD $8
           TUTEST $40
           TUCAT $200
           TUORRES $200
           TUSTRESC $200
           TUSTRESU $20
           TUEVAL $40
           TULNKID $200
           VISIT $200
           TUDTC $20
           TULAT $20
           TULOC $200
           TUMETHOD $200;
    
    * Set domain;
    DOMAIN = 'TU';
    
    * Map test code and test name based on measurement type;
    if upcase(strip(TESTCD)) = 'TUMIDENT' then do;
        TUTESTCD = 'TUMIDENT';
        TUTEST = 'Tumor Identification';
    end;
    else if upcase(strip(TESTCD)) = 'DIAMETER' then do;
        TUTESTCD = 'DIAMETER';
        TUTEST = 'Diameter';
    end;
    else if upcase(strip(TESTCD)) = 'LDIAM' then do;
        TUTESTCD = 'LDIAM';
        TUTEST = 'Longest Diameter';
    end;
    else if upcase(strip(TESTCD)) = 'PLDIAM' then do;
        TUTESTCD = 'PLDIAM';
        TUTEST = 'Perpendicular Diameter';
    end;
    else if upcase(strip(TESTCD)) = 'TUMSTATE' then do;
        TUTESTCD = 'TUMSTATE';
        TUTEST = 'Tumor State';
    end;
    else do;
        TUTESTCD = strip(TESTCD);
        TUTEST = strip(TEST);
    end;
    
    * Category for assessment;
    if not missing(CAT) then TUCAT = strip(CAT);
    
    * Original result;
    if not missing(ORRES) then TUORRES = strip(ORRES);
    
    * Standard character result;
    if not missing(ORRES) then TUSTRESC = strip(ORRES);
    
    * Numeric result;
    if not missing(STRESN) then TUSTRESN = STRESN;
    else if not missing(ORRES) and notdigit(compress(ORRES,'.-')) = 0 then 
        TUSTRESN = input(ORRES, ?? best.);
    
    * Standard units;
    if not missing(STRESU) then TUSTRESU = strip(STRESU);
    
    * Evaluator;
    if not missing(EVAL) then TUEVAL = strip(EVAL);
    
    * Link ID;
    if not missing(LNKID) then TULNKID = strip(LNKID);
    
    * Visit information;
    if not missing(VISITNUM_RAW) then VISITNUM = VISITNUM_RAW;
    if not missing(VISIT_RAW) then VISIT = strip(VISIT_RAW);
    
    * Date/Time of collection (ISO 8601);
    if not missing(DTC) then TUDTC = strip(DTC);
    
    * Study day;
    if not missing(TUDTC) and not missing(RFSTDTC) then do;
        if length(strip(TUDTC)) >= 10 and length(strip(RFSTDTC)) >= 10 then do;
            _tudt = input(substr(strip(TUDTC),1,10), ?? yymmdd10.);
            _rfstdt = input(substr(strip(RFSTDTC),1,10), ?? yymmdd10.);
            if not missing(_tudt) and not missing(_rfstdt) then do;
                if _tudt >= _rfstdt then TUDY = _tudt - _rfstdt + 1;
                else TUDY = _tudt - _rfstdt;
            end;
        end;
    end;
    
    * Laterality;
    if not missing(LAT) then TULAT = strip(LAT);
    
    * Location;
    if not missing(LOC) then TULOC = strip(LOC);
    
    * Method;
    if not missing(METHOD) then TUMETHOD = strip(METHOD);
    
    drop TESTCD TEST CAT ORRES STRESN STRESU EVAL LNKID 
         VISITNUM_RAW VISIT_RAW DTC LAT LOC METHOD
         RFSTDTC _tudt _rfstdt;
run;

* Derive sequence number;
proc sort data=tu_pre;
    by STUDYID USUBJID TUTESTCD VISITNUM TUDTC TULNKID;
run;

data sdtm.tu;
    set tu_pre;
    by STUDYID USUBJID;
    
    retain TUSEQ;
    
    if first.USUBJID then TUSEQ = 0;
    TUSEQ + 1;
    
    label STUDYID  = "Study Identifier"
          DOMAIN   = "Domain Abbreviation"
          USUBJID  = "Unique Subject Identifier"
          TUSEQ    = "Sequence Number"
          TUTESTCD = "Tumor Identification Test Short Name"
          TUTEST   = "Tumor Identification Test Name"
          TUCAT    = "Category for Tumor Identification"
          TUORRES  = "Result or Finding in Original Units"
          TUSTRESC = "Character Result/Finding in Std Format"
          TUSTRESN = "Numeric Result/Finding in Standard Units"
          TUSTRESU = "Standard Units"
          TUEVAL   = "Evaluator"
          TULNKID  = "Link ID"
          VISITNUM = "Visit Number"
          VISIT    = "Visit Name"
          TUDTC    = "Date/Time of Collection"
          TUDY     = "Study Day of Collection"
          TULAT    = "Laterality"
          TULOC    = "Location of the Tumor"
          TUMETHOD = "Method of Identification";
    
    keep &keepvars;
run;

* Final sort per SDTM IG;
proc sort data=sdtm.tu;
    by STUDYID USUBJID TUSEQ;
run;

* Generate summary report;
proc freq data=sdtm.tu;
    tables TUTESTCD*TUTEST TUCAT TUEVAL TUMETHOD TULAT / missing list;
    title "TU Domain - Frequency Summary";
run;

proc means data=sdtm.tu n nmiss min max mean median;
    var TUSEQ TUSTRESN VISITNUM TUDY;
    title "TU Domain - Numeric Variables Summary";
run;

title;

/*-- END TU --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.tu;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.tu varnum;
run;

proc freq data=sdtm.tu;
  tables DOMAIN / nocum nopercent;
run;

/* End of tu.sas */
