/***********************************************************************
* Macro:    %tlf_pctfmt
* Purpose:  Standard company display format for a count with percentage:
*           "n (xx.x%)", or bare "n" when the denominator is zero
* Author:   Macro Library
* Params:   n        = count variable name
*           bign     = Big-N denominator variable name (see %tlf_bign)
*           dec      = decimal places for the percentage (default: 1)
* Notes:    This is an INLINE (open-code) macro — it expands to an
*           expression, not a data step, so call it on the right-hand
*           side of an assignment:
*             value = %tlf_pctfmt(n=n, bign=bigN, dec=1);
*           Matches company convention: percentage suppressed (not 0.0%)
*           when the denominator is zero.
***********************************************************************/
%macro tlf_pctfmt(n=, bign=, dec=1);
  ifc(&bign > 0,
      strip(put(&n, 8.)) || " (" || strip(put(100*&n/&bign, 8.&dec)) || "%)",
      strip(put(&n, 8.)))
%mend tlf_pctfmt;
