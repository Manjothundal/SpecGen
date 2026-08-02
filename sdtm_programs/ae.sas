/*******************************************************************************
* Program:    ae.sas
* Domain:     AE (Events)
* Purpose:    Create SDTM AE domain dataset
* Variables:  53
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.ae (source CRF data)
* Output:     sdtm.ae (AE domain dataset)
*
* Variables:  STUDYID, DOMAIN, USUBJID, AESEQ, AEGRPID, AEREFID, AESPID, AETERM
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-----------------------------------------------------------------------------
  Program:      AE.sas
  Description:  Create SDTM AE (Adverse Events) domain
  Input:        raw.ae, raw.dm
  Output:       sdtm.ae
  -----------------------------------------------------------------------------*/

/*-- BEGIN AE --*/

*-----------------------------------------------------------------------*
* Step 1: Read DM for reference dates and subject identifiers
*-----------------------------------------------------------------------*;
proc sort data=raw.dm out=dm_sorted;
    by studyid siteid subjid;
run;

data dm_subset;
    set dm_sorted;
    by studyid siteid subjid;
    
    keep studyid siteid subjid usubjid rfstdtc rfxstdtc rfxendtc;
run;

*-----------------------------------------------------------------------*
* Step 2: Read and prepare source AE data
*-----------------------------------------------------------------------*;
proc sort data=raw.ae out=ae_sorted;
    by studyid siteid subjid aestdat aeterm;
run;

