/*******************************************************************************
* Program:    eg.sas
* Domain:     EG (Findings)
* Purpose:    Create SDTM EG domain dataset
* Variables:  19
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.eg (source CRF data)
* Output:     sdtm.eg (EG domain dataset)
*
* Variables:  STUDYID, EGSEQ, USUBJID, DOMAIN, EGTESTCD, EGTEST, EGCAT, EGORRES
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*=======================================================================================
  Program:      SDTM_EG.sas
  Description:  Create SDTM EG (Electrocardiogram) domain
  Study:        [Study Protocol]
  Version:      1.0
  Author:       Senior CDISC SDTM Programmer
  Date:         [Date]
=======================================================================================*/

/*-- BEGIN EG --*/

/*---------------------------------------------------------------------------------------
  Step 1: Read DM domain for subject-level information
---------------------------------------------------------------------------------------*/
proc sort data=sdtm.dm(keep=studyid usubjid rfstdtc) out=dm_ref nodupkey;
    by usubjid;
run;

/*---------------------------------------------------------------------------------------
  Step 2: Read raw EG data and merge with DM
  Assumption: raw.eg contains one row per visit per subject with test results
---------------------------------------------------------------------------------------*/
data eg_raw;
    merge raw.eg(in=a)
          dm_ref(in=b);
    by usubjid;
    if a;
    
    /* Ensure STUDYID is populated from DM */
    if missing(studyid) and b then studyid = dm_ref.studyid;
    
    length egdtc_raw $19;
    /* Ensure date/time is in ISO 8601 format */
    if not missing(egdat) then do;
        if not missing(egtim) then 
            egdtc_raw = put(egdat, yymmdd10.) || 'T' || put(egtim, time8.);
        else 
            egdtc_raw = put(egdat, yymmdd10.);
    end;
run;

