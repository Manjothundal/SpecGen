/*******************************************************************************
* Program:    dv.sas
* Domain:     DV (Events)
* Purpose:    Create SDTM DV domain dataset
* Variables:  14
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.dv (source CRF data)
* Output:     sdtm.dv (DV domain dataset)
*
* Variables:  STUDYID, DVSEQ, USUBJID, DOMAIN, DVTERM, DVDECOD, DVCAT, DVSCAT
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-----------------------------------------------------------------------------
  Program Name: sdtm_dv.sas
  Description:  Create SDTM DV (Protocol Deviation) domain
  Specifications: CDISC SDTM Implementation Guide v3.x
  Input:        raw.dv, sdtm.dm
  Output:       sdtm.dv
-----------------------------------------------------------------------------*/

/*-- BEGIN DV --*/

*-----------------------------------------------------------------------------;
* Read source DV data and merge with DM for subject identifiers and dates    ;
*-----------------------------------------------------------------------------;
proc sort data=raw.dv out=dv_sorted;
    by studyid usubjid;
run;

proc sort data=sdtm.dm(keep=studyid usubjid rfstdtc) out=dm;
    by studyid usubjid;
run;

data dv_base;
    merge dv_sorted(in=indv)
          dm(in=indm);
    by studyid usubjid;
    
    if indv;
    
    * Store RFSTDTC for study day calculations;
    length rfstdtc_dm $19;
    if indm then rfstdtc_dm = rfstdtc;
    else rfstdtc_dm = '';
run;

*-----------------------------------------------------------------------------;
* Create DV domain with all required variables and derivations               ;
*-----------------------------------------------------------------------------;
data sdtm.dv;
    set dv_base;
    
    length STUDYID $20
           DOMAIN $2
           USUBJID $40
           DVSEQ 8
           DVTERM $200
           DVDECOD $200
           DVCAT $40
           DVSCAT $40
           DVBODSYS $200
           DVSTDTC $19
           DVENDTC $19
           DVSTDY 8
           DVENDY 8
           EPOCH $40;
    
    *-------------------------------------------------------------------------*
    * Assign Domain                                                           *
    *-------------------------------------------------------------------------*;
    DOMAIN = 'DV';
    
    *-------------------------------------------------------------------------*
    * Map DVTERM - Reported Term for the Event                                *
    *-------------------------------------------------------------------------*;
    if not missing(dvterm_raw) then DVTERM = strip(dvterm_raw);
    else if not missing(dvterm) then DVTERM = strip(dvterm);
    
    *-------------------------------------------------------------------------*
    * Map DVDECOD - Dictionary-Derived Term                                   *
    *-------------------------------------------------------------------------*;
    if not missing(dvdecod_raw) then DVDECOD = strip(dvdecod_raw);
    else if not missing(dvdecod) then DVDECOD = strip(dvdecod);
    else if not missing(DVTERM) then DVDECOD = DVTERM;
    
    *-------------------------------------------------------------------------*
    * Map DVCAT - Category for Event                                          *
    *-------------------------------------------------------------------------*;
    if not missing(dvcat_raw) then DVCAT = strip(dvcat_raw);
    else if not missing(dvcat) then DVCAT = strip(dvcat);
    
    *-------------------------------------------------------------------------*
    * Map DVSCAT - Subcategory for Event                                      *
    *-------------------------------------------------------------------------*;
    if not missing(dvscat_raw) then DVSCAT = strip(dvscat_raw);
    else if not missing(dvscat) then DVSCAT = strip(dvscat);
    
    *-------------------------------------------------------------------------*
    * Map DVBODSYS - Body System or Organ Class (if applicable)               *
    *-------------------------------------------------------------------------*;
    if not missing(dvbodsys_raw) then DVBODSYS = strip(dvbodsys_raw);
    else if not missing(dvbodsys) then DVBODSYS = strip(dvbodsys);
    
    *-------------------------------------------------------------------------*
    * Map DVSTDTC - Start Date/Time of Event (ISO 8601 format)                *
    *-------------------------------------------------------------------------*;
    if not missing(dvstdat) then do;
        if not missing(dvsttim) then 
            DVSTDTC = strip(put(dvstdat, yymmdd10.)) || 'T' || 
                     put(dvsttim, time5.);
        else 
            DVSTDTC = strip(put(dvstdat, yymmdd10.));
    end;
    else if not missing(dvstdtc_raw) then DVSTDTC = strip(dvstdtc_raw);
    else if not missing(dvstdtc) then DVSTDTC = strip(dvstdtc);
    
    *-------------------------------------------------------------------------*
    * Map DVENDTC - End Date/Time of Event (ISO 8601 format)                  *
    *-------------------------------------------------------------------------*;
    if not missing(dvendat) then do;
        if not missing(dventim) then 
            DVENDTC = strip(put(dvendat, yymmdd10.)) || 'T' || 
                     put(dventim, time5.);
        else 
            DVENDTC = strip(put(dvendat, yymmdd10.));
    end;
    else if not missing(dvendtc_raw) then DVENDTC = strip(dvendtc_raw);
    else if not missing(dvendtc) then DVENDTC = strip(dvendtc);
    
    *-------------------------------------------------------------------------*
    * Derive DVSTDY - Study Day of Start of Event                             *
    *-------------------------------------------------------------------------*;
    if not missing(DVSTDTC) and not missing(rfstdtc_dm) then do;
        stdt = input(scan(DVSTDTC,1,'T'), yymmdd10.);
        rfstdt = input(scan(rfstdtc_dm,1,'T'), yymmdd10.);
        
        if not missing(stdt) and not missing(rfstdt) then do;
            if stdt >= rfstdt then
                DVSTDY = stdt - rfstdt + 1;
            else
                DVSTDY = stdt - rfstdt;
        end;
    end;
    
    *-------------------------------------------------------------------------*
    * Derive DVENDY - Study Day of End of Event                               *
    *-------------------------------------------------------------------------*;
    if not missing(DVENDTC) and not missing(rfstdtc_dm) then do;
        endt = input(scan(DVENDTC,1,'T'), yymmdd10.);
        rfstdt = input(scan(rfstdtc_dm,1,'T'), yymmdd10.);
        
        if not missing(endt) and not missing(rfstdt) then do;
            if endt >= rfstdt then
                DVENDY = endt - rfstdt + 1;
            else
                DVENDY = endt - rfstdt;
        end;
    end;
    
    *-------------------------------------------------------------------------*
    * Derive EPOCH based on date relative to treatment period                 *
    *-------------------------------------------------------------------------*;
    if not missing(epoch_raw) then EPOCH = strip(epoch_raw);
    else if not missing(epoch) then EPOCH = strip(epoch);
    else if not missing(DVSTDY) then do;
        if DVSTDY < 1 then EPOCH = 'SCREENING';
        else if DVSTDY >= 1 then EPOCH = 'TREATMENT';
    end;
    
    *-------------------------------------------------------------------------*
    * Keep only necessary variables for processing                            *
    *-------------------------------------------------------------------------*;
    keep STUDYID DOMAIN USUBJID DVTERM DVDECOD DVCAT DVSCAT DVBODSYS 
         DVSTDTC DVENDTC DVSTDY DVENDY EPOCH;
