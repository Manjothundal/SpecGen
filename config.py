# Which model writes the code, and which one QCs it.
# "local" = Ollama on this machine (offline)
# "api"   = Claude via Anthropic API (requires internet)

WRITER = "local"
REVIEWER = "api"

LOCAL_MODEL = "qwen2.5-coder:7b"
API_MODEL = "claude-sonnet-4-5"