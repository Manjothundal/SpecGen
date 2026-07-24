/***********************************************************************
* Macro:    %adsl_agegr
* Purpose:  Derive age group variables (character + numeric) from AGE
* Author:   Macro Library
* Params:   inds     = input dataset (default: adsl)
*           agevar   = source age variable (default: AGE)
*           grpvar   = output character variable (default: AGEGR1)
*           grpnvar  = output numeric variable (default: AGEGR1N)
*           cuts     = cut points, pipe-delimited (default: 65|80)
*           labels   = group labels, pipe-delimited (default: <65|65-80|>80)
* Notes:    Handles missing AGE (sets both outputs to missing).
*           Labels list must have one more entry than cuts.
***********************************************************************/
%macro adsl_agegr(inds=adsl, agevar=AGE, grpvar=AGEGR1, grpnvar=AGEGR1N,
                  cuts=65|80, labels=<65|65-80|>80);

  /* Parse cuts and labels */
  %let ncuts = %sysfunc(countw(&cuts, |));
  %let nlabels = %sysfunc(countw(&labels, |));

  data &inds;
    set &inds;
    length &grpvar $10;

    if missing(&agevar) then do;
      call missing(&grpvar);
      &grpnvar = .;
    end;
    %do i = 1 %to &ncuts;
      %let c = %scan(&cuts, &i, |);
      %let lbl = %scan(&labels, &i, |);
      %if &i = 1 %then %do;
        else if &agevar < &c then do; &grpvar = "&lbl"; &grpnvar = &i; end;
      %end;
      %else %do;
        else if &agevar <= &c then do; &grpvar = "&lbl"; &grpnvar = &i; end;
      %end;
    %end;
    %let lastlbl = %scan(&labels, &nlabels, |);
    else do; &grpvar = "&lastlbl"; &grpnvar = &nlabels; end;
  run;

%mend adsl_agegr;
