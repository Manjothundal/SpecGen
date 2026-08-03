/***********************************************************************
* Macro:    %tlf_bign
* Purpose:  Compute the Big-N denominator (distinct subjects) per
*           treatment arm/column, for use in table column headers and
*           as the percentage denominator in n (%) display rows
* Author:   Macro Library
* Params:   indata   = input dataset, one row per subject per arm
*                      (already restricted to the analysis population)
*           armvar   = arm/column grouping variable (default: _ARM)
*           idvar    = subject identifier (default: USUBJID)
*           outdata  = output dataset with &armvar and bigN (default: _bign)
* Notes:    One row per distinct &armvar value. Standard company
*           convention: Big-N counts distinct subjects, never records.
***********************************************************************/
%macro tlf_bign(indata=, armvar=_ARM, idvar=USUBJID, outdata=_bign);

  proc sql noprint;
    create table &outdata as
    select &armvar, count(distinct &idvar) as bigN
    from &indata
    group by &armvar;
  quit;

%mend tlf_bign;
