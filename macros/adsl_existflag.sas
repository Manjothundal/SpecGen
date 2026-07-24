/***********************************************************************
* Macro:    %adsl_existflag
* Purpose:  Derive an existence flag (Y/N) based on whether a subject
*           has any records matching a condition in a source dataset
* Author:   Macro Library
* Params:   inds     = target dataset to update (default: adsl)
*           srcds    = source dataset to check (e.g. cm, mh)
*           flagvar  = output flag variable (e.g. CMFL)
*           cond     = where condition on source dataset
*                      (e.g. cmcat in ('PRIOR','CONCOMITANT'))
*           label    = variable label
*           byvar    = merge key (default: usubjid)
* Notes:    Creates flag via PROC SQL existence check, then merges.
***********************************************************************/
%macro adsl_existflag(inds=adsl, srcds=, flagvar=, cond=1, label=, byvar=usubjid);

  proc sql;
    create table _exist_ as select distinct
      &byvar
    from &srcds
    where &cond;
  quit;

  data &inds;
    merge &inds(in=a) _exist_(in=b);
    by &byvar;
    if a;
    length &flagvar $1;
    label &flagvar = "&label";
    if b then &flagvar = 'Y';
    else &flagvar = 'N';
  run;

  proc delete data=_exist_; run;

%mend adsl_existflag;
