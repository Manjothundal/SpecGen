/***********************************************************************
* Macro:    %sdtm_suppqual
* Purpose:  Build one SUPP-- row (IDVAR/IDVARVAL/QNAM/QLABEL/QVAL/QORIG)
*           from a single non-standard variable on the parent domain
* Author:   Macro Library
* Params:   inds     = parent domain dataset, already containing the
*                      non-standard variable to promote
*           domain   = parent domain code (e.g. AE, CM) — populates
*                      RDOMAIN on the SUPP-- record
*           idvar    = parent key variable name (e.g. AESEQ) — leave
*                      blank if the qualifier applies at the USUBJID
*                      level with no additional key
*           srcvar   = the non-standard variable on &inds to promote
*           qnam     = QNAM value (<=8 chars, no special characters)
*           qlabel   = QLABEL value (<=40 chars)
*           qorig    = QORIG value (default: CRF)
*           outds    = output SUPP-- dataset (default: _suppqual)
* Notes:    Appends to &outds if it already exists, so multiple calls
*           (one per non-standard variable) build up the full SUPP--
*           dataset. Rows with a missing &srcvar are dropped — SUPP--
*           carries only non-missing qualifier values.
***********************************************************************/
%macro sdtm_suppqual(inds=, domain=, idvar=, srcvar=, qnam=, qlabel=, qorig=CRF, outds=_suppqual);

  data _sq_&qnam;
    set &inds;
    where not missing(&srcvar);
    length STUDYID $20 RDOMAIN $2 USUBJID $40 IDVAR $8 IDVARVAL $20
           QNAM $8 QLABEL $40 QVAL $200 QORIG $20;
    RDOMAIN  = "&domain";
    IDVAR    = "&idvar";
    %if %length(&idvar) %then %do;
      IDVARVAL = strip(vvalue(&idvar));
    %end;
    %else %do;
      IDVARVAL = "";
    %end;
    QNAM  = "&qnam";
    QLABEL = "&qlabel";
    QVAL  = strip(vvalue(&srcvar));
    QORIG = "&qorig";
    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG;
  run;

  proc append base=&outds data=_sq_&qnam force; run;

%mend sdtm_suppqual;
