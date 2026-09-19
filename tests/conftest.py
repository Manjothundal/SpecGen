"""Make the repo root importable so tests can `import review` (the project
keeps its modules at the repo root, not in an installed package)."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
