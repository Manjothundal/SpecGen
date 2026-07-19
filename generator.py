import os
from dotenv import load_dotenv
from anthropic import Anthropic

# Load the key from .env into the environment
load_dotenv()

client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

def generate_sas(prompt):
    """Send a prompt to Claude, return the SAS code it writes."""
    response = client.messages.create(
        model="claude-sonnet-4-5",
        max_tokens=1000,
        messages=[{"role": "user", "content": prompt}]
    )
    return response.content[0].text