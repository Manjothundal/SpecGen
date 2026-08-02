/*******************************************************************************
* Program:    rs.sas
* Domain:     RS (Findings About Events)
* Purpose:    Create SDTM RS domain dataset
* Variables:  17
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.rs (source CRF data)
* Output:     sdtm.rs (RS domain dataset)
*
* Variables:  STUDYID, RSSEQ, USUBJID, DOMAIN, RSTESTCD, RSTEST, RSCAT, RSORRES
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN RS --*/
/*====================================================================================*/
/* Program Name: SDTM_RS.sas                                                          */
/* Domain: RS (Disease Response and Clinical Classification)                         */
/* Purpose: Create SDTM RS domain from raw data                                       */
/* Findings About Events class - tumor/response assessments                          */
/*====================================================================================*/

%let keepvars = STUDYID DOMAIN USUBJID RSSEQ RSTESTCD RSTEST RSCAT RSORRES 
                RSSTRESC RSSTRESN RSSTRESU RSEVAL RSLNKID VISITNUM VISIT 
                RSDTC RSDY;

* Read in DM for subject-level information;
proc sort data=raw.dm out=dm(keep=STUDYID USUBJID RFSTDTC);
    by STUDYID USUBJID;
run;

* Read raw RS data and merge with DM;
data rs_01;
    merge raw.rs(in=a)
          dm(in=b);
    by STUDYID USUBJID;
    if a;
    
    length STUDYID $20
           DOMAIN $2 
           USUBJID $40
           RSTESTCD $8 
           RSTEST $40 
           RSCAT $200
           RSORRES $200 
           RSSTRESC $200 
           RSSTRESU $20
           RSEVAL $40
           RSLNKID $200
           VISIT $200
           RSDTC $20;
    
    * Set Domain;
    DOMAIN = 'RS';
    
    * Map assessment test code and test name from source;
    RSTESTCD = upcase(strip(RSTESTCD));
    RSTEST = strip(RSTEST);
    
    * Map assessment category (e.g., RECIST 1.1);
    RSCAT = strip(RSCAT);
    
    * Map original result;
    RSORRES = strip(RSORRES);
    
    * Derive standard character result;
    * Standardize common response values;
    if upcase(RSORRES) in ('CR' 'COMPLETE RESPONSE') then RSSTRESC = 'CR';
    else if upcase(RSORRES) in ('PR' 'PARTIAL RESPONSE') then RSSTRESC = 'PR';
    else if upcase(RSORRES) in ('SD' 'STABLE DISEASE') then RSSTRESC = 'SD';
    else if upcase(RSORRES) in ('PD' 'PROGRESSIVE DISEASE') then RSSTRESC = 'PD';
    else if upcase(RSORRES) in ('NE' 'NOT EVALUABLE') then RSSTRESC = 'NE';
    else if upcase(RSORRES) in ('NA' 'NOT APPLICABLE') then RSSTRESC = 'NA';
    else if upcase(RSORRES) in ('ND' 'NOT DONE') then RSSTRESC = 'ND';
    else if upcase(RSORRES) in ('NR' 'NON-CR/NON-PD') then RSSTRESC = 'NON-CR/NON-PD';
    else if not missing(RSORRES) then RSSTRESC = strip(upcase(RSORRES));
    
    * Derive numeric result if applicable;
    if not missing(RSORRES) then RSSTRESN = input(RSORRES, ?? best.);
    
    * Map standard units;
    if not missing(RSSTRESU) then RSSTRESU = strip(RSSTRESU);
    
    * Map evaluator;
    if upcase(RSEVAL) = 'INV' then RSEVAL = 'INVESTIGATOR';
    else if upcase(RSEVAL) in ('IRC' 'INDEPENDENT') then RSEVAL = 'INDEPENDENT ASSESSOR';
    else if not missing(RSEVAL) then RSEVAL = strip(upcase(RSEVAL));
    
    * Map link ID for connecting to TU/TR domains;
    if not missing(RSLNKID) then RSLNKID = strip(RSLNKID);
    
    * Map visit information;
    if not missing(VISIT) then VISIT = strip(VISIT);
    
    * Map collection date/time in ISO 8601 format;
    if not missing(RSDTC) then RSDTC = strip(RSDTC);
    
    * Derive study day;
    if not missing(RSDTC) and not missing(RFSTDTC) then do;
        if length(strip(RSDTC)) >= 10 and length(strip(RFSTDTC)) >= 10 then do;
            _rsdt = input(substr(RSDTC,1,10), ?? yymmdd10.);
            _rfstdt = input(substr(RFSTDTC,1,10), ?? yymmdd10.);
            if not missing(_rsdt) and not missing(_rfstdt) then do;
                if _rsdt >= _rfstdt then RSDY = _rsdt - _rfstdt + 1;
                else RSDY = _rsdt - _rfstdt;
            end;
        end;
    end;
    
    drop _rsdt _rfstdt RFSTDTC;
run;

* Sort by subject and visit;
proc sort data=rs_01;
    by STUDYID USUBJID RSTESTCD VISITNUM RSDTC;
run;

* Derive sequence number;
data rs_02;
    set rs_01;
    by STUDYID USUBJID;
    
    retain RSSEQ;
    
    if first.USUBJID then RSSEQ = 0;
    RSSEQ + 1;
run;

* Final sort by STUDYID USUBJID RSSEQ;
proc sort data=rs_02;
    by STUDYID USUBJID RSSEQ;