/*---------------------------------------------------------------------------------------
  Step 3: Transpose data from wide to vertical format (one row per test per timepoint)
  Assumption: Source has columns like HEART_RATE, PR_INT, QRS_DUR, QT_INT, QTC_INT, etc.
---------------------------------------------------------------------------------------*/
data eg_vertical;
    set eg_raw;
    
    length egtestcd $8 egtest $40 egcat $40 egorres $200 egorresu $20 
           egstat $8 egreasnd $200;
    
    /* Initialize category */
    egcat = "ELECTROCARDIOGRAM";
    
    /* Initialize variables for each record */
    egstat = "";
    egreasnd = "";
    
    /* Heart Rate */
    if not missing(heart_rate) or not missing(heart_rate_nd) then do;
        egtestcd = "HR";
        egtest = "Heart Rate";
        if not missing(heart_rate) then do;
            egorres = strip(put(heart_rate, best.));
            egorresu = "beats/min";
            egstat = "";
            egreasnd = "";
        end;
        else if not missing(heart_rate_nd) then do;
            egorres = "";
            egorresu = "";
            egstat = "NOT DONE";
            egreasnd = strip(heart_rate_nd);
        end;
        output;
    end;
    
    /* Reset for next test */
    egstat = "";
    egreasnd = "";
    
    /* PR Interval */
    if not missing(pr_int) or not missing(pr_int_nd) then do;
        egtestcd = "PRINTR";
        egtest = "PR Interval";
        if not missing(pr_int) then do;
            egorres = strip(put(pr_int, best.));
            egorresu = "msec";
            egstat = "";
            egreasnd = "";
        end;
        else if not missing(pr_int_nd) then do;
            egorres = "";
            egorresu = "";
            egstat = "NOT DONE";
            egreasnd = strip(pr_int_nd);
        end;
        output;
    end;
    
    egstat = "";
    egreasnd = "";
    
    /* QRS Duration */
    if not missing(qrs_dur) or not missing(qrs_dur_nd) then do;
        egtestcd = "QRSDUR";
        egtest = "QRS Duration";
        if not missing(qrs_dur) then do;
            egorres = strip(put(qrs_dur, best.));
            egorresu = "msec";
            egstat = "";
            egreasnd = "";
        end;
        else if not missing(qrs_dur_nd) then do;
            egorres = "";
            egorresu = "";
            egstat = "NOT DONE";
            egreasnd = strip(qrs_dur_nd);
        end;
        output;
    end;
    
    egstat = "";
    egreasnd = "";
    
    /* QT Interval */
    if not missing(qt_int) or not missing(qt_int_nd) then do;
        egtestcd = "QT";
        egtest = "QT Interval";
        if not missing(qt_int) then do;
            egorres = strip(put(qt_int, best.));
            egorresu = "msec";
            egstat = "";
            egreasnd = "";
        end;
        else if not missing(qt_int_nd) then do;
            egorres = "";
            egorresu = "";
            egstat = "NOT DONE";
            egreasnd = strip(qt_int_nd);
        end;
        output;
    end;
    
    egstat = "";
    egreasnd = "";
    
    /* QTc Interval (Corrected) */
    if not missing(qtc_int) or not missing(qtc_int_nd) then do;
        egtestcd = "QTC";
        egtest = "QT Corrected";
        if not missing(qtc_int) then do;
            egorres = strip(put(qtc_int, best.));
            egorresu = "msec";
            egstat = "";
            egreasnd = "";
        end;
        else if not missing(qtc_int_nd) then do;
            egorres = "";
            egorresu = "";
            egstat = "NOT DONE";
            egreasnd = strip(qtc_int_nd);
        end;
        output;
    end;
    
    egstat = "";
    egreasnd = "";
    
    /* RR Interval */
    if not missing(rr_int) or not missing(rr_int_nd) then do;
        egtestcd = "RR";
        egtest = "RR Interval";
        if not missing(rr_int) then do;
            egorres = strip(put(rr_int, best.));
            egorresu = "msec";
            egstat = "";
            egreasnd = "";
        end;
        else if not missing(rr_int_nd) then do;
            egorres = "";
            egorresu = "";
            egstat = "NOT DONE";
            egreasnd = strip(rr_int_nd);
        end;
        output;
    end;
    
    egstat = "";
    egreasnd = "";
    
    /* QTcB (Bazett) */
    if not missing(qtcb) or not missing(qtcb_nd) then do;
        egtestcd = "QTCB";
        egtest = "QT Corrected by Bazett's Formula";
        if not missing(qtcb) then do;
            egorres = strip(put(qtcb, best.));
            egorresu = "msec";
            egstat = "";
            egreasnd = "";
        end;
        else if not missing(qtcb_nd) then do;
            egorres = "";
            egorresu = "";
            egstat = "NOT DONE";
            egreasnd = strip(qtcb_nd);
        end;
        output;
    end;
    
    egstat = "";
    egreasnd = "";
    
    /* QTcF (Fridericia) */
    if not missing(qtcf) or not missing(qtcf_nd) then do;
        egtestcd = "QTCF";
        egtest = "QT Corrected by Fridericia's Formula";
        if not missing(qtcf) then do;
            egorres = strip(put(qtcf, best.));
            egorresu = "msec";
            egstat = "";
            egreasnd = "";
        end;
        else if not missing(qtcf_nd) then do;
            egorres = "";
            egorresu = "";
            egstat = "NOT DONE";
            egreasnd = strip(qtcf_nd);
        end;
        output;
    end;
    
    keep studyid usubjid egtestcd egtest egcat egorres egorresu egstat egreasnd 
         visitnum visit egdtc_raw rfstdtc egeval;
run;

