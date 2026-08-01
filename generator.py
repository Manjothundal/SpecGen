import os
import requests
from dotenv import load_dotenv
from anthropic import Anthropic
from config import WRITER, REVIEWER, LOCAL_MODEL, API_MODEL

load_dotenv()

client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))


def generate_api(prompt):
    """Send a prompt to Claude via the API."""
    response = client.messages.create(
        model=API_MODEL,
        max_tokens=8192,
        messages=[{"role": "user", "content": prompt}]
    )
    return response.content[0].text


def generate_local(prompt):
    """Send a prompt to the local Ollama model."""
    response = requests.post(
        "http://localhost:11434/api/generate",
        json={"model": LOCAL_MODEL, "prompt": prompt, "stream": False},
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
# generate_code/review_code are the names to use going forward; generate_sas/
# review_sas remain as aliases so existing callers keep working.
# ---------------------------------------------------------------------------

def generate_code(prompt):
    """Writer: generates the code (SAS or R — the prompt decides)."""
    return run_model(prompt, WRITER)


def review_code(prompt):
    """Reviewer: QCs the code (SAS or R — the prompt decides)."""
    return run_model(prompt, REVIEWER)


# --- Back-compat aliases (unchanged behaviour) ---
generate_sas = generate_code
review_sas = review_code


def model_name(mode):
    """Readable name of whichever model a mode uses (for logging)."""
    return LOCAL_MODEL if mode == "local" else API_MODEL
