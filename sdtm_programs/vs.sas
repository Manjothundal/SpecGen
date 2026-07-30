/*******************************************************************************
* Program:    vs.sas
* Domain:     VS (Findings)
* Purpose:    Create SDTM VS domain dataset
* Variables:  19
* Generated:  SpecGen Phase 5c - SDTM Program Generation
*
* Input:      raw.vs (source CRF data)
* Output:     sdtm.vs (VS domain dataset)
*
* Variables:  STUDYID, VSSEQ, USUBJID, DOMAIN, VSTESTCD, VSTEST, VSCAT, VSORRES
*             ...
*******************************************************************************/

/*-- Library assignments --*/
libname raw  'C:\sas_data\raw'  access=readonly;
libname sdtm 'C:\sas_data\sdtm';

/*-----------------------------------------------------------------------------
  PROGRAM:        SDTM_VS.sas
  DESCRIPTION:    Create SDTM VS (Vital Signs) Domain
  PROGRAMMER:     [Programmer Name]
  DATE:           [Date]
  
  INPUT:          raw.vs       - Raw vital signs data
                  raw.dm       - Raw demographics (for USUBJID, RFSTDTC)
                  
  OUTPUT:         sdtm.vs      - SDTM VS Domain
  
  ASSUMPTIONS:    - Raw data is in wide format (one column per test)
                  - Tests: SYSBP, DIABP, PULSE, RESP, TEMP, WEIGHT, HEIGHT
-----------------------------------------------------------------------------*/

/*-- BEGIN VS --*/

/*-----------------------------------------------------------------------------
  Step 1: Merge DM data to get USUBJID and RFSTDTC for study day calculation
-----------------------------------------------------------------------------*/
proc sort data=raw.dm out=dm_sub(keep=studyid siteid subjid usubjid rfstdtc);
    by studyid siteid subjid;
run;

proc sort data=raw.vs;
    by studyid siteid subjid;
run;

data vs_dm;
    length usubjid $40;
    merge raw.vs(in=a)
          dm_sub(in=b);
    by studyid siteid subjid;
    if a;
    
    /* Derive USUBJID if not in source */
    if missing(usubjid) then usubjid = catx('-', studyid, siteid, subjid);
run;

