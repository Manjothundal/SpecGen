/*******************************************************************************
* Program:    ta.sas
* Domain:     TA (General)
* Purpose:    Create SDTM TA domain dataset
* Variables:  10
*
* Input:      raw.ta (source CRF data)
* Output:     sdtm.ta (TA domain dataset)
*
* Variables:  STUDYID, DOMAIN, ARMCD, ARM, TAETORD, ETCD, ELEMENT, TABRANCH,
*             TATRANS, EPOCH
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN TA --*/

*-----------------------------------------------------------------------------*
* Read source TA data
*-----------------------------------------------------------------------------*;
data ta_source;
    set raw.ta;
    
    * Keep only necessary source variables;
    * Expecting source variables like:
      STUDYID, ARMCD, ARM, TAETORD, ETCD, ELEMENT, 
      TABRANCH, TATRANS, EPOCH;
run;

*-----------------------------------------------------------------------------*
* Create SDTM TA domain
*-----------------------------------------------------------------------------*;
data sdtm.ta;
    set ta_source;
    
    *-------------------------------------------------------------------------*
    * Standard SDTM variables
    *-------------------------------------------------------------------------*;
    
    * Domain Abbreviation;
    length DOMAIN $2;
    DOMAIN = 'TA';

    *-------------------------------------------------------------------------*
    * TA-specific variables
    *-------------------------------------------------------------------------*;

    length ARMCD $20 ARM $200 ETCD $8 ELEMENT $200 TABRANCH $200 TATRANS $200 EPOCH $200;

    * Branch - from source;
    if not missing(TABRANCH) then TABRANCH = TABRANCH;
    else TABRANCH = '';

    * Transition Rule - from source;
    if not missing(TATRANS) then TATRANS = TATRANS;
    else TATRANS = '';

    *-------------------------------------------------------------------------*
    * Apply variable labels
    *-------------------------------------------------------------------------*;
    label
        STUDYID  = "Study Identifier"
        DOMAIN   = "Domain Abbreviation"
        ARMCD    = "Planned Arm Code"
        ARM      = "Description of Planned Arm"
        TAETORD  = "Order of Element within Arm"
        ETCD     = "Element Code"
        ELEMENT  = "Description of Element"
        TABRANCH = "Branch"
        TATRANS  = "Transition Rule"
        EPOCH    = "Epoch"
    ;
    
    *-------------------------------------------------------------------------*
    * Keep only SDTM variables in specification order
    *-------------------------------------------------------------------------*;
    keep
        STUDYID
        DOMAIN
        ARMCD
        ARM
        TAETORD
        ETCD
        ELEMENT
        TABRANCH
        TATRANS
        EPOCH
    ;
run;

*-----------------------------------------------------------------------------*
* Sort TA domain by key variables
*-----------------------------------------------------------------------------*;
proc sort data=sdtm.ta;
    by STUDYID ARMCD TAETORD;
run;

*-----------------------------------------------------------------------------*
* Generate summary report
*-----------------------------------------------------------------------------*;
proc freq data=sdtm.ta;
    tables ARMCD*ARM / list missing;
    tables ETCD*ELEMENT / list missing;
    tables EPOCH / list missing;
    title1 "TA Domain - Frequency Checks";
    title2 "Total Records: &SYSNOBS";
run;

proc print data=sdtm.ta (obs=10);
    title1 "TA Domain - First 10 Records";
run;

title;

/*-- END TA --*/

/* End of ta.sas */
