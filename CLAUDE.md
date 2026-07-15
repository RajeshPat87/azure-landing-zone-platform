# CLAUDE.md — Azure Landing Zone Platform

Terraform platform-engineering repo (Azure Landing Zone blueprint). Read this before acting.

## What this repo is
- `modules/` — reusable building blocks (MGs, governance, core-services, identity, hub/spoke network, subscription vending).
- `environments/` — deployable root compositions, **each its own Terraform state boundary**: `mgmt`, `connectivity`, `landingzone-prod` (one tfvars per app).
- Deploy order: `bootstrap-state.sh → mgmt → connectivity → landingzone-prod`.
- Auth in CI is **OIDC** (no stored secrets). Locally, auth is the rotating **Azure lab SP** (see below).

## Guardrails are enforced by hooks (not optional)
This repo ships `.claude/` guardrails — the 20-hook lifecycle in
`.claude/skills/infra-safety-hooks/SKILL.md`. You will hit these; work with them:

- **Never** print or read `*.tfstate`, `*.tfvars`, `az` tokens, or Key Vault secret values.
- **Never** mutate state directly (`terraform state rm`, `force-unlock`) — fix via config + plan.
- `terraform apply`/`destroy` and live `az` mutations (`delete`, `role assignment`) are **ASK-gated**. Produce a reviewed plan first.
- Editing `providers.tf`, `backend.hcl`, governance/identity/MG modules, or CI workflows is **ASK-gated** — tenant-wide blast radius.
- Before `apply`/`destroy` in a prod/mgmt dir, **confirm the active subscription is the intended target** (`az account show`).

## Working conventions
- Change infra through Terraform, not imperative `az` commands. `az` is for read-only inspection.
- Run `terraform fmt -recursive` before finishing — the Definition-of-Done gate blocks otherwise.
- One landing zone = one new tfvars file + one pipeline run; never fork module code per app.
- Respect state isolation: a change in one environment must not require re-planning another.
- Real `*.tfvars` are secrets and gitignored; only edit/commit `*.tfvars.example`.

## Azure lab credentials (rotate ~1h)
Local Azure auth comes from a shared creds file that the lab refreshes hourly.
- Point Claude at it once: `export ALZ_AZURE_CREDS_FILE=/path/to/lab-creds.json` (JSON or `.env`).
- `.claude/scripts/azure-lab-creds.sh` logs in the service principal; `SessionStart` warms it and `PreToolUse` re-checks freshness before every `terraform`/`az` call, so a mid-session rotation self-heals. No manual re-login needed.

## Reuse
`.claude/` here is the reference implementation of the org-wide Claude automation strategy
(`docs/CLAUDE-AUTOMATION.md`) — the same template drops into the IDP repo and any other repo.
