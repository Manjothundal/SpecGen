"""
Build a sample annotated CRF (aCRF) PDF for testing the aCRF parser.

Real aCRFs look like printed CRF pages with colored annotations (usually blue)
next to each field, showing the SDTM domain and variable (e.g. DM.BRTHDTC).
Fields that don't map to standard SDTM variables are annotated with SUPP--
(e.g. SUPPAE.AEACNOTH).

This script creates a 4-page sample covering:
  Page 1: Demographics (DM + SUPPDM)
  Page 2: Vital Signs (VS + SUPPVS)
  Page 3: Adverse Events (AE + SUPPAE)
  Page 4: Concomitant Medications (CM + SUPPCM)
"""

from reportlab.lib.pagesizes import letter
from reportlab.lib.colors import HexColor, black, white
from reportlab.lib.units import inch
from reportlab.pdfgen import canvas

BLUE = HexColor("#0000CC")       # annotation color
GRAY_BG = HexColor("#F0F0F0")    # field box background
DARK_GRAY = HexColor("#333333")  # form labels
LIGHT_BLUE = HexColor("#E8F0FE") # section header background
BORDER = HexColor("#999999")
SUPP_GREEN = HexColor("#006600") # SUPP annotation color (dark green)

WIDTH, HEIGHT = letter  # 612 x 792


def draw_header(c, page_title, page_num, total_pages):
    """Top banner with study ID and page title."""
    c.setFillColor(HexColor("#1A3C6E"))
    c.rect(0, HEIGHT - 50, WIDTH, 50, fill=True, stroke=False)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(30, HEIGHT - 35, f"Study ABC-1234 — Annotated CRF")
    c.setFont("Helvetica", 10)
    c.drawRightString(WIDTH - 30, HEIGHT - 35, f"Page {page_num} of {total_pages}")

    # Page title
    c.setFillColor(black)
    c.setFont("Helvetica-Bold", 16)
    c.drawString(30, HEIGHT - 80, page_title)

    # Legend
    c.setFont("Helvetica-Oblique", 8)
    c.setFillColor(DARK_GRAY)
    c.drawString(30, HEIGHT - 95, "Black = CRF field labels")
    c.setFillColor(BLUE)
    c.drawString(200, HEIGHT - 95, "Blue = SDTM annotation (Domain.Variable)")
    c.setFillColor(black)


def draw_section(c, y, title):
    """Section header bar."""
    c.setFillColor(LIGHT_BLUE)
    c.rect(30, y - 5, WIDTH - 60, 22, fill=True, stroke=False)
    c.setStrokeColor(BORDER)
    c.rect(30, y - 5, WIDTH - 60, 22, fill=False, stroke=True)
    c.setFillColor(DARK_GRAY)
    c.setFont("Helvetica-Bold", 11)
    c.drawString(40, y, title)
    c.setFillColor(black)
    return y - 30


def draw_field(c, y, label, annotation, codelist=None, field_width=200):
    """
    One CRF field: black label on left, gray input box, blue annotation on right.
    Optional codelist shown in parentheses after annotation.
    """
    c.setFont("Helvetica", 10)
    c.setFillColor(DARK_GRAY)
    c.drawString(50, y, label)

    x_box = 230
    c.setFillColor(GRAY_BG)
    c.rect(x_box, y - 4, field_width, 16, fill=True, stroke=False)
    c.setStrokeColor(BORDER)
    c.rect(x_box, y - 4, field_width, 16, fill=False, stroke=True)

    x_annot = x_box + field_width + 15
    c.setFont("Helvetica-Bold", 9)
    c.setFillColor(BLUE)
    c.drawString(x_annot, y, annotation)

    if codelist:
        c.setFont("Helvetica-Oblique", 8)
        c.drawString(x_annot, y - 12, f"Codelist: {codelist}")
        y -= 12

    c.setFillColor(black)
    return y - 28


def draw_checkbox_field(c, y, label, options, annotation, codelist=None):
    """CRF field with checkboxes (e.g. SEX: Male / Female)."""
    c.setFont("Helvetica", 10)
    c.setFillColor(DARK_GRAY)
    c.drawString(50, y, label)

    x = 230
    for opt in options:
        c.setStrokeColor(BORDER)
        c.rect(x, y - 2, 10, 10, fill=False, stroke=True)
        c.setFont("Helvetica", 9)
        c.setFillColor(DARK_GRAY)
        c.drawString(x + 14, y, opt)
        x += len(opt) * 6 + 30

    c.setFont("Helvetica-Bold", 9)
    c.setFillColor(BLUE)
    c.drawString(x + 20, y, annotation)
    if codelist:
        c.setFont("Helvetica-Oblique", 8)
        c.drawString(x + 20, y - 12, f"Codelist: {codelist}")
        y -= 12

    c.setFillColor(black)
    return y - 28


