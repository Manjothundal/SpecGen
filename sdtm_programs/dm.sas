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

/*==========================================================================================*
  Program:      dm.sas
  Description:  Create SDTM DM (Demographics) Domain
  Study:        [STUDY_NAME]
  Programmer:   [PROGRAMMER_NAME]
  Date:         [DATE]
  
  Input:        raw.dm  - Demographics CRF data
                raw.ex  - Exposure data for reference dates
                
  Output:       sdtm.dm - SDTM Demographics Domain
*===========================================================================================*/

/*-- BEGIN DM --*/

*==============================================================================;
* Step 1: Extract first and last exposure dates from EX domain
*==============================================================================;
proc sort data=raw.ex out=ex_temp;
    by studyid siteid subjid exstdtc;
    where exstdtc ne '';
run;

data ex_dates;
    set ex_temp;
    by studyid siteid subjid;
    
    length rfstdtc rfendtc rfxstdtc rfxendtc $19;
    
    retain rfstdtc rfendtc rfxstdtc rfxendtc;
    
    * Keep first exposure date;
    if first.subjid then do;
        rfstdtc = exstdtc;
        rfxstdtc = exstdtc;
    end;
    
    * Keep last exposure date;
    if last.subjid then do;
        rfendtc = exstdtc;
        rfxendtc = exstdtc;
        output;
    end;
    
    keep studyid siteid subjid rfstdtc rfendtc rfxstdtc rfxendtc;
run;

*==============================================================================;
* Step 2: Create DM domain from demographics CRF data
*==============================================================================;
data dm_pre;
    merge raw.dm(in=a)
          ex_dates(in=b);
    by studyid siteid subjid;
    if a;
    
    length 
        studyid $20
        domain $2
        usubjid $40
        subjid $20
        siteid $10
        invid $10
        invnam $60
        country $3
        armcd $20
        arm $200
        actarmcd $20
        actarm $200
        ethnic $40
        race $40
        randnum $20
        rficdtc $19
        sex $1
        brthdtc $19
        rfstdtc $19
        rfendtc $19
        rfxstdtc $19
        rfxendtc $19
    ;
    
    *---------------------------------------------------------;
    * Assign constant values
    *---------------------------------------------------------;
    domain = 'DM';
    
    *---------------------------------------------------------;
    * Derive USUBJID
    *---------------------------------------------------------;
    usubjid = catx('-', studyid, siteid, subjid);
    
    *---------------------------------------------------------;
    * Map CRF variables to SDTM variables
    *---------------------------------------------------------;
    * Direct mappings from raw.dm;
    studyid = studyid;
    siteid = siteid;
    subjid = subjid;
    sex = upcase(sex);
    
    * Convert birth date to ISO 8601;
    if not missing(brthdt) then brthdtc = put(brthdt, e8601da.);
    else brthdtc = '';
    
    * Map ethnicity;
    ethnic = strip(ethnic);
    
    * Map race;
    race = strip(race);
    
    * Randomization number and informed consent date;
    randnum = strip(randnum);
    if not missing(icfdt) then rficdtc = put(icfdt, e8601da.);
    else rficdtc = '';
    
    *---------------------------------------------------------;
    * Derive/Map ARM and ARMCD
    *---------------------------------------------------------;
    armcd = strip(armcd);
    arm = strip(arm);
    
    *---------------------------------------------------------;
    * Derive ACTARM and ACTARMCD (use planned if actual not available)
    *---------------------------------------------------------;
    if not missing(actarmcd_crf) then actarmcd = strip(actarmcd_crf);
    else actarmcd = armcd;
    
    if not missing(actarm_crf) then actarm = strip(actarm_crf);
    else actarm = arm;
    
    *---------------------------------------------------------;
    * Assign investigator information
    *---------------------------------------------------------;
    invid = strip(invid);
    invnam = strip(invnam);
    
    *---------------------------------------------------------;
    * Assign country (derive from siteid or use collected value)
    *---------------------------------------------------------;
    if missing(country) then do;
        if substr(siteid,1,2) = '01' then country = 'USA';
        else if substr(siteid,1,2) = '02' then country = 'CAN';
        else if substr(siteid,1,2) = '03' then country = 'GBR';
        else if substr(siteid,1,2) = '04' then country = 'DEU';
        else if substr(siteid,1,2) = '05' then country = 'FRA';
    end;
    else country = strip(country);
    
    *---------------------------------------------------------;
    * Derive AGE if not directly collected
    *---------------------------------------------------------;
    if not missing(age_crf) then age = age_crf;
    else if not missing(brthdt) and not missing(rfstdtc) then do;
        age = floor((input(substr(rfstdtc,1,10), yymmdd10.) - brthdt) / 365.25);
    end;
    
    *---------------------------------------------------------;
    * Reference dates from EX are already merged
    *---------------------------------------------------------;
    rfstdtc = rfstdtc;
    rfendtc = rfendtc;
    rfxstdtc = rfxstdtc;
    rfxendtc = rfxendtc;
    
run;

*==============================================================================;
* Step 3: Assign DMSEQ sequence number
*==============================================================================;
proc sort data=dm_pre;
    by studyid usubjid;
run;

data sdtm.dm;
    set dm_pre;
    by studyid usubjid;
    
    * Assign sequence number (one record per subject);
    dmseq = 1;
    
    * Apply variable labels;
    label
        studyid   = 'Study Identifier'
        dmseq     = 'Sequence Number'
        usubjid   = 'Unique Subject Identifier'
        subjid    = 'Subject Identifier for the Study'
        domain    = 'Domain Abbreviation'
        rfstdtc   = 'Subject Reference Start Date/Time'
        rfendtc   = 'Subject Reference End Date/Time'
        rfxstdtc  = 'Date/Time of First Study Treatment'
        rfxendtc  = 'Date/Time of Last Study Treatment'
        siteid    = 'Study Site Identifier'
        invid     = 'Investigator Identifier'
        invnam    = 'Investigator Name'
        country   = 'Country'
        armcd     = 'Planned Arm Code'
        arm       = 'Description of Planned Arm'
        actarmcd  = 'Actual Arm Code'
        actarm    = 'Description of Actual Arm'
        age       = 'Age'
        brthdtc   = 'Date/Time of Birth'
        ethnic    = 'Ethnicity'
        race      = 'Race'
        randnum   = 'Randomization Number'
        rficdtc   = 'Date/Time of Informed Consent'
        sex       = 'Sex'
    ;
    
    * Keep only required variables in specification order;
    keep
        studyid
        dmseq
        usubjid
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
        subjid
    ;
run;

*==============================================================================;
* Step 4: Final sort by USUBJID
*==============================================================================;
proc sort data=sdtm.dm;
    by usubjid;
run;

*==============================================================================;
* Step 5: Generate contents and summary report
*==============================================================================;
proc contents data=sdtm.dm varnum;
    title "Contents of SDTM.DM Domain";
run;

proc freq data=sdtm.dm;
    tables sex race ethnic armcd actarmcd country / missing;
    title "Frequency Counts for SDTM.DM Domain";
run;

proc means data=sdtm.dm n nmiss min max mean median;
    var age dmseq;
    title "Descriptive Statistics for SDTM.DM Domain";
run;

*==============================================================================;
* Clean up temporary datasets
*==============================================================================;
proc datasets library=work nolist;
    delete ex_temp ex_dates dm_pre;
quit;

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
