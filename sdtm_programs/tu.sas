/*******************************************************************************
* Program:    tu.sas
* Domain:     TU (Findings About Events)
* Purpose:    Create SDTM TU domain dataset
* Variables:  20
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.tu (source CRF data)
* Output:     sdtm.tu (TU domain dataset)
*
* Variables:  STUDYID, TUSEQ, USUBJID, DOMAIN, TUTESTCD, TUTEST, TUCAT, TUORRES
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-- BEGIN TU --*/
*******************************************************************************;
* Program:      TU.sas                                                        *;
* Description:  Create SDTM TU domain (Tumor/Lesion Identification)          *;
* Study:        Protocol XXXX                                                 *;
* Domain:       TU (Findings About Events - Tumor/Response Assessments)       *;
*******************************************************************************;

*--- Read in DM domain for subject info and reference dates ---;
proc sort data=raw.dm out=dm;
    by usubjid;
run;

*--- Read in source TU data ---;
data tu_raw;
    set raw.tu;
run;

*--- Merge with DM to get STUDYID and RFSTDTC ---;
proc sort data=tu_raw;
    by usubjid;
run;

data tu_merged;
    merge tu_raw (in=a)
          dm (in=b keep=usubjid studyid rfstdtc);
    by usubjid;
    if a;
    
    length studyid $20
           domain $2
           usubjid $40
           tutestcd $8
           tutest $40
           tucat $200
           tuorres $200
           tustresc $200
           tustresu $20
           tueval $40
           tulnkid $200
           visit $200
           tudtc $20
           tulat $200
           tuloc $200
           tumethod $200;
    
    *--- Set domain ---;
    domain = 'TU';
    
    *--- Assign TUTESTCD and TUTEST based on assessment type ---;
    if upcase(strip(tutestcd)) = 'TUMIDENT' then do;
        tutestcd = 'TUMIDENT';
        tutest = 'Tumor Identification';
    end;
    else if upcase(strip(tutestcd)) = 'TUMSTATE' then do;
        tutestcd = 'TUMSTATE';
        tutest = 'Tumor State';
    end;
    else if upcase(strip(tutestcd)) = 'DIAM' then do;
        tutestcd = 'DIAM';
        tutest = 'Diameter';
    end;
    else if upcase(strip(tutestcd)) = 'LDIAM' then do;
        tutestcd = 'LDIAM';
        tutest = 'Longest Diameter';
    end;
    else if upcase(strip(tutestcd)) = 'PLDIAM' then do;
        tutestcd = 'PLDIAM';
        tutest = 'Perpendicular Diameter';
    end;
    
    *--- Set TUCAT for assessment criteria ---;
    if strip(tucat) = '' then tucat = 'RECIST 1.1';
    else tucat = strip(tucat);
    
    *--- Process TUORRES and derive TUSTRESC and TUSTRESN ---;
    if strip(tuorres) ne '' then do;
        tustresc = strip(tuorres);
        
        *--- Derive numeric result for diameter measurements ---;
        if tutestcd in ('DIAM', 'LDIAM', 'PLDIAM') then do;
            if notdigit(compress(tuorres,'.-')) = 0 and 
               notdigit(compress(tuorres,'.')) > 0 then do;
                tustresn = input(tuorres, ?? best.);
                if strip(tustresu) = '' then tustresu = 'mm';
            end;
        end;
        *--- For categorical results like TUMIDENT and TUMSTATE ---;
        else if tutestcd = 'TUMIDENT' then do;
            if upcase(strip(tustresc)) = 'TARGET' then tustresn = 1;
            else if upcase(strip(tustresc)) = 'NON-TARGET' then tustresn = 2;
            else if upcase(strip(tustresc)) = 'NEW' then tustresn = 3;
        end;
        else if tutestcd = 'TUMSTATE' then do;
            if upcase(strip(tustresc)) in ('PRESENT', 'MEASURABLE') then tustresn = 1;
            else if upcase(strip(tustresc)) in ('ABSENT', 'NOT PRESENT') then tustresn = 2;
        end;
    end;
    
    *--- Map TUEVAL ---;
    if upcase(strip(tueval)) in ('INV', 'INVESTIGATOR') then tueval = 'INVESTIGATOR';
    else if upcase(strip(tueval)) in ('IRC', 'INDEPENDENT', 'INDEPENDENT ASSESSOR') then 
        tueval = 'INDEPENDENT ASSESSOR';
    else tueval = strip(tueval);
    
    *--- Keep TULNKID for linking ---;
    tulnkid = strip(tulnkid);
    
    *--- Map VISIT and VISITNUM ---;
    visit = strip(visit);
    if visitnum = . and strip(visit) ne '' then do;
        if upcase(visit) = 'SCREENING' then visitnum = 0;
        else if upcase(visit) = 'BASELINE' then visitnum = 1;
        else if index(upcase(visit), 'WEEK') > 0 then 
            visitnum = input(compress(visit,,'kd'), ?? best.) + 1;
        else if index(upcase(visit), 'CYCLE') > 0 then 
            visitnum = input(compress(visit,,'kd'), ?? best.) * 10;
        else if upcase(visit) = 'END OF TREATMENT' then visitnum = 99;
        else if upcase(visit) = 'FOLLOW-UP' then visitnum = 100;
    end;
    
    *--- Map TUDTC (keep as character ISO 8601) ---;
    tudtc = strip(tudtc);
    
    *--- Derive TUDY (Study Day) ---;
    if strip(tudtc) ne '' and strip(rfstdtc) ne '' then do;
        if length(strip(tudtc)) >= 10 and length(strip(rfstdtc)) >= 10 then do;
            tudy = input(substr(tudtc,1,10), ?? yymmdd10.) - 
                   input(substr(rfstdtc,1,10), ?? yymmdd10.);
            if tudy >= 0 then tudy = tudy + 1;
        end;
    end;
    
    *--- Map TULAT (Laterality) ---;
    if upcase(strip(tulat)) = 'LEFT' then tulat = 'LEFT';
    else if upcase(strip(tulat)) = 'RIGHT' then tulat = 'RIGHT';
    else if upcase(strip(tulat)) in ('BILATERAL', 'BOTH') then tulat = 'BILATERAL';
    else tulat = strip(tulat);
    
    *--- Map TULOC (Tumor Location) ---;
    tuloc = strip(tuloc);
    
    *--- Map TUMETHOD ---;
    if upcase(strip(tumethod)) = 'CT' then tumethod = 'CT SCAN';
    else if upcase(strip(tumethod)) = 'MRI' then tumethod = 'MRI';
    else if upcase(strip(tumethod)) in ('PE', 'PHYSICAL EXAM') then tumethod = 'PHYSICAL EXAM';
    else if upcase(strip(tumethod)) in ('XRAY', 'X-RAY') then tumethod = 'X-RAY';
    else tumethod = strip(tumethod);
    
    if strip(usubjid) ne '';
