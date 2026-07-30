"""
Build a sample clinical trial protocol PDF for testing the protocol parser.

Extracts trial design metadata for:
  TA - Trial Arms (arm sequences and elements)
  TE - Trial Elements (screening, treatment, follow-up periods)
  TV - Trial Visits (planned visit schedule with windows)
  TI - Trial Inclusion/Exclusion criteria
  TS - Trial Summary (sponsor, phase, indication, etc.)

The PDF mimics a real protocol with structured sections:
  Section 1: Synopsis / Trial Summary
  Section 2: Study Design (arms, elements, epochs)
  Section 3: Visit Schedule (table with visit windows)
  Section 4: Inclusion Criteria
  Section 5: Exclusion Criteria
"""

from reportlab.lib.pagesizes import letter
from reportlab.lib.colors import HexColor, black, white
from reportlab.lib.units import inch
from reportlab.pdfgen import canvas
from reportlab.lib import colors

BLUE = HexColor("#1A3C6E")
DARK_GRAY = HexColor("#333333")
LIGHT_GRAY = HexColor("#F5F5F5")
BORDER = HexColor("#CCCCCC")
WIDTH, HEIGHT = letter
MARGIN = 50


def draw_page_header(c, section_title, page_num):
    """Top header bar."""
    c.setFillColor(BLUE)
    c.rect(0, HEIGHT - 40, WIDTH, 40, fill=True, stroke=False)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 12)
    c.drawString(30, HEIGHT - 28, "Protocol ABC-1234-001  |  CONFIDENTIAL")
    c.setFont("Helvetica", 9)
    c.drawRightString(WIDTH - 30, HEIGHT - 28, f"Page {page_num}")
    # Section title
    c.setFillColor(black)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(MARGIN, HEIGHT - 70, section_title)
    return HEIGHT - 95


def draw_subsection(c, y, title):
    c.setFont("Helvetica-Bold", 11)
    c.setFillColor(BLUE)
    c.drawString(MARGIN, y, title)
    c.setFillColor(black)
    return y - 20


def draw_text(c, y, text, indent=0, font_size=10, bold=False):
    font = "Helvetica-Bold" if bold else "Helvetica"
    c.setFont(font, font_size)
    c.setFillColor(DARK_GRAY)
    # Simple word wrap
    max_width = WIDTH - 2 * MARGIN - indent
    words = text.split()
    lines = []
    current = ""
    for w in words:
        test = f"{current} {w}".strip()
        if c.stringWidth(test, font, font_size) < max_width:
            current = test
        else:
            lines.append(current)
            current = w
    if current:
        lines.append(current)
    for line in lines:
        c.drawString(MARGIN + indent, y, line)
        y -= 14
    return y


def draw_table_row(c, y, cells, col_widths, fill=None, bold=False):
    x = MARGIN
    font = "Helvetica-Bold" if bold else "Helvetica"
    c.setFont(font, 8)
    row_height = 16
    for i, (cell, w) in enumerate(zip(cells, col_widths)):
        if fill:
            c.setFillColor(fill)
            c.rect(x, y - 4, w, row_height, fill=True, stroke=False)
        c.setStrokeColor(BORDER)
        c.rect(x, y - 4, w, row_height, fill=False, stroke=True)
        c.setFillColor(DARK_GRAY if not fill or fill == LIGHT_GRAY else white)
        c.setFont(font, 8)
        # Truncate if too long
        display = str(cell)[:int(w / 5)]
        c.drawString(x + 3, y, display)
        x += w
    c.setFillColor(black)
    return y - row_height


# ─── Page 1: Synopsis / Trial Summary ───────────────────────────────

def page_synopsis(c):
    y = draw_page_header(c, "1. TRIAL SYNOPSIS", 1)

    y = draw_subsection(c, y, "1.1 Trial Summary")

    # Key-value pairs like TS domain
    summary_items = [
        ("Sponsor:", "PharmaCo International, Inc."),
        ("Protocol Number:", "ABC-1234-001"),
        ("Protocol Title:", "A Phase III, Randomized, Double-Blind, Placebo-Controlled Study to Evaluate the Efficacy and Safety of Drug ABC in Patients with Moderate to Severe Condition X"),
        ("Short Title:", "Drug ABC Phase III in Condition X"),
        ("Phase:", "Phase III"),
        ("Indication:", "Condition X (Moderate to Severe)"),
        ("Study Type:", "Interventional"),
        ("Number of Subjects:", "450 (planned)"),
        ("Number of Sites:", "60 sites across 12 countries"),
        ("Planned Duration:", "24 months enrollment + 12 months treatment + 4 weeks follow-up"),
        ("Treatment Duration:", "52 weeks"),
        ("Randomization Ratio:", "1:1:1"),
        ("Blinding:", "Double-Blind"),
        ("Comparator:", "Placebo"),
        ("Primary Endpoint:", "Change from baseline in Total Score at Week 52"),
        ("Key Secondary Endpoint:", "Proportion of responders (>=50% improvement) at Week 52"),
        ("Statistical Method:", "MMRM for primary; logistic regression for key secondary"),
        ("Regulatory Agency:", "FDA, EMA"),
    ]

    for label, value in summary_items:
        y = draw_text(c, y, label, bold=True)
        y = draw_text(c, y, value, indent=20)
        y -= 2
        if y < 80:
            c.showPage()
            y = draw_page_header(c, "1. TRIAL SYNOPSIS (continued)", 2)


