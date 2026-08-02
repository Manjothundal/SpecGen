/*******************************************************************************
* Program:    dm.sas
* Domain:     DM (DM)
* Purpose:    Create SDTM DM domain dataset
* Variables:  28
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.dm (source CRF data)
* Output:     sdtm.dm (DM domain dataset)
*
* Variables:  STUDYID, DOMAIN, USUBJID, SUBJID, SITEID, RFSTDTC, RFENDTC, RFXSTDTC
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*****************************************************************************************
Program:      dm.sas
Purpose:      Create SDTM DM (Demographics) domain
Programmer:   Senior CDISC SDTM Programmer
Date:         [Date]
Input:        raw.dm - Demographics CRF data
              raw.ex - Exposure data
Output:       sdtm.dm
******************************************************************************************/

/*-- BEGIN DM --*/

*-----------------------------------------------------------------------------*
* Step 1: Get first and last exposure dates from EX domain for RFXSTDTC/RFXENDTC
*-----------------------------------------------------------------------------*;
proc sort data=raw.ex(where=(exstdtc ne '')) out=ex_sorted;
    by studyid siteid subjid exstdtc;
run;

data ex_dates;
    set ex_sorted;
    by studyid siteid subjid;
    
    length usubjid $200 rfxstdtc rfxendtc $20;
    
    * Create USUBJID *;
    usubjid = catx('-', put(studyid,$20.-L), put(siteid,$10.-L), put(subjid,$20.-L));
    
    retain rfxstdtc rfxendtc;
    
    * Keep first exposure date *;
    if first.subjid then rfxstdtc = exstdtc;
    
    * Keep last exposure date *;
    if last.subjid then do;
        rfxendtc = exstdtc;
        output;
    end;
    
    keep usubjid rfxstdtc rfxendtc;
run;

*-----------------------------------------------------------------------------*
* Step 2: Read demographics source data and merge with exposure dates
*-----------------------------------------------------------------------------*;
proc sort data=raw.dm;
    by studyid siteid subjid;
run;

data dm_base;
    merge raw.dm(in=a)
          ex_dates(in=b);
    by usubjid;
    
    if a; * Keep all subjects from DM *;
    
    length studyid $20 domain $2 usubjid $200 subjid $20 siteid $10 
           rfstdtc rfendtc rfxstdtc rfxendtc rficdtc rfpendtc dthdtc $20
           dthfl $1 invnam $200 invid $20
           brthdtc $20 age 8 ageu $10 sex $1 race $200 ethnic $200
           armcd $20 arm $200 actarmcd $20 actarm $200 country $3 dmdtc $20 dmdy 8;
    
    * Assign constant values *;
    domain = 'DM';
    
    * Derive USUBJID *;
    usubjid = catx('-', put(studyid,$20.-L), put(siteid,$10.-L), put(subjid,$20.-L));
    
    * Direct mappings from CRF *;
    subjid = put(subjid, $20.-L);
    siteid = put(siteid, $10.-L);
    sex = upcase(sex);
    
    * Reference dates from exposure *;
    rfstdtc = rfxstdtc;  * First dose date *;
    rfendtc = rfxendtc;  * Last dose date *;
    
    * Informed consent date *;
    if not missing(icdtc) then rficdtc = icdtc;
    
    * Protocol end date - map from raw if available *;
    if not missing(pendtc) then rfpendtc = pendtc;
    
    * Death information *;
    if not missing(dthdtc_raw) then do;
        dthdtc = dthdtc_raw;
        dthfl = 'Y';
    end;
    else if not missing(dthfl_raw) and upcase(dthfl_raw) = 'Y' then dthfl = 'Y';
    else dthfl = 'N';
    
    * Investigator information *;
    if not missing(invnam_raw) then invnam = invnam_raw;
    if not missing(invid_raw) then invid = invid_raw;
    
    * Country mapping - derive from raw.dm if available *;
    if not missing(country_raw) then country = upcase(country_raw);
    
    * DM Collection Date *;
    if not missing(dmdtc_raw) then dmdtc = dmdtc_raw;
    
run;

*-----------------------------------------------------------------------------*
* Step 3: Derive AGE and AGEU
*-----------------------------------------------------------------------------*;
data dm_age;
    set dm_base;
    
    * Derive AGE if not collected directly *;
    if missing(age) and not missing(brthdtc) and not missing(rfstdtc) then do;
        * Calculate age in years *;
        age = floor((input(substr(rfstdtc,1,10), yymmdd10.) - 
                     input(substr(brthdtc,1,10), yymmdd10.)) / 365.25);
        ageu = 'YEARS';
    end;
    else if not missing(age) and missing(ageu) then ageu = 'YEARS';
    
    * Format age as numeric *;
    format age 8.;
    
run;

*-----------------------------------------------------------------------------*
* Step 4: Derive DMDY (Study Day of DM Collection)
*-----------------------------------------------------------------------------*;
data dm_dmdy;
    set dm_age;
    
    * Derive DMDY relative to RFSTDTC *;
    if not missing(dmdtc) and not missing(rfstdtc) then do;
        dmdy = input(substr(dmdtc,1,10), yymmdd10.) - input(substr(rfstdtc,1,10), yymmdd10.);
        if dmdy >= 0 then dmdy = dmdy + 1;
    end;
    
    format dmdy 8.;
    
run;

*-----------------------------------------------------------------------------*
* Step 5: Apply labels and create final DM dataset
*-----------------------------------------------------------------------------*;
data sdtm.dm;
    set dm_dmdy;
    
    label
        studyid  = "Study Identifier"
        domain   = "Domain Abbreviation"
        usubjid  = "Unique Subject Identifier"
        subjid   = "Subject Identifier for the Study"
        siteid   = "Study Site Identifier"
        rfstdtc  = "Subject Reference Start Date/Time"
        rfendtc  = "Subject Reference End Date/Time"
        rfxstdtc = "Date/Time of First Study Treatment"
        rfxendtc = "Date/Time of Last Study Treatment"
        rficdtc  = "Date/Time of Informed Consent"
        rfpendtc = "Date/Time of End of Participation"
        dthdtc   = "Date/Time of Death"
        dthfl    = "Subject Death Flag"
        invnam   = "Investigator Name"
        invid    = "Investigator Identifier"
        brthdtc  = "Date/Time of Birth"
        age      = "Age"
        ageu     = "Age Units"
        sex      = "Sex"
        race     = "Race"
        ethnic   = "Ethnicity"
        armcd    = "Planned Arm Code"
        arm      = "Description of Planned Arm"
        actarmcd = "Actual Arm Code"
        actarm   = "Description of Actual Arm"
        country  = "Country"
        dmdtc    = "Date/Time of Collection"
        dmdy     = "Study Day of Collection"
    ;
    
    keep
        studyid
        domain
        usubjid
        subjid
        siteid
        rfstdtc
        rfendtc
        rfxstdtc
        rfxendtc
        rficdtc
        rfpendtc
        dthdtc
        dthfl
        invnam
        invid
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
    ;
run;

*-----------------------------------------------------------------------------*
* Step 6: Sort final dataset by STUDYID USUBJID
*-----------------------------------------------------------------------------*;
proc sort data=sdtm.dm;
    by studyid usubjid;
run;

*-----------------------------------------------------------------------------*
* Step 7: Generate summary report
*-----------------------------------------------------------------------------*;
proc freq data=sdtm.dm;
    tables sex race ethnic armcd actarmcd dthfl / missing;
    title "DM Domain - Frequency Counts";
run;

proc means data=sdtm.dm n nmiss mean std min max;
    var age;
    title "DM Domain - Age Statistics";
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
