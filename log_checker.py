"""log_checker.py — parse a SAS .log file and flag ERROR/WARNING/actionable
NOTE lines, each with a suggested fix where the message matches a known
pattern.

Deterministic parsing and matching (same "no AI needed for the mechanical
part" spirit as spec_differ.py) — a SAS log's ERROR:/WARNING:/NOTE: marker
lines and their well-documented message families are fixed text, not
something that needs a model to recognize. The vast majority of NOTEs
(dataset created with N observations, PROC used N.NN seconds, etc.) are
routine and are not findings — only NOTEs matching a known actionable
pattern below are surfaced, so a checked log isn't buried in noise.

check_log()'s `mode` argument is an optional escape hatch: for a finding
whose message doesn't match any known pattern, pass a generator.py mode
("local"/"api") to ask the model for a one-line suggestion instead of
leaving it blank. Omit it (the default) for pure offline/free/deterministic
checking — every KNOWN pattern's suggestion is already in the table below
and never touches a model either way.
"""

import re

from generator import generate_code

_MARKER_RE = re.compile(r"^(ERROR|WARNING|NOTE)(\s\d+-\d+)?:\s?(.*)$")
_SOURCE_ECHO_RE = re.compile(r"^\s*\d+\s")
_LOCATION_RE = re.compile(r"line (\d+) column (\d+)", re.IGNORECASE)

# (regex matched against the finding's full joined message, category override
# or None to keep the marker's own severity, suggestion). Checked in order,
# first match wins. category overrides exist because a few well-known
# messages are more/less severe in practice than their literal SAS marker
# suggests (e.g. "may be incomplete" WARNINGs are usually fallout from an
# ERROR earlier in the same step, not an independent problem).
_KNOWN_PATTERNS = [
    (re.compile(r"variable (\S+) is uninitialized", re.I), None,
     "The variable is referenced before it's ever assigned in this data step "
     "— check for a typo against the intended source variable, or a RETAIN/"
     "initialization statement that's missing."),
    (re.compile(r"character values have been converted to numeric", re.I), None,
     "An implicit character-to-numeric conversion happened — make it explicit "
     "with INPUT() at the point of conversion, and check whether the mixed "
     "types indicate a real derivation bug."),
    (re.compile(r"numeric values have been converted to character", re.I), None,
     "An implicit numeric-to-character conversion happened — make it explicit "
     "with PUT() at the point of conversion, and check whether the mixed "
     "types indicate a real derivation bug."),
    (re.compile(r"missing values were generated", re.I), None,
     "An arithmetic or comparison operation ran on a missing value — add an "
     "explicit missing-value guard (e.g. `if not missing(x)`) before the "
     "operation if missing inputs are expected."),
    (re.compile(r"invalid (data|argument)", re.I), None,
     "The raw input didn't match the expected informat/type for this field — "
     "check the source data for unexpected values and consider a more "
     "permissive INFORMAT or explicit data cleaning before this step."),
    (re.compile(r"(merge|match-merge) statement has more than one data set "
                r"with repeats of by", re.I), None,
     "A many-to-many merge — at least one BY-group appears more than once in "
     "more than one input dataset. Confirm this is intentional (it usually "
     "isn't); if not, deduplicate one side or add BY variables that make the "
     "match unique."),
    (re.compile(r"file \S+ does not exist", re.I), None,
     "A referenced dataset was never created — check the step that should "
     "have created it for an earlier ERROR (a failed step often leaves "
     "nothing behind for a later step to read), or check for a DATA=/SET= "
     "typo."),
    (re.compile(r"variable (\S+) not found", re.I), None,
     "The variable isn't in the input dataset at this point in the program — "
     "check spelling, and check whether an earlier step dropped, renamed, or "
     "failed to create it."),
    (re.compile(r"apparent symbolic reference (\S+) not resolved", re.I), None,
     "A macro variable (&...) was referenced before it was defined, or its "
     "name is misspelled. If a literal & is intended (not a macro reference), "
     "protect it with %NRSTR()."),
    (re.compile(r"data set \S+ may be incomplete", re.I), "warning",
     "This step stopped before finishing — look for the ERROR earlier in the "
     "same step log that halted it; fixing that will usually resolve this "
     "warning too."),
    (re.compile(r"format \S+ was not found or could not be loaded", re.I), None,
     "A user-defined format isn't available — confirm PROC FORMAT ran (and "
     "created a catalog) before this step, and check FMTSEARCH / the CMPLIB "
     "path if the format lives in a separate catalog."),
    (re.compile(r"multiple lengths were specified for the variable (\S+)", re.I), None,
     "Different input datasets declare different lengths for this variable — "
     "the LONGEST one silently applies. Declare its LENGTH explicitly before "
     "the SET/MERGE that first uses it if truncation is a concern."),
    (re.compile(r"no matching %mend statement", re.I), None,
     "A %MACRO definition is missing its closing %MEND (or an earlier one is "
     "unbalanced) — check macro definitions above this point for a missing "
     "%MEND."),
]


