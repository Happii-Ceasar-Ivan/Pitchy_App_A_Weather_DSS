"""Safety assessment contract (FR-SAF-001..007, FR-MAT-003, NFR-AUD-001).

Levels, actions and sources come only from the approved rules file (P-12,
``services/safety_engine/thresholds/rules.yaml``). ``classification`` is the level id set by the
deterministic engine, or null when no approved rule applies or the inputs are not current.
Pitchy explains the rules; the official decision stays with the people named in ``decided_by``.
"""

from enum import StrEnum
from uuid import UUID

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel, GuidanceReference, Limitation
from api.schemas.match import AgeGroup, MatchContext
from api.schemas.weather import Provenance


class Hazard(StrEnum):
    """Hazards the engine assesses (P-04). Alerts and cyclone signals are official info, below."""

    HEAT = "heat"
    LIGHTNING = "lightning"
    RAINFALL = "rainfall"


class IndicatorStatus(StrEnum):
    AVAILABLE = "available"
    LIMITED = "limited"
    UNAVAILABLE = "unavailable"


class InputValue(ContractModel):
    """A weather value the engine used, with its provenance (FR-CLI-004)."""

    parameter: str = Field(description="Parameter code. The list is OPEN (DEC-03).")
    value: float | None
    unit: str | None
    provenance: Provenance


class AssessmentLevel(ContractModel):
    """The approved rule level that applies, with what the rule says to do and its source."""

    id: str = Field(examples=["cooling_breaks_required"])
    label: str
    action: str = Field(description="What the source says officials do at this level.")
    source: GuidanceReference
    also_supported_by: list[GuidanceReference] = Field(default_factory=list)


class IndicatorPoint(ContractModel):
    """The indicator at one time (heat: WBGT for one forecast hour)."""

    at: AwareDatetime = Field(description="The time this value stands for.")
    forecast_stamp: AwareDatetime = Field(
        description="Open-Meteo stamp used: instant values at it, radiation the hour before."
    )
    value: float | None
    used_for_level: bool = Field(description="True for the value that set the level.")
    missing: list[str] = Field(default_factory=list, description="Inputs that were missing.")


class RuleNotice(ContractModel):
    """Official guidance shown as information; it never changes the level (e.g. PFF midday)."""

    id: str
    text: str
    source: GuidanceReference


class HazardIndicator(ContractModel):
    hazard: Hazard
    status: IndicatorStatus
    indicator_value: float | None = Field(description="Calculated indicator, e.g. WBGT, if any.")
    indicator_unit: str | None
    classification: str | None = Field(
        description="Level id from the approved rules; null without a rule or current inputs."
    )
    level: AssessmentLevel | None = None
    basis: str | None = Field(description="Method and level set the classification used.")
    decided_by: str | None = Field(
        default=None, description="Who makes the official decision under the source rules."
    )
    points: list[IndicatorPoint] = Field(
        default_factory=list,
        description="Heat: WBGT at the FIFA measurement times (90 and 60 min before kickoff).",
    )
    hourly: list[IndicatorPoint] = Field(
        default_factory=list, description="Heat: WBGT for each hour of the match (information)."
    )
    notices: list[RuleNotice] = Field(default_factory=list)
    procedure: list[str] = Field(
        default_factory=list, description="Lightning: the official on-site procedure, when shown."
    )
    inputs: list[InputValue] = Field(default_factory=list)
    limitations: list[Limitation] = Field(default_factory=list)
    guidance: list[GuidanceReference] = Field(default_factory=list)


class OfficialNotice(ContractModel):
    """Official alert or cyclone signal, shown as issued; never turned into a classification."""

    kind: str = Field(examples=["severe_weather_alert", "tropical_cyclone_signal"])
    issuer: str
    title: str
    issued_at: AwareDatetime | None
    valid_until: AwareDatetime | None
    provenance: Provenance


class SafetyAssessment(ContractModel):
    id: UUID = Field(description="The saved assessment (a new one only when inputs change).")
    match_context: MatchContext
    assessed_at: AwareDatetime = Field(description="When this assessment was first saved.")
    checked_at: AwareDatetime = Field(description="When the inputs were last checked.")
    age_group: AgeGroup
    rules_approved: bool
    rule_version: str = Field(description="Version of the rule/configuration set (FR-SAF-005).")
    indicators: list[HazardIndicator]
    official_notices: list[OfficialNotice] = Field(default_factory=list)
    limitations: list[Limitation] = Field(default_factory=list)
