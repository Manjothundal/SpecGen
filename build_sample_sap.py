"""
Build a sample Statistical Analysis Plan PDF for testing the review module.

Mirrors build_sample_protocol.py: generate once, commit the output as a fixture
(data/sample_sap.pdf). Numbered sections cover the things the review checks
read from a SAP:

  4  Analysis populations (Randomised / ITT / Safety, Big N rule)
  5  Baseline (defined per period) and visit windows
  6  Adverse events (TEAE window: first dose to last dose + 7 days)
  7  Statistical methods
  8  Reporting conventions (decimal rules)
  9  Table inventory (what must be delivered)

The SAP itself is correct and self-consistent. The three deliberate
inconsistencies live in the DATA and OUTPUTS built by
build_sample_review_data.py, and are written down against this SAP in
data/sample_planted.json:

  1. TEAE window - section 6.2 says last dose + 7 days; ADAE was derived
     with + 30 days.
  2. Big N - section 4.5 says Safety Population counts; one arm header in
     Table 14.1.1 uses the ITT count.
  3. Table inventory - section 9 lists Table 14.3.2; it was never delivered.
"""

import os

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

BASE = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(BASE, "data", "sample_sap.pdf")

STYLES = getSampleStyleSheet()
H1 = ParagraphStyle("H1", parent=STYLES["Heading2"], spaceBefore=14, spaceAfter=6, keepWithNext=1)
H2 = ParagraphStyle("H2", parent=STYLES["Heading3"], spaceBefore=8, spaceAfter=3, keepWithNext=1)
BODY = ParagraphStyle("Body", parent=STYLES["BodyText"], fontSize=10, leading=14)

# (section number, heading) -> list of items. A str item is a paragraph; a
# tuple ("table", rows, col_widths_in_inches) is a grid.
SECTIONS = [
    ("1", "Introduction", [
        "This Statistical Analysis Plan (SAP) describes the planned analyses for "
        "Protocol STUDY01, a randomised, double-blind, placebo-controlled study of "
        "Drug A in adult subjects. It is a synthetic document written to exercise "
        "SpecGen; it does not describe a real study.",
    ]),
    ("2", "Study Objectives", [
        "The primary objective is to assess the safety and tolerability of Drug A "
        "50 mg and Drug A 100 mg compared with placebo. Vital signs are assessed "
        "as a secondary safety objective.",
    ]),
    ("3", "Study Design", [
        "Subjects are randomised 1:1:1 to Placebo, Drug A 50 mg or Drug A 100 mg "
        "and treated for approximately 8 weeks (Period 1). Subjects are followed "
        "for safety after the last dose of study treatment.",
    ]),
    ("4", "Analysis Populations", [
        ("4.1", "Randomised Population",
         "All subjects randomised, analysed by planned treatment (TRT01P)."),
        ("4.2", "Intent-to-Treat (ITT) Population",
         "All randomised subjects. Flag ITTFL = 'Y' in ADSL."),
        ("4.3", "Safety Population",
         "All randomised subjects who received at least one dose of study "
         "treatment, analysed by treatment actually received (TRT01A). Flag "
         "SAFFL = 'Y' in ADSL. All demographic and safety tables use the "
         "Safety Population."),
        ("4.4", "Subjects excluded",
         "A subject randomised but never dosed is in the ITT Population and "
         "not in the Safety Population."),
        ("4.5", "Big N",
         "The N shown in each column header is the number of subjects in the "
         "analysis population of that table for that treatment group. For "
         "Safety Population tables, N is the count of SAFFL = 'Y' subjects in "
         "ADSL by TRT01A. The same N must be used in every Safety Population "
         "table."),
    ]),
    ("5", "Baseline and Visit Windows", [
        ("5.1", "Baseline definition",
         "Baseline is defined per treatment period: the last non-missing "
         "assessment on or before the first dose of that period. ABLFL = 'Y' "
         "flags the baseline record within each period, so a subject in more "
         "than one period has one baseline record per period."),
        ("5.2", "Visit windows",
         "Assessments are assigned to analysis visits using the windows below "
         "(study day, where Day 1 is the first dose)."),
        ("table", [
            ["Visit", "Target day", "Window (study days)"],
            ["Baseline", "1", "Up to Day 1"],
            ["Week 4", "29", "22 to 35"],
            ["Week 8", "57", "50 to 63"],
        ], [1.6, 1.2, 2.0]),
    ]),
    ("6", "Safety Analyses", [
        ("6.1", "Adverse events",
         "Adverse events are coded with MedDRA and summarised by System Organ "
         "Class (SOC) and Preferred Term (PT), by treatment received."),
        ("6.2", "Treatment-emergent adverse events (TEAE)",
         "A TEAE is an adverse event with onset on or after the date of first "
         "dose of study treatment and on or before the date of last dose of "
         "study treatment + 7 days. TRTEMFL = 'Y' flags these events in ADAE. "
         "Events starting before the first dose, or more than 7 days after the "
         "last dose, are not treatment-emergent."),
        ("6.3", "Maximum severity",
         "For a subject with more than one TEAE, the maximum severity is the "
         "highest of MILD, MODERATE, SEVERE among that subject's TEAEs."),
        ("6.4", "Relationship to study drug",
         "An event is related if the investigator assessment (AEREL) is "
         "POSSIBLE or PROBABLE."),
    ]),
    ("7", "Statistical Methods", [
        ("7.1", "Continuous variables",
         "Summarised with n, mean, standard deviation (SD), median, minimum and "
         "maximum."),
        ("7.2", "Categorical variables",
         "Summarised with n and percentage. The denominator for a percentage "
         "is the Big N of the column (section 4.5). A count of zero is shown "
         "as 0 with no percentage."),
        ("7.3", "Subject counts",
         "A subject with more than one event is counted once per SOC, once per "
         "PT, and once overall."),
    ]),
    ("8", "Reporting Conventions", [
        ("8.1", "Decimal places",
         "Mean and median are shown to one more decimal place than the "
         "collected data; SD to two more. Minimum and maximum use the "
         "precision of the collected data. Percentages are shown to one "
         "decimal place."),
        ("8.2", "Population and titles",
         "Each table carries its population under the title and its source "
         "dataset and program in the footnotes."),
    ]),
    ("9", "Table Inventory", [
        "The following tables are required for the clinical study report. Each "
        "must be delivered.",
        ("table", [
            ["Table", "Title", "Population"],
            ["14.1.1", "Summary of Demographic and Baseline Characteristics", "Safety"],
            ["14.3.1", "Overview of Treatment-Emergent Adverse Events", "Safety"],
            ["14.3.2", "Treatment-Emergent Adverse Events by System Organ Class "
                       "and Preferred Term", "Safety"],
        ], [0.8, 4.4, 0.9]),
    ]),
]


