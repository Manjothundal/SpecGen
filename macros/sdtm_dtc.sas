/***********************************************************************
* Macro:    %sdtm_dtc
* Purpose:  Convert a raw CRF date (and optional time) into an ISO 8601
*           character value for an SDTM --DTC variable, preserving
*           partial dates (year-only, year-month) instead of dropping them
* Author:   Macro Library
* Params:   inds     = input dataset (default: _last_)
*           rawdt    = raw date variable, any of: SAS numeric date,
*                      or character in YYYY-MM-DD / partial form
*           rawtm    = raw time variable, character HH:MM (optional —
*                      omit for a date-only --DTC)
*           dtcvar   = output ISO 8601 character variable (e.g. AESTDTC)
* Notes:    A raw date already missing/blank produces a missing --DTC
*           (SDTM does not carry forward or impute at this layer).
*           Partial raw dates (year only, or year+month) are passed
*           through as partial ISO 8601 (e.g. "2023", "2023-06") rather
*           than forced to a full date — full-date derivations should
*           resolve partials before calling this macro.
***********************************************************************/
%macro sdtm_dtc(inds=_last_, rawdt=, rawtm=, dtcvar=);

  data &inds;
    set &inds;
    length &dtcvar $19;

    if missing(&rawdt) then &dtcvar = "";
    else &dtcvar = put(&rawdt, e8601da.);

    %if %length(&rawtm) %then %do;
      if not missing(&dtcvar) and not missing(&rawtm) then
        &dtcvar = strip(&dtcvar) || "T" || strip(&rawtm);
    %end;
  run;

%mend sdtm_dtc;