/*-----------------------------------------------------------------------------
  Step 2: Transpose data from wide to vertical format (one row per test)
-----------------------------------------------------------------------------*/
data vs_vert;
    set vs_dm;
    
    length vstestcd $8 vstest $40 vsorres $200 vsorresu $40 vscat $40 
           vsstat $20 vsreasnd $200 vspos $20;
    
    /* Systolic Blood Pressure */
    if not missing(sysbp) or sysbp_nd = 'Y' then do;
        vstestcd = 'SYSBP';
        vstest = 'Systolic Blood Pressure';
        if sysbp_nd = 'Y' then do;
            vsorres = '';
            vsorresu = '';
            vsstat = 'NOT DONE';
            vsreasnd = sysbp_reason;
        end;
        else do;
            vsorres = strip(put(sysbp, best.));
            vsorresu = 'mmHg';
            vsstat = '';
            vsreasnd = '';
        end;
        vscat = 'VITAL SIGNS';
        vspos = upcase(strip(position));
        output;
    end;
    
    /* Diastolic Blood Pressure */
    if not missing(diabp) or diabp_nd = 'Y' then do;
        vstestcd = 'DIABP';
        vstest = 'Diastolic Blood Pressure';
        if diabp_nd = 'Y' then do;
            vsorres = '';
            vsorresu = '';
            vsstat = 'NOT DONE';
            vsreasnd = diabp_reason;
        end;
        else do;
            vsorres = strip(put(diabp, best.));
            vsorresu = 'mmHg';
            vsstat = '';
            vsreasnd = '';
        end;
        vscat = 'VITAL SIGNS';
        vspos = upcase(strip(position));
        output;
    end;
    
    /* Pulse Rate */
    if not missing(pulse) or pulse_nd = 'Y' then do;
        vstestcd = 'PULSE';
        vstest = 'Pulse Rate';
        if pulse_nd = 'Y' then do;
            vsorres = '';
            vsorresu = '';
            vsstat = 'NOT DONE';
            vsreasnd = pulse_reason;
        end;
        else do;
            vsorres = strip(put(pulse, best.));
            vsorresu = 'beats/min';
            vsstat = '';
            vsreasnd = '';
        end;
        vscat = 'VITAL SIGNS';
        vspos = upcase(strip(position));
        output;
    end;
    
    /* Respiratory Rate */
    if not missing(resp) or resp_nd = 'Y' then do;
        vstestcd = 'RESP';
        vstest = 'Respiratory Rate';
        if resp_nd = 'Y' then do;
            vsorres = '';
            vsorresu = '';
            vsstat = 'NOT DONE';
            vsreasnd = resp_reason;
        end;
        else do;
            vsorres = strip(put(resp, best.));
            vsorresu = 'breaths/min';
            vsstat = '';
            vsreasnd = '';
        end;
        vscat = 'VITAL SIGNS';
        vspos = upcase(strip(position));
        output;
    end;
    
    /* Temperature */
    if not missing(temp) or temp_nd = 'Y' then do;
        vstestcd = 'TEMP';
        vstest = 'Temperature';
        if temp_nd = 'Y' then do;
            vsorres = '';
            vsorresu = '';
            vsstat = 'NOT DONE';
            vsreasnd = temp_reason;
        end;
        else do;
            vsorres = strip(put(temp, best.));
            vsorresu = strip(temp_unit); /* C or F from source */
            vsstat = '';
            vsreasnd = '';
        end;
        vscat = 'VITAL SIGNS';
        vspos = '';
        output;
    end;
    
    /* Weight */
    if not missing(weight) or weight_nd = 'Y' then do;
        vstestcd = 'WEIGHT';
        vstest = 'Weight';
        if weight_nd = 'Y' then do;
            vsorres = '';
            vsorresu = '';
            vsstat = 'NOT DONE';
            vsreasnd = weight_reason;
        end;
        else do;
            vsorres = strip(put(weight, best.));
            vsorresu = strip(weight_unit); /* kg or lb from source */
            vsstat = '';
            vsreasnd = '';
        end;
        vscat = 'VITAL SIGNS';
        vspos = '';
        output;
    end;
    
    /* Height */
    if not missing(height) or height_nd = 'Y' then do;
        vstestcd = 'HEIGHT';
        vstest = 'Height';
        if height_nd = 'Y' then do;
            vsorres = '';
            vsorresu = '';
            vsstat = 'NOT DONE';
            vsreasnd = height_reason;
        end;
        else do;
            vsorres = strip(put(height, best.));
            vsorresu = strip(height_unit); /* cm or in from source */
            vsstat = '';
            vsreasnd = '';
        end;
        vscat = 'VITAL SIGNS';
        vspos = '';
        output;
    end;
    
    keep studyid usubjid vstestcd vstest vscat vsorres vsorresu 
         vsstat vsreasnd visitnum visit vsdtc vspos rfstdtc vsdate vstime;
run;

/*-----------------------------------------------------------------------------
  Step 3: Derive VSDTC in ISO 8601 format
-----------------------------------------------------------------------------*/
data vs_dtc;
    set vs_vert;
    
    length vsdtc $19;
    
    /* Convert SAS date/datetime to ISO 8601 */
    if not missing(vsdate) then do;
        if not missing(vstime) then do;
            /* Check if vstime is a time value or datetime value */
            if vstime < 86400 then do;
                /* vstime is a time value */
                vsdtc = strip(put(vsdate, yymmdd10.)) || 'T' || put(vstime, time5.);
            end;
            else do;
                /* vstime might be a datetime */
                vsdtc = strip(put(datepart(vstime), yymmdd10.)) || 'T' || put(timepart(vstime), time5.);
            end;
        end;
        else do;
            vsdtc = put(vsdate, yymmdd10.);
        end;
    end;
    else vsdtc = '';
    
    drop vsdate vstime;
run;

/*-----------------------------------------------------------------------------
  Step 4: Derive standardized character and numeric results
-----------------------------------------------------------------------------*/
data vs_std;
    set vs_dtc;
    
    length vsstresc $200 vsstresu $40;
    
    /* Derive VSSTRESC and VSSTRESN */
    if vsstat ne 'NOT DONE' then do;
        vsstresc = vsorres;
        vsstresn = input(vsorres, ?? best.);
        
        /* Derive VSSTRESU with unit conversions */
        if vstestcd in ('SYSBP', 'DIABP') then do;
            vsstresu = 'mmHg';
            /* No conversion needed - already in mmHg */
        end;
        else if vstestcd = 'PULSE' then do;
            vsstresu = 'beats/min';
            /* No conversion needed */
        end;
        else if vstestcd = 'RESP' then do;
            vsstresu = 'breaths/min';
            /* No conversion needed */
        end;
        else if vstestcd = 'TEMP' then do;
            vsstresu = 'C';
            /* Convert Fahrenheit to Celsius if needed */
            if upcase(vsorresu) in ('F', 'FAHRENHEIT') then do;
                vsstresn = round((vsstresn - 32) * 5/9, 0.1);
                vsstresc = strip(put(vsstresn, 8.1));
            end;
        end;
        else if vstestcd = 'WEIGHT' then do;
            vsstresu = 'kg';
            /* Convert pounds to kg if needed */
            if upcase(vsorresu) in ('LB', 'LBS', 'POUNDS') then do;
                vsstresn = round(vsstresn * 0.453592, 0.01);
                vsstresc = strip(put(vsstresn, 8.2));
            end;
        end;
        else if vstestcd = 'HEIGHT' then do;
            vsstresu = 'cm';
            /* Convert inches to cm if needed */
            if upcase(vsorresu) in ('IN', 'INCH', 'INCHES') then do;
                vsstresn = round(vsstresn * 2.54, 0.1);
                vsstresc = strip(put(vsstresn, 8.1));
            end;
        end;
    end;
    else do;
        vsstresc = '';
        vsstresn = .;
        vsstresu = '';
    end;
