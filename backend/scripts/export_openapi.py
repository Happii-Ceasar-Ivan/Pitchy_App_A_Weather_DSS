"""Write the committed API contract: ``contract/openapi.v1.json``.

Run from ``backend/`` after changing any route or schema::

    uv run python scripts/export_openapi.py

``tests/test_contract.py`` fails if the committed file is out of date.
"""

import json
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
CONTRACT_PATH = BACKEND_DIR / "contract" / "openapi.v1.json"


def render_contract() -> str:
    sys.path.insert(0, str(BACKEND_DIR))
    from api.app import create_app
    from shared.settings import Settings

    spec = create_app(Settings(env="test")).openapi()
    return json.dumps(spec, indent=2, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    CONTRACT_PATH.parent.mkdir(exist_ok=True)
    CONTRACT_PATH.write_text(render_contract(), encoding="utf-8", newline="\n")
    print(f"Wrote {CONTRACT_PATH.relative_to(BACKEND_DIR)}")
