"""
sdtm_spec_builder.py - Build a draft SDTM specification from reviewed aCRF metadata.

Phase 5b in the SpecGen pipeline:
  acrf_metadata.xlsx (reviewed) --> sdtm_spec_draft.xlsx (one sheet per domain)

Handles both standard domains (DM, AE, VS, CM, EX) and SUPP-- domains
(SUPPAE, SUPPDM, etc.) with the correct structural variable templates.

Usage:
  python sdtm_spec_builder.py acrf_metadata.xlsx --output sdtm_spec_draft.xlsx
  python sdtm_spec_builder.py acrf_metadata.xlsx --output sdtm_spec_draft.xlsx --offline
"""

import argparse
import json
import os

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter


# ── CDISC structural variables ──────────────────────────────────────
# {D} = domain abbreviation (AE, VS, etc.)

STRUCTURAL_VARS = [
    ("STUDYID",    "Study Identifier",                       "Char",  20, "Assigned", "Req"),
    ("{D}SEQ",     "Sequence Number",                        "Num",    8, "Derived",  "Req"),
    ("USUBJID",    "Unique Subject Identifier",              "Char",  40, "Derived",  "Req"),
    ("DOMAIN",     "Domain Abbreviation",                    "Char",   2, "Assigned", "Req"),
]

DM_EXTRA_VARS = [
    ("RFSTDTC",   "Subject Reference Start Date/Time",      "Char",  19, "CRF",      "Exp"),
    ("RFENDTC",   "Subject Reference End Date/Time",        "Char",  19, "CRF",      "Exp"),
    ("RFXSTDTC",  "Date/Time of First Study Treatment",     "Char",  19, "CRF",      "Exp"),
    ("RFXENDTC",  "Date/Time of Last Study Treatment",      "Char",  19, "CRF",      "Exp"),
    ("SITEID",    "Study Site Identifier",                   "Char",  10, "CRF",      "Req"),
    ("INVID",     "Investigator Identifier",                 "Char",  10, "Assigned", "Perm"),
    ("INVNAM",    "Investigator Name",                       "Char",  60, "Assigned", "Perm"),
    ("COUNTRY",   "Country",                                "Char",   3, "Assigned", "Req"),
    ("ARMCD",     "Planned Arm Code",                       "Char",  20, "Assigned", "Req"),
    ("ARM",       "Description of Planned Arm",             "Char", 200, "CRF",      "Req"),
    ("ACTARMCD",  "Actual Arm Code",                        "Char",  20, "Derived",  "Req"),
    ("ACTARM",    "Description of Actual Arm",              "Char", 200, "Derived",  "Req"),
]

FINDINGS_DOMAINS = {"VS", "LB", "EG", "PE", "QS", "SC", "DA", "MB", "MS", "PC", "PP"}

FINDINGS_EXTRA_VARS = [
    ("{D}TESTCD", "Short Name of Measurement",              "Char",   8, "Assigned", "Req"),
    ("{D}TEST",   "Name of Measurement",                    "Char",  40, "Assigned", "Req"),
    ("{D}ORRES",  "Result or Finding in Original Units",    "Char", 200, "CRF",      "Exp"),
    ("{D}ORRESU", "Original Units",                         "Char",  40, "Assigned", "Exp"),
    ("{D}STRESC", "Character Result in Std Format",         "Char", 200, "Derived",  "Exp"),
    ("{D}STRESN", "Numeric Result in Standard Units",       "Num",    8, "Derived",  "Exp"),
    ("{D}STRESU", "Standard Units",                         "Char",  40, "Assigned", "Exp"),
]

TIMING_VARS = [
    ("VISITNUM",  "Visit Number",                           "Num",    8, "Derived",  "Exp"),
    ("VISIT",     "Visit Name",                             "Char",  40, "CRF",      "Exp"),
    ("{D}DTC",    "Date/Time of Collection",                "Char",  19, "CRF",      "Exp"),
    ("{D}DY",     "Study Day of Collection",                "Num",    8, "Derived",  "Perm"),
]

