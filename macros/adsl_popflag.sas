/***********************************************************************
* Macro:    %adsl_popflag
* Purpose:  Derive a population flag (Y/N) from a simple condition
* Author:   Macro Library
* Params:   inds     = input dataset (default: adsl)
*           flagvar  = output flag variable (e.g. SAFFL)
*           cond     = SAS condition expression (e.g. not missing(TRTSDT))
*           label    = variable label (e.g. Safety Population Flag)
* Notes:    Always character $1. Y if condition true, N otherwise.
***********************************************************************/
%macro adsl_popflag(inds=adsl, flagvar=, cond=, label=);

  data &inds;
    set &inds;
    length &flagvar $1;
    label &flagvar = "&label";

    if &cond then &flagvar = 'Y';
    else &flagvar = 'N';
  run;

%mend adsl_popflag;
