"""Safety assessment contract (FR-SAF-001..007, FR-MAT-003, NFR-AUD-001).

Structure only. Indicator methods, thresholds and classification values are not defined here:
they come from approved sources (DEC-05, DEC-06, P-11). ``classification`` is therefore a free
string set by the deterministic engine, or null when the assessment is limited/unavailable.
"""

from enum import StrEnum
from uuid import UUID

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel, GuidanceReference, Limitation
from api.schemas.match import MatchContext
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


class HazardIndicator(ContractModel):
    hazard: Hazard
    status: IndicatorStatus
    indicator_value: float | None = Field(description="Calculated indicator, e.g. WBGT, if any.")
    indicator_unit: str | None
    classification: str | None = Field(description="Set only by approved deterministic rules.")
    basis: str | None = Field(description="Method/rule identifier the classification used.")
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
    id: UUID
    match_context: MatchContext
    assessed_at: AwareDatetime
    rule_version: str = Field(description="Version of the rule/configuration set (FR-SAF-005).")
    indicators: list[HazardIndicator]
    official_notices: list[OfficialNotice] = Field(default_factory=list)
    limitations: list[Limitation] = Field(default_factory=list)
