/*******************************************************************************
* Program:    mh.sas
* Domain:     MH (Events)
* Purpose:    Create SDTM MH domain dataset
* Variables:  15
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.mh (source CRF data)
* Output:     sdtm.mh (MH domain dataset)
*
* Variables:  STUDYID, MHSEQ, USUBJID, DOMAIN, MHTERM, MHDECOD, MHCAT, MHSCAT
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-----------------------------------------------------------------------------
  Program Name:    sdtm_mh.sas
  Program Purpose: Create SDTM MH (Medical History) Domain
  SAS Version:     9.4 or later
  Input:           raw.mh, sdtm.dm
  Output:          sdtm.mh
-----------------------------------------------------------------------------*/

/*-- BEGIN MH --*/

*-----------------------------------------------------------------------------;
* Read DM domain to get reference dates and subject identifiers              ;
*-----------------------------------------------------------------------------;
proc sort data=sdtm.dm(keep=studyid usubjid rfstdtc) out=dm nodupkey;
    by studyid usubjid;
run;

*-----------------------------------------------------------------------------;
* Read raw MH data and merge with DM                                         ;
*-----------------------------------------------------------------------------;
data mh_raw;
    merge raw.mh(in=a)
          dm(in=b);
    by studyid usubjid;
    
    if a;
    
    * Ensure reference start date is available for derivations;
    if b;
    
    * Convert reference date to numeric for study day calculations;
    if rfstdtc ne '' then do;
        rfstdt_num = input(scan(rfstdtc,1,'T'), yymmdd10.);
    end;
run;

*-----------------------------------------------------------------------------;
* Create MH domain                                                           ;
*-----------------------------------------------------------------------------;
data mh_pre;
    set mh_raw;
    
    length STUDYID $20
           DOMAIN $2 
           USUBJID $40
           MHTERM MHDECOD MHBODSYS $200
           MHCAT MHSCAT $200
           MHENRF $3
           EPOCH $20
           MHSTDTC MHENDTC $19;
    
    *---------------------------------------------------------------------------;
    * Assign domain abbreviation                                               ;
    *---------------------------------------------------------------------------;
    DOMAIN = 'MH';
    
    *---------------------------------------------------------------------------;
    * Map reported and dictionary-derived terms                                ;
    *---------------------------------------------------------------------------;
    MHTERM = strip(mhverbat);
    MHDECOD = strip(mhdecd);
    if missing(MHDECOD) then MHDECOD = strip(MHTERM);
    
    *---------------------------------------------------------------------------;
    * Map body system or organ class                                           ;
    *---------------------------------------------------------------------------;
    MHBODSYS = strip(mhbdsys);
    
    *---------------------------------------------------------------------------;
    * Map category and subcategory                                             ;
    *---------------------------------------------------------------------------;
    MHCAT = strip(mhcatgry);
    MHSCAT = strip(mhsubcat);
    
    *---------------------------------------------------------------------------;
    * Map start and end dates to ISO 8601 format                               ;
    *---------------------------------------------------------------------------;
    if not missing(mhstdat) then do;
        mhstdat_c = strip(mhstdat);
        * Check if already in ISO 8601 format (YYYY-MM-DD);
        if length(mhstdat_c) = 10 and index(mhstdat_c,'-') > 0 then 
            MHSTDTC = mhstdat_c;
        else do;
            mhstdt_num = input(mhstdat, ?? yymmdd10.);
            if not missing(mhstdt_num) then 
                MHSTDTC = put(mhstdt_num, yymmdd10.);
        end;
    end;
    
    if not missing(mhendat) then do;
        mhendat_c = strip(mhendat);
        * Check if already in ISO 8601 format (YYYY-MM-DD);
        if length(mhendat_c) = 10 and index(mhendat_c,'-') > 0 then 
            MHENDTC = mhendat_c;
        else do;
            mhendt_num = input(mhendat, ?? yymmdd10.);
            if not missing(mhendt_num) then 
                MHENDTC = put(mhendt_num, yymmdd10.);
        end;
    end;
    
    *---------------------------------------------------------------------------;
    * Derive study day for start date                                          ;
    *---------------------------------------------------------------------------;
    if not missing(MHSTDTC) and not missing(rfstdt_num) then do;
        mhstdt_num = input(scan(MHSTDTC,1,'T'), ?? yymmdd10.);
        if not missing(mhstdt_num) then do;
            if mhstdt_num >= rfstdt_num then 
                MHSTDY = mhstdt_num - rfstdt_num + 1;
            else 
                MHSTDY = mhstdt_num - rfstdt_num;
        end;
    end;
    
    *---------------------------------------------------------------------------;
    * Derive study day for end date                                            ;
    *---------------------------------------------------------------------------;
    if not missing(MHENDTC) and not missing(rfstdt_num) then do;
        mhendt_num = input(scan(MHENDTC,1,'T'), ?? yymmdd10.);
        if not missing(mhendt_num) then do;
            if mhendt_num >= rfstdt_num then 
                MHENDY = mhendt_num - rfstdt_num + 1;
            else 
                MHENDY = mhendt_num - rfstdt_num;
        end;
    end;
    
    *---------------------------------------------------------------------------;
    * Map ongoing flag (MHENRF should be ONGOING, not Yes/No)                 ;
    *---------------------------------------------------------------------------;
    if not missing(mhongo) then do;
        if upcase(strip(mhongo)) in ('Y' 'YES') then MHENRF = 'ONGOING';
        else MHENRF = '';
    end;
    
    *---------------------------------------------------------------------------;
    * Derive EPOCH based on study day                                          ;
    *---------------------------------------------------------------------------;
    EPOCH = '';
    if not missing(MHSTDY) then do;
        if MHSTDY < 1 then EPOCH = 'SCREENING';
        else EPOCH = 'TREATMENT';
    end;
    else if not missing(MHENDY) then do;
        if MHENDY < 1 then EPOCH = 'SCREENING';
        else EPOCH = 'TREATMENT';
    end;
    
    * Drop temporary and source variables;
    drop rfstdtc rfstdt_num mhstdt_num mhendt_num mhstdat_c mhendat_c
         mhverbat mhdecd mhbdsys mhcatgry mhsubcat 
         mhstdat mhendat mhongo;
