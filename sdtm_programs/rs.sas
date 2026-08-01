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
*---------------------------------------------------------------------------*
| Program Name     : RS.sas                                                |
| Purpose          : Create SDTM RS domain (Disease Response Assessments)  |
| SDTM Version     : 3.2                                                   |
| Input            : raw.rs, raw.dm                                        |
| Output           : sdtm.RS                                               |
*---------------------------------------------------------------------------*;

** Read DM domain for STUDYID, USUBJID, and RFSTDTC **;
proc sort data=raw.dm(keep=STUDYID USUBJID RFSTDTC) 
          out=dm nodupkey;
    by USUBJID;
run;

** Read raw RS data **;
data rs_raw;
    set raw.rs;
run;

** Sort raw data **;
proc sort data=rs_raw;
    by USUBJID RSTESTCD VISITNUM RSDTC;
run;

** Create RS domain **;
data sdtm.RS;
    merge rs_raw(in=a)
          dm(in=b keep=STUDYID USUBJID RFSTDTC);
    by USUBJID;
    if a;
    
    length STUDYID $20
           DOMAIN $2
           USUBJID $40
           RSSEQ 8
           RSTESTCD $8
           RSTEST $40
           RSCAT $200
           RSORRES $200
           RSSTRESC $200
           RSSTRESN 8
           RSSTRESU $20
           RSEVAL $40
           RSLNKID $200
           VISITNUM 8
           VISIT $200
           RSDTC $20
           RSDY 8;
    
    ** Set DOMAIN **;
    DOMAIN = 'RS';
    
    ** Map RSTESTCD and RSTEST **;
    length RSTESTCD_temp $8;
    RSTESTCD_temp = upcase(strip(RSTESTCD));
    
    select(RSTESTCD_temp);
        when('OVRLRESP','OVERALL')  do;
            RSTESTCD = 'OVRLRESP';
            RSTEST = 'Overall Response';
        end;
        when('TUMSTATE','TUMORST')  do;
            RSTESTCD = 'TUMSTATE';
            RSTEST = 'Tumor State';
        end;
        when('TUMIDENT','TUMORIDENT') do;
            RSTESTCD = 'TUMIDENT';
            RSTEST = 'Tumor Identification';
        end;
        when('NEOPL','NEOPLASM') do;
            RSTESTCD = 'NEOPL';
            RSTEST = 'Neoplasm Status';
        end;
        otherwise do;
            if missing(RSTEST) then RSTEST = propcase(RSTESTCD);
        end;
    end;
    
    drop RSTESTCD_temp;
    
    ** Map RSCAT - leave as is from source or set default **;
    if missing(RSCAT) then RSCAT = 'RECIST 1.1';
    
    ** Map RSORRES from source **;
    RSORRES = strip(RSORRES);
    
    ** Derive RSSTRESC from RSORRES **;
    if not missing(RSORRES) then do;
        RSSTRESC = upcase(strip(RSORRES));
        
        ** Standardize common response values **;
        if RSSTRESC in ('CR','COMPLETE RESPONSE') then RSSTRESC = 'CR';
        else if RSSTRESC in ('PR','PARTIAL RESPONSE') then RSSTRESC = 'PR';
        else if RSSTRESC in ('SD','STABLE DISEASE') then RSSTRESC = 'SD';
        else if RSSTRESC in ('PD','PROGRESSIVE DISEASE') then RSSTRESC = 'PD';
        else if RSSTRESC in ('NE','NOT EVALUABLE') then RSSTRESC = 'NE';
        else if RSSTRESC in ('NON-CR/NON-PD','NON-CR NON-PD') then RSSTRESC = 'NON-CR/NON-PD';
        else if RSSTRESC in ('NA','NOT APPLICABLE') then RSSTRESC = 'NA';
        else if RSSTRESC in ('ND','NOT DONE') then RSSTRESC = 'ND';
        else RSSTRESC = strip(RSSTRESC);
    end;
    
    ** Derive RSSTRESN - typically not applicable for RS domain **;
    if not missing(RSSTRESC) then do;
        if notdigit(strip(compress(RSSTRESC,'.')))=0 and anydigit(RSSTRESC)>0 then 
            RSSTRESN = input(RSSTRESC, ?? best.);
        else RSSTRESN = .;
    end;
    else RSSTRESN = .;
    
    ** Map RSSTRESU - typically not applicable for RS domain **;
    RSSTRESU = strip(RSSTRESU);
    
    ** Map RSEVAL **;
    if not missing(RSEVAL) then do;
        RSEVAL = upcase(strip(RSEVAL));
        if RSEVAL in ('INV','INVESTIGATOR') then RSEVAL = 'INVESTIGATOR';
        else if RSEVAL in ('IRC','INDEPENDENT','INDEPENDENT ASSESSOR','INDEPENDENT REVIEW') 
            then RSEVAL = 'INDEPENDENT ASSESSOR';
    end;
    
    ** Map RSLNKID **;
    RSLNKID = strip(RSLNKID);
    
    ** Map VISITNUM **;
    if missing(VISITNUM) then VISITNUM = .;
    
    ** Map VISIT **;
    VISIT = strip(VISIT);
    
    ** Map RSDTC - ensure ISO 8601 format **;
    RSDTC = strip(RSDTC);
    
    ** Derive RSDY **;
    if not missing(RSDTC) and not missing(RFSTDTC) then do;
        length rsdtc_date rfstdtc_date 8;
        
        ** Extract date portion from ISO8601 datetime **;
        if index(RSDTC,'T') > 0 then 
            rsdtc_date = input(scan(RSDTC,1,'T'), ?? yymmdd10.);
        else 
            rsdtc_date = input(RSDTC, ?? yymmdd10.);
        
        if index(RFSTDTC,'T') > 0 then 
            rfstdtc_date = input(scan(RFSTDTC,1,'T'), ?? yymmdd10.);
        else 
            rfstdtc_date = input(RFSTDTC, ?? yymmdd10.);
        
        if not missing(rsdtc_date) and not missing(rfstdtc_date) then do;
            if rsdtc_date >= rfstdtc_date then 
                RSDY = rsdtc_date - rfstdtc_date + 1;
            else 
                RSDY = rsdtc_date - rfstdtc_date;
        end;
        else RSDY = .;
        
        drop rsdtc_date rfstdtc_date;
    end;
    else RSDY = .;
    
    drop RFSTDTC;
