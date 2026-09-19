"""output_reader.py - read rendered TLF outputs (RTF, DOCX, PDF) into one
structured record per table.

Each record:
    table_id        "14.1.1" (from the "Table 14.1.1 ..." title line)
    kind            "table" | "listing" | "figure"
    title           the full title line
    subtitle        lines between the title and the table (population line etc.)
    footnotes       lines after the table, up to the next title
    column_headers  first row of the grid after any title band
    rows            list of lists of strings (the body of the table)
    page            1-based page the table starts on (1 when not knowable)
    source_file     file name the record came from

All three formats are turned into the same "stream" of text lines and table
grids, and one shared assembler builds the records - so the title/footnote
rules are identical whatever the file type. Deterministic; no model calls.
A table that continues across pages is read as one record per page.
"""

import os
import re

import docx as docx_lib
from docx.table import Table as DocxTable
from docx.text.paragraph import Paragraph as DocxParagraph
import pdfplumber
from striprtf.striprtf import rtf_to_text

SUPPORTED = (".rtf", ".docx", ".pdf")

TITLE_RE = re.compile(r"^\s*(Table|Listing|Figure)\s+(\d+(?:\.\d+)*)\b", re.I)
_PAGE_LINE_RE = re.compile(r"^\s*page\s+\d+(\s+of\s+\d+)?\s*$", re.I)

_TABLE_MARK = "@@TABLE@@"
_PAGE_MARK = "@@PAGE@@"


# ---------------------------------------------------------------------------
# Shared assembly: stream of ("text", line, page) / ("table", grid, page)
# -> output records
# ---------------------------------------------------------------------------

def _split_grid(grid):
    """Clean a raw grid -> (band_title, column_headers, rows).

    A "title band" is a leading row whose only content is a Table/Listing/
    Figure title (PDF and Word exports often put the title inside the grid).
    """
    grid = [[(c or "").strip() for c in row] for row in grid]
    grid = [row for row in grid if any(row)]
    band = None
    if grid:
        filled = [c for c in grid[0] if c]
        if len(filled) == 1 and TITLE_RE.match(filled[0]):
            band = filled[0]
            grid = grid[1:]
    headers = grid[0] if grid else []
    rows = grid[1:] if grid else []
    return band, headers, rows


def _assemble(stream, source_file):
    outputs = []
    pending = []          # text lines seen since the last table

    for kind, payload, page in stream:
        if kind == "text":
            line = payload.strip()
            if line and not _PAGE_LINE_RE.match(line):
                pending.append(line)
            continue

        band, headers, rows = _split_grid(payload)

        # Lines before the last title-looking line belong to the previous
        # table (its footnotes); from that title on they head this table.
        title_idx = None
        for i, line in enumerate(pending):
            if TITLE_RE.match(line):
                title_idx = i
        if title_idx is None:
            if outputs:
                outputs[-1]["footnotes"].extend(pending)
                pre = []
            else:
                pre = pending
        else:
            if outputs:
                outputs[-1]["footnotes"].extend(pending[:title_idx])
            pre = pending[title_idx:]
        pending = []

        if band:
            title = band
        elif pre and TITLE_RE.match(pre[0]):
            title = pre[0]
        else:
            title = pre[0] if pre else ""
        # A wrapped title in the PDF is a piece of the band, not a subtitle.
        subtitle_lines = [l for l in pre if l != title and l not in title]

        m = TITLE_RE.match(title)
        outputs.append({
            "table_id": m.group(2) if m else "",
            "kind": m.group(1).lower() if m else "table",
            "title": title,
            "subtitle": " ".join(subtitle_lines),
            "footnotes": [],
            "column_headers": headers,
            "rows": rows,
            "page": page,
            "source_file": source_file,
        })

    if outputs:
        outputs[-1]["footnotes"].extend(pending)
    return outputs


# ---------------------------------------------------------------------------
# RTF
# ---------------------------------------------------------------------------

_ROW_RUN = re.compile(r"(?:\\trowd.*?\\row(?![a-z])\s*)+", re.S)
_ROW = re.compile(r"\\trowd(.*?)\\row(?![a-z])", re.S)
_CELLX = re.compile(r"\\cellx-?\d+")
_CELL_END = re.compile(r"\\cell(?![a-z])")
_PAGE_BREAK = re.compile(r"\\page(?![a-z])")


def _rtf_cell_text(fragment):
    return rtf_to_text("{\\rtf1\\ansi " + fragment + "}").replace("\n", " ").strip()


def _rtf_run_to_grid(run):
    grid = []
    for m in _ROW.finditer(run):
        body = _CELLX.split(m.group(1))[-1]      # text after the last \cellx
        cells = _CELL_END.split(body)[:-1]       # last piece is trailing junk
        grid.append([_rtf_cell_text(c) for c in cells])
    return grid


