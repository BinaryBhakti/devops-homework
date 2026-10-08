# Where the pipeline lives

GitHub Actions only runs workflow files from the **repository root** `/.github/workflows/`. This
project is one folder inside the `devops-homework` monorepo, so its pipeline is:

**[`/.github/workflows/hw20-final.yml`](../../../.github/workflows/hw20-final.yml)**

It is path-filtered to `20-final-devops-project/**` (plus the workflow file itself), so changes to
other homeworks never trigger it, and every `run:` step defaults to this folder as its working
directory. Runs: <https://github.com/BinaryBhakti/devops-homework/actions/workflows/hw20-final.yml>

A copy or symlink here would not run (GitHub ignores nested `.github` folders) and would drift from
the real file, so this README points at it instead.
