/*******************************************************************************
* Program:    dm.sas
* Domain:     DM (DM)
* Purpose:    Create SDTM DM domain dataset
* Variables:  24
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.dm (source CRF data)
* Output:     sdtm.dm (DM domain dataset)
*
* Variables:  STUDYID, DMSEQ, USUBJID, DOMAIN, RFSTDTC, RFENDTC, RFXSTDTC, RFXENDTC
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*=======================================================================================
  Program:      DM_SDTM.sas
  Description:  Create SDTM Demographics (DM) Domain
  Input:        raw.dm, raw.ex
  Output:       sdtm.dm
=======================================================================================*/

/*-- BEGIN DM --*/

*----------------------------------------------------------------------------*
* Step 1: Derive Reference Dates from Exposure (EX) Domain                   *
*----------------------------------------------------------------------------*;
proc sort data=raw.ex(where=(exstdtc ne '')) out=ex_dates;
    by usubjid exstdtc;
run;

* Get first dose date (RFSTDTC, RFXSTDTC);
data ex_first;
    set ex_dates;
    by usubjid exstdtc;
    if first.usubjid;
    length rfstdtc_ex $20;
    rfstdtc_ex = exstdtc;
    keep usubjid rfstdtc_ex;
run;

* Get last dose date (RFENDTC, RFXENDTC);
proc sort data=ex_dates;
    by usubjid descending exstdtc;
run;

data ex_last;
    set ex_dates;
    by usubjid descending exstdtc;
    if first.usubjid;
    length rfendtc_ex $20;
    rfendtc_ex = exstdtc;
    keep usubjid rfendtc_ex;
run;

* Merge first and last exposure dates;
data ex_ref_dates;
    merge ex_first ex_last;
    by usubjid;
run;

*----------------------------------------------------------------------------*
* Step 2: Create DM Domain                                                   *
*----------------------------------------------------------------------------*;
data dm_temp;
    merge raw.dm(in=a)
          ex_ref_dates;
    by usubjid;
    if a;
    
    *--- Define Variable Attributes ---;
    length studyid $20 
           domain $2
           usubjid $40
           subjid $20
           rfstdtc $20
           rfendtc $20
           rfxstdtc $20
           rfxendtc $20
           siteid $10
           invid $20
           invnam $100
           country $3
           armcd $20
           arm $200
           actarmcd $20
           actarm $200
           brthdtc $10
           ethnic $50
           race $50
           sex $1
           randnum $20
           rficdtc $20;
    
    *--- Constants ---;
    studyid = "PROTOCOL001";
    domain = "DM";
    
    *--- Derive USUBJID if missing ---;
    if missing(usubjid) then
        usubjid = catx('-', studyid, siteid, subjid);
    
    *--- Derive Reference Dates ---;
    rfstdtc = rfstdtc_ex;
    rfendtc = rfendtc_ex;
    rfxstdtc = rfstdtc_ex;
    rfxendtc = rfendtc_ex;
    
    *--- Derive Actual Arm from Planned Arm if not available ---;
    if missing(actarmcd) then actarmcd = armcd;
    if missing(actarm) then actarm = arm;
    
    *--- Derive AGE if not collected and both dates available ---;
    if missing(age) and not missing(brthdtc) and not missing(rfstdtc) then do;
        birth_date = input(brthdtc, ??yymmdd10.);
        if missing(birth_date) then birth_date = input(brthdtc, ??yymmdd8.);
        if missing(birth_date) then birth_date = input(substr(brthdtc,1,10), ??yymmdd10.);
        
        ref_date = input(substr(rfstdtc,1,10), ??yymmdd10.);
        
        if not missing(birth_date) and not missing(ref_date) then
            age = floor(yrdif(birth_date, ref_date, 'AGE'));
    end;
    
    drop rfstdtc_ex rfendtc_ex birth_date ref_date;
run;

*----------------------------------------------------------------------------*
* Step 3: Assign Sequence Number                                             *
*----------------------------------------------------------------------------*;
proc sort data=dm_temp;
    by studyid usubjid;
run;

data dm_sorted;
    set dm_temp;
    by studyid usubjid;
    
    *--- Derive DMSEQ ---;
    dmseq = _N_;
    
    *--- Apply Variable Labels ---;
    label
        studyid    = "Study Identifier"
        dmseq      = "Sequence Number"
        usubjid    = "Unique Subject Identifier"
        subjid     = "Subject Identifier for the Study"
        domain     = "Domain Abbreviation"
        rfstdtc    = "Subject Reference Start Date/Time"
        rfendtc    = "Subject Reference End Date/Time"
        rfxstdtc   = "Date/Time of First Study Treatment"
        rfxendtc   = "Date/Time of Last Study Treatment"
        siteid     = "Study Site Identifier"
        invid      = "Investigator Identifier"
        invnam     = "Investigator Name"
        country    = "Country"
        armcd      = "Planned Arm Code"
        arm        = "Description of Planned Arm"
        actarmcd   = "Actual Arm Code"
        actarm     = "Description of Actual Arm"
        age        = "Age"
        brthdtc    = "Date/Time of Birth"
        ethnic     = "Ethnicity"
        race       = "Race"
        randnum    = "Randomization Number"
        rficdtc    = "Date/Time of Informed Consent"
        sex        = "Sex"
    ;
run;

*----------------------------------------------------------------------------*
* Step 4: Create Final Dataset with Correct Variable Order                   *
*----------------------------------------------------------------------------*;
data sdtm.dm;
    retain
        studyid
        domain
        usubjid
        subjid
        rfstdtc
        rfendtc
        rfxstdtc
        rfxendtc
        rficdtc
        rfpendtc
        dthdtc
        dthfl
        siteid
        invid
        invnam
        brthdtc
        age
        ageu
        sex
        race
        ethnic
        armcd
        arm
        actarmcd
        actarm
        country
        dmdtc
        dmdy
        randnum;
    set dm_sorted;
    
    *--- Keep Only Required Variables ---;
    keep
        studyid
        dmseq
        usubjid
        subjid
        domain
        rfstdtc
        rfendtc
        rfxstdtc
        rfxendtc
        siteid
        invid
        invnam
        country
        armcd
        arm
        actarmcd
        actarm
        age
        brthdtc
        ethnic
        race
        randnum
        rficdtc
        sex
    ;
run;

*----------------------------------------------------------------------------*
* Step 5: Final Sort by USUBJID                                              *
*----------------------------------------------------------------------------*;
proc sort data=sdtm.dm;
    by usubjid;
run;

*----------------------------------------------------------------------------*
* Step 6: Generate Summary Report                                            *
*----------------------------------------------------------------------------*;
proc contents data=sdtm.dm varnum;
    title "SDTM DM Domain - Contents";
run;

proc freq data=sdtm.dm;
    tables sex race ethnic armcd actarmcd / missing;
    title "SDTM DM Domain - Frequency Counts";
run;

proc means data=sdtm.dm n nmiss min max mean std;
    var age dmseq;
    title "SDTM DM Domain - Continuous Variables";
run;

title;

/*-- END DM --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.dm;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.dm varnum;
run;

proc freq data=sdtm.dm;
  tables DOMAIN / nocum nopercent;
run;

/* End of dm.sas */
