"""Load and validate the safety rules file (P-12): ``thresholds/rules.yaml``.

Fails closed: an unknown key, a missing source, or heat levels that overlap or leave a gap raise
``RulesFileError`` at load time, so the engine never classifies with a broken rule set. This
module only reads rules and maps a value to a level; it makes no official decision.
"""

import math
from datetime import time
from functools import lru_cache
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator

RULES_PATH = Path(__file__).parent / "thresholds" / "rules.yaml"

# How strongly the app colours a level (P-19, team decision 2026-11-24). Display only: it never
# changes a level or a classification.
Severity = Literal["advisory", "warning", "danger"]


class RulesFileError(ValueError):
    """The rules file is missing, malformed or inconsistent."""


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class Source(_Strict):
    issuer: str
    title: str
    version: str
    section: str
    pages: str | None = None
    location: str


class Condition(_Strict):
    gte: float | None = None
    gt: float | None = None
    lt: float | None = None
    lte: float | None = None

    @model_validator(mode="after")
    def _one_side_each(self):
        if self.gte is not None and self.gt is not None:
            raise ValueError("use gte or gt, not both")
        if self.lt is not None and self.lte is not None:
            raise ValueError("use lt or lte, not both")
        if all(v is None for v in (self.gte, self.gt, self.lt, self.lte)):
            raise ValueError("a condition needs at least one bound")
        return self

    def matches(self, value: float) -> bool:
        return (
            (self.gte is None or value >= self.gte)
            and (self.gt is None or value > self.gt)
            and (self.lt is None or value < self.lt)
            and (self.lte is None or value <= self.lte)
        )

    def bounds(self) -> list[float]:
        return [v for v in (self.gte, self.gt, self.lt, self.lte) if v is not None]


class Level(_Strict):
    id: str
    when: Condition
    source: str
    also_supported_by: list[str] = Field(default_factory=list)
    label: str
    action: str
    severity: Severity | None = None  # display grade for the app's colour (P-19)


class LevelSet(_Strict):
    id: str
    applies_to: str
    levels: list[Level] = Field(min_length=1)

    def level_for(self, value: float) -> Level:
        if not math.isfinite(value):
            raise ValueError("WBGT must be a finite number")
        return next(level for level in self.levels if level.when.matches(value))

    def check_complete(self) -> None:
        """Every value must match exactly one level: probe each boundary and around it."""
        ids = [lv.id for lv in self.levels]
        if len(ids) != len(set(ids)):
            raise ValueError(f"level ids in set {self.id!r} must be unique")
        edges = sorted({b for lv in self.levels for b in lv.when.bounds()})
        probes = [-1e6, 1e6] + edges
        probes += [math.nextafter(e, -math.inf) for e in edges]
        probes += [math.nextafter(e, math.inf) for e in edges]
        for value in probes:
            hits = [lv.id for lv in self.levels if lv.when.matches(value)]
            if len(hits) != 1:
                raise ValueError(
                    f"set {self.id!r}: WBGT {value} matches {len(hits)} levels {hits}; need 1"
                )


class TimeWindow(_Strict):
    local_kickoff_between: tuple[time, time]
    timezone: str


class Notice(_Strict):
    id: str
    source: str
    applies_when: TimeWindow
    text: str


class NotApplied(_Strict):
    source: str
    rule: str
    reason: str


class HeatRules(_Strict):
    indicator: Literal["wbgt_outdoor"]
    unit: Literal["°C"]
    method: str
    measurement_note: str
    evaluate_at_minutes_before_kickoff: list[int] = Field(min_length=1)
    decided_by: str
    level_sets: list[LevelSet] = Field(min_length=1)
    notices: list[Notice] = Field(default_factory=list)
    not_applied: list[NotApplied] = Field(default_factory=list)

    def level_set(self, set_id: str = "senior") -> LevelSet:
        for level_set in self.level_sets:
            if level_set.id == set_id:
                return level_set
        raise KeyError(f"no heat level set {set_id!r}")

    def level_for(self, value: float, set_id: str = "senior") -> Level:
        return self.level_set(set_id).level_for(value)


class NoRule(_Strict):
    status: Literal["no_approved_rule"]
    reason: str
    show_instead: str


class DistanceLevel(_Strict):
    id: str
    when: Condition
    unit: Literal["km"]
    source: str
    basis: str
    label: str
    action: str
    severity: Severity | None = None  # display grade for the app's colour (P-19)


class LightningGuidance(_Strict):
    """Official on-site procedure shown as guidance; never an automatic "stop play"."""

    status: Literal["guidance_only"]
    source: str
    procedure: list[str] = Field(min_length=1)
    applies_note: str
    show_when: str
    distance_levels: list[DistanceLevel] = Field(default_factory=list)
    reason: str

    def level_for_distance(self, km: float | None) -> DistanceLevel | None:
        if km is None or not math.isfinite(km) or km < 0:
            return None
        return next((lv for lv in self.distance_levels if lv.when.matches(km)), None)


class Hazards(_Strict):
    heat: HeatRules
    lightning: LightningGuidance | NoRule
    rainfall: NoRule


class RuleSet(_Strict):
    schema_version: Literal[1]
    rule_set_version: str
    status: Literal["draft", "approved"]
    sources: dict[str, Source]
    hazards: Hazards

    @property
    def approved(self) -> bool:
        return self.status == "approved"

    @model_validator(mode="after")
    def _consistent(self):
        heat = self.hazards.heat
        used = [lv.source for ls in heat.level_sets for lv in ls.levels]
        used += [x for ls in heat.level_sets for lv in ls.levels for x in lv.also_supported_by]
        used += [n.source for n in heat.notices] + [n.source for n in heat.not_applied]
        lightning = self.hazards.lightning
        if isinstance(lightning, LightningGuidance):
            used.append(lightning.source)
            used += [lv.source for lv in lightning.distance_levels]
            edges = sorted({b for lv in lightning.distance_levels for b in lv.when.bounds()})
            for value in [0.0, *edges, *(math.nextafter(e, math.inf) for e in edges)]:
                hits = [lv.id for lv in lightning.distance_levels if lv.when.matches(value)]
                if len(hits) > 1:
                    raise ValueError(f"lightning distance {value} km matches {hits}; need <= 1")
        unknown = sorted(set(used) - set(self.sources))
        if unknown:
            raise ValueError(f"unknown source(s): {', '.join(unknown)}")
        set_ids = [ls.id for ls in heat.level_sets]
        if len(set_ids) != len(set(set_ids)) or "senior" not in set_ids:
            raise ValueError("heat level sets need unique ids and a 'senior' set")
        for level_set in heat.level_sets:
            level_set.check_complete()
        return self


def load_rules(path: Path = RULES_PATH) -> RuleSet:
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise RulesFileError(f"Cannot read rules file {path.name}: {exc}") from None
    except yaml.YAMLError as exc:
        raise RulesFileError(f"Rules file {path.name} is not valid YAML: {exc}") from None
    try:
        return RuleSet.model_validate(raw)
    except ValidationError as exc:
        raise RulesFileError(f"Rules file {path.name} is invalid:\n{exc}") from None


@lru_cache
def get_rules() -> RuleSet:
    return load_rules()
