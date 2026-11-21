"""Create (or rotate) the backend's least-privilege database login and save it to the root .env.

Run from ``backend/`` after migrations, with the admin ``SUPABASE_DB_URL`` set::

    uv run python scripts/create_db_login.py

- Generates a random password locally; it is never printed or logged.
- Creates or updates login role ``pitchy_backend`` and grants it ``pitchy_app``.
- Writes ``PITCHY_APP_DB_URL`` into the root ``.env`` (replacing an existing line).
  Close ``.env`` in your editor first so an open copy does not overwrite it.

Re-running rotates the password. For a Supabase pooler URL the user becomes
``pitchy_backend.<project-ref>``, which is how Supavisor routes custom roles.
"""

import secrets
import sys
from pathlib import Path
from urllib.parse import quote, urlsplit, urlunsplit

import psycopg
from psycopg import sql

BACKEND_DIR = Path(__file__).resolve().parent.parent
LOGIN_ROLE = "pitchy_backend"
ENV_VAR = "PITCHY_APP_DB_URL"


def app_url(admin_url: str, password: str) -> str:
    parts = urlsplit(admin_url)
    admin_user = parts.username or ""
    _, dot, project_ref = admin_user.partition(".")
    user = f"{LOGIN_ROLE}.{project_ref}" if dot else LOGIN_ROLE
    host = parts.hostname or ""
    netloc = f"{quote(user, safe='.')}:{quote(password, safe='')}@{host}"
    if parts.port:
        netloc += f":{parts.port}"
    return urlunsplit((parts.scheme, netloc, parts.path, parts.query, parts.fragment))


def ensure_login(conn: psycopg.Connection, password: str) -> None:
    exists = conn.execute("select 1 from pg_roles where rolname = %s", (LOGIN_ROLE,)).fetchone()
    verb = "alter" if exists else "create"
    conn.execute(
        sql.SQL("{} role {} with login inherit nocreatedb nocreaterole password {}").format(
            sql.SQL(verb), sql.Identifier(LOGIN_ROLE), sql.Literal(password)
        )
    )
    conn.execute(sql.SQL("grant pitchy_app to {}").format(sql.Identifier(LOGIN_ROLE)))


def write_env(env_path: Path, value: str) -> None:
    text = env_path.read_text(encoding="utf-8-sig") if env_path.exists() else ""
    lines = [line for line in text.splitlines() if not line.startswith(f"{ENV_VAR}=")]
    while lines and not lines[-1].strip():
        lines.pop()
    lines += [
        "",
        "# SERVER ONLY - least-privilege runtime login (created by scripts/create_db_login.py)",
        f"{ENV_VAR}={value}",
    ]
    env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    sys.path.insert(0, str(BACKEND_DIR))
    from shared.settings import ROOT_ENV_FILE, Settings

    settings = Settings()
    if not settings.supabase_db_url:
        print("SUPABASE_DB_URL (admin) is not set in the root .env.", file=sys.stderr)
        return 2
    admin_url = settings.supabase_db_url.get_secret_value()
    password = secrets.token_urlsafe(32)
    try:
        with psycopg.connect(admin_url, autocommit=True, connect_timeout=15) as conn:
            if not conn.execute("select 1 from pg_roles where rolname = 'pitchy_app'").fetchone():
                print("Role pitchy_app is missing: run scripts/migrate.py first.", file=sys.stderr)
                return 1
            ensure_login(conn, password)
    except psycopg.Error as exc:
        print(f"Could not create the login: {type(exc).__name__}", file=sys.stderr)
        return 1
    write_env(ROOT_ENV_FILE, app_url(admin_url, password))
    print(f"Login '{LOGIN_ROLE}' ready; {ENV_VAR} written to {ROOT_ENV_FILE.name}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
