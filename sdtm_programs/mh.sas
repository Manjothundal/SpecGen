/*******************************************************************************
* Program:    mh.sas
* Domain:     MH (Events)
* Purpose:    Create SDTM MH domain dataset
* Variables:  24
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.mh (source CRF data)
* Output:     sdtm.mh (MH domain dataset)
*
* Variables:  STUDYID, DOMAIN, USUBJID, MHSEQ, MHCAT, MHTERM, MHLLT, MHLLTCD
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*=====================================================================*
 | Program Name   : SDTM_MH.sas                                        |
 | Purpose        : Create SDTM MH (Medical History) domain           |
 | SDTM Version   : 3.2                                                |
 | Domain         : MH (Events Class)                                  |
 |---------------------------------------------------------------------|
 | Input          : raw.mh, raw.dm                                     |
 | Output         : sdtm.mh                                            |
 |---------------------------------------------------------------------|
 | Programmer     : [Name]                                             |
 | Date           : [Date]                                             |
 *=====================================================================*/

/*-- BEGIN MH --*/

/*---------------------------------------------------------------------*
 | Step 1: Read DM domain for subject-level reference information      |
 *---------------------------------------------------------------------*/
proc sort data=sdtm.dm(keep=studyid usubjid rfstdtc) out=dm_ref nodupkey;
    by usubjid;
run;

/*---------------------------------------------------------------------*
 | Step 2: Read raw Medical History data                               |
 *---------------------------------------------------------------------*/
data mh_raw;
    set raw.mh;
    
    /* Derive USUBJID if not already in raw data */
    if missing(usubjid) then usubjid = catx('-', studyid, siteid, subjid);
    
run;

/*---------------------------------------------------------------------*
 | Step 3: Merge with DM to get reference start date                   |
 *---------------------------------------------------------------------*/
proc sort data=mh_raw;
    by usubjid;
run;

data mh_merge;
    merge mh_raw(in=a)
          dm_ref(in=b);
    by usubjid;
    if a;
run;

/*---------------------------------------------------------------------*
 | Step 4: Create MH domain with all derivations                       |
 *---------------------------------------------------------------------*/