run;

** Sort by key variables and derive RSSEQ **;
proc sort data=sdtm.RS;
    by STUDYID USUBJID RSTESTCD VISITNUM RSDTC;
run;

data sdtm.RS;
    set sdtm.RS;
    by STUDYID USUBJID;
    
    retain RSSEQ;
    
    if first.USUBJID then RSSEQ = 1;
    else RSSEQ + 1;
run;

** Final dataset with variable ordering and labels **;
data sdtm.RS(keep=STUDYID DOMAIN USUBJID RSSEQ 
                  RSTESTCD RSTEST RSCAT 
                  RSORRES RSSTRESC RSSTRESN RSSTRESU
                  RSEVAL RSLNKID
                  VISITNUM VISIT RSDTC RSDY);
    set sdtm.RS;
    
    label STUDYID  = "Study Identifier"
          DOMAIN   = "Domain Abbreviation"
          USUBJID  = "Unique Subject Identifier"
          RSSEQ    = "Sequence Number"
          RSTESTCD = "Disease Response Assessment Short Name"
          RSTEST   = "Disease Response Assessment Name"
          RSCAT    = "Category for Disease Response"
          RSORRES  = "Result or Finding in Original Units"
          RSSTRESC = "Character Result/Finding in Std Format"
          RSSTRESN = "Numeric Result/Finding in Standard Units"
          RSSTRESU = "Standard Units"
          RSEVAL   = "Evaluator"
          RSLNKID  = "Link ID"
          VISITNUM = "Visit Number"
          VISIT    = "Visit Name"
          RSDTC    = "Date/Time of Assessment"
          RSDY     = "Study Day of Assessment";
run;

** Final sort by SDTM key variables **;
proc sort data=sdtm.RS;
    by STUDYID USUBJID RSSEQ;
run;

** Clean up temporary datasets **;
proc datasets library=work nolist;
    delete dm rs_raw;
quit;

/*-- END RS --*/


/*-- BEGIN SUPPRS --*/
******************************************************************************;
* Program:      SUPPRS.sas                                                   *;
* Description:  Create SUPPRS supplemental qualifiers domain for RS          *;
* RDOMAIN:      RS                                                           *;
* IDVAR:        RSSEQ                                                        *;
******************************************************************************;

******************************************************************************;
* Step 1: Read source data and merge with SDTM RS to get RSSEQ              *;
******************************************************************************;
proc sort data=raw.rs out=raw_rs_sort;
    by studyid usubjid rstestcd rsdtc;
run;

proc sort data=sdtm.rs(keep=studyid usubjid rsseq rstestcd rsdtc) out=sdtm_rs_sort;
    by studyid usubjid rstestcd rsdtc;
run;

data rs_with_seq;
    merge raw_rs_sort(in=a)
          sdtm_rs_sort(in=b);
    by studyid usubjid rstestcd rsdtc;
    if a and b;
run;

******************************************************************************;
* Step 2: Transpose qualifier variables into QNAM/QVAL structure            *;
******************************************************************************;
data supprs_pre;
    length STUDYID $20 RDOMAIN $2 USUBJID $40 IDVAR $8 IDVARVAL $200 
           QNAM $200 QLABEL $200 QVAL $200 QORIG $8 QEVAL $40;
    
    set rs_with_seq;
    
    RDOMAIN = 'RS';
    IDVAR = 'RSSEQ';
    IDVARVAL = put(RSSEQ, best.);
    QORIG = 'CRF';
    QEVAL = '';
    
    * Qualifier 1: RSBORRESP;
    if not missing(RSBORRESP) then do;
        QNAM = 'RSBORRESP';
        QLABEL = 'Best Overall Response: CR PR SD PD';
        QVAL = strip(RSBORRESP);
        output;
    end;
    
    * Qualifier 2: RSCONFDTC;
    if not missing(RSCONFDTC) then do;
        QNAM = 'RSCONFDTC';
        QLABEL = 'Date of Confirmation';
        QVAL = strip(put(RSCONFDTC, is8601da.));
        output;
    end;
    
    * Qualifier 3: RSCONFYN;
    if not missing(RSCONFYN) then do;
        QNAM = 'RSCONFYN';
        QLABEL = 'Confirmed Response?: Yes No';
        QVAL = strip(RSCONFYN);
        output;
    end;
    
    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
run;

******************************************************************************;
* Step 3: Apply labels and sort by required variables                        *;
******************************************************************************;
proc sort data=supprs_pre 
          out=sdtm.supprs(label="Supplemental Qualifiers for RS");
    by STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM;
run;

data sdtm.supprs;
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

******************************************************************************;
* Step 4: Generate summary report                                            *;
******************************************************************************;
proc freq data=sdtm.supprs;
    tables QNAM*QORIG / list missing;
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