run;

*--- Sort data before deriving sequence ---;
proc sort data=tu_merged;
    by studyid usubjid tulnkid tutestcd visitnum tudtc;
run;

*--- Derive TUSEQ ---;
data tu_seq;
    set tu_merged;
    by studyid usubjid;
    
    retain tuseq;
    
    if first.usubjid then tuseq = 0;
    tuseq + 1;
run;

*--- Final sort ---;
proc sort data=tu_seq;
    by studyid usubjid tuseq;
run;

*--- Create final TU domain with labels and output ---;
data sdtm.tu;
    set tu_seq;
    
    label
        studyid  = "Study Identifier"
        domain   = "Domain Abbreviation"
        usubjid  = "Unique Subject Identifier"
        tuseq    = "Sequence Number"
        tutestcd = "Tumor Test Short Name"
        tutest   = "Tumor Test Name"
        tucat    = "Category for Tumor"
        tuorres  = "Result or Finding in Original Units"
        tustresc = "Character Result/Finding in Std Format"
        tustresn = "Numeric Result/Finding in Standard Units"
        tustresu = "Standard Units"
        tueval   = "Evaluator"
        tulnkid  = "Link ID"
        visitnum = "Visit Number"
        visit    = "Visit Name"
        tudtc    = "Date/Time of Collection"
        tudy     = "Study Day of Collection"
        tulat    = "Laterality"
        tuloc    = "Location of the Tumor"
        tumethod = "Method of Test or Examination"
    ;
    
    keep studyid domain usubjid tuseq tutestcd tutest tucat tuorres tustresc
         tustresn tustresu tueval tulnkid visitnum visit tudtc tudy
         tulat tuloc tumethod;
         
    format tustresn best. visitnum best. tudy best. tuseq best.;
run;

*--- Print summary ---;
proc freq data=sdtm.tu;
    tables tutestcd*tutest tucat tueval / list missing;
    title "TU Domain - Frequency Summary";
run;

proc means data=sdtm.tu n nmiss min max;
    var tuseq visitnum tudy tustresn;
    title "TU Domain - Numeric Variable Summary";
run;

title;
/*-- END TU --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.tu;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.tu varnum;
run;

proc freq data=sdtm.tu;
  tables DOMAIN / nocum nopercent;
run;

/* End of tu.sas */
