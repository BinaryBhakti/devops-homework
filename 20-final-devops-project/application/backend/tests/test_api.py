SEV1 = {
    "title": "Checkout returns 502",
    "service": "payments",
    "severity": "SEV1",
    "assignee": "on-call",
}


def create(client, **overrides):
    resp = client.post("/api/incidents", json={**SEV1, **overrides})
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_root_reports_service_name(client):
    body = client.get("/").json()
    assert body["service"] == "IncidentDesk API"


def test_health_is_up_without_touching_db(client):
    assert client.get("/health").json() == {"status": "UP"}


def test_ready_checks_the_database(client):
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.json() == {"status": "READY", "database": "ok"}


def test_create_and_get_incident(client):
    created = create(client)
    assert created["id"] == 1
    assert created["status"] == "OPEN"
    assert created["resolved_at"] is None
    fetched = client.get(f"/api/incidents/{created['id']}").json()
    assert fetched["title"] == "Checkout returns 502"


def test_list_newest_first_and_filter_by_status(client):
    create(client, title="first incident")
    create(client, title="second incident", status="INVESTIGATING")
    all_items = client.get("/api/incidents").json()
    assert [i["title"] for i in all_items] == ["second incident", "first incident"]
    investigating = client.get("/api/incidents", params={"status": "INVESTIGATING"}).json()
    assert [i["title"] for i in investigating] == ["second incident"]


def test_resolving_sets_resolved_at_and_reopening_clears_it(client):
    inc = create(client)
    resolved = client.put(f"/api/incidents/{inc['id']}", json={"status": "RESOLVED"}).json()
    assert resolved["status"] == "RESOLVED"
    assert resolved["resolved_at"] is not None
    reopened = client.put(f"/api/incidents/{inc['id']}", json={"status": "OPEN"}).json()
    assert reopened["resolved_at"] is None


def test_partial_update_keeps_other_fields(client):
    inc = create(client)
    updated = client.put(f"/api/incidents/{inc['id']}", json={"assignee": "sre-team"}).json()
    assert updated["assignee"] == "sre-team"
    assert updated["severity"] == "SEV1"


def test_delete_incident(client):
    inc = create(client)
    assert client.delete(f"/api/incidents/{inc['id']}").status_code == 204
    assert client.get(f"/api/incidents/{inc['id']}").status_code == 404


def test_unknown_incident_is_404_for_get_put_delete(client):
    assert client.get("/api/incidents/999").status_code == 404
    assert client.put("/api/incidents/999", json={"status": "RESOLVED"}).status_code == 404
    assert client.delete("/api/incidents/999").status_code == 404


def test_validation_rejects_bad_severity_and_short_title(client):
    assert client.post("/api/incidents", json={**SEV1, "severity": "SEV9"}).status_code == 422
    assert client.post("/api/incidents", json={**SEV1, "title": "x"}).status_code == 422
    assert client.get("/api/incidents", params={"status": "MAYBE"}).status_code == 422


def test_stats_counts_by_status_and_open_sev1(client):
    create(client)  # SEV1 OPEN
    create(client, severity="SEV3", status="INVESTIGATING")
    create(client, status="RESOLVED")  # SEV1 but resolved
    assert client.get("/api/incidents/stats").json() == {
        "total": 3,
        "open": 1,
        "investigating": 1,
        "resolved": 1,
        "sev1_open": 1,
    }


def test_metrics_endpoint_exposes_red_and_business_metrics(client):
    create(client)
    client.get("/api/incidents")
    body = client.get("/metrics").text
    assert "http_requests_total" in body
    assert 'incidents_created_total{severity="SEV1"}' in body


def test_no_cors_by_default(client):
    """Same-origin only: without CORS_ORIGINS no Access-Control-Allow-Origin header is sent."""
    r = client.get("/health", headers={"Origin": "https://evil.example"})
    assert r.status_code == 200
    assert "access-control-allow-origin" not in {k.lower() for k in r.headers}
