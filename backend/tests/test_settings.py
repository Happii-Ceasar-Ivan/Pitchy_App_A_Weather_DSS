import pytest
from pydantic import ValidationError

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


def test_pagasa_gap_defaults_to_four_hours_and_is_bounded(env_file, monkeypatch) -> None:
    """P-27 A3: a setting, shipped at the decided 240 min; 60-240 only."""
    from datetime import timedelta

    from api.routes.match_contexts import gap_text
    from services.weather_ingestion.registry import adapter_groups

    s = Settings(_env_file=env_file)
    assert s.pagasa_min_interval_minutes == 240 and gap_text(s) == "4 hours"
    pagasa = next(g for g in adapter_groups(s) if g.name == "pagasa")
    assert pagasa.min_interval == timedelta(hours=4) and pagasa.run_check
    monkeypatch.setenv("PITCHY_PAGASA_MIN_INTERVAL_MINUTES", "120")
    s = Settings(_env_file=env_file)
    assert gap_text(s) == "2 hours"
    assert next(g for g in adapter_groups(s) if g.name == "pagasa").min_interval == timedelta(
        hours=2
    )
    monkeypatch.setenv("PITCHY_PAGASA_MIN_INTERVAL_MINUTES", "90")
    assert gap_text(Settings(_env_file=env_file)) == "90 minutes"
    for bad in ("59", "241"):
        monkeypatch.setenv("PITCHY_PAGASA_MIN_INTERVAL_MINUTES", bad)
        with pytest.raises(ValidationError):
            Settings(_env_file=env_file)


def test_openweather_key_is_masked_and_its_group_waits_an_hour(env_file, monkeypatch) -> None:
    """P-30: secret key, 7 h freshness, 60 min per-venue gap, 15 min cool-down."""
    from datetime import timedelta

    from services.weather_ingestion.registry import adapter_groups

    monkeypatch.delenv("OPENWEATHER_API_KEY", raising=False)
    s = Settings(_env_file=env_file)
    assert s.openweather_api_key is None and s.fresh_openweather_hours == 7
    group = next(g for g in adapter_groups(s) if g.name == "openweather")
    assert group.source_ids == ("openweather",) and not group.run_check
    assert group.min_interval == timedelta(minutes=60)
    assert group.failure_cooldown == timedelta(minutes=15)
    monkeypatch.setenv("OPENWEATHER_API_KEY", "not-a-real-ow-key")
    s = Settings(_env_file=env_file)
    assert s.openweather_api_key.get_secret_value() == "not-a-real-ow-key"
    assert "not-a-real-ow-key" not in repr(s)
