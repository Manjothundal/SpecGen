/***********************************************************************
* Macro:    %adsl_dtctodt
* Purpose:  Convert an ISO 8601 --DTC character variable to a numeric
*           SAS date, handling partial dates and missing values
* Author:   Macro Library
* Params:   inds     = input dataset (default: adsl)
*           dtcvar   = source --DTC character variable (e.g. DTHDTC)
*           dtvar    = output numeric date variable (e.g. DTHDT)
*           fmt      = output format (default: DATE9.)
* Notes:    Requires complete date (>=10 chars). Partial dates set to missing.
*           Uses E8601DA. informat for CDISC compliance.
***********************************************************************/
%macro adsl_dtctodt(inds=adsl, dtcvar=, dtvar=, fmt=DATE9.);

  data &inds;
    set &inds;
    length &dtvar 8;
    format &dtvar &fmt;
    label &dtvar = "&dtvar";

    if missing(&dtcvar) or length(strip(&dtcvar)) < 10 then
      call missing(&dtvar);
    else
      &dtvar = input(substr(&dtcvar, 1, 10), ?? E8601DA.);
  run;

%mend adsl_dtctodt;
