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
/* Program Name: TR.sas                                                      */
/* Description:  Create SDTM TR (Tumor/Lesion Results) Domain                */
/*===========================================================================*/

/*-- BEGIN TR --*/

****************************************************************************;
** Read source TR data and merge with DM for subject-level variables      **;
****************************************************************************;

proc sort data=raw.dm(keep=usubjid studyid rfstdtc) out=dm nodupkey;
    by usubjid;
run;

proc sort data=raw.tr out=tr_src;
    by usubjid;
run;

data tr_merged;
    merge tr_src(in=a)
          dm(in=b);
    by usubjid;
    if a and b;
run;

****************************************************************************;
** Create TR domain                                                        **;
****************************************************************************;

data sdtm.tr;
    set tr_merged;
    by usubjid;
    
    length STUDYID      $20
           DOMAIN       $2
           USUBJID      $40
           TRSEQ        8
           TRTESTCD     $8
           TRTEST       $40
           TRCAT        $40
           TRORRES      $200
           TRSTRESC     $200
           TRSTRESN     8
           TRSTRESU     $40
           TREVAL       $40
           TRLNKID      $40
           VISITNUM     8
           VISIT        $40
           TRDTC        $20
           TRDY         8;
    
    ** Retain sequence counter **;
    retain TRSEQ;
    if first.usubjid then TRSEQ = 0;
    TRSEQ + 1;
    
    ** Set Domain **;
    DOMAIN = 'TR';
    
    ** STUDYID and USUBJID from DM **;
    STUDYID = studyid;
    USUBJID = usubjid;
    
    ** Test Code and Test Name **;
    TRTESTCD = upcase(strip(trtestcd));
    TRTEST = strip(trtest);
    
    ** Category **;
    if not missing(trcat) then TRCAT = strip(trcat);
    
    ** Original Result **;
    TRORRES = strip(trorres);
    
    ** Standard Character Result **;
    TRSTRESC = strip(trorres);
    
    ** Numeric Result **;
    if not missing(trstresn) then TRSTRESN = trstresn;
    else if not missing(trorres) and anydigit(strip(trorres)) then do;
        TRSTRESN = input(compress(trorres, , 'kd'), best.);
    end;
    
    ** Standard Units **;
    if not missing(trstresu) then TRSTRESU = strip(trstresu);
    
    ** Evaluator **;
    if not missing(treval) then do;
        if upcase(strip(treval)) = 'INVESTIGATOR' then TREVAL = 'INVESTIGATOR';
        else if upcase(strip(treval)) in ('INDEPENDENT' 'INDEPENDENT ASSESSOR' 'INDEPENDENT REVIEW') 
            then TREVAL = 'INDEPENDENT ASSESSOR';
        else TREVAL = strip(treval);
    end;
    
    ** Link ID **;
    if not missing(trlnkid) then TRLNKID = strip(trlnkid);
    
    ** Visit Number **;
    if not missing(visitnum) then VISITNUM = visitnum;
    
    ** Visit Name **;
    if not missing(visit) then VISIT = strip(visit);
    
    ** Date/Time of Collection **;
    if not missing(trdtc) then TRDTC = strip(trdtc);
    
    ** Derive Study Day **;
    if not missing(trdtc) and not missing(rfstdtc) then do;
        if length(strip(trdtc)) >= 10 and length(strip(rfstdtc)) >= 10 then do;
            _trdt = input(substr(strip(trdtc), 1, 10), ??yymmdd10.);
            _rfstdt = input(substr(strip(rfstdtc), 1, 10), ??yymmdd10.);
            if not missing(_trdt) and not missing(_rfstdt) then do;
                if _trdt >= _rfstdt then TRDY = _trdt - _rfstdt + 1;
                else TRDY = _trdt - _rfstdt;
            end;
        end;
    end;
    
    ** Apply Labels **;
    label STUDYID   = "Study Identifier"
          DOMAIN    = "Domain Abbreviation"
          USUBJID   = "Unique Subject Identifier"
          TRSEQ     = "Sequence Number"
          TRTESTCD  = "Tumor/Lesion Result Short Name"
          TRTEST    = "Tumor/Lesion Result Name"
          TRCAT     = "Category for Tumor/Lesion"
          TRORRES   = "Result or Finding in Original Units"
          TRSTRESC  = "Character Result/Finding in Std Format"
          TRSTRESN  = "Numeric Result/Finding in Standard Units"
          TRSTRESU  = "Standard Units"
          TREVAL    = "Evaluator"
          TRLNKID   = "Link ID"
          VISITNUM  = "Visit Number"
          VISIT     = "Visit Name"
          TRDTC     = "Date/Time of Collection"
          TRDY      = "Study Day of Collection";
    
    ** Keep only required variables **;
    keep STUDYID DOMAIN USUBJID TRSEQ TRTESTCD TRTEST TRCAT TRORRES 
         TRSTRESC TRSTRESN TRSTRESU TREVAL TRLNKID VISITNUM VISIT 
         TRDTC TRDY;
    
    ** Drop temporary variables **;
    drop _trdt _rfstdt rfstdtc;
run;

****************************************************************************;
** Sort TR domain                                                          **;
****************************************************************************;

proc sort data=sdtm.tr;
    by STUDYID USUBJID TRLNKID TRTESTCD VISITNUM TRDTC TRSEQ;
run;

****************************************************************************;
** Generate summary report                                                 **;
****************************************************************************;

proc freq data=sdtm.tr;
    tables TRTESTCD*TRTEST TRCAT TREVAL / list missing;
    title "TR Domain - Frequency Summary";
run;

proc means data=sdtm.tr n nmiss min max mean median;
    var TRSTRESN VISITNUM TRDY;
    title "TR Domain - Numeric Variable Summary";
run;

title;

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
