"""IncidentDesk API — track production incidents from detection to resolution."""

from datetime import UTC, datetime

from fastapi import Depends, FastAPI, HTTPException, Query, Response, status
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .models import Incident
from .schemas import IncidentCreate, IncidentOut, IncidentUpdate, StatsOut, Status

app = FastAPI(title=settings.app_name, version=settings.app_version)
_origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
if _origins:  # no middleware at all when nothing is allowed — same-origin only
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_origins,
        allow_methods=["GET", "POST", "PUT", "DELETE"],
        allow_headers=["Content-Type"],
    )

# RED metrics for every route (http_requests_total, http_request_duration_seconds) on /metrics.
Instrumentator(excluded_handlers=["/metrics", "/health", "/ready"]).instrument(app).expose(
    app, endpoint="/metrics", include_in_schema=False
)
INCIDENTS_CREATED = Counter("incidents_created_total", "Incidents opened", ["severity"])
INCIDENTS_RESOLVED = Counter("incidents_resolved_total", "Incidents resolved", ["severity"])


def _get_or_404(db: Session, incident_id: int) -> Incident:
    incident = db.get(Incident, incident_id)
    if incident is None:
        raise HTTPException(status_code=404, detail="Incident not found")
    return incident


@app.get("/")
def root():
    return {"service": settings.app_name, "version": settings.app_version, "docs": "/docs"}


@app.get("/health")
def health():
    """Liveness: the process is up and serving. Deliberately does NOT touch the database."""
    return {"status": "UP"}


@app.get("/ready")
def ready(response: Response, db: Session = Depends(get_db)):
    """Readiness: only take traffic when the database answers."""
    try:
        db.execute(text("SELECT 1"))
    except Exception:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "NOT_READY", "database": "unreachable"}
    return {"status": "READY", "database": "ok"}


@app.get("/api/incidents", response_model=list[IncidentOut])
def list_incidents(
    status_filter: Status | None = Query(default=None, alias="status"),
    db: Session = Depends(get_db),
):
    query = select(Incident).order_by(Incident.id.desc())
    if status_filter:
        query = query.where(Incident.status == status_filter)
    return list(db.scalars(query))


@app.get("/api/incidents/stats", response_model=StatsOut)
def stats(db: Session = Depends(get_db)):
    rows = db.execute(
        select(Incident.status, func.count(Incident.id)).group_by(Incident.status)
    ).all()
    counts = {s: c for s, c in rows}
    sev1_open = db.scalar(
        select(func.count(Incident.id)).where(
            Incident.severity == "SEV1", Incident.status != "RESOLVED"
        )
    )
    return StatsOut(
        total=sum(counts.values()),
        open=counts.get("OPEN", 0),
        investigating=counts.get("INVESTIGATING", 0),
        resolved=counts.get("RESOLVED", 0),
        sev1_open=sev1_open or 0,
    )


@app.get("/api/incidents/{incident_id}", response_model=IncidentOut)
def get_incident(incident_id: int, db: Session = Depends(get_db)):
    return _get_or_404(db, incident_id)


@app.post("/api/incidents", response_model=IncidentOut, status_code=status.HTTP_201_CREATED)
def create_incident(payload: IncidentCreate, db: Session = Depends(get_db)):
    incident = Incident(**payload.model_dump())
    if incident.status == "RESOLVED":
        incident.resolved_at = datetime.now(UTC)
    db.add(incident)
    db.commit()
    db.refresh(incident)
    INCIDENTS_CREATED.labels(incident.severity).inc()
    return incident


@app.put("/api/incidents/{incident_id}", response_model=IncidentOut)
def update_incident(incident_id: int, payload: IncidentUpdate, db: Session = Depends(get_db)):
    incident = _get_or_404(db, incident_id)
    was_resolved = incident.status == "RESOLVED"
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(incident, key, value)
    if incident.status == "RESOLVED" and not was_resolved:
        incident.resolved_at = datetime.now(UTC)
        INCIDENTS_RESOLVED.labels(incident.severity).inc()
    elif incident.status != "RESOLVED":
        incident.resolved_at = None
    db.commit()
    db.refresh(incident)
    return incident


@app.delete("/api/incidents/{incident_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_incident(incident_id: int, db: Session = Depends(get_db)):
    incident = _get_or_404(db, incident_id)
    db.delete(incident)
    db.commit()
