"""
Build a sample annotated CRF (aCRF) PDF for testing the aCRF parser.

8 pages covering 12 standard domains + SUPP domains:
  Page 1: Demographics (DM + SUPPDM)
  Page 2: Vital Signs (VS + SUPPVS)
  Page 3: Adverse Events (AE + SUPPAE)
  Page 4: Concomitant Medications (CM + SUPPCM)
  Page 5: Disposition (DS) + Medical History (MH)
  Page 6: Protocol Deviations (DV) + ECG (EG + SUPPEG)
  Page 7: Tumor Identification (TU) + Tumor Results (TR)
  Page 8: Response (RS + SUPPRS)
"""

from reportlab.lib.pagesizes import letter
from reportlab.lib.colors import HexColor, black, white
from reportlab.pdfgen import canvas

BLUE = HexColor("#0000CC")
GRAY_BG = HexColor("#F0F0F0")
DARK_GRAY = HexColor("#333333")
LIGHT_BLUE = HexColor("#E8F0FE")
BORDER = HexColor("#999999")

WIDTH, HEIGHT = letter


def draw_header(c, page_title, page_num, total_pages):
    c.setFillColor(HexColor("#1A3C6E"))
    c.rect(0, HEIGHT - 50, WIDTH, 50, fill=True, stroke=False)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(30, HEIGHT - 35, "Study ABC-1234 — Annotated CRF")
    c.setFont("Helvetica", 10)
    c.drawRightString(WIDTH - 30, HEIGHT - 35, f"Page {page_num} of {total_pages}")
    c.setFillColor(black)
    c.setFont("Helvetica-Bold", 16)
    c.drawString(30, HEIGHT - 80, page_title)
    c.setFont("Helvetica-Oblique", 8)
    c.setFillColor(DARK_GRAY)
    c.drawString(30, HEIGHT - 95, "Black = CRF field labels")
    c.setFillColor(BLUE)
    c.drawString(200, HEIGHT - 95, "Blue = SDTM annotation (Domain.Variable)")
    c.setFillColor(black)


def draw_section(c, y, title):
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


TOTAL_PAGES = 8


# ─── Page 1: Demographics ───────────────────────────────────────────

def page_demographics(c):
    draw_header(c, "Demographics", 1, TOTAL_PAGES)
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
    y = draw_section(c, y, "Additional Information")
    y = draw_checkbox_field(c, y, "Completed Study?:", ["Yes", "No"],
                            "SUPPDM.COMPLT", "NY")
    y = draw_field(c, y, "Reason for Discontinuation:", "SUPPDM.DCSREAS",
                   codelist="DCSREAS")
    y = draw_field(c, y, "Years of Education:", "SUPPDM.EDUYRN", field_width=80)


# ─── Page 2: Vital Signs ────────────────────────────────────────────

def page_vital_signs(c):
    draw_header(c, "Vital Signs", 2, TOTAL_PAGES)
    y = HEIGHT - 120
    y = draw_section(c, y, "Visit Information")
    y = draw_field(c, y, "Visit Name:", "VS.VISIT", codelist="VISIT")
    y = draw_field(c, y, "Visit Date:", "VS.VSDTC")
    y = draw_section(c, y, "Measurements")
    for label, tc in [("Systolic Blood Pressure (mmHg):", "SYSBP"),
                      ("Diastolic Blood Pressure (mmHg):", "DIABP"),
                      ("Heart Rate (beats/min):", "HR"),
                      ("Temperature (C):", "TEMP"),
                      ("Weight (kg):", "WEIGHT"),
                      ("Height (cm):", "HEIGHT")]:
        y = draw_field(c, y, label, "VS.VSSTRESN", codelist=f"VSTESTCD={tc}")
    y = draw_section(c, y, "Position and Assessment")
    y = draw_checkbox_field(c, y, "Position:", ["Sitting", "Standing", "Supine"],
                            "VS.VSPOS", "POSITION")
    y = draw_checkbox_field(c, y, "Clinically Significant?:", ["Yes", "No"],
                            "SUPPVS.VSCLSIG", "NY")
    y = draw_field(c, y, "Location of Measurement:", "SUPPVS.VSLOC", codelist="LOC")
    y = draw_checkbox_field(c, y, "Fasting?:", ["Yes", "No"],
                            "SUPPVS.VSFAST", "NY")


# ─── Page 3: Adverse Events ─────────────────────────────────────────

