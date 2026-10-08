"""create incidents table

Revision ID: 0001_create_incidents
"""

import sqlalchemy as sa

from alembic import op

revision = "0001_create_incidents"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "incidents",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("service", sa.String(length=80), nullable=False, server_default="unknown"),
        sa.Column("severity", sa.String(length=10), nullable=False, server_default="SEV3"),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="OPEN"),
        sa.Column("assignee", sa.String(length=120), nullable=False, server_default="unassigned"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_incidents_status", "incidents", ["status"])


def downgrade():
    op.drop_index("ix_incidents_status", table_name="incidents")
    op.drop_table("incidents")
