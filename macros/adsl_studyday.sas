/***********************************************************************
* Macro:    %adsl_studyday
* Purpose:  Derive a CDISC --DY study day variable (no day zero)
* Author:   Macro Library
* Params:   inds     = input dataset (default: adsl)
*           datevar  = event date variable (e.g. DTHDT)
*           refvar   = reference date variable (e.g. TRTSDT)
*           dyvar    = output --DY variable (e.g. DTHDY)
*           label    = variable label
* Notes:    Uses CDISC convention: (date - ref) + (date >= ref).
*           Missing if either date is missing.
***********************************************************************/
%macro adsl_studyday(inds=adsl, datevar=, refvar=TRTSDT, dyvar=, label=);

  data &inds;
    set &inds;
    length &dyvar 8;
    label &dyvar = "&label";

    if missing(&datevar) or missing(&refvar) then call missing(&dyvar);
    else &dyvar = (&datevar - &refvar) + (&datevar >= &refvar);
  run;

%mend adsl_studyday;