# SUPP-- domains have a fixed structure: RDOMAIN, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL, QORIG, QEVAL
SUPP_STRUCTURAL_VARS = [
    ("STUDYID",   "Study Identifier",                       "Char",  20, "Assigned", "Req"),
    ("RDOMAIN",   "Related Domain Abbreviation",            "Char",   2, "Assigned", "Req"),
    ("USUBJID",   "Unique Subject Identifier",              "Char",  40, "Derived",  "Req"),
    ("IDVAR",     "Identifying Variable",                   "Char",   8, "Assigned", "Req"),
    ("IDVARVAL",  "Identifying Variable Value",             "Char",  40, "Derived",  "Req"),
    ("QNAM",      "Qualifier Variable Name",                "Char",   8, "Assigned", "Req"),
    ("QLABEL",    "Qualifier Variable Label",               "Char",  40, "Assigned", "Req"),
    ("QVAL",      "Data Value",                             "Char", 200, "CRF",      "Req"),
    ("QORIG",     "Origin",                                 "Char",  20, "Assigned", "Req"),
    ("QEVAL",     "Evaluator",                              "Char",  20, "Assigned", "Perm"),
]


# ── Read reviewed aCRF metadata ─────────────────────────────────────

def read_acrf_metadata(xlsx_path):
    """
    Read the reviewed acrf_metadata.xlsx.
    Returns a dict: {domain: [list of field dicts]}
    Skips rows where Review Status = "Delete".
    """
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    ws = wb["By Domain"]

    headers = [cell.value for cell in ws[1]]

    domains = {}
    for row in ws.iter_rows(min_row=2, values_only=True):
        record = dict(zip(headers, row))
        status = (record.get("Review Status") or "").strip().upper()
        if status == "DELETE":
            continue

        domain = record.get("Domain", "")
        if not domain:
            continue

        domains.setdefault(domain, []).append(record)

    wb.close()
    return domains


# ── Build structural variables per domain ───────────────────────────

def _expand_template(var_tuple, domain):
    """Replace {D} with domain abbreviation."""
    name, label, vtype, length, origin, core = var_tuple
    name = name.replace("{D}", domain)
    label = label.replace("{D}", domain)
    return {
        "variable": name,
        "label": label,
        "type": vtype,
        "length": length,
        "origin": origin,
        "core": core,
        "codelist": "",
        "crf_page": "",
        "derivation": "",
        "source": "structural",
    }


def get_structural_vars(domain):
    """Return structural variables for a given domain."""
    is_supp = domain.startswith("SUPP")

    if is_supp:
        # SUPP domains have their own fixed structure
        return [_expand_template(v, domain) for v in SUPP_STRUCTURAL_VARS]

    result = []
    for v in STRUCTURAL_VARS:
        result.append(_expand_template(v, domain))

    if domain == "DM":
        for v in DM_EXTRA_VARS:
            result.append(_expand_template(v, domain))

    if domain in FINDINGS_DOMAINS:
        for v in FINDINGS_EXTRA_VARS:
            result.append(_expand_template(v, domain))

    if domain != "DM":
        for v in TIMING_VARS:
            result.append(_expand_template(v, domain))

    return result


# ── Claude API enrichment ───────────────────────────────────────────

def _call_claude(prompt):
    """Call Claude API and return the text response."""
    import anthropic
    client = anthropic.Anthropic()
    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
    )
    return response.content[0].text


def enrich_with_claude(domain, crf_fields):
    """Ask Claude to fill in SDTM metadata for CRF-sourced variables."""
    is_supp = domain.startswith("SUPP")

    field_lines = []
    for f in crf_fields:
        line = f"  {f['Variable']}: CRF label = \"{f['CRF Label'] or ''}\" | codelist = \"{f['Codelist'] or ''}\" | qualifier = \"{f['Qualifier'] or ''}\""
        field_lines.append(line)

    if is_supp:
        parent_domain = domain.replace("SUPP", "")
        prompt = f"""You are an expert CDISC SDTM programmer. I extracted these supplemental qualifier variables from an aCRF for {domain} (parent domain: {parent_domain}):

{chr(10).join(field_lines)}

These are non-standard variables that go into a SUPP-- dataset. For each variable, provide metadata for the QNAM/QLABEL/QVAL rows. Return ONLY a JSON array (no markdown fences, no explanation) where each element has:
  "variable": the QNAM value (e.g. "AEACNOTH"),
  "label": the QLABEL value - a proper variable label (e.g. "Other Action Taken"),
  "type": always "Char" (QVAL is always character in SUPP),
  "length": 200 (standard QVAL length),
  "origin": "CRF" or "Derived",
  "core": "Perm",
  "codelist": codelist name if applicable or empty string,
  "derivation": short note if derived, otherwise empty string

Return valid JSON only."""
    else:
        prompt = f"""You are an expert CDISC SDTM programmer. I extracted these variables from an aCRF for domain {domain}:

{chr(10).join(field_lines)}

For each variable, provide the correct SDTM metadata. Return ONLY a JSON array (no markdown fences, no explanation) where each element has:
  "variable": the SDTM variable name (e.g. "AETERM"),
  "label": the proper SDTM variable label per CDISC (e.g. "Reported Term for the Adverse Event"),
  "type": "Char" or "Num",
  "length": integer (dates=19, short codes=8, terms/text=200, numeric=8),
  "origin": "CRF" or "Derived" or "Assigned",
  "core": "Req" or "Exp" or "Perm",
  "codelist": codelist name if applicable or empty string,
  "derivation": short derivation note if origin is Derived, otherwise empty string

Rules:
- Use standard CDISC SDTM variable labels, NOT the CRF field label
- For findings domains with qualifiers like VSTESTCD=SYSBP, produce ONE row per unique variable name
- Only return the CRF-sourced variables listed above, not structural ones

Return valid JSON only."""

    try:
        raw = _call_claude(prompt)
        cleaned = raw.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.split("\n", 1)[1]
        if cleaned.endswith("```"):
            cleaned = cleaned.rsplit("```", 1)[0]
        cleaned = cleaned.strip()
        return json.loads(cleaned)
    except Exception as e:
        print(f"  Warning: Claude API call failed for {domain}: {e}")
        print(f"  Falling back to basic metadata inference")
        return _fallback_enrich(domain, crf_fields)