run;

*-----------------------------------------------------------------------------;
* Sort and derive sequence number                                            ;
*-----------------------------------------------------------------------------;
proc sort data=mh_pre;
    by STUDYID USUBJID MHSTDTC MHTERM;
run;

data sdtm.mh;
    set mh_pre;
    by STUDYID USUBJID;
    
    *---------------------------------------------------------------------------;
    * Derive sequence number                                                   ;
    *---------------------------------------------------------------------------;
    if first.USUBJID then MHSEQ = 1;
    else MHSEQ + 1;
    
    *---------------------------------------------------------------------------;
    * Apply variable labels                                                    ;
    *---------------------------------------------------------------------------;
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        USUBJID  = "Unique Subject Identifier"
        MHSEQ    = "Sequence Number"
        MHTERM   = "Reported Term for the Medical History"
        MHDECOD  = "Dictionary-Derived Term"
        MHCAT    = "Category for Medical History"
        MHSCAT   = "Subcategory for Medical History"
        MHBODSYS = "Body System or Organ Class"
        MHSTDTC  = "Start Date/Time of Medical History Event"
        MHENDTC  = "End Date/Time of Medical History Event"
        MHSTDY   = "Study Day of Start of Medical History Event"
        MHENDY   = "Study Day of End of Medical History Event"
        MHENRF   = "End Relative to Reference Period"
        EPOCH    = "Epoch"
    ;
    
    keep STUDYID DOMAIN USUBJID MHSEQ MHTERM MHDECOD MHCAT MHSCAT 
         MHBODSYS MHSTDTC MHENDTC MHSTDY MHENDY MHENRF EPOCH;
run;

*-----------------------------------------------------------------------------;
* Final sort by protocol-specified order                                     ;
*-----------------------------------------------------------------------------;
proc sort data=sdtm.mh;
    by STUDYID USUBJID MHSEQ;
run;

/*-- END MH --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.mh;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.mh varnum;
run;

proc freq data=sdtm.mh;
  tables DOMAIN / nocum nopercent;
run;

/* End of mh.sas */
