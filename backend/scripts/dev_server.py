"""Start the backend locally with the dev demo routes, then open the interactive API docs.

Run from ``backend/``::

    uv run python scripts/dev_server.py

Docs page: http://127.0.0.1:8000/api/v1/docs (only reachable from this computer).
"""

import os
import sys
from pathlib import Path

import uvicorn

if __name__ == "__main__":
    os.environ.setdefault("PITCHY_ENV", "development")
    os.environ["PITCHY_ENABLE_DEV_ROUTES"] = "true"
    if os.environ["PITCHY_ENV"] != "development":
        sys.exit("dev_server.py is for PITCHY_ENV=development only.")
    backend_dir = Path(__file__).resolve().parent.parent
    os.chdir(backend_dir)
    sys.path.insert(0, str(backend_dir))
    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run("api.app:app", host="127.0.0.1", port=port, reload=False)
