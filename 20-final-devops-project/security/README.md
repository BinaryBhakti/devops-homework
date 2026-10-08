# DevSecOps — what is scanned, with what, and what blocks a release

| Stage | Tool | Scans | Config here |
|---|---|---|---|
| **SAST** | Semgrep (`p/python`, `p/dockerfile` + project rules) | our source code for injection, debug mode, shell=True, inline credentials | [`semgrep.yml`](semgrep.yml) |
| **SAST** | Bandit | Python-specific insecure patterns | [`bandit.yaml`](bandit.yaml) |
| **SCA** | pip-audit | `requirements.txt` against the PyPA advisory DB + OSV | — |
| **SCA** | npm audit | production npm dependencies | — |
| **SCA / IaC** | Trivy `fs` | lockfiles, Dockerfiles, Kubernetes/Helm/Terraform misconfiguration, stray secrets | [`trivy.yaml`](trivy.yaml), [`.trivyignore`](.trivyignore) |
| **Secrets** | gitleaks | the **whole Git history** of the project, not just the current tree | [`gitleaks.toml`](gitleaks.toml) |
| **Image** | Trivy `image` | OS packages + language packages inside the built images | [`.trivyignore`](.trivyignore) |

## The security gate

The `security-gate` job in [`hw20-final.yml`](../../.github/workflows/hw20-final.yml) runs after
every scanner (`if: always()`), writes a table of results to the run summary, and **fails unless
every check succeeded**. `push` depends on the gate, so an image that failed any check is never
published, and `deploy`/`gitops` never see it.

| Finding | Policy |
|---|---|
| CRITICAL or HIGH vulnerability **with a fixed version** (deps or image) | **block** — upgrade |
| CRITICAL or HIGH with **no fix available** | allow, tracked — `--ignore-unfixed`; re-checked every run, so it blocks the day a fix ships |
| MEDIUM / LOW | report only |
| Any Semgrep finding (`--error`: every reported result fails the step) or a Bandit issue of MEDIUM+ severity (`-ll`) | **block** |
| Any secret in any commit of the project | **block** — and rotate the secret: deleting the commit does not un-leak it |
| Kubernetes/Dockerfile misconfiguration rated HIGH+ | **block** |

## Accepting a risk

Only through `.trivyignore`, one line per finding, each with a justification and a review date
in a comment, and only via a reviewed pull request. An entry without a reason is rejected.

## Secrets in this project

- No real credential is committed. The only password-shaped strings are `local-dev-only`
  (Compose and `values-dev.yaml`, a throwaway for a database that exists only on a laptop or in an
  ephemeral CI cluster) and documented placeholders (`change-me`, `REPLACE_ME`). Each is
  allow-listed **by exact value** in `gitleaks.toml`, so a *different* password in the same
  place still fails the scan.
- CI generates the database password for its kind cluster at deploy time (`openssl rand`).
- Production uses `postgres.existingSecret`, created outside Git.
