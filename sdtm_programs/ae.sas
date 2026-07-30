/*******************************************************************************
* Program:    ae.sas
* Domain:     AE (Events)
* Purpose:    Create SDTM AE domain dataset
* Variables:  19
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.ae (source CRF data)
* Output:     sdtm.ae (AE domain dataset)
*
* Variables:  STUDYID, AESEQ, USUBJID, DOMAIN, AETERM, AEDECOD, AECAT, AESCAT
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*====================================================================================*/
/* Program:      AE_SDTM.sas                                                          */
/* Description:  Create SDTM AE (Adverse Events) Domain                               */
/* CDISC Model:  SDTM v3.x                                                            */
/*====================================================================================*/

/*-- BEGIN AE --*/

%let domain = AE;

/*====================================================================================*/
/* Step 1: Read in source data and merge with DM for reference dates                 */
/*====================================================================================*/

proc sql;
    create table ae_dm as
    select dm.studyid,
           dm.usubjid,
           dm.siteid,
           dm.subjid,
           dm.rfstdtc,
           dm.rfxstdtc,
           dm.rfxendtc,
           dm.rfendtc,
           ae.*
    from raw.ae as ae
    left join raw.dm as dm
    on ae.studyid = dm.studyid 
       and ae.siteid = dm.siteid 
       and ae.subjid = dm.subjid;
quit;

/*====================================================================================*/
/* Step 2: Create base AE dataset with mappings                                       */
/*====================================================================================*/