def _fallback_enrich(domain, crf_fields):
    """Basic fallback if Claude API is unavailable."""
    is_supp = domain.startswith("SUPP")
    results = []
    seen = set()

    for f in crf_fields:
        var = f["Variable"]
        if var in seen:
            continue
        seen.add(var)

        if is_supp:
            # SUPP variables are always Char 200 (they go in QVAL)
            results.append({
                "variable": var,
                "label": (f["CRF Label"] or var).rstrip(":").strip(),
                "type": "Char",
                "length": 200,
                "origin": "CRF",
                "core": "Perm",
                "codelist": f.get("Codelist") or "",
                "derivation": "",
            })
        else:
            # Infer type/length from naming patterns
            if var.endswith("DTC"):
                vtype, length = "Char", 19
            elif var.endswith("STRESN") or var.endswith("SEQ") or var.endswith("NUM") or var == "AGE":
                vtype, length = "Num", 8
            elif var.endswith("CD") or var.endswith("FL") or var in ("SEX", "DOMAIN"):
                vtype, length = "Char", 8
            elif var.endswith("TERM") or var.endswith("TRT") or var.endswith("DECOD"):
                vtype, length = "Char", 200
            elif var == "CMDOSE":
                vtype, length = "Num", 8
            else:
                vtype, length = "Char", 40

            results.append({
                "variable": var,
                "label": (f["CRF Label"] or var).rstrip(":").strip(),
                "type": vtype,
                "length": length,
                "origin": "CRF",
                "core": "Exp",
                "codelist": f.get("Codelist") or "",
                "derivation": "",
            })

    return results


# ── Merge structural + CRF-enriched variables ──────────────────────

def build_domain_spec(domain, crf_fields, use_api=True):
    """Build the full SDTM spec for one domain."""
    is_supp = domain.startswith("SUPP")
    tag = " [SUPP]" if is_supp else ""
    print(f"\n  Building spec for domain: {domain}{tag} ({len(crf_fields)} CRF fields)")

    structural = get_structural_vars(domain)
    structural_names = {v["variable"] for v in structural}

    if use_api:
        enriched = enrich_with_claude(domain, crf_fields)
    else:
        enriched = _fallback_enrich(domain, crf_fields)

    crf_vars = []
    seen_vars = set()
    for e in enriched:
        var_name = e["variable"]
        if var_name in seen_vars:
            continue
        seen_vars.add(var_name)

        crf_page = ""
        for f in crf_fields:
            if f["Variable"] == var_name:
                crf_page = f.get("Page Title") or ""
                break

        if var_name in structural_names:
            for sv in structural:
                if sv["variable"] == var_name:
                    sv["codelist"] = e.get("codelist", "")
                    sv["crf_page"] = crf_page
                    if e.get("origin") == "CRF":
                        sv["origin"] = "CRF"
                    break
            continue

        crf_vars.append({
            "variable": var_name,
            "label": e.get("label", var_name),
            "type": e.get("type", "Char"),
            "length": e.get("length", 40),
            "origin": e.get("origin", "CRF"),
            "core": e.get("core", "Exp"),
            "codelist": e.get("codelist", ""),
            "crf_page": crf_page,
            "derivation": e.get("derivation", ""),
            "source": "crf",
        })

    all_vars = structural + crf_vars

    if is_supp:
        # For SUPP, also add a QNAM reference table as a note
        # The CRF variables become QNAM values, not separate columns
        print(f"    {len(structural)} structural (SUPP template) + {len(crf_vars)} qualifier values")
        print(f"    QNAM values: {', '.join(v['variable'] for v in crf_vars)}")
    else:
        print(f"    {len(structural)} structural + {len(crf_vars)} CRF = {len(all_vars)} total variables")

    return all_vars


