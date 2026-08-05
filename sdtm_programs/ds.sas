/*******************************************************************************
* Program:    ds.sas
* Domain:     DS (Disposition)
* Purpose:    Create SDTM DS domain dataset
* Variables:  14
*
* Input:      raw.ds (source CRF data)
*             sdtm.dm (for USUBJID, RFSTDTC)
* Output:     sdtm.ds (DS domain dataset)
*
* Variables:  STUDYID, DSSEQ, USUBJID, DOMAIN, DSTERM, DSDECOD, DSCAT, DSSCAT,
*             DSBODSYS, DSSTDTC, DSENDTC, DSSTDY, DSENDY, EPOCH
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- Read DM for subject-level information --*/
proc sort data=sdtm.dm(keep=studyid usubjid rfstdtc) out=dm_lookup nodupkey;
    by studyid usubjid;
run;

/*-- Read and sort source disposition data --*/
proc sort data=raw.ds out=raw_ds_sorted;
    by studyid usubjid;
run;

/*-- Merge and create DS domain --*/
data ds_pre;
    length STUDYID $20
           DOMAIN $2
           USUBJID $40
           DSSEQ 8
           DSTERM $200
           DSDECOD $200
           DSCAT $40
           DSSCAT $40
           DSBODSYS $200
           DSSTDTC $20
           DSENDTC $20
           DSSTDY 8
           DSENDY 8
           EPOCH $20;
    
    merge raw_ds_sorted(in=a)
          dm_lookup(in=b);
    by studyid usubjid;
    
    if a;
    
    * Warn if subject not in DM;
    if not b then do;
        put "WARNING: Subject not found in DM - " studyid= usubjid=;
    end;
    
    * Set domain abbreviation;
    DOMAIN = 'DS';
    
    * Map disposition term and decoded term;
    DSTERM = strip(ds_term);
    DSDECOD = strip(ds_decod);
    
    * If no decoded term provided, use the reported term;
    if missing(DSDECOD) and not missing(DSTERM) then DSDECOD = DSTERM;
    
    * Map category and subcategory;
    DSCAT = strip(ds_cat);
    DSSCAT = strip(ds_scat);
    
    * Map body system;
    DSBODSYS = strip(ds_bodsys);
    
    * Map epoch;
    EPOCH = strip(ds_epoch);
    
    * Convert start date/time to ISO 8601 format;
    if not missing(ds_stdt) then do;
        dsstdtc_sas = input(ds_stdt, ??yymmdd10.);
        if not missing(dsstdtc_sas) then do;
            DSSTDTC = put(dsstdtc_sas, e8601da.);
            if not missing(ds_sttm) then do;
                DSSTDTC = strip(DSSTDTC) || 'T' || put(ds_sttm, time5.);
            end;
        end;
    end;
    
    * Convert end date/time to ISO 8601 format;
    if not missing(ds_endt) then do;
        dsendtc_sas = input(ds_endt, ??yymmdd10.);
        if not missing(dsendtc_sas) then do;
            DSENDTC = put(dsendtc_sas, e8601da.);
            if not missing(ds_entm) then do;
                DSENDTC = strip(DSENDTC) || 'T' || put(ds_entm, time5.);
            end;
        end;
    end;
    
    * Calculate study day for start date;
    if not missing(DSSTDTC) and not missing(rfstdtc) then do;
        rfstdtc_sas = input(scan(rfstdtc, 1, 'T'), ??e8601da.);
        if missing(rfstdtc_sas) then rfstdtc_sas = input(scan(rfstdtc, 1, 'T'), ??yymmdd10.);
        dsstdtc_sas = input(scan(DSSTDTC, 1, 'T'), ??e8601da.);
        if not missing(dsstdtc_sas) and not missing(rfstdtc_sas) then do;
            if dsstdtc_sas >= rfstdtc_sas then 
                DSSTDY = dsstdtc_sas - rfstdtc_sas + 1;
            else 
                DSSTDY = dsstdtc_sas - rfstdtc_sas;
        end;
    end;
    
    * Calculate study day for end date;
    if not missing(DSENDTC) and not missing(rfstdtc) then do;
        rfstdtc_sas = input(scan(rfstdtc, 1, 'T'), ??e8601da.);
        if missing(rfstdtc_sas) then rfstdtc_sas = input(scan(rfstdtc, 1, 'T'), ??yymmdd10.);
        dsendtc_sas = input(scan(DSENDTC, 1, 'T'), ??e8601da.);
        if not missing(dsendtc_sas) and not missing(rfstdtc_sas) then do;
            if dsendtc_sas >= rfstdtc_sas then 
                DSENDY = dsendtc_sas - rfstdtc_sas + 1;
            else 
                DSENDY = dsendtc_sas - rfstdtc_sas;
        end;
    end;
    
    keep STUDYID DOMAIN USUBJID DSTERM DSDECOD DSCAT DSSCAT DSBODSYS 
         DSSTDTC DSENDTC DSSTDY DSENDY EPOCH;
run;

/*-- Sort and assign sequence number --*/
proc sort data=ds_pre;
    by STUDYID USUBJID DSSTDTC DSTERM;
run;

data ds_seq;
    set ds_pre;
    by STUDYID USUBJID;
    
    * Create sequence number within subject;
    if first.USUBJID then DSSEQ = 0;
    DSSEQ + 1;
run;

/*-- Final dataset with proper variable order and labels --*/
data sdtm.ds;
    retain STUDYID DOMAIN USUBJID DSSEQ DSTERM DSDECOD DSCAT DSSCAT DSBODSYS 
           DSSTDTC DSENDTC DSSTDY DSENDY EPOCH;
    set ds_seq;
    
    label STUDYID   = "Study Identifier"
          DOMAIN    = "Domain Abbreviation"
          USUBJID   = "Unique Subject Identifier"
          DSSEQ     = "Sequence Number"
          DSTERM    = "Reported Term for the Disposition Event"
          DSDECOD   = "Standardized Disposition Term"
          DSCAT     = "Category for Disposition Event"
          DSSCAT    = "Subcategory for Disposition Event"
          DSBODSYS  = "Body System or Organ Class"
          DSSTDTC   = "Start Date/Time of Disposition Event"
          DSENDTC   = "End Date/Time of Disposition Event"
          DSSTDY    = "Study Day of Start of Disposition Event"
          DSENDY    = "Study Day of End of Disposition Event"
          EPOCH     = "Epoch";
run;

/*-- Final sort by STUDYID USUBJID DSSEQ per SDTM standard --*/
proc sort data=sdtm.ds;
    by STUDYID USUBJID DSSEQ;
run;

/*-- Output verification --*/
proc contents data=sdtm.ds varnum;
    title "DS Domain Contents";
run;

proc sql;
    title "DS Domain Summary";
    select count(*) as Total_Records,
           count(distinct USUBJID) as Total_Subjects,
           count(distinct DSDECOD) as Unique_DS_Terms
    from sdtm.ds;
quit;

title;

/* End of ds.sas */