*-----------------------------------------------------------------------*
* Step 3: Merge AE with DM and perform derivations
*-----------------------------------------------------------------------*;
data ae_derived;
    merge ae_sorted (in=a)
          dm_subset (in=b);
    by studyid siteid subjid;
    
    length STUDYID $20
           DOMAIN $2
           USUBJID $40
           AESEQ 8
           AEGRPID $20
           AEREFID $20
           AESPID $200
           AETERM $200
           AEMODIFY $200
           AELLT $100
           AELLTCD 8
           AEDECOD $200
           AEPTCD 8
           AEHLT $100
           AEHLTCD 8
           AEHLGT $100
           AEHLGTCD 8
           AECAT $200
           AESCAT $200
           AEPRESP $1
           AEBODSYS $200
           AEBDSYCD 8
           AESOC $200
           AESOCCD 8
           AELOC $200
           AESEV $20
           AESER $1
           AEACN $40
           AEACNOTH $200
           AEREL $40
           AERELNST $200
           AEPATT $40
           AEOUT $40
           AESCAN $1
           AESCONG $1
           AESDISAB $1
           AESDTH $1
           AESHOSP $1
           AESLIFE $1
           AESOD $1
           AESMIE $1
           AECONTRT $1
           AETOXGR $2
           AESTDTC $20
           AEENDTC $20
           AESTDY 8
           AEENDY 8
           AEDUR $8
           AEENRF $9
           AESTRTPT $40
           AESTTPT $40
           AEENRTPT $40
           AEENTPT $40
    ;
    
    if a;
    
    *-----------------------------------------------------------------------*
    * Standard Variables
    *-----------------------------------------------------------------------*;
    STUDYID = strip(studyid);
    DOMAIN = 'AE';
    
    * Derive USUBJID if not already in source *;
    if missing(USUBJID) then do;
        USUBJID = catx('-', strip(studyid), strip(siteid), strip(subjid));
    end;
    else do;
        USUBJID = strip(USUBJID);
    end;
    
    * Sponsor-Defined Identifier *;
    if not missing(aeid) then AESPID = strip(put(aeid, best.));
    
    *-----------------------------------------------------------------------*
    * Event Terms and Coding
    *-----------------------------------------------------------------------*;
    
    * Reported Term *;
    if not missing(aeverbat) then AETERM = strip(aeverbat);
    
    * Modified Reported Term *;
    if not missing(aemodver) then AEMODIFY = strip(aemodver);
    
    * MedDRA Coding - Lowest Level Term *;
    if not missing(aelltn) then AELLT = strip(aelltn);
    if not missing(aelltc) then AELLTCD = aelltc;
    
    * MedDRA Coding - Preferred Term *;
    if not missing(aeptn) then AEDECOD = strip(aeptn);
    if not missing(aeptc) then AEPTCD = aeptc;
    
    * MedDRA Coding - High Level Term *;
    if not missing(aehltn) then AEHLT = strip(aehltn);
    if not missing(aehltc) then AEHLTCD = aehltc;
    
    * MedDRA Coding - High Level Group Term *;
    if not missing(aehlgtn) then AEHLGT = strip(aehlgtn);
    if not missing(aehlgtc) then AEHLGTCD = aehlgtc;
    
    * MedDRA Coding - Body System/Organ Class *;
    if not missing(aebodsysn) then AEBODSYS = strip(aebodsysn);
    if not missing(aebodsysc) then AEBDSYCD = aebodsysc;
    
    * MedDRA Coding - Primary System Organ Class *;
    if not missing(aesocn) then AESOC = strip(aesocn);
    if not missing(aesocc) then AESOCCD = aesocc;
    
    *-----------------------------------------------------------------------*
    * Category and Subcategory
    *-----------------------------------------------------------------------*;
    if not missing(aecatn) then AECAT = strip(aecatn);
    if not missing(aescatn) then AESCAT = strip(aescatn);
    
    * Pre-Specified Event *;
    if not missing(aeprespc) then do;
        if upcase(strip(aeprespc)) in ('Y' 'YES') then AEPRESP = 'Y';
        else if upcase(strip(aeprespc)) in ('N' 'NO') then AEPRESP = 'N';
    end;
    
    *-----------------------------------------------------------------------*
    * Event Characteristics
    *-----------------------------------------------------------------------*;
    
    * Location of Event *;
    if not missing(aelocn) then AELOC = strip(aelocn);
    
    * Severity/Intensity *;
    if not missing(aesevn) then AESEV = strip(aesevn);
    
    * Serious Event *;
    if not missing(aesern) then do;
        if upcase(strip(aesern)) in ('Y' 'YES') then AESER = 'Y';
        else if upcase(strip(aesern)) in ('N' 'NO') then AESER = 'N';
    end;
    
    * Action Taken with Study Treatment *;
    if not missing(aeacnn) then AEACN = strip(aeacnn);
    
    * Other Action Taken *;
    if not missing(aeacnot) then AEACNOTH = strip(aeacnot);
    
    * Causality *;
    if not missing(aereln) then AEREL = strip(aereln);
    
    * Relationship to Non-Study Treatment *;
    if not missing(aerelnstn) then AERELNST = strip(aerelnstn);
    
    * Pattern of Event *;
    if not missing(aepattn) then AEPATT = strip(aepattn);
    
    * Outcome *;
    if not missing(aeoutn) then AEOUT = strip(aeoutn);
    
    *-----------------------------------------------------------------------*
    * Serious Event Criteria
    *-----------------------------------------------------------------------*;
    
    * Involves Cancer *;
    if not missing(aescann) then do;
        if upcase(strip(aescann)) in ('Y' 'YES') then AESCAN = 'Y';
        else if upcase(strip(aescann)) in ('N' 'NO') then AESCAN = 'N';
    end;
    
    * Congenital Anomaly *;
    if not missing(aescongn) then do;
        if upcase(strip(aescongn)) in ('Y' 'YES') then AESCONG = 'Y';
        else if upcase(strip(aescongn)) in ('N' 'NO') then AESCONG = 'N';
    end;
    
    * Disability *;
    if not missing(aesdisabn) then do;
        if upcase(strip(aesdisabn)) in ('Y' 'YES') then AESDISAB = 'Y';
        else if upcase(strip(aesdisabn)) in ('N' 'NO') then AESDISAB = 'N';
    end;
    
    * Results in Death *;
    if not missing(aesdthn) then do;
        if upcase(strip(aesdthn)) in ('Y' 'YES') then AESDTH = 'Y';
        else if upcase(strip(aesdthn)) in ('N' 'NO') then AESDTH = 'N';
    end;
    
    * Hospitalization *;
    if not missing(aeshospn) then do;
        if upcase(strip(aeshospn)) in ('Y' 'YES') then AESHOSP = 'Y';
        else if upcase(strip(aeshospn)) in ('N' 'NO') then AESHOSP = 'N';
    end;
    
    * Life Threatening *;
    if not missing(aeslifen) then do;
        if upcase(strip(aeslifen)) in ('Y' 'YES') then AESLIFE = 'Y';
        else if upcase(strip(aeslifen)) in ('N' 'NO') then AESLIFE = 'N';
    end;
    
    * Overdose *;
    if not missing(aesodn) then do;
        if upcase(strip(aesodn)) in ('Y' 'YES') then AESOD = 'Y';
        else if upcase(strip(aesodn)) in ('N' 'NO') then AESOD = 'N';
    end;
    
    * Other Medically Important *;
    if not missing(aesmien) then do;
        if upcase(strip(aesmien)) in ('Y' 'YES') then AESMIE = 'Y';
        else if upcase(strip(aesmien)) in ('N' 'NO') then AESMIE = 'N';
    end;
    
    * Concomitant Treatment Given *;
    if not missing(aecontrtn) then do;
        if upcase(strip(aecontrtn)) in ('Y' 'YES') then AECONTRT = 'Y';
        else if upcase(strip(aecontrtn)) in ('N' 'NO') then AECONTRT = 'N';
    end;
    
    * Toxicity Grade *;
    if not missing(aetoxgrn) then AETOXGR = strip(aetoxgrn);
    
    *-----------------------------------------------------------------------*
    * Dates and Study Days
    *-----------------------------------------------------------------------*;
    
    * Start Date/Time - convert to ISO 8601 *;
    if not missing(aestdat) then do;
        if not missing(aesttim) then do;
            AESTDTC = strip(put(aestdat, is8601da.)) || 'T' || 
                     strip(put(input(put(aesttim, time5.), time5.), time8.));
        end;
        else do;
            AESTDTC = strip(put(aestdat, is8601da.));
        end;
    end;
    
    * End Date/Time - convert to ISO 8601 *;
    if not missing(aeendat) then do;
        if not missing(aeentim) then do;
            AEENDTC = strip(put(aeendat, is8601da.)) || 'T' || 
                     strip(put(input(put(aeentim, time5.), time5.), time8.));
        end;
        else do;
            AEENDTC = strip(put(aeendat, is8601da.));
        end;
    end;
    
    * Study Day Derivations *;
    if not missing(aestdat) and not missing(rfstdtc) then do;
        rfstdt = input(scan(rfstdtc,1,'T'), yymmdd10.);
        if not missing(rfstdt) then do;
            if aestdat >= rfstdt then AESTDY = aestdat - rfstdt + 1;
            else AESTDY = aestdat - rfstdt;
        end;
    end;
    
    if not missing(aeendat) and not missing(rfstdtc) then do;
        rfstdt = input(scan(rfstdtc,1,'T'), yymmdd10.);
        if not missing(rfstdt) then do;
            if aeendat >= rfstdt then AEENDY = aeendat - rfstdt + 1;
            else AEENDY = aeendat - rfstdt;
        end;
    end;
    
    * Duration *;
    if not missing(aestdat) and not missing(aeendat) then do;
        aedurn = aeendat - aestdat + 1;
        if aedurn >= 0 then AEDUR = strip(put(aedurn, best.));
    end;
    
    *-----------------------------------------------------------------------*
    * Reference Time Points
    *-----------------------------------------------------------------------*;
    if not missing(aestrtptn) then AESTRTPT = strip(aestrtptn);
    if not missing(aesttptn) then AESTTPT = strip(aesttptn);
    if not missing(aeenrtptn) then AEENRTPT = strip(aeenrtptn);
    if not missing(aeentptn) then AEENTPT = strip(aeentptn);
    if not missing(aeenrfn) then AEENRF = strip(aeenrfn);
    
    * Group ID and Reference ID *;
    if not missing(aegrpidn) then AEGRPID = strip(aegrpidn);
    if not missing(aerefidn) then AEREFID = strip(aerefidn);
    
    drop rfstdt aedurn aestdat aeendat aesttim aeentim aeid aeverbat aemodver
         aelltn aelltc aeptn aeptc aehltn aehltc aehlgtn aehlgtc aebodsysn
         aebodsysc aesocn aesocc aecatn aescatn aeprespc aelocn aesevn aesern
         aeacnn aeacnot aereln aerelnstn aepattn aeoutn aescann aescongn
         aesdisabn aesdthn aeshospn aeslifen aesodn aesmien aecontrtn aetoxgrn
         aestrtptn aesttptn aeenrtptn aeentptn aeenrfn aegrpidn aerefidn
         siteid subjid rfxstdtc rfxendtc;