# ── Write the draft SDTM spec to Excel ──────────────────────────────

def write_sdtm_spec(domain_specs, output_path):
    """Write the draft SDTM spec to Excel with one sheet per domain."""
    wb = openpyxl.Workbook()

    # Styles
    header_font = Font(name="Arial", bold=True, size=11, color="FFFFFF")
    header_fill = PatternFill(start_color="1A3C6E", end_color="1A3C6E", fill_type="solid")
    header_align = Alignment(horizontal="center", vertical="center", wrap_text=True)
    body_font = Font(name="Arial", size=10)
    struct_fill = PatternFill(start_color="FFF2CC", end_color="FFF2CC", fill_type="solid")
    crf_fill = PatternFill(start_color="E8F0FE", end_color="E8F0FE", fill_type="solid")
    supp_struct_fill = PatternFill(start_color="E2EFDA", end_color="E2EFDA", fill_type="solid")
    supp_crf_fill = PatternFill(start_color="D5E8D4", end_color="D5E8D4", fill_type="solid")
    thin_border = Border(
        left=Side(style="thin"), right=Side(style="thin"),
        top=Side(style="thin"), bottom=Side(style="thin"),
    )

    headers = ["Variable", "Label", "Type", "Length", "Origin",
               "Core", "Codelist", "CRF Page", "Derivation"]
    col_widths = [14, 45, 8, 8, 10, 8, 20, 20, 40]

    # ── Cover sheet ─────────────────────────────────────────────────

    cover = wb.active
    cover.title = "Cover"
    cover.cell(row=1, column=1, value="SDTM Specification Draft").font = Font(
        name="Arial", bold=True, size=16, color="1A3C6E")
    cover.cell(row=2, column=1, value="Generated by SpecGen - Phase 5b").font = Font(
        name="Arial", size=11, color="666666")
    cover.cell(row=3, column=1, value="Review each domain sheet, then pass to Phase 5c for program generation.").font = Font(
        name="Arial", size=10)
    cover.cell(row=4, column=1, value="Yellow = structural vars | Blue = CRF vars | Green = SUPP domains").font = Font(
        name="Arial", size=9, color="666666")

    for col_idx, header in enumerate(["Domain", "Variables", "Type", "Structural", "CRF"], start=1):
        cell = cover.cell(row=6, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.border = thin_border

    cover.column_dimensions["A"].width = 12
    cover.column_dimensions["B"].width = 12
    cover.column_dimensions["C"].width = 12
    cover.column_dimensions["D"].width = 12
    cover.column_dimensions["E"].width = 12

    total_vars = 0
    for row_idx, domain in enumerate(sorted(domain_specs), start=7):
        vars_list = domain_specs[domain]
        n_struct = sum(1 for v in vars_list if v.get("source") == "structural")
        n_crf = sum(1 for v in vars_list if v.get("source") != "structural")
        dtype = "SUPP" if domain.startswith("SUPP") else "Standard"
        cover.cell(row=row_idx, column=1, value=domain).font = body_font
        cover.cell(row=row_idx, column=1).border = thin_border
        cover.cell(row=row_idx, column=2, value=len(vars_list)).font = body_font
        cover.cell(row=row_idx, column=2).border = thin_border
        cover.cell(row=row_idx, column=3, value=dtype).font = body_font
        cover.cell(row=row_idx, column=3).border = thin_border
        cover.cell(row=row_idx, column=4, value=n_struct).font = body_font
        cover.cell(row=row_idx, column=4).border = thin_border
        cover.cell(row=row_idx, column=5, value=n_crf).font = body_font
        cover.cell(row=row_idx, column=5).border = thin_border
        if domain.startswith("SUPP"):
            for ci in range(1, 6):
                cover.cell(row=row_idx, column=ci).fill = supp_struct_fill
        total_vars += len(vars_list)

    total_row = 7 + len(domain_specs)
    bold = Font(name="Arial", bold=True, size=10)
    cover.cell(row=total_row, column=1, value="TOTAL").font = bold
    cover.cell(row=total_row, column=1).border = thin_border
    cover.cell(row=total_row, column=2, value=total_vars).font = bold
    cover.cell(row=total_row, column=2).border = thin_border

    # ── One sheet per domain ────────────────────────────────────────

    for domain in sorted(domain_specs):
        is_supp = domain.startswith("SUPP")
        vars_list = domain_specs[domain]
        ws = wb.create_sheet(title=domain)

        # For SUPP sheets, add a note explaining the structure
        if is_supp:
            parent = domain.replace("SUPP", "")
            note_row = 1
            ws.cell(row=note_row, column=1,
                    value=f"SUPP-- Structure: Each CRF field below becomes a QNAM row in {domain}").font = Font(
                name="Arial", bold=True, size=10, color="006600")
            ws.cell(row=note_row + 1, column=1,
                    value=f"RDOMAIN = {parent} | IDVAR = {parent}SEQ | QORIG = CRF").font = Font(
                name="Arial", size=9, color="666666")
            start_row = 4
        else:
            start_row = 1

        # Headers
        for col_idx, (h, w) in enumerate(zip(headers, col_widths), start=1):
            cell = ws.cell(row=start_row, column=col_idx, value=h)
            cell.font = header_font
            cell.fill = header_fill
            cell.alignment = header_align
            cell.border = thin_border
            ws.column_dimensions[get_column_letter(col_idx)].width = w

        # Data rows
        for row_idx, v in enumerate(vars_list, start=start_row + 1):
            row_data = [
                v["variable"], v["label"], v["type"], v["length"],
                v["origin"], v["core"], v["codelist"],
                v.get("crf_page", ""), v.get("derivation", ""),
            ]
            if is_supp:
                fill = supp_struct_fill if v.get("source") == "structural" else supp_crf_fill
            else:
                fill = struct_fill if v.get("source") == "structural" else crf_fill

            for col_idx, val in enumerate(row_data, start=1):
                cell = ws.cell(row=row_idx, column=col_idx, value=val)
                cell.font = body_font
                cell.fill = fill
                cell.border = thin_border

        ws.freeze_panes = f"A{start_row + 1}"
        last_row = start_row + len(vars_list)
        ws.auto_filter.ref = f"A{start_row}:{get_column_letter(len(headers))}{last_row}"

    wb.save(output_path)

    n_std = sum(1 for d in domain_specs if not d.startswith("SUPP"))
    n_supp = sum(1 for d in domain_specs if d.startswith("SUPP"))
    print(f"\nDraft SDTM spec written to {output_path}")
    print(f"  {n_std} standard + {n_supp} SUPP domain sheets + Cover")
    print(f"  {total_vars} total variables")


# ── Main pipeline ──────────────────────────────────────────────────

def build_sdtm_spec(acrf_metadata_path, output_path, use_api=True):
    """Full pipeline: read reviewed aCRF metadata -> build SDTM spec -> write Excel."""
    print(f"Reading reviewed aCRF metadata: {acrf_metadata_path}")
    domain_fields = read_acrf_metadata(acrf_metadata_path)

    std_domains = [d for d in sorted(domain_fields) if not d.startswith("SUPP")]
    supp_domains = [d for d in sorted(domain_fields) if d.startswith("SUPP")]
    print(f"  Standard domains: {', '.join(std_domains)}")
    print(f"  SUPP domains: {', '.join(supp_domains)}")

    domain_specs = {}
    for domain in std_domains + supp_domains:
        crf_fields = domain_fields[domain]
        spec = build_domain_spec(domain, crf_fields, use_api=use_api)
        domain_specs[domain] = spec

    write_sdtm_spec(domain_specs, output_path)
    return domain_specs


# ── CLI entry point ─────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Build a draft SDTM specification from reviewed aCRF metadata."
    )
    parser.add_argument("metadata",
                        help="Path to reviewed acrf_metadata.xlsx")
    parser.add_argument("--output", "-o", default="sdtm_spec_draft.xlsx",
                        help="Output path (default: sdtm_spec_draft.xlsx)")
    parser.add_argument("--offline", action="store_true",
                        help="Skip Claude API, use fallback inference only")

    args = parser.parse_args()
    build_sdtm_spec(args.metadata, args.output, use_api=not args.offline)
