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


def run_model(prompt, mode):
    """Route a prompt to local or api based on mode."""
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

def generate_code(prompt, mode=None):
    """Writer: generates the code (SAS or R — the prompt decides)."""
    return run_model(prompt, mode or config.WRITER)


def review_code(prompt, mode=None):
    """Reviewer: QCs the code (SAS or R — the prompt decides)."""
    return run_model(prompt, mode or config.REVIEWER)


# --- Back-compat aliases (unchanged behaviour) ---
generate_sas = generate_code
review_sas = review_code


def model_name(mode):
    """Readable name of whichever model a mode uses (for logging)."""
    return config.LOCAL_MODEL if mode == "local" else config.API_MODEL