data mh_derived;
    set mh_merge;
    by usubjid;
    
    length STUDYID $20
           DOMAIN $2
           USUBJID $40
           MHCAT $200
           MHSCAT $200
           MHTERM $200
           MHLLT $100
           MHLLTCD 8
           MHDECOD $200
           MHHLT $100
           MHHLTCD 8
           MHHLGT $100
           MHHLGTCD 8
           MHPTCD 8
           MHBODSYS $200
           MHBDSYCD 8
           MHSOC $200
           MHSOCCD 8
           MHSTDTC $20
           MHENDTC $20
           MHENRF $20
           MHSTDY 8
           MHENDY 8
           MHDUR $20;
    
    /*-----------------------------------------------------------------*
     | Assign DOMAIN                                                    |
     *-----------------------------------------------------------------*/
    DOMAIN = 'MH';
    
    /*-----------------------------------------------------------------*
     | Derive MHSEQ - Sequence number within subject                   |
     *-----------------------------------------------------------------*/
    retain MHSEQ;
    if first.usubjid then MHSEQ = 0;
    MHSEQ + 1;
    
    /*-----------------------------------------------------------------*
     | Map Medical History Term - Verbatim term                        |
     *-----------------------------------------------------------------*/
    MHTERM = strip(mhraw);
    
    /*-----------------------------------------------------------------*
     | Map Dictionary-Derived Term (from coding)                       |
     *-----------------------------------------------------------------*/
    MHDECOD = strip(mhcode);
    if missing(MHDECOD) then MHDECOD = MHTERM;
    
    /*-----------------------------------------------------------------*
     | Map MedDRA hierarchy variables                                   |
     | Assume coding information available in raw or lookup             |
     *-----------------------------------------------------------------*/
    MHLLT = strip(mh_llt);
    MHLLTCD = input(mh_lltcd, ??best.);
    MHHLT = strip(mh_hlt);
    MHHLTCD = input(mh_hltcd, ??best.);
    MHHLGT = strip(mh_hlgt);
    MHHLGTCD = input(mh_hlgtcd, ??best.);
    MHPTCD = input(mh_ptcd, ??best.);
    MHBODSYS = strip(mh_bodsys);
    MHBDSYCD = input(mh_bdsycd, ??best.);
    MHSOC = strip(mh_soc);
    MHSOCCD = input(mh_soccd, ??best.);
    
    /*-----------------------------------------------------------------*
     | Map Category and Subcategory                                    |
     *-----------------------------------------------------------------*/
    MHCAT = strip(mhcat);
    MHSCAT = strip(mhscat);
    
    /*-----------------------------------------------------------------*
     | Map Start Date/Time - Convert to ISO 8601 format                |
     *-----------------------------------------------------------------*/
    if not missing(mhstdat) then do;
        MHSTDTC = put(mhstdat, is8601da.);
    end;
    else if not missing(mhstdat_c) then do;
        MHSTDTC = strip(mhstdat_c);
    end;
    
    /*-----------------------------------------------------------------*
     | Map End Date/Time - Convert to ISO 8601 format                  |
     *-----------------------------------------------------------------*/
    if not missing(mhendat) then do;
        MHENDTC = put(mhendat, is8601da.);
    end;
    else if not missing(mhendat_c) then do;
        MHENDTC = strip(mhendat_c);
    end;
    
    /*-----------------------------------------------------------------*
     | Map End Relative to Reference Period                            |
     *-----------------------------------------------------------------*/
    MHENRF = strip(upcase(mhenr));
    
    /*-----------------------------------------------------------------*
     | Derive Study Day of Start (MHSTDY)                              |
     | Study day calculation: (Event Date - Reference Date) + 1 if >=0 |
     |                        (Event Date - Reference Date)     if < 0 |
     *-----------------------------------------------------------------*/
    if not missing(MHSTDTC) and not missing(RFSTDTC) and length(strip(MHSTDTC)) >= 10 and length(strip(RFSTDTC)) >= 10 then do;
        stdt_num = input(substr(MHSTDTC,1,10), ??yymmdd10.);
        rfdt_num = input(substr(RFSTDTC,1,10), ??yymmdd10.);
        
        if not missing(stdt_num) and not missing(rfdt_num) then do;
            if stdt_num >= rfdt_num then 
                MHSTDY = stdt_num - rfdt_num + 1;
            else 
                MHSTDY = stdt_num - rfdt_num;
        end;
    end;
    
    /*-----------------------------------------------------------------*
     | Derive Study Day of End (MHENDY)                                |
     *-----------------------------------------------------------------*/
    if not missing(MHENDTC) and not missing(RFSTDTC) and length(strip(MHENDTC)) >= 10 and length(strip(RFSTDTC)) >= 10 then do;
        endt_num = input(substr(MHENDTC,1,10), ??yymmdd10.);
        rfdt_num2 = input(substr(RFSTDTC,1,10), ??yymmdd10.);
        
        if not missing(endt_num) and not missing(rfdt_num2) then do;
            if endt_num >= rfdt_num2 then 
                MHENDY = endt_num - rfdt_num2 + 1;
            else 
                MHENDY = endt_num - rfdt_num2;
        end;
    end;
    
    /*-----------------------------------------------------------------*
     | Derive Duration (MHDUR) - ISO 8601 duration format              |
     *-----------------------------------------------------------------*/
    if not missing(MHSTDTC) and not missing(MHENDTC) and length(strip(MHSTDTC)) >= 10 and length(strip(MHENDTC)) >= 10 then do;
        st_date = input(substr(MHSTDTC,1,10), ??yymmdd10.);
        en_date = input(substr(MHENDTC,1,10), ??yymmdd10.);
        
        if not missing(st_date) and not missing(en_date) then do;
            dur_days = en_date - st_date + 1;
            if dur_days >= 0 then 
                MHDUR = cats('P', dur_days, 'D');
        end;
    end;
    
    /*-----------------------------------------------------------------*
     | Apply variable labels                                            |
     *-----------------------------------------------------------------*/
    label STUDYID  = "Study Identifier"
          DOMAIN   = "Domain Abbreviation"
          USUBJID  = "Unique Subject Identifier"
          MHSEQ    = "Sequence Number"
          MHCAT    = "Category for Medical History"
          MHSCAT   = "Subcategory for Medical History"
          MHTERM   = "Reported Term for the Medical History"
          MHLLT    = "Lowest Level Term"
          MHLLTCD  = "Lowest Level Term Code"
          MHDECOD  = "Dictionary-Derived Term"
          MHHLT    = "High Level Term"
          MHHLTCD  = "High Level Term Code"
          MHHLGT   = "High Level Group Term"
          MHHLGTCD = "High Level Group Term Code"
          MHPTCD   = "Preferred Term Code"
          MHBODSYS = "Body System or Organ Class"
          MHBDSYCD = "Body System or Organ Class Code"
          MHSOC    = "Primary System Organ Class"
          MHSOCCD  = "Primary System Organ Class Code"
          MHSTDTC  = "Start Date/Time of Medical History Event"
          MHENDTC  = "End Date/Time of Medical History Event"
          MHENRF   = "End Relative to Reference Period"
          MHSTDY   = "Study Day of Start of Medical History Event"
          MHENDY   = "Study Day of End of Medical History Event"
          MHDUR    = "Duration of Medical History Event";
    
    /*-----------------------------------------------------------------*
     | Drop variables not needed in final dataset                      |
     *-----------------------------------------------------------------*/
    drop mhraw mhcode mhstdat mhendat mhsttim mhentim mhstdat_c mhendat_c
         mhenr mh_llt mh_lltcd mh_hlt mh_hltcd mh_hlgt mh_hlgtcd mh_ptcd
         mh_bodsys mh_bdsycd mh_soc mh_soccd siteid subjid rfstdtc
         mhcat mhscat stdt_num rfdt_num endt_num rfdt_num2 st_date en_date dur_days;
         
run;

/*---------------------------------------------------------------------*
 | Step 5: Sort and create final dataset                               |
 *---------------------------------------------------------------------*/
proc sort data=mh_derived out=sdtm.mh;
    by STUDYID USUBJID MHSEQ;
run;

/*---------------------------------------------------------------------*
 | Step 6: Generate summary report                                     |
 *---------------------------------------------------------------------*/
proc freq data=sdtm.mh;
    tables MHCAT MHDECOD MHBODSYS / missing nocum;
    title "MH Domain Frequency Summary";
run;

proc means data=sdtm.mh n nmiss min max;
    var MHSEQ MHSTDY MHENDY;
    title "MH Domain Numeric Variable Summary";
run;

title;

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
