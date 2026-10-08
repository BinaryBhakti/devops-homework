from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Severity = Literal["SEV1", "SEV2", "SEV3", "SEV4"]
Status = Literal["OPEN", "INVESTIGATING", "RESOLVED"]


class IncidentCreate(BaseModel):
    title: str = Field(min_length=3, max_length=200)
    description: str = Field(default="", max_length=5000)
    service: str = Field(default="unknown", min_length=1, max_length=80)
    severity: Severity = "SEV3"
    status: Status = "OPEN"
    assignee: str = Field(default="unassigned", max_length=120)


class IncidentUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    service: str | None = Field(default=None, min_length=1, max_length=80)
    severity: Severity | None = None
    status: Status | None = None
    assignee: str | None = Field(default=None, max_length=120)


class IncidentOut(IncidentCreate):
    id: int
    created_at: datetime
    resolved_at: datetime | None = None
    model_config = ConfigDict(from_attributes=True)


class StatsOut(BaseModel):
    total: int
    open: int
    investigating: int
    resolved: int
    sev1_open: int