# ─── Page 1: Demographics ───────────────────────────────────────────

def page_demographics(c):
    draw_header(c, "Demographics", 1, 4)
    y = HEIGHT - 120

    y = draw_section(c, y, "Subject Information")
    y = draw_field(c, y, "Subject ID:", "DM.SUBJID")
    y = draw_field(c, y, "Site Number:", "DM.SITEID")
    y = draw_field(c, y, "Date of Informed Consent:", "DM.RFICDTC")
    y = draw_field(c, y, "Screening Date:", "DM.RFSTDTC")

    y = draw_section(c, y, "Demographics")
    y = draw_field(c, y, "Date of Birth:", "DM.BRTHDTC")
    y = draw_field(c, y, "Age:", "DM.AGE", field_width=80)
    y = draw_checkbox_field(c, y, "Sex:", ["Male", "Female"], "DM.SEX", "SEX (M, F)")
    y = draw_checkbox_field(c, y, "Race:", ["White", "Black", "Asian", "Other"],
                            "DM.RACE", "RACE")
    y = draw_field(c, y, "Ethnicity:", "DM.ETHNIC",
                   codelist="ETHNIC (Hispanic or Latino, Not Hispanic or Latino)")

    y = draw_section(c, y, "Study Information")
    y = draw_field(c, y, "Randomization Number:", "DM.RANDNUM")
    y = draw_checkbox_field(c, y, "Treatment Arm:",
                            ["Drug A 10mg", "Drug A 20mg", "Placebo"],
                            "DM.ARM", "ARM")
    y = draw_field(c, y, "Date of First Dose:", "EX.EXSTDTC")
    y = draw_field(c, y, "Date of Last Dose:", "EX.EXENDTC")

    # SUPPDM fields
    y = draw_section(c, y, "Additional Information")
    y = draw_checkbox_field(c, y, "Completed Study?:", ["Yes", "No"],
                            "SUPPDM.COMPLT", "NY")
    y = draw_field(c, y, "Reason for Discontinuation:", "SUPPDM.DCSREAS",
                   codelist="DCSREAS")
    y = draw_field(c, y, "Years of Education:", "SUPPDM.EDUYRN", field_width=80)


# ─── Page 2: Vital Signs ────────────────────────────────────────────

def page_vital_signs(c):
    draw_header(c, "Vital Signs", 2, 4)
    y = HEIGHT - 120

    y = draw_section(c, y, "Visit Information")
    y = draw_field(c, y, "Visit Name:", "VS.VISIT", codelist="VISIT")
    y = draw_field(c, y, "Visit Date:", "VS.VSDTC")

    y = draw_section(c, y, "Measurements")
    vitals = [
        ("Systolic Blood Pressure (mmHg):", "VS.VSSTRESN", "VSTESTCD=SYSBP"),
        ("Diastolic Blood Pressure (mmHg):", "VS.VSSTRESN", "VSTESTCD=DIABP"),
        ("Heart Rate (beats/min):", "VS.VSSTRESN", "VSTESTCD=HR"),
        ("Temperature (C):", "VS.VSSTRESN", "VSTESTCD=TEMP"),
        ("Weight (kg):", "VS.VSSTRESN", "VSTESTCD=WEIGHT"),
        ("Height (cm):", "VS.VSSTRESN", "VSTESTCD=HEIGHT"),
    ]
    for label, annot, cl in vitals:
        y = draw_field(c, y, label, annot, codelist=cl)

    y = draw_section(c, y, "Position and Assessment")
    y = draw_checkbox_field(c, y, "Position:", ["Sitting", "Standing", "Supine"],
                            "VS.VSPOS", "POSITION")
    # SUPPVS fields
    y = draw_checkbox_field(c, y, "Clinically Significant?:", ["Yes", "No"],
                            "SUPPVS.VSCLSIG", "NY")
    y = draw_field(c, y, "Location of Measurement:", "SUPPVS.VSLOC",
                   codelist="LOC")
    y = draw_checkbox_field(c, y, "Fasting?:", ["Yes", "No"],
                            "SUPPVS.VSFAST", "NY")


# ─── Page 3: Adverse Events ─────────────────────────────────────────

