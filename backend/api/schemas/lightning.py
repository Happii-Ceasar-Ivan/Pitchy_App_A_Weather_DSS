"""Live lightning contract (DEC-06). Measured detection near the venue, never a Pitchy decision."""

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel
from api.schemas.weather import Attribution, CoverageWindow, WeatherDataState


class FlashOut(ContractModel):
    detected_at: AwareDatetime
    distance_km: float = Field(
        description="Great-circle distance from the venue, computed by Pitchy."
    )
    latitude: float
    longitude: float


class LightningStatus(ContractModel):
    state: WeatherDataState = Field(
        description="current while the last check is under 5 minutes old; stale after that."
    )
    last_checked_at: AwareDatetime | None = Field(description="Last successful check.")
    current_until: AwareDatetime | None
    last_error_code: str | None = Field(
        default=None, description="Set when the latest attempt failed."
    )


class OfficialGuidance(ContractModel):
    """Official procedure, shown as issued. Officials decide on site (AFC art. 8.3)."""

    source: str = Field(examples=["AFC Competition Operations Manual, Edition 2026, art. 8.3"])
    procedure: list[str]
    applies_note: str
    shown_because: list[str] = Field(examples=[["LIGHTNING_DETECTED", "PAGASA_THUNDERSTORM_ALERT"]])


class LightningLevel(ContractModel):
    """Approved distance level for the nearest flash (team decision 2026-11-23)."""

    id: str = Field(examples=["within_30_second_distance"])
    label: str
    action: str
    basis: str = Field(
        description="Where the level comes from (AFC 30 s ≈ 10 km, Pitchy's conversion)."
    )


class VenueLightning(ContractModel):
    venue: str
    live_window: CoverageWindow = Field(
        description="Live checks happen only in this window (before kickoff to match end)."
    )
    in_live_window: bool
    status: LightningStatus
    radius_km: float
    detection_minutes: int = Field(description="Each check covers this many minutes back.")
    flash_count: int | None = Field(
        description="Flashes in the last successful check; null if none yet."
    )
    nearest_km: float | None
    latest_flash_at: AwareDatetime | None
    flashes: list[FlashOut] = Field(description="Nearest first, from the last successful check.")
    level: LightningLevel | None = Field(
        description="Set only when a current check found lightning inside an approved distance"
        " level. Null otherwise; null never means safe."
    )
    guidance: OfficialGuidance | None
    attribution: Attribution
    note: str = Field(
        description="Plain-language reminder of what the data is and is not; always show it."
    )
