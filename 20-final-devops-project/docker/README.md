# Docker — the full stack locally

```bash
cd 20-final-devops-project/docker
docker compose up --build            # UI http://localhost:3000   API http://localhost:8000/docs
FRONTEND_PORT=3080 docker compose up --build   # if 3000 is taken (it was on the machine this was built on)
docker compose down -v               # stop and delete the database volume
```

| Service | Image | Notes |
|---|---|---|
| `postgres` | `postgres:16-alpine` | named volume `pgdata`; healthcheck `pg_isready` |
| `backend` | built from `../application/backend` | waits for a **healthy** database (`depends_on: condition: service_healthy`), runs `alembic upgrade head`, then uvicorn; runs as uid 10001 |
| `frontend` | built from `../application/frontend` | multi-stage: Node builds, unprivileged nginx (uid 101, port 8080) serves and proxies `/api` to `$BACKEND_URL` |

Every service has `cpus: 1` and a memory cap: this stack shares a laptop with a 2-node Minikube,
and an uncapped build or load test has already starved that cluster's control plane once.

The database password defaults to `local-dev-only` — a throwaway for a database that exists only
inside your Docker. Override it with `POSTGRES_PASSWORD` in a `.env` file for anything shared.
