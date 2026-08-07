import pandas as pd
import chromadb

CATALOG_FILE = "macro_catalog.csv"

# Cosine-distance cutoff below which a nearest-neighbor match is considered
# usable; above this the query is treated as "no good match" (mirrors the
# old find_by_pattern's `pattern == "none"` bail-out).
MATCH_DISTANCE_THRESHOLD = 0.65

def load_catalog():
    return pd.read_csv(CATALOG_FILE)

def find_macro(variable, catalog):
    """Exact variable-name lookup, ADaM scope only. Returns row dict or None.
    (SDTM/TLF catalog rows use non-variable-name values in this column —
    suffix globs like "*SEQ", or "all" — so they'd never accidentally
    exact-match a real ADaM variable name even without this filter, but
    scoping explicitly keeps the two lookup styles from ever crossing.)"""
    match = catalog[(catalog["scope"] == "adam") & (catalog["variable"] == variable)]
    if not match.empty:
        return match.iloc[0].to_dict()
    return None

def find_sdtm_macros(variables, catalog):
    """Suffix-pattern lookup for SDTM: which catalog macros (scope=sdtm)
    are relevant to at least one variable in this domain's variable list?
    Unlike ADaM's exact per-variable match, SDTM programs are generated one
    whole domain at a time, so this returns every macro that MIGHT apply —
    used as hints in the domain prompt for the Writer to use where it
    actually fits, not a forced substitution. variables: list of variable
    name strings (e.g. ["AESEQ", "AETERM", "AESTDTC", ...])."""
    sdtm_rows = catalog[catalog["scope"] == "sdtm"]
    upper_vars = [str(v).upper() for v in variables]
    hits = []
    for _, row in sdtm_rows.iterrows():
        suffix = str(row["variable"]).lstrip("*").upper()
        if any(v.endswith(suffix) for v in upper_vars):
            hits.append(row.to_dict())
    return hits

_collection = None


def _get_collection(catalog):
    """Lazily build (once per process) an in-memory Chroma collection over
    the ADaM-scope rows of the macro catalog — each macro's purpose/pattern
    text embedded via Chroma's bundled local MiniLM model (downloaded once,
    then fully offline — same "runs on this machine" spirit as the local
    Ollama Writer). Cached at module level since the catalog doesn't change
    within a process, same pattern as `catalog = load_catalog()` elsewhere."""
    global _collection
    if _collection is not None:
        return _collection
    client = chromadb.Client()
    _collection = client.get_or_create_collection(
        "macro_catalog", metadata={"hnsw:space": "cosine"}
    )
    adam_rows = catalog[catalog["scope"] == "adam"].reset_index(drop=True)
    if not adam_rows.empty:
        _collection.add(
            ids=[str(i) for i in adam_rows.index],
            documents=(adam_rows["purpose"] + " (pattern: " + adam_rows["pattern"] + ")").tolist(),
            metadatas=adam_rows.to_dict("records"),
        )
    return _collection


def find_by_pattern(variable, derivation, catalog):
    """
    Semantic retrieval: embed "{variable}: {derivation}" and find the
    nearest macro by cosine distance against the catalog's purpose text —
    a real embedding pipeline (Chroma + local MiniLM), replacing the old
    approach of asking the model to classify the derivation into one of a
    fixed set of pattern names and then exact-matching that name. ADaM
    scope only. Returns a row dict with a suggested_call key, or None if
    the nearest match isn't close enough to be useful.
    """
    collection = _get_collection(catalog)
    if collection.count() == 0:
        return None

    result = collection.query(query_texts=[f"{variable}: {derivation}"], n_results=1)
    if not result["ids"][0]:
        return None

    distance = result["distances"][0][0]
    if distance > MATCH_DISTANCE_THRESHOLD:
        return None

    row = dict(result["metadatas"][0][0])
    row["suggested_call"] = (
        f"/* Closest catalog match ({row['pattern']}, distance={distance:.2f}) - "
        f"consider adapting this macro call for {variable}: */\n"
        f"/* {row['call']} */"
    )
    return row