# ─── Page 2-3: Study Design ─────────────────────────────────────────

def page_study_design(c):
    y = draw_page_header(c, "2. STUDY DESIGN", 3)

    y = draw_subsection(c, y, "2.1 Trial Arms")
    y = draw_text(c, y, "Subjects will be randomized in a 1:1:1 ratio to one of three treatment arms:")
    y -= 5

    arms = [
        ("1", "ARM A", "Drug ABC 10 mg once daily for 52 weeks"),
        ("2", "ARM B", "Drug ABC 20 mg once daily for 52 weeks"),
        ("3", "ARM C", "Matching placebo once daily for 52 weeks"),
    ]
    col_w = [40, 80, 390]
    y = draw_table_row(c, y, ["#", "Arm Code", "Description"], col_w, fill=BLUE, bold=True)
    for arm in arms:
        y = draw_table_row(c, y, arm, col_w, fill=LIGHT_GRAY)

    y -= 15
    y = draw_subsection(c, y, "2.2 Trial Elements and Epochs")
    y = draw_text(c, y, "The study consists of the following sequential elements within each epoch:")
    y -= 5

    elements = [
        ("1", "SCRN", "Screening", "SCREENING", "Up to 28 days", "Day -28 to Day -1"),
        ("2", "LEAD", "Lead-in Period", "LEAD-IN", "14 days", "Day -14 to Day -1"),
        ("3", "TRT", "Treatment Period", "TREATMENT", "52 weeks", "Day 1 to Week 52"),
        ("4", "TAPER", "Dose Taper", "TREATMENT", "2 weeks", "Week 52 to Week 54"),
        ("5", "FU", "Follow-up", "FOLLOW-UP", "4 weeks", "Week 54 to Week 58"),
    ]
    col_w = [30, 45, 100, 90, 70, 160]
    y = draw_table_row(c, y, ["#", "Code", "Element", "Epoch", "Duration", "Timing"], col_w, fill=BLUE, bold=True)
    for elem in elements:
        y = draw_table_row(c, y, elem, col_w, fill=LIGHT_GRAY)

    y -= 15
    y = draw_subsection(c, y, "2.3 Arm-Element Sequence")
    y = draw_text(c, y, "All arms follow the same element sequence: Screening -> Lead-in -> Treatment -> Taper -> Follow-up")
    y = draw_text(c, y, "The only difference between arms is the treatment administered during TRT and TAPER elements.")

    y -= 15
    y = draw_subsection(c, y, "2.4 Study Schema")
    y = draw_text(c, y, "Screening (28d) --> Lead-in (14d) --> Randomization --> Treatment (52wk) --> Taper (2wk) --> Follow-up (4wk)")


# ─── Page 4: Visit Schedule ─────────────────────────────────────────

def page_visits(c):
    y = draw_page_header(c, "3. SCHEDULE OF ASSESSMENTS", 4)

    y = draw_subsection(c, y, "3.1 Visit Schedule")
    y = draw_text(c, y, "The following table summarizes the planned visits, target study days, and visit windows:")
    y -= 5

    visits = [
        ("1",  "Screening",    "-28",   "-28 to -1",    "SCREENING"),
        ("2",  "Lead-in",      "-14",   "-14 to -1",    "LEAD-IN"),
        ("3",  "Baseline/Randomization", "1", "1", "TREATMENT"),
        ("4",  "Week 2",       "15",    "12 to 18",     "TREATMENT"),
        ("5",  "Week 4",       "29",    "26 to 32",     "TREATMENT"),
        ("6",  "Week 8",       "57",    "54 to 60",     "TREATMENT"),
        ("7",  "Week 12",      "85",    "82 to 88",     "TREATMENT"),
        ("8",  "Week 16",      "113",   "110 to 116",   "TREATMENT"),
        ("9",  "Week 24",      "169",   "166 to 172",   "TREATMENT"),
        ("10", "Week 36",      "253",   "250 to 256",   "TREATMENT"),
        ("11", "Week 52 / EOT","365",   "362 to 368",   "TREATMENT"),
        ("12", "Taper Visit 1","372",   "370 to 375",   "TREATMENT"),
        ("13", "Taper Visit 2","379",   "377 to 382",   "TREATMENT"),
        ("14", "Follow-up",    "393",   "390 to 400",   "FOLLOW-UP"),
        ("15", "Early Termination", "",  "Unscheduled",  ""),
    ]

    col_w = [35, 120, 55, 80, 80]
    y = draw_table_row(c, y, ["Visit#", "Visit Name", "Target Day", "Window (Days)", "Epoch"], col_w, fill=BLUE, bold=True)
    for v in visits:
        y = draw_table_row(c, y, v, col_w, fill=LIGHT_GRAY)
        if y < 80:
            c.showPage()
            y = draw_page_header(c, "3. SCHEDULE OF ASSESSMENTS (continued)", 5)

    y -= 10
    y = draw_subsection(c, y, "3.2 Assessments per Visit")
    y = draw_text(c, y, "Demographics and Medical History: Screening only")
    y = draw_text(c, y, "Vital Signs: All visits except Early Termination")
    y = draw_text(c, y, "ECG: Screening, Baseline, Week 12, Week 24, Week 52, Follow-up")
    y = draw_text(c, y, "Adverse Events: Continuous from Lead-in through Follow-up")
    y = draw_text(c, y, "Tumor Assessments: Baseline, Week 12, Week 24, Week 36, Week 52 (oncology sites only)")
    y = draw_text(c, y, "Lab Tests: Screening, Baseline, Week 4, Week 12, Week 24, Week 52, Follow-up")
    y = draw_text(c, y, "Concomitant Medications: Continuous from Screening through Follow-up")


