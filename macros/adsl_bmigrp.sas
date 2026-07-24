/***********************************************************************
* Macro:    %adsl_bmigrp
* Purpose:  Derive BMI group variable with missing-value guard
* Author:   Macro Library
* Params:   inds     = input dataset (default: adsl)
*           bmivar   = source BMI variable (default: BMIBL)
*           grpvar   = output group variable (default: BMIBLGR1)
*           cuts     = cut points, pipe-delimited (default: 25|30)
*           labels   = group labels, pipe-delimited (default: <25|25-<30|>=30)
* Notes:    Guards against missing BMI before any comparison.
*           Reuses %adsl_agegr logic with missing guard.
***********************************************************************/
%macro adsl_bmigrp(inds=adsl, bmivar=BMIBL, grpvar=BMIBLGR1,
                   cuts=25|30, labels=<25|25-<30|>=30);

  data &inds;
    set &inds;
    length &grpvar $20;

    if missing(&bmivar) then call missing(&grpvar);
    else do;
      %let ncuts = %sysfunc(countw(&cuts, |));
      %let nlabels = %sysfunc(countw(&labels, |));
      %do i = 1 %to &ncuts;
        %let c = %scan(&cuts, &i, |);
        %let lbl = %scan(&labels, &i, |);
        %if &i = 1 %then %do;
          if &bmivar < &c then &grpvar = "&lbl";
        %end;
        %else %do;
          else if &bmivar < &c then &grpvar = "&lbl";
        %end;
      %end;
      %let lastlbl = %scan(&labels, &nlabels, |);
      else &grpvar = "&lastlbl";
    end;
  run;

%mend adsl_bmigrp;