def _rtf_text_only_stream(lines):
    """RTF written as plain text lines with space-aligned columns (what a
    listing-style SAS/R export produces). A run of 2+ consecutive lines that
    each split into 2+ cells on runs of 2+ spaces is a table."""
    stream, run = [], []

    def flush():
        if len(run) >= 2:
            stream.append(("table", [list(r) for r in run], 1))
        else:
            for r in run:
                stream.append(("text", "  ".join(r), 1))
        run.clear()

    for line in lines:
        cells = re.split(r"\s{2,}", line.strip()) if line.strip() else []
        if len(cells) >= 2:
            run.append(cells)
            continue
        flush()
        if line.strip():
            stream.append(("text", line.strip(), 1))
    flush()
    return stream


def _rtf_stream(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        raw = f.read()

    if "\\trowd" not in raw:
        text = rtf_to_text(raw)
        return _rtf_text_only_stream(text.splitlines())

    grids = [_rtf_run_to_grid(m.group(0)) for m in _ROW_RUN.finditer(raw)]
    marked = _ROW_RUN.sub(f"\\\\par {_TABLE_MARK}\\\\par ", raw)
    marked = _PAGE_BREAK.sub(f"\\\\par {_PAGE_MARK}\\\\par ", marked)
    stream, page, grid_iter = [], 1, iter(grids)
    for line in rtf_to_text(marked).splitlines():
        line = line.strip()
        if line == _PAGE_MARK:
            page += 1
        elif line == _TABLE_MARK:
            stream.append(("table", next(grid_iter), page))
        elif line:
            stream.append(("text", line, page))
    return stream


# ---------------------------------------------------------------------------
# DOCX
# ---------------------------------------------------------------------------

def _docx_grid(table):
    grid = []
    for row in table.rows:
        seen, cells = set(), []
        for cell in row.cells:
            # A merged cell shows up once per grid column it spans - keep the
            # text once and blank the repeats so a title band stays a band.
            key = id(cell._tc)
            cells.append("" if key in seen else cell.text.strip())
            seen.add(key)
        grid.append(cells)
    return grid


def _docx_stream(path):
    doc = docx_lib.Document(path)
    stream, page = [], 1
    for child in doc.element.body.iterchildren():
        tag = child.tag.rsplit("}", 1)[-1]
        if tag == "p":
            para = DocxParagraph(child, doc)
            if 'w:type="page"' in child.xml or "w:pageBreakBefore" in child.xml:
                page += 1
            if para.text.strip():
                stream.append(("text", para.text, page))
        elif tag == "tbl":
            stream.append(("table", _docx_grid(DocxTable(child, doc)), page))
    return stream


# ---------------------------------------------------------------------------
# PDF
# ---------------------------------------------------------------------------

def _inside(obj, bbox, pad=1.5):
    return (obj["x0"] >= bbox[0] - pad and obj["x1"] <= bbox[2] + pad
            and obj["top"] >= bbox[1] - pad and obj["bottom"] <= bbox[3] + pad)


def _pdf_stream(path):
    stream = []
    with pdfplumber.open(path) as pdf:
        for page_no, page in enumerate(pdf.pages, start=1):
            positioned = []
            tables = page.find_tables()
            bboxes = [t.bbox for t in tables]
            for t in tables:
                positioned.append((t.bbox[1], "table", t.extract(), page_no))

            outside = page.filter(lambda o: not (
                o.get("object_type") == "char" and any(_inside(o, b) for b in bboxes)))
            for line in outside.extract_text_lines():
                positioned.append((line["top"], "text", line["text"], page_no))

            positioned.sort(key=lambda item: item[0])
            stream.extend((kind, payload, pg) for _, kind, payload, pg in positioned)
    return stream


_STREAMS = {".rtf": _rtf_stream, ".docx": _docx_stream, ".pdf": _pdf_stream}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def read_output(path):
    """Read one RTF / DOCX / PDF file. Returns a list of output records."""
    ext = os.path.splitext(path)[1].lower()
    if ext not in _STREAMS:
        raise ValueError(f"Unsupported output type {ext!r} (supported: {', '.join(SUPPORTED)})")
    return _assemble(_STREAMS[ext](path), os.path.basename(path))


def read_outputs(folder):
    """Read every supported output in a folder, sorted by file name."""
    records = []
    for fname in sorted(os.listdir(folder)):
        if fname.startswith("~$") or os.path.splitext(fname)[1].lower() not in _STREAMS:
            continue
        records.extend(read_output(os.path.join(folder, fname)))
    return records
