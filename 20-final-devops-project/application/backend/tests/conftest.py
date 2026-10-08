"""Tests run against a real, SEPARATE PostgreSQL database (TEST_DATABASE_URL), never the app's.

The schema is created by running the Alembic migrations, so the migration itself is tested.
"""

import os

import pytest

TEST_DB = os.environ.get("TEST_DATABASE_URL")
if not TEST_DB:
    pytest.exit(
        "TEST_DATABASE_URL is not set — refusing to run tests against the application database", 2
    )
os.environ["DATABASE_URL"] = TEST_DB  # must happen before the app is imported

from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from alembic import command  # noqa: E402
from app.db import engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def migrated_schema():
    cfg = Config(os.path.join(os.path.dirname(__file__), "..", "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(os.path.dirname(__file__), "..", "alembic"))
    command.downgrade(cfg, "base")
    command.upgrade(cfg, "head")
    yield
    command.downgrade(cfg, "base")


@pytest.fixture(autouse=True)
def clean_table():
    with engine.begin() as conn:
        conn.execute(text("TRUNCATE incidents RESTART IDENTITY"))
    yield


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c