def _classify(marker):
    return {"ERROR": "error", "WARNING": "warning", "NOTE": "note"}[marker]


def check_log(log_text, mode=None):
    """Parse a SAS .log's text and return a list of findings, most-severe
    first: [{severity, message, line_no, location, suggestion}, ...].

    Every ERROR and WARNING is included. Only NOTEs matching a known
    actionable pattern are — the rest (dataset created with N observations,
    PROC ... used N.NN seconds, etc.) are routine and would just be noise.

    mode: optional generator.py mode ("local"/"api"/"mock") — when given,
    an unmatched finding gets a model-suggested fix instead of None. Omit
    for pure deterministic checking (default).
    """
    lines = log_text.splitlines()
    raw_findings = []  # (marker, message_lines, source_line_no)
    i = 0
    source_line_no = None
    while i < len(lines):
        line = lines[i]
        echo = _SOURCE_ECHO_RE.match(line)
        if echo:
            source_line_no = int(line.split(None, 1)[0])
            i += 1
            continue

        m = _MARKER_RE.match(line)
        if not m:
            i += 1
            continue

        marker = m.group(1)
        message_lines = [m.group(3)]
        i += 1
        # Continuation lines: indented, and not themselves a new marker or a
        # source-code echo.
        while i < len(lines) and lines[i].strip() and not _MARKER_RE.match(lines[i]) \
                and not _SOURCE_ECHO_RE.match(lines[i]):
            message_lines.append(lines[i].strip())
            i += 1

        raw_findings.append((marker, message_lines, source_line_no))

    findings = []
    for marker, message_lines, source_line_no in raw_findings:
        message = " ".join(message_lines).strip()
        severity = _classify(marker)

        suggestion = None
        for pattern, category_override, fix in _KNOWN_PATTERNS:
            if pattern.search(message):
                if category_override:
                    severity = category_override
                suggestion = fix
                break

        if severity == "note" and suggestion is None:
            continue  # routine NOTE, not a finding

        if suggestion is None and mode:
            suggestion = _ask_model(message, mode)

        loc = _LOCATION_RE.search(message)
        location = f"line {loc.group(1)} column {loc.group(2)}" if loc else None

        findings.append({
            "severity": severity,
            "message": message,
            "line_no": source_line_no,
            "location": location,
            "suggestion": suggestion,
        })

    order = {"error": 0, "warning": 1, "note": 2}
    findings.sort(key=lambda f: order[f["severity"]])
    return findings


def _ask_model(message, mode):
    prompt = f"""A SAS log contains this message:

{message}

In one sentence, suggest the most likely fix a clinical SAS programmer
should check first. No preamble, no markdown — just the sentence."""
    try:
        return generate_code(prompt, mode=mode).strip()
    except Exception as e:
        return f"(no suggestion available: {e})"


def print_log_check(findings):
    """Human-readable summary, same style as spec_differ.print_diff."""
    print(f"\n{'='*50}")
    print("SAS LOG CHECK")
    print(f"{'='*50}")
    counts = {"error": 0, "warning": 0, "note": 0}
    for f in findings:
        counts[f["severity"]] += 1
    print(f"Errors   : {counts['error']}")
    print(f"Warnings : {counts['warning']}")
    print(f"Notes    : {counts['note']}")
    for f in findings:
        loc = f" ({f['location']})" if f["location"] else (
            f" (near source line {f['line_no']})" if f["line_no"] else "")
        print(f"\n[{f['severity'].upper()}]{loc} {f['message']}")
        if f["suggestion"]:
            print(f"  -> {f['suggestion']}")