run;

*-----------------------------------------------------------------------*
* Step 4: Sort and assign sequence number
*-----------------------------------------------------------------------*;
proc sort data=ae_derived;
    by studyid usubjid aestdtc aeterm aespid;
run;

data ae_seq;
    set ae_derived;
    by studyid usubjid;
    
    retain AESEQ;
    
    if first.usubjid then AESEQ = 1;
    else AESEQ + 1;
    
    label
        STUDYID  = 'Study Identifier'
        DOMAIN   = 'Domain Abbreviation'
        USUBJID  = 'Unique Subject Identifier'
        AESEQ    = 'Sequence Number'
        AEGRPID  = 'Group ID'
        AEREFID  = 'Reference ID'
        AESPID   = 'Sponsor-Defined Identifier'
        AETERM   = 'Reported Term for the Adverse Event'
        AEMODIFY = 'Modified Reported Term'
        AELLT    = 'Lowest Level Term'
        AELLTCD  = 'Lowest Level Term Code'
        AEDECOD  = 'Dictionary-Derived Term'
        AEPTCD   = 'Preferred Term Code'
        AEHLT    = 'High Level Term'
        AEHLTCD  = 'High Level Term Code'
        AEHLGT   = 'High Level Group Term'
        AEHLGTCD = 'High Level Group Term Code'
        AECAT    = 'Category for Adverse Event'
        AESCAT   = 'Subcategory for Adverse Event'
        AEPRESP  = 'Pre-Specified Adverse Event'
        AEBODSYS = 'Body System or Organ Class'
        AEBDSYCD = 'Body System or Organ Class Code'
        AESOC    = 'Primary System Organ Class'
        AESOCCD  = 'Primary System Organ Class Code'
        AELOC    = 'Location of Event'
        AESEV    = 'Severity/Intensity'
        AESER    = 'Serious Event'
        AEACN    = 'Action Taken with Study Treatment'
        AEACNOTH = 'Other Action Taken'
        AEREL    = 'Causality'
        AERELNST = 'Relationship to Non-Study Treatment'
        AEPATT   = 'Pattern of Adverse Event'
        AEOUT    = 'Outcome of Adverse Event'
        AESCAN   = 'Involves Cancer'
        AESCONG  = 'Congenital Anomaly or Birth Defect'
        AESDISAB = 'Persist or Signif Disability/Incapacity'
        AESDTH   = 'Results in Death'
        AESHOSP  = 'Requires or Prolongs Hospitalization'
        AESLIFE  = 'Is Life Threatening'
        AESOD    = 'Occurred with Overdose'
        AESMIE   = 'Other Medically Important Serious Event'
        AECONTRT = 'Concomitant or Additional Trtmnt Given'
        AETOXGR  = 'Standard Toxicity Grade'
        AESTDTC  = 'Start Date/Time of Adverse Event'
        AEENDTC  = 'End Date/Time of Adverse Event'
        AESTDY   = 'Study Day of Start of Adverse Event'
        AEENDY   = 'Study Day of End of Adverse Event'
        AEDUR    = 'Duration of Adverse Event'
        AEENRF   = 'End Relative to Reference Period'
        AESTRTPT = 'Start Relative to Reference Time Point'
        AESTTPT  = 'Start Reference Time Point'
        AEENRTPT = 'End Relative to Reference Time Point'
        AEENTPT  = 'End Reference Time Point'
    ;
