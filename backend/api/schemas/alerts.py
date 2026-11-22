"""Official alerts contract (FR-SAF-007). Shown as issued by PAGASA, never as a Pitchy
classification. All text fields are plain text from an untrusted source: never render as HTML."""

from typing import Literal

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel
from api.schemas.weather import AlertsStatus

OFFICIAL_LABEL = "Official PAGASA information, shown as issued. Not a Pitchy classification."


class AlertArea(ContractModel):
    name: str = Field(description="Municipality or province name, as issued.")
    code: str = Field(description="9-digit PSGC code.")
    level: Literal["municipality", "province"]
    relation: str = Field(description="PAGASA's own wording, e.g. affecting, watch.")


class OfficialAlertOut(ContractModel):
    issuer: str
    event: str
    subtype: str
    headline: str = Field(description="Plain text. Never render as HTML.")
    message: str = Field(description="Plain text. Never render as HTML.")
    issued_at: AwareDatetime | None
    valid_until: AwareDatetime | None
    matched_areas: list[AlertArea] = Field(description="The areas that include this venue.")


class VenueAlerts(ContractModel):
    venue: str
    status: AlertsStatus
    active_tropical_cyclones: int | None = Field(
        description="Count from PAGASA's cyclone track at the last successful check."
    )
    alerts: list[OfficialAlertOut] = Field(
        description="Alerts covering this venue and not past valid_until."
    )
    label: str = OFFICIAL_LABEL