# ─── Page 5: Inclusion Criteria ──────────────────────────────────────

def page_inclusion(c):
    y = draw_page_header(c, "4. INCLUSION CRITERIA", 5)

    y = draw_text(c, y, "Subjects must meet ALL of the following criteria to be eligible for the study:")
    y -= 5

    criteria = [
        ("IN01", "Age >= 18 years and <= 75 years at time of informed consent"),
        ("IN02", "Documented diagnosis of Condition X for at least 6 months prior to screening"),
        ("IN03", "Moderate to severe disease activity defined as Total Score >= 6 at screening"),
        ("IN04", "Inadequate response or intolerance to at least one prior standard therapy"),
        ("IN05", "Body Mass Index (BMI) between 18.0 and 40.0 kg/m2 at screening"),
        ("IN06", "Female subjects of childbearing potential must use highly effective contraception"),
        ("IN07", "Willing and able to provide written informed consent"),
        ("IN08", "Able to comply with study procedures and visit schedule"),
        ("IN09", "Stable doses of permitted concomitant medications for at least 4 weeks prior to baseline"),
        ("IN10", "Adequate organ function as defined by laboratory values within protocol-specified ranges"),
    ]

    for code, text in criteria:
        y = draw_text(c, y, f"{code}.", bold=True)
        y = draw_text(c, y, text, indent=40)
        y -= 4


# ─── Page 6: Exclusion Criteria ──────────────────────────────────────

def page_exclusion(c):
    y = draw_page_header(c, "5. EXCLUSION CRITERIA", 6)

    y = draw_text(c, y, "Subjects meeting ANY of the following criteria will be excluded:")
    y -= 5

    criteria = [
        ("EX01", "Known hypersensitivity to Drug ABC or any excipient"),
        ("EX02", "Current or history of malignancy within the past 5 years (except adequately treated basal cell carcinoma)"),
        ("EX03", "Active or latent tuberculosis"),
        ("EX04", "Known HIV, Hepatitis B, or Hepatitis C infection"),
        ("EX05", "Severe hepatic impairment (Child-Pugh C)"),
        ("EX06", "Estimated GFR < 30 mL/min/1.73m2 at screening"),
        ("EX07", "Pregnant or breastfeeding women"),
        ("EX08", "Use of prohibited medications within 5 half-lives or 4 weeks prior to baseline, whichever is longer"),
        ("EX09", "Participation in another interventional clinical study within 30 days or 5 half-lives prior to screening"),
        ("EX10", "History of major surgical procedure within 4 weeks prior to screening or planned surgery during the study"),
        ("EX11", "Any condition that, in the opinion of the investigator, would compromise the safety of the subject or interfere with study assessments"),
        ("EX12", "QTcF interval > 500 msec at screening ECG"),
    ]

    for code, text in criteria:
        y = draw_text(c, y, f"{code}.", bold=True)
        y = draw_text(c, y, text, indent=40)
        y -= 4
        if y < 80:
            c.showPage()
            y = draw_page_header(c, "5. EXCLUSION CRITERIA (continued)", 7)


# ─── Build the PDF ──────────────────────────────────────────────────

def main():
    out = "/home/claude/sample_protocol.pdf"
    c = canvas.Canvas(out, pagesize=letter)

    page_synopsis(c)
    c.showPage()

    page_study_design(c)
    c.showPage()

    page_visits(c)
    c.showPage()

    page_inclusion(c)
    c.showPage()

    page_exclusion(c)
    c.showPage()

    c.save()
    print(f"Sample protocol written to {out}")
    print("Sections: Synopsis, Study Design (arms/elements), Visit Schedule, I/E Criteria")
    print("Provides metadata for: TA, TE, TV, TI, TS domains")


if __name__ == "__main__":
    main()
