/*******************************************************************************
* Program:    tr.sas
* Domain:     TR (Findings About Events)
* Purpose:    Create SDTM TR domain dataset
* Variables:  17
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.tr (source CRF data)
* Output:     sdtm.tr (TR domain dataset)
*
* Variables:  STUDYID, TRSEQ, USUBJID, DOMAIN, TRTESTCD, TRTEST, TRCAT, TRORRES
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*===========================================================================*/
/* Program Name: SDTM_TR.sas                                                 */
/* Description:  Create SDTM TR domain (Tumor Response Assessments)          */
/* Domain:       TR (Findings About Events)                                  */
/*===========================================================================*/

/*-- BEGIN TR --*/

%let keepvars = STUDYID DOMAIN USUBJID TRSEQ TRTESTCD TRTEST TRCAT 
                TRORRES TRSTRESC TRSTRESN TRSTRESU TREVAL TRLNKID 
                VISITNUM VISIT TRDTC TRDY;

* Read DM domain for subject-level data;
proc sort data=raw.dm out=dm(keep=STUDYID USUBJID RFSTDTC);
    by STUDYID USUBJID;
run;

* Read raw TR data;
data tr_raw;
    set raw.tr;
run;

* Sort raw TR data;
proc sort data=tr_raw;
    by STUDYID USUBJID;
run;

* Merge with DM and create TR domain;
data tr_pre;
    merge tr_raw(in=a)
          dm(in=b);
    by STUDYID USUBJID;
    if a;
    
    length STUDYID $20 DOMAIN $2 USUBJID $40 TRTESTCD $8 TRTEST $40 
           TRCAT $200 TRORRES $200 TRSTRESC $200 TRSTRESU $20 
           TREVAL $40 TRLNKID $200 VISIT $200 TRDTC $20;
    
    * Set domain;
    DOMAIN = 'TR';
    
    * Map test code and test name;
    TRTESTCD = upcase(strip(TRTESTCD));
    TRTEST = strip(TRTEST);
    
    * Map category;
    TRCAT = strip(TRCAT);
    
    * Map original results;
    TRORRES = strip(TRORRES);
    
    * Derive character result in standard format;
    if not missing(TRORRES) then TRSTRESC = strip(TRORRES);
    else TRSTRESC = '';
    
    * Derive numeric result;
    if not missing(TRSTRESN) then TRSTRESN = TRSTRESN;
    else if not missing(TRORRES) and notdigit(compress(TRORRES)) = 0 then 
        TRSTRESN = input(TRORRES, ?best.);
    
    * Map standard units;
    TRSTRESU = strip(TRSTRESU);
    
    * Map evaluator;
    TREVAL = strip(TREVAL);
    
    * Map link ID;
    TRLNKID = strip(TRLNKID);
    
    * Map visit information;
    if not missing(VISITNUM) then VISITNUM = VISITNUM;
    VISIT = strip(VISIT);
    
    * Map date/time of collection (ISO 8601);
    TRDTC = strip(TRDTC);
    
    * Derive study day;
    if not missing(TRDTC) and not missing(RFSTDTC) and 
       length(strip(TRDTC)) >= 10 and length(strip(RFSTDTC)) >= 10 then do;
        length trdtc_num rfstdtc_num 8;
        trdtc_num = input(substr(strip(TRDTC),1,10), ??yymmdd10.);
        rfstdtc_num = input(substr(strip(RFSTDTC),1,10), ??yymmdd10.);
        
        if not missing(trdtc_num) and not missing(rfstdtc_num) then do;
            if trdtc_num >= rfstdtc_num then 
                TRDY = trdtc_num - rfstdtc_num + 1;
            else 
                TRDY = trdtc_num - rfstdtc_num;
        end;
        
        drop trdtc_num rfstdtc_num;
    end;
    
    * Drop RFSTDTC as it's not part of TR domain;
    drop RFSTDTC;
run;

* Sort for TRSEQ assignment;
proc sort data=tr_pre;
    by STUDYID USUBJID TRTESTCD VISITNUM TRDTC TRLNKID;
run;

* Assign sequence number;
data tr_seq;
    set tr_pre;
    by STUDYID USUBJID;
    
    retain TRSEQ;
    
    if first.USUBJID then TRSEQ = 1;
    else TRSEQ + 1;
run;

* Apply labels and create final dataset;
data sdtm.tr;
    retain &keepvars;
    set tr_seq;
    
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        TRSEQ    = "Sequence Number"
        TRTESTCD = "Tumor Response Test Short Name"
        TRTEST   = "Tumor Response Test Name"
        TRCAT    = "Category for Tumor Response"
        TRORRES  = "Result or Finding in Original Units"
        TRSTRESC = "Character Result/Finding in Std Format"
        TRSTRESN = "Numeric Result/Finding in Standard Units"
        TRSTRESU = "Standard Units"
        TREVAL   = "Evaluator"
        TRLNKID  = "Link ID"
        VISITNUM = "Visit Number"
        VISIT    = "Visit Name"
        TRDTC    = "Date/Time of Collection"
        TRDY     = "Study Day of Collection"
    ;
    
    keep &keepvars;
run;

* Final sort;
proc sort data=sdtm.tr;
    by STUDYID USUBJID TRSEQ;
run;

* Generate contents and print first 10 records;
proc contents data=sdtm.tr varnum;
run;

proc print data=sdtm.tr(obs=10) label;
run;

/*-- END TR --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.tr;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.tr varnum;
run;

proc freq data=sdtm.tr;
  tables DOMAIN / nocum nopercent;
run;

/* End of tr.sas */
