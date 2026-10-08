from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "IncidentDesk API"
    app_version: str = "1.0.0"  # set from the APP_VERSION env var at build time
    # Every real environment sets DATABASE_URL. The fallback deliberately has NO password:
    # an earlier version shipped "incidentdesk:incidentdesk@..." here and gitleaks flagged it.
    database_url: str = "postgresql+psycopg://incidentdesk@localhost:5432/incidentdesk"
    # Browser origins allowed to call the API directly (comma-separated, e.g. for a dev server on
    # another port). Empty by default: the frontend's nginx proxies /api on the SAME origin, so
    # the browser never needs CORS. The first pipeline run blocked the wildcard "*" this replaced.
    cors_origins: str = ""
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
