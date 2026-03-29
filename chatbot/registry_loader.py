"""
Load and cache the four registry JSON files from registry/ at the project root.
"""

import json
from pathlib import Path

REGISTRY_DIR = Path(__file__).parent.parent / "registry"
_REGISTRY_NAMES = ["models", "algorithms", "states", "systems"]

# returns the Information from the registry for the LLM to work with
def load_all() -> dict:
    """
    Load all four registry files and return them as a dict keyed by name.
    Raises FileNotFoundError with a clear message if any file is missing.
    """
    result = {}
    for name in _REGISTRY_NAMES:
        path = REGISTRY_DIR / f"{name}.json"
        if not path.exists():
            raise FileNotFoundError(
                f"Registry file not found: {path}\n"
                f"Make sure you are running from the TNCodebase project root."
            )
        result[name] = json.loads(path.read_text(encoding="utf-8"))
    return result
