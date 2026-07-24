import pandas as pd
from generator import review_sas

CATALOG_FILE = "macro_catalog.csv"

PATTERNS = [
    "condition_flag",
    "codelist_decode",
    "numeric_range_group",
    "date_conversion",
    "study_day",
    "none",
]

def load_catalog():
    return pd.read_csv(CATALOG_FILE)

def find_macro(variable, catalog):
    """Exact variable-name lookup. Returns row dict or None."""
    match = catalog[catalog["variable"] == variable]
    if not match.empty:
        return match.iloc[0].to_dict()
    return None

def find_by_pattern(variable, derivation, catalog):
    """
    Agentic lookup: ask Claude which derivation pattern fits,
    then find the best macro for that pattern.
    Returns a row dict with a suggested_call key, or None.
    """
    prompt = f"""You are a clinical SAS programming expert.

Classify this ADaM derivation into exactly one pattern:

Variable: {variable}
Derivation: {derivation}

Patterns:
- condition_flag: Y/N flag derived from a single condition (e.g. Y if X is non-missing)
- codelist_decode: character or numeric code from a controlled list or ARM mapping
- numeric_range_group: group assignment from numeric cut points (e.g. age groups, BMI groups)
- date_conversion: convert an ISO 8601 --DTC character to a numeric SAS date
- study_day: CDISC --DY calculation (event date minus reference date, no day zero)
- none: does not fit any pattern above

Reply with ONLY the pattern name, nothing else."""

    result = review_sas(prompt).strip().lower()
    pattern = result if result in PATTERNS else "none"

    if pattern == "none":
        return None

    # Find the first catalog row matching this pattern
    matches = catalog[catalog["pattern"] == pattern]
    if matches.empty:
        return None

    # Return the best match — first row for this pattern as a template
    row = matches.iloc[0].to_dict()

    # Build a suggested call note for the model to adapt
    row["suggested_call"] = (
    f"/* Pattern: {pattern} - consider adapting this macro call for {variable}: */\n"
    f"/* {row['call']} */"
)
    return row