run;

/*-----------------------------------------------------------------------------
  Step 5: Derive study day (VSDY)
-----------------------------------------------------------------------------*/
data vs_dy;
    set vs_std;
    
    /* Calculate study day relative to RFSTDTC */
    if not missing(vsdtc) and not missing(rfstdtc) then do;
        if length(vsdtc) >= 10 and length(rfstdtc) >= 10 then do;
            _vsdt = input(substr(vsdtc,1,10), yymmdd10.);
            _rfstdt = input(substr(rfstdtc,1,10), yymmdd10.);
            
            if not missing(_vsdt) and not missing(_rfstdt) then do;
                if _vsdt >= _rfstdt then vsdy = _vsdt - _rfstdt + 1;
                else vsdy = _vsdt - _rfstdt;
            end;
        end;
    end;
    
    drop _vsdt _rfstdt rfstdtc;
run;

/*-----------------------------------------------------------------------------
  Step 6: Sort and derive sequence number
-----------------------------------------------------------------------------*/
proc sort data=vs_dy;
    by studyid usubjid visitnum vsdtc vstestcd;
run;

data vs_seq;
    set vs_dy;
    by studyid usubjid;
    
    retain vsseq;
    
    if first.usubjid then vsseq = 0;
    vsseq + 1;
run;

/*-----------------------------------------------------------------------------
  Step 7: Assign DOMAIN and create final dataset with labels
-----------------------------------------------------------------------------*/
data sdtm.vs;
    length studyid $20 domain $2 usubjid $40 vstestcd $8 vstest $40 
           vscat $40 vsorres $200 vsorresu $40 vsstresc $200 
           vsstresu $40 vsstat $20 vsreasnd $200 visit $200 
           vsdtc $19 vspos $20;
    set vs_seq;
    
    domain = 'VS';
    
    /* Apply variable labels */
    label
        studyid  = 'Study Identifier'
        domain   = 'Domain Abbreviation'
        usubjid  = 'Unique Subject Identifier'
        vsseq    = 'Sequence Number'
        vstestcd = 'Vital Signs Test Short Name'
        vstest   = 'Vital Signs Test Name'
        vscat    = 'Category for Vital Signs'
        vsorres  = 'Result or Finding in Original Units'
        vsorresu = 'Original Units'
        vsstresc = 'Character Result/Finding in Std Format'
        vsstresn = 'Numeric Result/Finding in Standard Units'
        vsstresu = 'Standard Units'
        vsstat   = 'Completion Status'
        vsreasnd = 'Reason Not Done'
        visitnum = 'Visit Number'
        visit    = 'Visit Name'
        vsdtc    = 'Date/Time of Measurements'
        vsdy     = 'Study Day of Vital Signs'
        vspos    = 'Vital Signs Position of Subject'
    ;
    
    /* Keep only SDTM variables in specified order */
    keep studyid domain usubjid vsseq vstestcd vstest vscat 
         vsorres vsorresu vsstresc vsstresn vsstresu 
         vsstat vsreasnd visitnum visit vsdtc vsdy vspos;
run;

/*-----------------------------------------------------------------------------
  Step 8: Final sort by specification
-----------------------------------------------------------------------------*/
proc sort data=sdtm.vs;
    by studyid usubjid visitnum vsdtc vstestcd;
run;

/*-- END VS --*/

/*-- Final sort and output verification --*/
proc sort data=sdtm.vs;
  by STUDYID USUBJID;
run;

proc contents data=sdtm.vs varnum;
run;

proc freq data=sdtm.vs;
  tables DOMAIN / nocum nopercent;
run;

/* End of vs.sas */