data ae_base;
    set ae_dm;
    
    length STUDYID $20 DOMAIN $2 USUBJID $40
           AETERM $200 AEDECOD $200 AEBODSYS $200
           AECAT $40 AESCAT $40
           AESTDTC $19 AEENDTC $19
           AEACN $40 AEOUT $40 AEREL $40 AESER $1 AESEV $20
           EPOCH $40;
    
    /* Domain */
    DOMAIN = "&domain";
    
    /* STUDYID */
    STUDYID = strip(STUDYID);
    
    /* USUBJID - Derive if not already present */
    if missing(USUBJID) then 
        USUBJID = catx('-', strip(STUDYID), strip(SITEID), strip(SUBJID));
    else
        USUBJID = strip(USUBJID);
    
    /* Map AE Term and Decoded Term */
    AETERM = strip(ae_verbatim);
    if not missing(ae_coded) then AEDECOD = strip(ae_coded);
    else AEDECOD = strip(ae_verbatim);
    
    /* Map Body System/Organ Class */
    if not missing(ae_soc) then AEBODSYS = strip(ae_soc);
    
    /* Map Category and Subcategory */
    if not missing(ae_category) then AECAT = strip(ae_category);
    if not missing(ae_subcategory) then AESCAT = strip(ae_subcategory);
    
    /* Map Start Date/Time - Convert to ISO 8601 format */
    if not missing(aestdat) then do;
        AESTDTC = strip(put(aestdat, is8601da.));
        if not missing(aesttim) then 
            AESTDTC = strip(put(aestdat, is8601da.)) || 'T' || put(aesttim, time8.);
    end;
    
    /* Map End Date/Time - Convert to ISO 8601 format */
    if not missing(aeendat) then do;
        AEENDTC = strip(put(aeendat, is8601da.));
        if not missing(aeentim) then 
            AEENDTC = strip(put(aeendat, is8601da.)) || 'T' || put(aeentim, time8.);
    end;
    
    /* Map Severity */
    if not missing(aeseverity) then do;
        if upcase(strip(aeseverity)) in ('1' 'MILD') then AESEV = 'MILD';
        else if upcase(strip(aeseverity)) in ('2' 'MODERATE') then AESEV = 'MODERATE';
        else if upcase(strip(aeseverity)) in ('3' 'SEVERE') then AESEV = 'SEVERE';
        else AESEV = strip(aeseverity);
    end;
    
    /* Map Action Taken */
    if not missing(aeaction) then do;
        if upcase(strip(aeaction)) in ('1' 'NONE') then AEACN = 'DOSE NOT CHANGED';
        else if upcase(strip(aeaction)) in ('2' 'DOSE REDUCED') then AEACN = 'DOSE REDUCED';
        else if upcase(strip(aeaction)) in ('3' 'DRUG WITHDRAWN') then AEACN = 'DRUG WITHDRAWN';
        else if upcase(strip(aeaction)) in ('4' 'DOSE NOT CHANGED') then AEACN = 'DOSE NOT CHANGED';
        else if upcase(strip(aeaction)) in ('5' 'DRUG INTERRUPTED') then AEACN = 'DRUG INTERRUPTED';
        else if upcase(strip(aeaction)) in ('6' 'DOSE INCREASED') then AEACN = 'DOSE INCREASED';
        else if upcase(strip(aeaction)) in ('7' 'NOT APPLICABLE') then AEACN = 'NOT APPLICABLE';
        else if upcase(strip(aeaction)) in ('8' 'UNKNOWN') then AEACN = 'UNKNOWN';
        else AEACN = strip(aeaction);
    end;
    
    /* Map Outcome */
    if not missing(aeoutcome) then do;
        if upcase(strip(aeoutcome)) in ('1' 'RECOVERED/RESOLVED') then AEOUT = 'RECOVERED/RESOLVED';
        else if upcase(strip(aeoutcome)) in ('2' 'RECOVERING/RESOLVING') then AEOUT = 'RECOVERING/RESOLVING';
        else if upcase(strip(aeoutcome)) in ('3' 'NOT RECOVERED/NOT RESOLVED') then AEOUT = 'NOT RECOVERED/NOT RESOLVED';
        else if upcase(strip(aeoutcome)) in ('4' 'FATAL') then AEOUT = 'FATAL';
        else if upcase(strip(aeoutcome)) in ('5' 'RECOVERED/RESOLVED WITH SEQUELAE') then AEOUT = 'RECOVERED/RESOLVED WITH SEQUELAE';
        else if upcase(strip(aeoutcome)) in ('6' 'UNKNOWN') then AEOUT = 'UNKNOWN';
        else AEOUT = strip(aeoutcome);
    end;
    
    /* Map Relationship */
    if not missing(aerelated) then do;
        if upcase(strip(aerelated)) in ('1' 'Y' 'YES' 'RELATED') then AEREL = 'RELATED';
        else if upcase(strip(aerelated)) in ('0' 'N' 'NO' 'NOT RELATED') then AEREL = 'NOT RELATED';
        else if upcase(strip(aerelated)) in ('2' 'POSSIBLY RELATED') then AEREL = 'POSSIBLY RELATED';
        else if upcase(strip(aerelated)) in ('3' 'PROBABLY RELATED') then AEREL = 'PROBABLY RELATED';
        else AEREL = strip(aerelated);
    end;
    
    /* Map Serious */
    if not missing(aeserious) then do;
        if upcase(strip(aeserious)) in ('1' 'Y' 'YES') then AESER = 'Y';
        else if upcase(strip(aeserious)) in ('0' 'N' 'NO') then AESER = 'N';
        else AESER = strip(aeserious);
    end;
    
    /* Keep required variables for further processing */
    keep STUDYID DOMAIN USUBJID 
         AETERM AEDECOD AEBODSYS
         AECAT AESCAT
         AESTDTC AEENDTC
         AEACN AEOUT AEREL AESER AESEV
         RFSTDTC RFXSTDTC RFXENDTC RFENDTC;
run;

/*====================================================================================*/
/* Step 3: Derive Study Days (AESTDY, AEENDY)                                         */
/*====================================================================================*/

data ae_sdy;
    set ae_base;
    
    length AESTDY AEENDY 8;
    
    /* Convert RFSTDTC to SAS date for calculations */
    if not missing(RFSTDTC) and length(strip(RFSTDTC)) >= 10 then do;
        rfstdt = input(substr(RFSTDTC,1,10), yymmdd10.);
    end;
    
    /* Derive Start Study Day */
    if not missing(AESTDTC) and not missing(rfstdt) and length(strip(AESTDTC)) >= 10 then do;
        aestdt = input(substr(AESTDTC,1,10), yymmdd10.);
        if aestdt >= rfstdt then AESTDY = aestdt - rfstdt + 1;
        else AESTDY = aestdt - rfstdt;
    end;
    
    /* Derive End Study Day */
    if not missing(AEENDTC) and not missing(rfstdt) and length(strip(AEENDTC)) >= 10 then do;
        aeendt = input(substr(AEENDTC,1,10), yymmdd10.);
        if aeendt >= rfstdt then AEENDY = aeendt - rfstdt + 1;
        else AEENDY = aeendt - rfstdt;
    end;
    
    drop rfstdt aestdt aeendt;