run;

*-----------------------------------------------------------------------*
* Step 5: Create final dataset with correct variable order
*-----------------------------------------------------------------------*;
data sdtm.ae;
    retain
        STUDYID
        DOMAIN
        USUBJID
        AESEQ
        AEGRPID
        AEREFID
        AESPID
        AETERM
        AEMODIFY
        AELLT
        AELLTCD
        AEDECOD
        AEPTCD
        AEHLT
        AEHLTCD
        AEHLGT
        AEHLGTCD
        AECAT
        AESCAT
        AEPRESP
        AEBODSYS
        AEBDSYCD
        AESOC
        AESOCCD
        AELOC
        AESEV
        AESER
        AEACN
        AEACNOTH
        AEREL
        AERELNST
        AEPATT
        AEOUT
        AESCAN
        AESCONG
        AESDISAB
        AESDTH
        AESHOSP
        AESLIFE
        AESOD
        AESMIE
        AECONTRT
        AETOXGR
        AESTDTC
        AEENDTC
        AESTDY
        AEENDY
        AEDUR
        AEENRF
        AESTRTPT
        AESTTPT
        AEENRTPT
        AEENTPT
    ;
    set ae_seq;
run;

*-----------------------------------------------------------------------*
* Step 6: Final sort
*-----------------------------------------------------------------------*;
proc sort data=sdtm.ae;
    by studyid usubjid aeseq;
run;

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
