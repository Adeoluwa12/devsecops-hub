# devsecops-hub

A small Flask application used as a **reference DevSecOps pipeline**. The goal is not the app itself but to answer one question honestly: *when you add security scanners to CI/CD, what do they actually catch, and what slips through?*

To find out, the pipeline was run twice against pull requests: once clean (a baseline) and once with deliberately planted flaws.

> **Everything planted is intentional and lives only in pull request #3, never on `main`.** All credentials used in the demo are randomly generated fakes, not real secrets.

## The pipeline

Defined in [`.github/workflows`](.github/workflows) and run on every pull request to `main`:

| Stage | Tool | What it checks |
|---|---|---|
| Lint and unit tests | ruff, pytest | Code style and basic behavior |
| Secrets scan | Gitleaks | Credentials committed in the pull request's commits |
| SAST | CodeQL | Insecure code patterns in the Python source |
| Dependency scan (SCA) | pip-audit | Known vulnerabilities in `requirements.txt` |
| IaC scan | Checkov | Misconfigurations in the Terraform under [`infra`](infra) |
| Container build and image scan | Docker, Trivy | Vulnerabilities in the built image; fails on HIGH and CRITICAL |

The container stage runs only after the lint and unit test stage succeeds (`needs`), which turned out to matter (see below).

## The experiment

| Run | Pull request | Purpose |
|---|---|---|
| Baseline | [#2](../../pull/2) | Clean branch, all nine checks passed |
| Planted flaws | [#3](../../pull/3) | One flaw planted per scanner layer |

Baseline stage durations: lint and test 18s, secrets 16s, dependency scan 20s, IaC 37s, SAST 54s, build and image scan 1m.

### Planted flaws

- **SAST:** a SQL query built from user input, `eval()` on user input, and Flask running in debug mode
- **Secrets:** a first fake credential, later replaced with a well-formed fake GitHub token and a fake private key
- **SCA:** an outdated pinned dependency with known vulnerabilities
- **IaC:** an insecure Terraform storage account configuration
- **Container:** an outdated base image

## Results

| Layer | Result | Notes |
|---|---|---|
| SAST (CodeQL) | Caught all 3 flaws | The `sast` job itself passed; the separate code scanning check failed the pull request on the critical alert |
| SCA (pip-audit) | Caught | Job failed in 20s |
| IaC (Checkov) | Caught | Alerts rose from 8 (baseline) to 12; job failed |
| Secrets (Gitleaks) | Missed the first planted credential, caught the second set | A well-formed GitHub token (rule `github-pat`) and a private key (rule `private-key`) failed the job in 9s |
| Container (Trivy) | Skipped, then failed the build | See the second lesson below |
| Lint and unit tests | Failed | A harmless change to the `/health` response text broke `test_health` |

## What I learned

1. **Scanners match patterns, not intent.** The secrets scanner passed the first planted credential, then fired immediately on two formats it has rules for. A secret in a shape the scanner does not recognize will pass a green check.
2. **Gate ordering can hide a security scan.** One failing unit test caused the container image scan to be skipped entirely, because the image job depended on the test job. The pull request looked "mostly green" while a whole security layer had not run. Security scans should not sit behind unrelated jobs.
3. **A passing job is not the same as a passing gate.** CodeQL's job succeeded while code scanning blocked the pull request. Know where each tool actually enforces.
4. **The Gitleaks job scans only the pull request's commits.** A secret already in the history of `main` would not be re-scanned by this configuration, so a periodic full-history scan is a useful complement.

## What is next

This repository covers the CI half of the story. Planned next steps, not yet built:

- Reproduce the same gaps at the cluster level with **Kyverno** admission policies (for example rejecting containers that run as root, or images that are not signed)
- Detect runtime behavior that no pre-deployment scanner can see using **Falco**
- Make the container scan independent of the unit test stage and re-measure stage timings

## Running locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
pytest
python app.py
```

The app listens on port 8080 by default and exposes a `/health` endpoint.

## Disclaimer

This is an educational reference project. The planted flaws in pull request #3 are deliberately insecure and must never be deployed.