run;

/*====================================================================================*/
/* Step 4: Derive EPOCH                                                               */
/*====================================================================================*/

data ae_epoch;
    set ae_sdy;
    
    /* Derive EPOCH based on date relative to treatment period */
    if not missing(AESTDTC) and length(strip(AESTDTC)) >= 10 then do;
        aestdt = input(substr(AESTDTC,1,10), yymmdd10.);
        
        if not missing(RFXSTDTC) and length(strip(RFXSTDTC)) >= 10 then 
            rfxstdt = input(substr(RFXSTDTC,1,10), yymmdd10.);
        if not missing(RFXENDTC) and length(strip(RFXENDTC)) >= 10 then 
            rfxendt = input(substr(RFXENDTC,1,10), yymmdd10.);
        
        if not missing(rfxstdt) and not missing(rfxendt) then do;
            if aestdt < rfxstdt then EPOCH = 'SCREENING';
            else if aestdt >= rfxstdt and aestdt <= rfxendt then EPOCH = 'TREATMENT';
            else if aestdt > rfxendt then EPOCH = 'FOLLOW-UP';
        end;
        else if not missing(rfxstdt) then do;
            if aestdt < rfxstdt then EPOCH = 'SCREENING';
            else EPOCH = 'TREATMENT';
        end;
    end;
    
    drop aestdt rfxstdt rfxendt RFSTDTC RFXSTDTC RFXENDTC RFENDTC;
run;

/*====================================================================================*/
/* Step 5: Assign AESEQ - Sequence number within subject                             */
/*====================================================================================*/

proc sort data=ae_epoch;
    by STUDYID USUBJID AESTDTC AETERM;
run;

data ae_seq;
    set ae_epoch;
    by STUDYID USUBJID;
    
    length AESEQ 8;
    
    if first.USUBJID then AESEQ = 0;
    AESEQ + 1;
    
    format AESEQ AESTDY AEENDY 8.;
run;

/*====================================================================================*/
/* Step 6: Final dataset with labels and variable order                              */
/*====================================================================================*/

data sdtm.ae (label="Adverse Events");
    retain STUDYID DOMAIN USUBJID AESEQ 
           AETERM AEDECOD AECAT AESCAT AEBODSYS
           AESTDTC AEENDTC AESTDY AEENDY
           EPOCH AEACN AEOUT AEREL AESER AESEV;
    
    set ae_seq;
    
    /* Apply Labels */
    label STUDYID = "Study Identifier"
          DOMAIN = "Domain Abbreviation"
          USUBJID = "Unique Subject Identifier"
          AESEQ = "Sequence Number"
          AETERM = "Reported Term for the Adverse Event"
          AEDECOD = "Dictionary-Derived Term"
          AECAT = "Category for Adverse Event"
          AESCAT = "Subcategory for Adverse Event"
          AEBODSYS = "Body System or Organ Class"
          AESTDTC = "Start Date/Time of Adverse Event"
          AEENDTC = "End Date/Time of Adverse Event"
          AESTDY = "Study Day of Start of Adverse Event"
          AEENDY = "Study Day of End of Adverse Event"
          EPOCH = "Epoch"
          AEACN = "Action Taken with Study Treatment"
          AEOUT = "Outcome of Adverse Event"
          AEREL = "Causality"
          AESER = "Serious Event"
          AESEV = "Severity/Intensity";
    
    /* Keep only required variables in specified order */
    keep STUDYID DOMAIN USUBJID AESEQ 
         AETERM AEDECOD AECAT AESCAT AEBODSYS
         AESTDTC AEENDTC AESTDY AEENDY
         EPOCH AEACN AEOUT AEREL AESER AESEV;
run;

/*====================================================================================*/
/* Step 7: Final sort                                                                 */
/*====================================================================================*/

proc sort data=sdtm.ae;
    by STUDYID USUBJID AESEQ;
run;

/*====================================================================================*/
/* Step 8: Generate summary report                                                    */
/*====================================================================================*/

proc sql;
    select "AE Domain Summary" as Report_Type,
           count(distinct USUBJID) as Subjects,
           count(*) as Total_Records,
           count(distinct AETERM) as Unique_Terms
    from sdtm.ae;
quit;

/*-- END AE --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.ae;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.ae varnum;
run;

proc freq data=sdtm.ae;
  tables DOMAIN / nocum nopercent;
run;

/* End of ae.sas */
