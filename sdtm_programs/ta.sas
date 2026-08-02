/*******************************************************************************
* Program:    ta.sas
* Domain:     TA (General)
* Purpose:    Create SDTM TA domain dataset
* Variables:  10
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.ta (source CRF data)
* Output:     sdtm.ta (TA domain dataset)
*
* Variables:  STUDYID, DOMAIN, ARMCD, ARM, TAETORD, ETCD, ELEMENT, TABRANCH
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*==========================================================================================
  Program:      TA.sas
  Description:  Create SDTM TA (Trial Arms) Domain
  SDTM Version: 3.2
  Domain:       TA (Trial Design - Trial Arms)
==========================================================================================*/

/*-- BEGIN TA --*/

/*------------------------------------------------------------------------------------------
  Step 1: Create TA Domain
------------------------------------------------------------------------------------------*/
data sdtm.ta;
    set raw.ta;
    
    /*---------------------------------------------------------------------------------------
      Define Variable Lengths
    ---------------------------------------------------------------------------------------*/
    length studyid $20
           domain $2
           armcd $20
           arm $200
           taetord 8
           etcd $8
           element $20
           tabranch $200
           tatrans $200
           epoch $20;
    
    /*---------------------------------------------------------------------------------------
      Assign Domain Variable
    ---------------------------------------------------------------------------------------*/
    domain = 'TA';
    
    /*---------------------------------------------------------------------------------------
      Derive and Format Variables
    ---------------------------------------------------------------------------------------*/
    /* STUDYID - Study Identifier */
    studyid = strip(studyid);
    
    /* ARMCD - Planned Arm Code */
    armcd = strip(armcd);
    
    /* ARM - Description of Planned Arm */
    arm = strip(arm);
    
    /* TAETORD - Order of Element within Arm */
    /* Numeric variable - no formatting needed */
    
    /* ETCD - Element Code */
    etcd = strip(etcd);
    
    /* ELEMENT - Description of Element */
    element = strip(element);
    
    /* TABRANCH - Branch */
    if not missing(tabranch) then tabranch = strip(tabranch);
    else call missing(tabranch);
    
    /* TATRANS - Transition Rule */
    if not missing(tatrans) then tatrans = strip(tatrans);
    else call missing(tatrans);
    
    /* EPOCH - Epoch */
    epoch = strip(epoch);
    
    /*---------------------------------------------------------------------------------------
      Apply Variable Labels
    ---------------------------------------------------------------------------------------*/
    label studyid   = 'Study Identifier'
          domain    = 'Domain Abbreviation'
          armcd     = 'Planned Arm Code'
          arm       = 'Description of Planned Arm'
          taetord   = 'Order of Element within Arm'
          etcd      = 'Element Code'
          element   = 'Description of Element'
          tabranch  = 'Branch'
          tatrans   = 'Transition Rule'
          epoch     = 'Epoch';
    
    /*---------------------------------------------------------------------------------------
      Keep Variables in Specification Order
    ---------------------------------------------------------------------------------------*/
    keep studyid
         domain
         armcd
         arm
         taetord
         etcd
         element
         tabranch
         tatrans
         epoch;
run;

/*------------------------------------------------------------------------------------------
  Step 2: Sort Final Dataset
------------------------------------------------------------------------------------------*/
proc sort data=sdtm.ta;
    by studyid armcd taetord;
run;

/*------------------------------------------------------------------------------------------
  Step 3: Quality Control - Check for Missing Required Variables
------------------------------------------------------------------------------------------*/
proc sql noprint;
    create table ta_qc as
    select *
    from sdtm.ta
    where missing(studyid) or 
          missing(domain) or 
          missing(armcd) or 
          missing(arm) or 
          missing(taetord) or 
          missing(etcd) or 
          missing(element);
quit;

data _null_;
    if 0 then set ta_qc nobs=n;
    if n > 0 then do;
        put "WARNING: " n "record(s) found with missing required variables in TA domain.";
    end;
    else do;
        put "NOTE: All required variables populated in TA domain.";
    end;
    stop;
run;

/*------------------------------------------------------------------------------------------
  Step 4: Generate Summary Report
------------------------------------------------------------------------------------------*/
proc freq data=sdtm.ta;
    tables armcd*arm / list missing;
    tables epoch / missing;
    title1 "TA Domain - Frequency Summary";
    title2 "Arms and Epochs";
run;

proc print data=sdtm.ta(obs=10) label;
    title1 "TA Domain - Sample Records";
    title2 "First 10 Records";
run;

title;

/*-- END TA --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.ta;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.ta varnum;
run;

proc freq data=sdtm.ta;
  tables DOMAIN / nocum nopercent;
run;

/* End of ta.sas */
