"""The safety rules file (P-12) loads, is consistent, and fails closed when broken."""

import copy
from pathlib import Path

import pytest
import yaml

from services.safety_engine.rules import RULES_PATH, RulesFileError, load_rules

RAW = yaml.safe_load(RULES_PATH.read_text(encoding="utf-8"))


def _write(tmp_path: Path, data: dict) -> Path:
    path = tmp_path / "rules.yaml"
    path.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    return path


def test_committed_rules_load_and_cite_their_sources() -> None:
    rules = load_rules()
    heat = rules.hazards.heat
    assert rules.status == "approved" and rules.approved
    assert {lv.source for lv in heat.level_set("senior").levels} == {"fifa_ecm_2022"}
    assert {lv.source for lv in heat.level_set("youth_u20").levels} == {"afc_com_2026"}
    assert rules.sources["fifa_ecm_2022"].issuer == "FIFA"
    assert heat.evaluate_at_minutes_before_kickoff == [90, 60]


@pytest.mark.parametrize(
    ("wbgt", "level"),
    [(31.99, "below_cooling_break_level"), (32.0, "cooling_breaks_required"),
     (35.5, "cooling_breaks_required"), (-5.0, "below_cooling_break_level")],
)  # fmt: skip
def test_fifa_cooling_break_level_is_32_inclusive(wbgt, level) -> None:
    assert load_rules().hazards.heat.level_for(wbgt).id == level


def test_below_32_is_never_called_safe() -> None:
    text = load_rules().hazards.heat.level_for(25.0).action.lower()
    assert "not a statement that conditions are safe" in text


@pytest.mark.parametrize(
    ("wbgt", "level"),
    [(27.99, "below_cooling_break_level"), (28.0, "cooling_breaks_required")],
)
def test_afc_youth_level_is_28_inclusive(wbgt, level) -> None:
    assert load_rules().hazards.heat.level_for(wbgt, "youth_u20").id == level


def test_lightning_is_guidance_only_and_rain_has_no_rule() -> None:
    hazards = load_rules().hazards
    assert hazards.lightning.status == "guidance_only"
    assert hazards.lightning.source == "afc_com_2026"
    assert any("30 minutes" in step for step in hazards.lightning.procedure)
    assert hazards.rainfall.status == "no_approved_rule"


@pytest.mark.parametrize(
    ("km", "level"),
    [(0.0, "within_30_second_distance"), (10.0, "within_30_second_distance"),
     (10.01, None), (39.0, None), (None, None), (-1.0, None)],
)  # fmt: skip
def test_lightning_10_km_level(km, level) -> None:
    found = load_rules().hazards.lightning.level_for_distance(km)
    assert (found.id if found else None) == level


def test_non_finite_wbgt_is_refused() -> None:
    with pytest.raises(ValueError):
        load_rules().hazards.heat.level_for(float("nan"))


def _senior(data):
    return data["hazards"]["heat"]["level_sets"][0]["levels"]


def _broken(mutate):
    data = copy.deepcopy(RAW)
    mutate(data)
    return data


@pytest.mark.parametrize(
    "mutate",
    [
        lambda d: _senior(d)[0].update(source="made_up"),
        lambda d: _senior(d)[0].update(also_supported_by=["made_up"]),
        lambda d: _senior(d)[1]["when"].update(lt=31.0),  # gap 31..32
        lambda d: _senior(d)[1]["when"].update(lt=33.0),  # overlap 32..33
        lambda d: _senior(d)[0].update(colour="red"),  # unknown key
        lambda d: _senior(d)[0].update(severity="red"),  # not a severity
        lambda d: d["hazards"]["lightning"]["distance_levels"][0].update(severity="critical"),
        lambda d: d["hazards"]["heat"]["level_sets"][0].update(id="adult"),  # no senior set
        lambda d: d["hazards"]["lightning"].update(source="made_up"),
        lambda d: d["hazards"]["lightning"]["distance_levels"].append(
            dict(d["hazards"]["lightning"]["distance_levels"][0], id="dup")
        ),  # overlap
        lambda d: d["hazards"]["lightning"]["distance_levels"][0].update(unit="miles"),
        lambda d: d.update(status="final"),
        lambda d: d["hazards"]["lightning"].update(status="approved"),
        lambda d: d["hazards"]["heat"].update(unit="°F"),
    ],
)
def test_broken_rules_files_are_refused(tmp_path, mutate) -> None:
    with pytest.raises(RulesFileError):
        load_rules(_write(tmp_path, _broken(mutate)))


def test_missing_or_invalid_yaml_is_refused(tmp_path) -> None:
    with pytest.raises(RulesFileError):
        load_rules(tmp_path / "nope.yaml")
    bad = tmp_path / "bad.yaml"
    bad.write_text("hazards: [unclosed", encoding="utf-8")
    with pytest.raises(RulesFileError):
        load_rules(bad)


def test_every_level_has_the_team_severity() -> None:
    """P-19 (team decision 2026-11-24): display grade only, set per level in rules.yaml."""
    rules = load_rules()
    for level_set in rules.hazards.heat.level_sets:
        grades = {lvl.id: lvl.severity for lvl in level_set.levels}
        assert grades == {"cooling_breaks_required": "warning",
                          "below_cooling_break_level": "advisory"}  # fmt: skip
    assert [d.severity for d in rules.hazards.lightning.distance_levels] == ["danger"]


def test_severity_is_optional(tmp_path) -> None:
    data = copy.deepcopy(RAW)
    del _senior(data)[0]["severity"]
    assert _senior_levels(load_rules(_write(tmp_path, data)))[0].severity is None


def _senior_levels(rules):
    return rules.hazards.heat.level_sets[0].levels
