/***********************************************************************
* Macro:    %sdtm_seq
* Purpose:  Assign a domain's --SEQ sequence number, unique within
*           USUBJID, in the dataset's current row order
* Author:   Macro Library
* Params:   inds     = input dataset (default: _last_)
*           byvar    = subject identifier (default: USUBJID)
*           seqvar   = output --SEQ variable (e.g. AESEQ, CMSEQ, VSSEQ)
* Notes:    Caller is responsible for sorting into the order --SEQ should
*           follow (usually by USUBJID and the domain's key dates) before
*           calling this macro — it only numbers within whatever order
*           the data already has.
***********************************************************************/
%macro sdtm_seq(inds=_last_, byvar=USUBJID, seqvar=);

  proc sort data=&inds; by &byvar; run;

  data &inds;
    set &inds;
    by &byvar;
    length &seqvar 8;
    label &seqvar = "&seqvar";

    retain &seqvar;
    if first.&byvar then &seqvar = 1;
    else &seqvar = &seqvar + 1;
  run;

%mend sdtm_seq;