def _page_furniture(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#555555"))
    canvas.drawString(0.75 * inch, 10.6 * inch,
                      "Statistical Analysis Plan - Protocol STUDY01 - Version 1.0 - CONFIDENTIAL")
    canvas.drawRightString(7.75 * inch, 10.6 * inch, f"Page {doc.page}")
    canvas.restoreState()


def _grid(rows, col_widths):
    # Wrap long cells so the title column does not run off the page.
    wrapped = [[Paragraph(str(c), STYLES["BodyText"]) if len(str(c)) > 40 else c
                for c in row] for row in rows]
    t = Table(wrapped, colWidths=[w * inch for w in col_widths], hAlign="LEFT")
    t.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#999999")),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E8EEF7")),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    return t


def build(path=OUT_PATH):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    doc = SimpleDocTemplate(path, pagesize=letter, leftMargin=0.75 * inch,
                            rightMargin=0.75 * inch, topMargin=0.9 * inch,
                            bottomMargin=0.8 * inch, title="Sample SAP - STUDY01")
    story = [
        Paragraph("Statistical Analysis Plan", STYLES["Title"]),
        Paragraph("Protocol STUDY01 - Drug A versus Placebo", STYLES["Heading3"]),
        Paragraph("Version 1.0 (synthetic, for SpecGen testing)", BODY),
        Spacer(1, 10),
    ]
    for num, heading, items in SECTIONS:
        story.append(Paragraph(f"{num}. {heading}", H1))
        for item in items:
            if isinstance(item, str):
                story.append(Paragraph(item, BODY))
            elif item[0] == "table":
                story.append(Spacer(1, 4))
                story.append(_grid(item[1], item[2]))
                story.append(Spacer(1, 6))
            else:
                sub_num, sub_head, text = item
                story.append(Paragraph(f"{sub_num} {sub_head}", H2))
                story.append(Paragraph(text, BODY))
    doc.build(story, onFirstPage=_page_furniture, onLaterPages=_page_furniture)
    return path


if __name__ == "__main__":
    print("Wrote", build())
