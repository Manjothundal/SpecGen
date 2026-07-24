/***********************************************************************
* Macro:    %adsl_trtvar
* Purpose:  Derive treatment variables (character + numeric) from ARM
* Author:   Macro Library
* Params:   inds     = input dataset (default: adsl)
*           srcvar   = source variable (default: ARM)
*           trtvar   = output character variable (default: TRT01P)
*           trtnvar  = output numeric variable (default: TRT01PN)
*           map      = treatment-to-number mapping, pipe-delimited
*                      format: label1=0|label2=1|label3=2
* Notes:    Handles missing/unmapped treatments (sets numeric to missing).
***********************************************************************/
%macro adsl_trtvar(inds=adsl, srcvar=ARM, trtvar=TRT01P, trtnvar=TRT01PN,
                   map=Placebo=0|Drug A 50mg=1|Drug A 100mg=2);

  data &inds;
    set &inds;
    length &trtvar $40;
    &trtvar = &srcvar;
    &trtnvar = .;

    %let n = %sysfunc(countw(&map, |));
    %do i = 1 %to &n;
      %let pair = %scan(&map, &i, |);
      %let lbl = %scan(&pair, 1, =);
      %let num = %scan(&pair, 2, =);
      if &trtvar = "&lbl" then &trtnvar = &num;
    %end;
  run;

%mend adsl_trtvar;
