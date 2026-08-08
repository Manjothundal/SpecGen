import re

import pandas as pd
import chromadb

CATALOG_FILE = "macro_catalog.csv"

# Cosine-distance cutoff below which a nearest-neighbor match is considered
# usable; above this the query is treated as "no good match" (mirrors the
# old find_by_pattern's `pattern == "none"` bail-out).
MATCH_DISTANCE_THRESHOLD = 0.65

def load_catalog():
    return pd.read_csv(CATALOG_FILE)


def _extract_range_group_params(derivation):
    """Pull (cuts, labels) out of a standard numeric_range_group derivation
    — N quoted band labels in order, and the N-1 numeric cut points between
    them (e.g. 'If AGE < 65 then AGEGR1 = "<65"; else if 65 <= AGE <= 75
    then AGEGR1 = "65-75"; else if AGE > 75 then AGEGR1 = ">75".' ->
    ("65|75", "<65|65-75|>75")). Returns None if the derivation doesn't
    match this recognizable shape (fewer than 2 labels, or the cut-point
    count doesn't line up) — the caller falls back to the catalog's static
    template unchanged in that case, so this is a strict improvement, never
    a regression."""
    labels = re.findall(r'"([^"]+)"', derivation)
    if len(labels) < 2:
        return None
    # Strip the quoted labels first so their own digits (e.g. "<65") can't
    # leak into the cut-point scan below.
    stripped = re.sub(r'"[^"]*"', "", derivation)
    numbers = re.findall(r"(?<![\w.])-?\d+(?:\.\d+)?(?![\w.])", stripped)
    seen = []
    for n in numbers:
        if n not in seen:
            seen.append(n)
    cuts = seen[: len(labels) - 1]
    if len(cuts) != len(labels) - 1:
        return None
    return "|".join(cuts), "|".join(labels)


def _substitute_call_kwarg(call, kwarg, new_value):
    return re.sub(rf"({re.escape(kwarg)}=)[^,)]*", rf"\g<1>{new_value}", call)


def _reparametrize(match, derivation):
    """An exact catalog match substitutes its `call` directly, with no
    Writer/Improver/Reviewer step — so unlike the pattern-hint path (which
    the model sees and is asked to adapt), a stale template value here
    would otherwise go out unnoticed: e.g. AGEGR1's cut points changing
    from 65|80 to 65|75 in a spec update wouldn't be reflected, since
    `call` is a static string keyed only on the variable name. Currently
    only handles numeric_range_group (the case that surfaced this) via a
    plain regex extraction — no model call, so the fast/deterministic
    exact-match path stays fast and deterministic. Returns `match`
    unchanged if the pattern isn't numeric_range_group or the derivation
    doesn't parse into recognizable cuts/labels."""
    if match.get("pattern") != "numeric_range_group" or not derivation:
        return match
    extracted = _extract_range_group_params(derivation)
    if not extracted:
        return match
    cuts, labels = extracted
    call = match["call"]
    call = _substitute_call_kwarg(call, "cuts", cuts)
    call = _substitute_call_kwarg(call, "labels", labels)
    if call == match["call"]:
        return match
    match = dict(match)
    match["call"] = call
    return match


def find_macro(variable, catalog, derivation=None):
    """Exact variable-name lookup, ADaM scope only. Returns row dict or None.
    (SDTM/TLF catalog rows use non-variable-name values in this column —
    suffix globs like "*SEQ", or "all" — so they'd never accidentally
    exact-match a real ADaM variable name even without this filter, but
    scoping explicitly keeps the two lookup styles from ever crossing.)

    derivation: the variable's current Derivation rule text, optional — when
    given, the matched macro call's parameters are reparametrized to match
    it where that's recognizable (see _reparametrize); omit it (or pass
    None) to get the catalog's static call verbatim, as before."""
    match = catalog[(catalog["scope"] == "adam") & (catalog["variable"] == variable)]
    if match.empty:
        return None
    row = match.iloc[0].to_dict()
    return _reparametrize(row, derivation)

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