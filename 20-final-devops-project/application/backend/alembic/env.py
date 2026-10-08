from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool, text

from alembic import context
from app import models  # noqa: F401 — registers the tables on Base.metadata
from app.config import settings
from app.db import Base

config = context.config
config.set_main_option("sqlalchemy.url", settings.database_url)
if config.config_file_name:
    fileConfig(config.config_file_name)
target_metadata = Base.metadata


def run_migrations_offline():
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online():
    connectable = engine_from_config(
        config.get_section(config.config_ini_section), prefix="sqlalchemy.", poolclass=pool.NullPool
    )
    with connectable.connect() as connection:
        if connection.dialect.name == "postgresql":
            # Several replicas may start at once and all run `alembic upgrade head`.
            # A session-level advisory lock makes them take turns instead of racing.
            connection.execute(text("SELECT pg_advisory_lock(20262021)"))
            connection.commit()
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
