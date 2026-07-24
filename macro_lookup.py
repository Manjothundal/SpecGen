import pandas as pd

CATALOG_FILE = "macro_catalog.csv"

def load_catalog():
    return pd.read_csv(CATALOG_FILE)

def find_macro(variable, catalog):
    """Return the catalog row for this variable, or None."""
    match = catalog[catalog["variable"] == variable]
    if not match.empty:
        return match.iloc[0].to_dict()
    return None