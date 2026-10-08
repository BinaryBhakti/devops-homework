from datetime import UTC, datetime

from sqlalchemy import DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def _now() -> datetime:
    return datetime.now(UTC)


class Incident(Base):
    __tablename__ = "incidents"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    service: Mapped[str] = mapped_column(String(80), nullable=False, default="unknown")
    severity: Mapped[str] = mapped_column(String(10), nullable=False, default="SEV3")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="OPEN")
    assignee: Mapped[str] = mapped_column(String(120), nullable=False, default="unassigned")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_now
    )
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
