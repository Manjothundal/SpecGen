import os
import requests
from dotenv import load_dotenv
from anthropic import Anthropic
import config

load_dotenv()

client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))


def generate_api(prompt):
    """Send a prompt to Claude via the API."""
    response = client.messages.create(
        model=config.API_MODEL,
        max_tokens=8192,
        messages=[{"role": "user", "content": prompt}]
    )
    return response.content[0].text


def generate_local(prompt):
    """Send a prompt to the local Ollama model."""
    response = requests.post(
        "http://localhost:11434/api/generate",
        json={"model": config.LOCAL_MODEL, "prompt": prompt, "stream": False},
        timeout=300,
    )
    return response.json()["response"]


def generate_mock(prompt, language="sas"):
    """Deterministic, no-network stand-in for local/api — CI's mode
    (SPECGEN_WRITER_MODE / SPECGEN_REVIEWER_MODE=mock, see test_patcher.py
    and .github/workflows/tests.yml) so pipeline tests don't need Ollama
    running or a paid Anthropic API call on every push.

    language matters here (unlike generate_local/generate_api, which just
    ship the prompt text to a model that reads the language off it) because
    this function has to fabricate syntactically valid output itself — R
    has no /* */ block comment, so the SAS-flavored stub would break a
    mutate() chain it's spliced into."""
    if (language or "sas").lower() == "r":
        return "# mock: deterministic CI stub, no model call\nMOCK = 1"
    return "/* mock: deterministic CI stub, no model call */\nMOCK = 1;"


def run_model(prompt, mode, language="sas"):
    """Route a prompt to local, api, or the mock stub based on mode."""
    if mode == "mock":
        return generate_mock(prompt, language=language)
    if mode == "local":
        return generate_local(prompt)
    return generate_api(prompt)


# ---------------------------------------------------------------------------
# Writer / Reviewer entry points.
#
# These are language-neutral: the prompt (built by prompt_builder with a
# language arg) already decides SAS vs R. run_model just ships text to a model.
#
# mode: explicit "local"|"api" override (e.g. the app's Mode switcher — see
# app.py's MODE_MAP). Reads config.WRITER/config.REVIEWER as module attributes
# (not `from config import ...`) so a per-request override actually takes
# effect; the plain import would bind the name at import time and never see
# a later change to config.WRITER/REVIEWER.
# ---------------------------------------------------------------------------

def generate_code(prompt, mode=None, language=None):
    """Writer: generates the code (SAS or R — the prompt decides; language
    is only used to pick the mock stub's syntax in mock mode)."""
    return run_model(prompt, mode or config.WRITER, language=language or config.LANGUAGE)


def review_code(prompt, mode=None, language=None):
    """Reviewer: QCs the code (SAS or R — the prompt decides; language is
    only used to pick the mock stub's syntax in mock mode)."""
    return run_model(prompt, mode or config.REVIEWER, language=language or config.LANGUAGE)


# --- Back-compat aliases (unchanged behaviour) ---
generate_sas = generate_code
review_sas = review_code


def model_name(mode):
    """Readable name of whichever model a mode uses (for logging)."""
    if mode == "local":
        return config.LOCAL_MODEL
    if mode == "mock":
        return "mock (CI stub, no model call)"
    return config.API_MODEL
