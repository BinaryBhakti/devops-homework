import pytest

from app.main import create_app


@pytest.fixture
def client():
    return create_app().test_client()


def test_index(client):
    body = client.get("/").get_json()
    assert body["app"] == "hw15-calculator"
    assert "divide" in body["operations"]


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_add_endpoint(client):
    body = client.get("/api/add?a=2&b=3").get_json()
    assert body["result"] == 5


def test_divide_by_zero_is_400(client):
    resp = client.get("/api/divide?a=1&b=0")
    assert resp.status_code == 400
    assert "divide by zero" in resp.get_json()["error"]


def test_missing_param_is_400(client):
    assert client.get("/api/add?a=2").status_code == 400


def test_non_numeric_is_400(client):
    assert client.get("/api/add?a=two&b=3").status_code == 400


def test_unknown_operation_is_400(client):
    assert client.get("/api/power?a=2&b=3").status_code == 400