def page_adverse_events(c):
    draw_header(c, "Adverse Events", 3, TOTAL_PAGES)
    y = HEIGHT - 120
    y = draw_section(c, y, "Event Details")
    y = draw_field(c, y, "AE Term (verbatim):", "AE.AETERM", field_width=250)
    y = draw_field(c, y, "AE Preferred Term:", "AE.AEDECOD", field_width=250)
    y = draw_section(c, y, "Dates")
    y = draw_field(c, y, "Start Date:", "AE.AESTDTC")
    y = draw_field(c, y, "End Date:", "AE.AEENDTC")
    y = draw_section(c, y, "Severity and Causality")
    y = draw_checkbox_field(c, y, "Severity:", ["Mild", "Moderate", "Severe"],
                            "AE.AESEV", "AESEV")
    y = draw_checkbox_field(c, y, "Serious?:", ["Yes", "No"], "AE.AESER", "NY")
    y = draw_checkbox_field(c, y, "Related to Study Drug?:", ["Yes", "No"],
                            "AE.AEREL", "NY")
    y = draw_section(c, y, "Outcome")
    y = draw_checkbox_field(c, y, "Outcome:", ["Recovered", "Ongoing", "Fatal"],
                            "AE.AEOUT", "OUT")
    y = draw_checkbox_field(c, y, "Action Taken:", ["None", "Dose Reduced", "Drug Withdrawn"],
                            "AE.AEACN", "ACN")
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
    draw_header(c, "Concomitant Medications", 4, TOTAL_PAGES)
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
    y = draw_checkbox_field(c, y, "Route:", ["Oral", "IV", "Topical", "Other"],
                            "CM.CMROUTE", "ROUTE")
    y = draw_checkbox_field(c, y, "Frequency:", ["QD", "BID", "TID", "PRN"],
                            "CM.CMDOSFRQ", "FREQ")
    y = draw_section(c, y, "Indication and Status")
    y = draw_field(c, y, "Indication:", "CM.CMINDC", field_width=250)
    y = draw_checkbox_field(c, y, "Ongoing at Screening?:", ["Yes", "No"],
                            "CM.CMONGO", "NY")
    y = draw_section(c, y, "Additional Medication Details")
    y = draw_checkbox_field(c, y, "Prior Medication?:", ["Yes", "No"],
                            "SUPPCM.CMPREVFL", "NY")
    y = draw_field(c, y, "Other Indication:", "SUPPCM.CMINDOTH", field_width=250)


# ─── Page 5: Disposition + Medical History ───────────────────────────

def page_disposition_medhist(c):
    draw_header(c, "Disposition / Medical History", 5, TOTAL_PAGES)
    y = HEIGHT - 120

    # DS - Disposition
    y = draw_section(c, y, "Disposition (DS)")
    y = draw_field(c, y, "Disposition Event:", "DS.DSTERM", field_width=250)
    y = draw_field(c, y, "Standardized Disposition Term:", "DS.DSDECOD", field_width=250)
    y = draw_checkbox_field(c, y, "Category:", ["PROTOCOL MILESTONE", "DISPOSITION EVENT", "OTHER"],
                            "DS.DSCAT", "DSCAT")
    y = draw_field(c, y, "Subcategory:", "DS.DSSCAT", codelist="DSSCAT")
    y = draw_field(c, y, "Date of Disposition:", "DS.DSSTDTC")
    y = draw_field(c, y, "Epoch:", "DS.EPOCH", codelist="EPOCH")

    # MH - Medical History
    y = draw_section(c, y, "Medical History (MH)")
    y = draw_field(c, y, "Condition (verbatim):", "MH.MHTERM", field_width=250)
    y = draw_field(c, y, "Dictionary Coded Term:", "MH.MHDECOD", field_width=250)
    y = draw_checkbox_field(c, y, "Category:", ["General", "Surgical", "Family"],
                            "MH.MHCAT", "MHCAT")
    y = draw_field(c, y, "Body System:", "MH.MHBODSYS", field_width=250)
    y = draw_field(c, y, "Start Date:", "MH.MHSTDTC")
    y = draw_field(c, y, "End Date:", "MH.MHENDTC")
    y = draw_checkbox_field(c, y, "Ongoing?:", ["Yes", "No"], "MH.MHENRF", "NY")


# ─── Page 6: Protocol Deviations + ECG ──────────────────────────────

def page_devs_ecg(c):
    draw_header(c, "Protocol Deviations / ECG", 6, TOTAL_PAGES)
    y = HEIGHT - 120

    # DV - Protocol Deviations
    y = draw_section(c, y, "Protocol Deviations (DV)")
    y = draw_field(c, y, "Deviation Term:", "DV.DVTERM", field_width=250)
    y = draw_field(c, y, "Deviation Coded Term:", "DV.DVDECOD", field_width=250)
    y = draw_checkbox_field(c, y, "Category:", ["MAJOR", "MINOR"],
                            "DV.DVCAT", "DVCAT")
    y = draw_field(c, y, "Subcategory:", "DV.DVSCAT", codelist="DVSCAT")
    y = draw_field(c, y, "Deviation Date:", "DV.DVSTDTC")
    y = draw_field(c, y, "Epoch:", "DV.EPOCH", codelist="EPOCH")

    # EG - ECG
    y = draw_section(c, y, "Electrocardiogram - ECG (EG)")
    y = draw_field(c, y, "Visit Name:", "EG.VISIT", codelist="VISIT")
    y = draw_field(c, y, "ECG Date:", "EG.EGDTC")
    for label, tc in [("Heart Rate (bpm):", "HR"),
                      ("PR Interval (msec):", "PRINTR"),
                      ("QRS Duration (msec):", "QRSDUR"),
                      ("QT Interval (msec):", "QTINT"),
                      ("QTcF (msec):", "QTCF")]:
        y = draw_field(c, y, label, "EG.EGSTRESN", codelist=f"EGTESTCD={tc}")
    y = draw_checkbox_field(c, y, "Overall Interpretation:", ["Normal", "Abnormal NCS", "Abnormal CS"],
                            "EG.EGEVAL", "NCSAB")
    y = draw_checkbox_field(c, y, "Clinically Significant?:", ["Yes", "No"],
                            "SUPPEG.EGCLSIG", "NY")