def page_adverse_events(c):
    draw_header(c, "Adverse Events", 3, 4)
    y = HEIGHT - 120

    y = draw_section(c, y, "Event Details")
    y = draw_field(c, y, "AE Term (verbatim):", "AE.AETERM", field_width=250)
    y = draw_field(c, y, "AE Preferred Term:", "AE.AEDECOD", field_width=250)

    y = draw_section(c, y, "Dates")
    y = draw_field(c, y, "Start Date:", "AE.AESTDTC")
    y = draw_field(c, y, "End Date:", "AE.AEENDTC")

    y = draw_section(c, y, "Severity and Causality")
    y = draw_checkbox_field(c, y, "Severity:",
                            ["Mild", "Moderate", "Severe"],
                            "AE.AESEV", "AESEV")
    y = draw_checkbox_field(c, y, "Serious?:", ["Yes", "No"],
                            "AE.AESER", "NY")
    y = draw_checkbox_field(c, y, "Related to Study Drug?:",
                            ["Yes", "No"],
                            "AE.AEREL", "NY")

    y = draw_section(c, y, "Outcome")
    y = draw_checkbox_field(c, y, "Outcome:",
                            ["Recovered", "Ongoing", "Fatal"],
                            "AE.AEOUT", "OUT")
    y = draw_checkbox_field(c, y, "Action Taken:",
                            ["None", "Dose Reduced", "Drug Withdrawn"],
                            "AE.AEACN", "ACN")

    # SUPPAE fields
    y = draw_section(c, y, "Additional AE Details")
    y = draw_field(c, y, "Other Action Taken:", "SUPPAE.AEACNOTH", field_width=250)
    y = draw_checkbox_field(c, y, "Treatment Emergent?:", ["Yes", "No"],
                            "SUPPAE.AETRTEM", "NY")
    y = draw_checkbox_field(c, y, "Led to Hospitalization?:", ["Yes", "No"],
                            "SUPPAE.AESHOSP", "NY")
    y = draw_checkbox_field(c, y, "Led to Death?:", ["Yes", "No"],
                            "SUPPAE.AESDTH", "NY")


# ─── Page 4: Concomitant Medications ─────────────────────────────────

def page_conmeds(c):
    draw_header(c, "Concomitant Medications", 4, 4)
    y = HEIGHT - 120

    y = draw_section(c, y, "Medication Details")
    y = draw_field(c, y, "Medication Name (verbatim):", "CM.CMTRT", field_width=250)
    y = draw_field(c, y, "Standardized Name:", "CM.CMDECOD", field_width=250)
    y = draw_field(c, y, "ATC Class:", "CM.CMCLAS", field_width=250)

    y = draw_section(c, y, "Dates and Dosing")
    y = draw_field(c, y, "Start Date:", "CM.CMSTDTC")
    y = draw_field(c, y, "End Date:", "CM.CMENDTC")
    y = draw_field(c, y, "Dose:", "CM.CMDOSE", field_width=80)
    y = draw_field(c, y, "Dose Unit:", "CM.CMDOSU", codelist="UNIT")
    y = draw_checkbox_field(c, y, "Route:",
                            ["Oral", "IV", "Topical", "Other"],
                            "CM.CMROUTE", "ROUTE")
    y = draw_checkbox_field(c, y, "Frequency:",
                            ["QD", "BID", "TID", "PRN"],
                            "CM.CMDOSFRQ", "FREQ")

    y = draw_section(c, y, "Indication and Status")
    y = draw_field(c, y, "Indication:", "CM.CMINDC", field_width=250)
    y = draw_checkbox_field(c, y, "Ongoing at Screening?:",
                            ["Yes", "No"],
                            "CM.CMONGO", "NY")

    # SUPPCM fields
    y = draw_section(c, y, "Additional Medication Details")
    y = draw_checkbox_field(c, y, "Prior Medication?:", ["Yes", "No"],
                            "SUPPCM.CMPREVFL", "NY")
    y = draw_field(c, y, "Other Indication:", "SUPPCM.CMINDOTH", field_width=250)


# ─── Build the PDF ──────────────────────────────────────────────────

def main():
    out = "/home/claude/sample_acrf.pdf"
    c = canvas.Canvas(out, pagesize=letter)

    page_demographics(c)
    c.showPage()

    page_vital_signs(c)
    c.showPage()

    page_adverse_events(c)
    c.showPage()

    page_conmeds(c)
    c.showPage()

    c.save()
    print(f"Sample aCRF written to {out}")
    print("4 pages: Demographics, Vital Signs, Adverse Events, Concomitant Medications")
    print("Includes SUPP domain annotations: SUPPDM, SUPPVS, SUPPAE, SUPPCM")


if __name__ == "__main__":
    main()