run;

* Create final RS domain dataset with labels;
data sdtm.rs(label="Disease Response and Clinical Classification");
    retain STUDYID DOMAIN USUBJID RSSEQ RSTESTCD RSTEST RSCAT RSORRES 
           RSSTRESC RSSTRESN RSSTRESU RSEVAL RSLNKID VISITNUM VISIT 
           RSDTC RSDY;
    set rs_02;
    
    label STUDYID  = "Study Identifier"
          DOMAIN   = "Domain Abbreviation"
          USUBJID  = "Unique Subject Identifier"
          RSSEQ    = "Sequence Number"
          RSTESTCD = "Disease Response or Assessment Short Name"
          RSTEST   = "Disease Response or Assessment Name"
          RSCAT    = "Category for Disease Response"
          RSORRES  = "Result or Finding in Original Units"
          RSSTRESC = "Character Result/Finding in Std Format"
          RSSTRESN = "Numeric Result/Finding in Standard Units"
          RSSTRESU = "Standard Units"
          RSEVAL   = "Evaluator"
          RSLNKID  = "Link ID"
          VISITNUM = "Visit Number"
          VISIT    = "Visit Name"
          RSDTC    = "Date/Time of Collection"
          RSDY     = "Study Day of Collection";
    
    keep &keepvars;
run;

* Generate summary report;
proc freq data=sdtm.rs;
    tables RSTESTCD * RSSTRESC / missing list;
    tables RSCAT * RSEVAL / missing list;
    title "RS Domain Frequency Counts";
run;

proc means data=sdtm.rs n nmiss min max;
    var RSSEQ VISITNUM RSDY RSSTRESN;
    title "RS Domain Numeric Variable Summary";
run;

title;
/*-- END RS --*/


/*-- BEGIN SUPPRS --*/
******************************************************************************;
* Program:       supprs.sas                                                   *
* Description:   Create SUPPRS (Supplemental Qualifiers for RS) domain       *
* Parent Domain: RS                                                           *
******************************************************************************;

%let studyid = XXXX;  /* Update with actual study identifier */

* Merge raw RS data with SDTM RS to get RSSEQ values;
proc sort data=raw.rs out=rs_raw;
    by studyid usubjid rstestcd rsdtc visitnum;
run;

proc sort data=sdtm.rs out=rs_sdtm(keep=studyid usubjid rsseq rstestcd rsdtc visitnum);
    by studyid usubjid rstestcd rsdtc visitnum;
run;

* Merge to get RSSEQ;
data rs_merged;
    merge rs_raw(in=a)
          rs_sdtm(in=b);
    by studyid usubjid rstestcd rsdtc visitnum;
    if a and b;
run;

* Transpose qualifier variables into QNAM/QVAL structure;
data supprs_01;
    length STUDYID $20 RDOMAIN $2 USUBJID $40 IDVAR $8 IDVARVAL $40 
           QNAM $8 QLABEL $40 QVAL $200 QORIG $20 QEVAL $20;
    
    set rs_merged;
    
    RDOMAIN = 'RS';
    IDVAR = 'RSSEQ';
    IDVARVAL = put(RSSEQ, best.);
    QORIG = 'CRF';
    QEVAL = '';
    
    * RSBORRESP;
    if not missing(rsborresp) then do;
        QNAM = 'RSBORRESP';
        QLABEL = 'Best Overall Response: CR PR SD PD';
        QVAL = strip(rsborresp);
        output;
    end;
    
    * RSCONFDTC;
    if not missing(rsconfdtc) then do;
        QNAM = 'RSCONFDTC';
        QLABEL = 'Date of Confirmation';
        QVAL = strip(put(input(rsconfdtc, ?? yymmdd10.), is8601da.));
        if missing(QVAL) then QVAL = strip(rsconfdtc);
        output;
    end;
    
    * RSCONFYN;
    if not missing(rsconfyn) then do;
        QNAM = 'RSCONFYN';
        QLABEL = 'Confirmed Response?: Yes No';
        QVAL = strip(rsconfyn);
        output;
    end;
    
    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
run;

* Sort and apply variable labels to final dataset;
proc sort data=supprs_01 out=sdtm.supprs;
    by STUDYID RDOMAIN USUBJID IDVARVAL QNAM;
run;

data sdtm.supprs;
    length STUDYID $20 RDOMAIN $2 USUBJID $40 IDVAR $8 IDVARVAL $40 
           QNAM $8 QLABEL $40 QVAL $200 QORIG $20 QEVAL $20;
    
    set sdtm.supprs;
    
    label
        STUDYID  = "Study Identifier"
        RDOMAIN  = "Related Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        IDVAR    = "Identifying Variable"
        IDVARVAL = "Identifying Variable Value"
        QNAM     = "Qualifier Variable Name"
        QLABEL   = "Qualifier Variable Label"
        QVAL     = "Data Value"
        QORIG    = "Origin"
        QEVAL    = "Evaluator"
    ;
run;

* Print summary statistics;
proc freq data=sdtm.supprs;
    tables QNAM / nocum;
    title "SUPPRS: Frequency of Qualifier Variables";
run;

proc contents data=sdtm.supprs varnum;
    title "SUPPRS: Dataset Contents";
run;

title;
/*-- END SUPPRS --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.rs;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.rs varnum;
run;

proc freq data=sdtm.rs;
  tables DOMAIN / nocum nopercent;
run;

/* End of rs.sas */