# ─── Page 7: Tumor Identification + Tumor Results ───────────────────

def page_tumor(c):
    draw_header(c, "Tumor Assessment", 7, TOTAL_PAGES)
    y = HEIGHT - 120

    # TU - Tumor Identification
    y = draw_section(c, y, "Tumor Identification (TU)")
    y = draw_field(c, y, "Tumor ID:", "TU.TULNKID", field_width=80)
    y = draw_field(c, y, "Tumor Location:", "TU.TULOC", codelist="LOC")
    y = draw_checkbox_field(c, y, "Laterality:", ["Left", "Right", "Bilateral"],
                            "TU.TULAT", "LAT")
    y = draw_checkbox_field(c, y, "Method:", ["CT", "MRI", "Physical Exam", "X-ray"],
                            "TU.TUMETHOD", "METHOD")
    y = draw_field(c, y, "Assessment Date:", "TU.TUDTC")
    y = draw_checkbox_field(c, y, "Evaluator:", ["INVESTIGATOR", "INDEPENDENT ASSESSOR"],
                            "TU.TUEVAL", "EVAL")

    # TR - Tumor Results
    y = draw_section(c, y, "Tumor Measurement Results (TR)")
    y = draw_field(c, y, "Linked Tumor ID:", "TR.TRLNKID", field_width=80)
    for label, tc in [("Longest Diameter (mm):", "LDIAM"),
                      ("Short Axis Diameter (mm):", "SAXIS"),
                      ("Sum of Diameters (mm):", "SUMDIAM")]:
        y = draw_field(c, y, label, "TR.TRSTRESN", codelist=f"TRTESTCD={tc}")
    y = draw_field(c, y, "Measurement Date:", "TR.TRDTC")
    y = draw_checkbox_field(c, y, "Evaluator:", ["INVESTIGATOR", "INDEPENDENT ASSESSOR"],
                            "TR.TREVAL", "EVAL")


# ─── Page 8: Response ───────────────────────────────────────────────

def page_response(c):
    draw_header(c, "Disease Response", 8, TOTAL_PAGES)
    y = HEIGHT - 120

    # RS - Response
    y = draw_section(c, y, "Tumor Response (RS)")
    y = draw_field(c, y, "Assessment Date:", "RS.RSDTC")
    y = draw_checkbox_field(c, y, "Response Criteria:", ["RECIST 1.1", "iRECIST"],
                            "RS.RSCAT", "RSCAT")
    for label, tc in [("Overall Response:", "OVRLRESP"),
                      ("Target Lesion Response:", "TRGRESP"),
                      ("Non-Target Response:", "NTRGRESP"),
                      ("New Lesion Status:", "NEWLIND")]:
        y = draw_field(c, y, label, "RS.RSORRES", codelist=f"RSTESTCD={tc}")
    y = draw_checkbox_field(c, y, "Evaluator:", ["INVESTIGATOR", "INDEPENDENT ASSESSOR"],
                            "RS.RSEVAL", "EVAL")

    # SUPPRS
    y = draw_section(c, y, "Additional Response Details")
    y = draw_checkbox_field(c, y, "Confirmed Response?:", ["Yes", "No"],
                            "SUPPRS.RSCONFYN", "NY")
    y = draw_field(c, y, "Date of Confirmation:", "SUPPRS.RSCONFDTC")
    y = draw_checkbox_field(c, y, "Best Overall Response:", ["CR", "PR", "SD", "PD"],
                            "SUPPRS.RSBORRESP", "RSRESP")


# ─── Build the PDF ──────────────────────────────────────────────────

def main():
    out = "sample_acrf.pdf"
    c = canvas.Canvas(out, pagesize=letter)

    page_demographics(c)
    c.showPage()
    page_vital_signs(c)
    c.showPage()
    page_adverse_events(c)
    c.showPage()
    page_conmeds(c)
    c.showPage()
    page_disposition_medhist(c)
    c.showPage()
    page_devs_ecg(c)
    c.showPage()
    page_tumor(c)
    c.showPage()
    page_response(c)
    c.showPage()

    c.save()
    print(f"Sample aCRF written to {out}")
    print(f"{TOTAL_PAGES} pages covering DM, VS, AE, CM, DS, MH, DV, EG, TU, TR, RS")
    print("Plus SUPP domains: SUPPDM, SUPPVS, SUPPAE, SUPPCM, SUPPEG, SUPPRS")


if __name__ == "__main__":
    main()
