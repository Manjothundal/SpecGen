# Which model writes the code, and which one QCs it.
# "local" = Ollama on this machine (offline)
# "api"   = Claude via Anthropic API (requires internet)

WRITER = "local"
REVIEWER = "api"

LOCAL_MODEL = "qwen2.5-coder:7b"
API_MODEL = "claude-sonnet-4-5"

# Output language for generated programs — independent of WRITER/REVIEWER.
# "sas" = emit SAS (.sas)   "r" = emit R / tidyverse (.R)
# This is the Language toggle from the mockup; Mode (above) and Language are
# separate axes: any mode can emit either language.
LANGUAGE = "sas"
