import pytest

from shared.settings import Settings


@pytest.fixture
def env_file(tmp_path, monkeypatch):
    for name in ("PITCHY_ENV", "SUPABASE_URL", "GEMINI_API_KEY", "SUPABASE_SERVICE_ROLE_KEY"):
        monkeypatch.delenv(name, raising=False)
    path = tmp_path / ".env"
    path.write_text(
        "PITCHY_ENV=production\n"
        "SUPABASE_URL=https://example.invalid\n"
        "SUPABASE_SERVICE_ROLE_KEY=not-a-real-key\n"
        "GEMINI_API_KEY=\n",
        encoding="utf-8",
    )
    return path


def test_reads_env_file_names_and_masks_secrets(env_file) -> None:
    s = Settings(_env_file=env_file)
    assert s.env == "production"
    assert s.supabase_url == "https://example.invalid"
    assert s.supabase_service_role_key.get_secret_value() == "not-a-real-key"
    assert "not-a-real-key" not in repr(s)


def test_empty_value_counts_as_unset(env_file) -> None:
    assert Settings(_env_file=env_file).gemini_api_key is None


def test_chat_limit_defaults_and_override(env_file, monkeypatch) -> None:
    s = Settings(_env_file=env_file)
    assert (s.chat_max_prompts, s.chat_window_minutes, s.chat_cooldown_minutes) == (10, 10, 20)
    monkeypatch.setenv("PITCHY_CHAT_MAX_PROMPTS", "5")
    assert Settings(_env_file=env_file).chat_max_prompts == 5