run;

*-----------------------------------------------------------------------------;
* Sort and create DVSEQ                                                      ;
*-----------------------------------------------------------------------------;
proc sort data=sdtm.dv;
    by STUDYID USUBJID DVSTDTC DVTERM;
run;

data sdtm.dv;
    set sdtm.dv;
    by STUDYID USUBJID;
    
    retain DVSEQ;
    
    *-------------------------------------------------------------------------*
    * Derive DVSEQ - Sequence Number within subject                           *
    *-------------------------------------------------------------------------*;
    if first.USUBJID then DVSEQ = 0;
    DVSEQ + 1;
run;

*-----------------------------------------------------------------------------;
* Final sort and output with specified variable order                        ;
*-----------------------------------------------------------------------------;
proc sort data=sdtm.dv;
    by STUDYID USUBJID DVSEQ;
run;

data sdtm.dv;
    retain STUDYID DOMAIN USUBJID DVSEQ DVTERM DVDECOD DVCAT DVSCAT 
           DVBODSYS DVSTDTC DVENDTC DVSTDY DVENDY EPOCH;
    set sdtm.dv;
    
    label STUDYID  = "Study Identifier"
          DOMAIN   = "Domain Abbreviation"
          USUBJID  = "Unique Subject Identifier"
          DVSEQ    = "Sequence Number"
          DVTERM   = "Reported Term for the Protocol Deviation"
          DVDECOD  = "Dictionary-Derived Term"
          DVCAT    = "Category for Protocol Deviation"
          DVSCAT   = "Subcategory for Protocol Deviation"
          DVBODSYS = "Body System or Organ Class"
          DVSTDTC  = "Start Date/Time of Protocol Deviation"
          DVENDTC  = "End Date/Time of Protocol Deviation"
          DVSTDY   = "Study Day of Start of Protocol Deviation"
          DVENDY   = "Study Day of End of Protocol Deviation"
          EPOCH    = "Epoch";
run;

*-----------------------------------------------------------------------------;
* Generate summary report                                                    ;
*-----------------------------------------------------------------------------;
proc freq data=sdtm.dv;
    tables DVCAT DVSCAT EPOCH / missing;
    title "DV Domain - Summary Report";
run;

proc means data=sdtm.dv n nmiss min max;
    var DVSEQ DVSTDY DVENDY;
    title "DV Domain - Numeric Variable Summary";
run;

title;

/*-- END DV --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.dv;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.dv varnum;
run;

proc freq data=sdtm.dv;
  tables DOMAIN / nocum nopercent;
run;

/* End of dv.sas */