/*---------------------------------------------------------------------------------------
  Step 4: Derive SDTM variables
---------------------------------------------------------------------------------------*/
data eg_derive;
    set eg_vertical;
    
    length domain $2 egstresc $200 egstresu $20 egdtc $19;
    
    /* Set domain */
    domain = "EG";
    
    /* Derive EGSTRESC and EGSTRESN from EGORRES */
    if egstat ne "NOT DONE" then do;
        egstresc = strip(egorres);
        egstresn = input(egorres, ?? best.);
    end;
    else do;
        egstresc = "";
        egstresn = .;
    end;
    
    /* Derive EGSTRESU - standard units (same as original for EG) */
    if egstat ne "NOT DONE" then egstresu = egorresu;
    else egstresu = "";
    
    /* Map EGDTC from raw date/time - keep in ISO 8601 format */
    egdtc = strip(egdtc_raw);
    
    /* Derive EGDY - study day relative to RFSTDTC */
    if not missing(egdtc) and not missing(rfstdtc) and length(egdtc) >= 10 and length(rfstdtc) >= 10 then do;
        egdy_calc = input(substr(egdtc, 1, 10), ?? yymmdd10.) - 
                    input(substr(rfstdtc, 1, 10), ?? yymmdd10.);
        if egdy_calc >= 0 then egdy = egdy_calc + 1;
        else egdy = egdy_calc;
    end;
    
    drop egdtc_raw rfstdtc egdy_calc;
run;

/*---------------------------------------------------------------------------------------
  Step 5: Sort and derive EGSEQ
---------------------------------------------------------------------------------------*/
proc sort data=eg_derive;
    by studyid usubjid visitnum egdtc egtestcd;
run;

data eg_seq;
    set eg_derive;
    by studyid usubjid;
    
    retain egseq;
    
    /* Derive sequence number */
    if first.usubjid then egseq = 0;
    egseq + 1;
run;

/*---------------------------------------------------------------------------------------
  Step 6: Apply labels and output final dataset
---------------------------------------------------------------------------------------*/
data sdtm.eg(label="Electrocardiogram");
    retain studyid domain usubjid egseq egtestcd egtest egcat egorres egorresu 
           egstresc egstresn egstresu egstat egreasnd visitnum visit egdtc egdy egeval;
    set eg_seq;
    
    /* Apply variable labels */
    label
        studyid  = "Study Identifier"
        domain   = "Domain Abbreviation"
        usubjid  = "Unique Subject Identifier"
        egseq    = "Sequence Number"
        egtestcd = "ECG Test Short Name"
        egtest   = "ECG Test Name"
        egcat    = "Category for ECG"
        egorres  = "Result or Finding in Original Units"
        egorresu = "Original Units"
        egstresc = "Character Result/Finding in Std Format"
        egstresn = "Numeric Result/Finding in Standard Units"
        egstresu = "Standard Units"
        egstat   = "Completion Status"
        egreasnd = "Reason Not Done"
        visitnum = "Visit Number"
        visit    = "Visit Name"
        egdtc    = "Date/Time of ECG"
        egdy     = "Study Day of ECG"
        egeval   = "Evaluator"
    ;
    
    /* Set variable lengths and formats */
    length studyid $20 domain $2 usubjid $40 egtestcd $8 egtest $40 
           egcat $40 egorres $200 egorresu $20 egstresc $200 egstresu $20 
           egstat $8 egreasnd $200 visit $200 egdtc $19 egeval $40;
    
    format egseq 8. egstresn 8. egdy 8. visitnum 8.;
    
    /* Keep only SDTM variables in specified order */
    keep studyid domain usubjid egseq egtestcd egtest egcat egorres egorresu 
         egstresc egstresn egstresu egstat egreasnd visitnum visit egdtc egdy egeval;
run;

/*---------------------------------------------------------------------------------------
  Step 7: Final sort
---------------------------------------------------------------------------------------*/
proc sort data=sdtm.eg;
    by studyid usubjid visitnum egdtc egtestcd;
run;

/*---------------------------------------------------------------------------------------
  Step 8: Generate summary report
---------------------------------------------------------------------------------------*/
proc freq data=sdtm.eg;
    tables egtestcd * egtest / list missing;
    tables egstat / missing;
    title "EG Domain - Test Code and Status Summary";
run;

proc means data=sdtm.eg n nmiss min max mean std;
    var egstresn egdy;
    class egtestcd;
    title "EG Domain - Numeric Results Summary by Test";
run;

title;

/*-- END EG --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.eg;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.eg varnum;
run;

proc freq data=sdtm.eg;
  tables DOMAIN / nocum nopercent;
run;

/* End of eg.sas */
