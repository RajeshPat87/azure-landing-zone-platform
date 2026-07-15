# Azure Landing Zone Platform — End-to-End Runbook

A ready-to-use Terraform platform-engineering repo that implements the 10-step Azure
Landing Zone blueprint (tenant foundation → management groups → subscription vending →
core central services → hub-spoke networking → governance → CI/CD → standardized app
onboarding → operations → continuous improvement).

**This single README is the run book.** It first walks the whole flow **locally from WSL**,
then runs the *same* Terraform **from GitHub Actions (and Azure DevOps) pipelines**. It also
consolidates what used to live in `docs/` (design notes, credential rotation, the Claude
automation strategy, and the guardrail hook map) so you have one place to operate from.

**AI-assisted, safely.** The repo ships a committed `.claude/` guardrail template that denies
irreversible operations, ASK-gates privileged changes, and injects short-lived credentials —
so the same agent that plans a landing zone can never silently `terraform destroy` one or leak
a secret. That system is documented inline in [§8](#8-claude-code-automation--guardrails).

---

## Table of contents

1. [What you are deploying (architecture)](#1-what-you-are-deploying-architecture)
2. [Repository layout](#2-repository-layout)
3. [State, modules & data-flow model](#3-state-modules--data-flow-model)
4. [Prerequisites](#4-prerequisites)
5. [PART A — Run end-to-end from local WSL](#5-part-a--run-end-to-end-from-local-wsl)
6. [PART B — Run end-to-end from GitHub Actions](#6-part-b--run-end-to-end-from-github-actions)
7. [PART C — Azure DevOps alternative](#7-part-c--azure-devops-alternative)
8. [Claude Code automation & guardrails](#8-claude-code-automation--guardrails)
9. [Local credentials — rotating lab SP](#9-local-credentials--rotating-lab-sp)
10. [Design decisions & trade-offs](#10-design-decisions--trade-offs)
11. [Operations (Step 9) & continuous improvement (Step 10)](#11-operations-step-9--continuous-improvement-step-10)
12. [Extending the platform](#12-extending-the-platform)
13. [Troubleshooting](#13-troubleshooting)
14. [Appendix — variable & command reference](#14-appendix--variable--command-reference)

---

## 1. What you are deploying (architecture)

### Blueprint step → code mapping

| Step | Blueprint stage | Where in this repo |
|------|-----------------|--------------------|
| 1 | Azure Tenant | Prerequisite (existing tenant) + `scripts/bootstrap-state.sh` |
| 2 | Management Groups | `modules/management-groups` via `environments/mgmt` |
| 3 | Subscriptions (scale unit) | `modules/subscription-vending` |
| 4 | Core Central Services | `modules/core-services` (Log Analytics, Key Vault, Recovery Services Vault, Automation) + `modules/identity` (Entra groups, RBAC, OIDC SPN) |
| 5 | Networking | `modules/hub-network` (Firewall, VPN GW, Bastion, Private DNS) + `modules/spoke-network` (peering, UDR, NSG) |
| 6 | Governance | `modules/governance` (Azure Policy assignments at MG scope) |
| 7 | DevOps & Automation | `.github/workflows/platform-cicd.yml` and `pipelines/azure-pipelines.yml` |
| 8 | App Onboarding | `environments/landingzone-prod` + `.github/workflows/app-onboarding.yml` |
| 9 | Operations | Diagnostics to central LA, backup policy, budgets/alerts, Update Management hooks |
| 10 | Continuous Improvement | PR-driven change flow, Checkov/TFLint gates, plan review on every PR |

### Logical topology

```
Tenant root
└── Management Group hierarchy  (modules/management-groups)
    ├── Platform MG        → platform_admins (Owner)
    │   ├── Management sub → core-services: Log Analytics, Key Vault, RSV, Automation
    │   ├── Connectivity sub → hub-network: Hub VNet, Azure Firewall, (VPN GW), (Bastion), Private DNS
    │   └── Identity sub   → identity: Entra groups, RBAC, GitHub OIDC SPN
    └── Landing Zones MG   → lz_contributors (Contributor)
        └── corp MG        → deny-public-IP policy
            └── App spokes  (environments/landingzone-prod, one per app)
                 spoke VNet ── peered ──► Hub ──► Azure Firewall (forced egress + DNS proxy)
```

Governance policy assignments sit at the **root MG** (allowed locations, mandatory tags,
storage-HTTPS-only, RG naming, inherit-tags) and flow down to every current and future
subscription; the **corp MG** adds a deny-public-IP restriction on top.

---

## 2. Repository layout

```
.
├── modules/                     # Reusable building blocks
│   ├── management-groups/       # Step 2 - MG hierarchy (CAF-aligned)
│   ├── governance/              # Step 6 - Policy definitions + assignments
│   ├── core-services/           # Step 4 - LA, Key Vault, RSV, Automation
│   ├── identity/                # Step 4 - Entra groups, RBAC, CI/CD OIDC
│   ├── hub-network/             # Step 5 - Hub VNet, AFW, VPN GW, Bastion, DNS
│   ├── spoke-network/           # Step 5 - Spoke VNet, peering, UDR, NSG
│   └── subscription-vending/    # Step 3/8 - Sub creation, MG placement, budget
├── environments/                # Deployable root compositions (state boundaries)
│   ├── mgmt/                    # Foundation: MGs + policy + core services + identity
│   ├── connectivity/           # Hub network
│   └── landingzone-prod/       # One instance per onboarded application
├── .github/workflows/           # GitHub Actions CI/CD (OIDC, plan-on-PR, gated apply)
│   ├── platform-cicd.yml        # Step 7 - validate → plan (PR) → apply (merge, gated)
│   └── app-onboarding.yml       # Step 8 - dispatch: plan/apply/destroy one app
├── pipelines/azure-pipelines.yml # Azure DevOps alternative (multi-stage, WIF)
├── scripts/
│   ├── bootstrap-state.sh       # One-time remote-state backend creation
│   └── register-providers.sh    # Resource-provider registration per subscription
├── .claude/                     # Claude Code guardrails (20-hook lifecycle, Profile A)
│   ├── settings.json            # Wires the 6 lifecycle hooks
│   ├── hooks/                   # session-start / user-prompt / pre+post-tool-use / stop / session-end
│   ├── scripts/azure-lab-creds.sh  # Rotating SP login (local auth)
│   └── skills/infra-safety-hooks/  # Guardrail reference (SKILL.md)
├── CLAUDE.md                    # Repo guardrails + conventions Claude reads first
├── .tflint.hcl                  # TFLint config
└── README.md                    # ← this run book
```

> **Note on `docs/`:** the design notes, credential-rotation guide, and Claude-automation
> strategy that previously lived under `docs/` are now consolidated into this README
> (sections 8–12). The `docs/` files remain as deep-dive references but this README is the
> single operating source.

---

## 3. State, modules & data-flow model

### One state file per composition

Each folder under `environments/` is an independently plannable/appliable root module with
its **own backend state key** in the shared state storage account:

| Composition | Backend key | Reads (remote state) | Produces |
|-------------|-------------|----------------------|----------|
| `mgmt` | `platform/mgmt.tfstate` | — | MG IDs, `log_analytics_workspace_id`, `key_vault_uri`, `cicd_client_id` |
| `connectivity` | `platform/connectivity.tfstate` | `mgmt` → LA workspace ID | `hub_vnet_id/name`, `hub_resource_group_name`, `firewall_private_ip` |
| `landingzone-prod` | `landingzones/<app>-prod.tfstate` | `mgmt` + `connectivity` | spoke VNet, peering, budget |

Wiring is via `terraform_remote_state`, never hardcoding: spokes read the hub's VNet ID and
firewall IP; connectivity reads the LA workspace ID from mgmt. This gives:

1. **Small blast radius** — a bad apply in one landing zone cannot touch the hub or another app.
2. **Independent cadence** — the network team ships hub changes without replanning every app.
3. **Clear RBAC** — the landing-zone pipeline identity can be scoped lower than the platform identity.

### Deployment order (never varies)

```
bootstrap-state.sh → register-providers.sh → mgmt → connectivity → landingzone-prod (per app)
```

Onboarding the *next* app is **one new `app-<name>.tfvars` file + one pipeline run** — never
a fork of module code.

---

## 4. Prerequisites

- **Permissions:** Owner + `Microsoft.Management` at tenant root. Assigning Owner at `/`
  (`az role assignment create --role Owner --scope /`) needs a one-time Global Admin elevation.
- **Tooling (WSL):** Azure CLI, Terraform ≥ 1.6 (CI pins 1.9.8), `openssl`, `jq`, `git`.
- **Subscriptions:** 2–4 (management, connectivity, identity, workload). Single-subscription
  labs work — pass the same subscription ID everywhere.
- **Region default:** `centralindia` / `cin` (override via variables).

Install the toolchain in WSL (Ubuntu) if needed:

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
# Terraform (HashiCorp apt repo)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform jq -y
terraform version && az version
```

---

## 5. PART A — Run end-to-end from local WSL

This is the full first-run runbook. Do it once locally to stand up the platform, then hand
day-2 changes to the pipeline (Part B). Every command runs from the repo root unless a
`cd` is shown.

### A0. Authenticate

Two supported local auth paths — pick one:

- **Interactive (simplest):** `az login` then `az account set --subscription <management-sub-id>`.
- **Rotating lab service principal (used for Claude-assisted work):** feed one JSON creds file
  and let the automation log in and keep it fresh. See [§9](#9-local-credentials--rotating-lab-sp)
  for the full flow. Quick version:

  ```bash
  export ALZ_AZURE_CREDS_FILE=/path/to/azure-lab-creds.json   # JSON or .env
  .claude/scripts/azure-lab-creds.sh --force                   # log the SP in now
  az account show                                              # confirm the active subscription
  ```

> Terraform's `azurerm` provider inherits the Azure CLI token cache automatically, so no
> `ARM_*` secret ever needs to be exported into your shell.

### A1. Bootstrap remote state (one time)

Creates a GRS storage account with blob versioning + 30-day soft-delete to hold Terraform state:

```bash
./scripts/bootstrap-state.sh <management-subscription-id> centralindia
./scripts/register-providers.sh <management-subscription-id>
# repeat register-providers.sh for connectivity/identity/workload subs if separate
```

The bootstrap script prints the generated storage account name (e.g. `sttfstate3f9a1b2c`).
**Copy that name into every `environments/*/backend.hcl`**, replacing `sttfstateREPLACEME`:

```hcl
# environments/{mgmt,connectivity,landingzone-prod}/backend.hcl
resource_group_name  = "rg-tfstate-prod-cin"
storage_account_name = "sttfstate3f9a1b2c"   # ← paste the real name
container_name       = "tfstate"
```

### A2. Deploy the foundation — `mgmt` (Steps 1–4, 6)

```bash
cd environments/mgmt
cp terraform.tfvars.example terraform.tfvars     # edit prefix, org name, subscription IDs, github_repository
terraform init -backend-config=backend.hcl
terraform plan       # review carefully — this touches tenant-wide scope
terraform apply
```

Creates: MG hierarchy, governance policy assignments, Log Analytics workspace, Key Vault,
Recovery Services Vault, Automation Account, Entra RBAC groups (`platform_admins`,
`lz_contributors`, `platform_readers`), and the **GitHub OIDC service principal**.

Capture the outputs you need for CI/CD:

```bash
terraform output cicd_client_id            # → GitHub secret AZURE_CLIENT_ID
terraform output log_analytics_workspace_id
az account show --query tenantId -o tsv     # → GitHub secret AZURE_TENANT_ID
```

### A3. Deploy the hub — `connectivity` (Step 5)

```bash
cd ../connectivity
cp terraform.tfvars.example terraform.tfvars   # set state_storage_account_name + address spaces
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Creates the hub VNet, Azure Firewall (Standard, with DNS proxy), optional VPN Gateway /
Bastion (both off/on per tfvars), private DNS zones, and firewall diagnostics wired to the
central Log Analytics workspace read from `mgmt` state.

> VPN Gateway is **off** by default (30–45 min deploy + cost). Flip `deploy_vpn_gateway = true`
> only when hybrid connectivity is needed.

### A4. Onboard an application — `landingzone-prod` (Step 8)

One tfvars file per app. Each app gets its **own state key**:

```bash
cd ../landingzone-prod
cp app-crm.tfvars.example app-crm.tfvars        # set workload, sub id, /22 spoke CIDR, budget, owner
terraform init -backend-config=backend.hcl \
  -backend-config="key=landingzones/crm-prod.tfstate"
terraform plan   -var-file=app-crm.tfvars
terraform apply  -var-file=app-crm.tfvars
```

Each app receives: subscription MG placement + monthly budget alerts (50/80/100%), a spoke
VNet peered to the hub, **forced egress through Azure Firewall** (UDR `0.0.0.0/0` → firewall),
a baseline NSG, a delegated data subnet (PostgreSQL flexible server), and private DNS links.

**To onboard the next app:** copy the tfvars example to `app-<name>.tfvars`, edit it, and
re-run `init` + `apply` with a new `-backend-config="key=landingzones/<name>-prod.tfstate"`.

### A5. Local teardown (labs only)

Reverse order. Destroy each app first, then connectivity, then mgmt:

```bash
cd environments/landingzone-prod && terraform destroy -var-file=app-crm.tfvars
cd ../connectivity && terraform destroy
cd ../mgmt && terraform destroy
```

> `terraform destroy` is **ASK-gated** under the Claude guardrails; `az group delete` /
> `mg delete` are hard-**DENIED**. Tear down through Terraform, never imperative `az`.

---

## 6. PART B — Run end-to-end from GitHub Actions

Once the foundation exists (Part A produced the OIDC SPN), all day-2 changes flow through
pipelines with **OIDC federation — no client secrets stored anywhere**.

### B1. Configure federation & secrets (one time)

The `identity` module already created the federated credentials for GitHub environments
`plan` and `apply` (subject `repo:<org/repo>:environment:<env>`). Now, in the GitHub repo:

**Settings → Secrets and variables → Actions → repository secrets:**

| Secret | Value |
|--------|-------|
| `AZURE_CLIENT_ID` | `cicd_client_id` output from `mgmt` (`terraform output cicd_client_id`) |
| `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | management subscription ID |

**Settings → Environments:** create two environments named **exactly** `plan` and `apply`
(the federated-credential subjects must match these names). Add **required reviewers** on
`apply` so every production apply is human-approved.

> If you renamed environments or the repo, update `github_environments` / `github_repository`
> in the `identity` module inputs and re-apply `mgmt` — the OIDC subject must line up or
> `azure/login` fails with an audience/subject error.

### B2. Platform CI/CD flow (`platform-cicd.yml`, Step 7)

Triggers on PRs and pushes to `main` touching `environments/**` or `modules/**`, plus manual
`workflow_dispatch`.

```
PR opened ─► validate (fmt · validate · TFLint · Checkov · Gitleaks)  [matrix: all 3 envs]
          └─► plan     (env: plan)   → terraform plan → posted as a PR comment  [mgmt, connectivity]

Merge to main ─► validate
             └─► apply (env: apply, reviewers gate, max-parallel:1)
                    mgmt  ──then──►  connectivity      (order enforced by remote-state dependency)
```

Key mechanics:
- **Auth:** `azure/login@v2` with `id-token: write` + `ARM_USE_OIDC=true`. No secrets on disk.
- **TF version pinned** to `1.9.8` across all jobs.
- **`apply` runs `mgmt` before `connectivity`** (`max-parallel: 1`) because connectivity reads
  mgmt's remote state.
- **Checkov `skip_check`** documents each org exception inline (e.g. `CKV_AZURE_59`).

Day-2 change loop: branch → edit Terraform → open PR → read the posted plan → get review →
merge → approve the `apply` gate.

### B3. App onboarding flow (`app-onboarding.yml`, Step 8)

Manually dispatched, one run per application — this is the pipeline equivalent of A4.

**Actions tab → app-onboarding → Run workflow:**
- `workload` — the app name; must match a committed `app-<workload>.tfvars` file.
- `action` — `plan` | `apply` | `destroy`.

The job selects the environment automatically (`plan` action → `plan` env; `apply`/`destroy`
→ `apply` env, which is reviewer-gated), inits with a per-app state key
(`landingzones/<workload>-prod.tfstate`), and runs the chosen Terraform command with
`-var-file="app-<workload>.tfvars"`.

So the full app-onboarding sequence from pipelines is:
1. Commit `environments/landingzone-prod/app-<name>.tfvars` via PR (validated by `platform-cicd`).
2. Run `app-onboarding` with `action=plan`, review the log.
3. Run `app-onboarding` with `action=apply`, approve the `apply` gate.

---

## 7. PART C — Azure DevOps alternative

`pipelines/azure-pipelines.yml` mirrors the GitHub flow for orgs on Azure DevOps:

- **Service connection:** `sc-azure-platform` using **Workload Identity Federation** (no secrets).
- **Stages:** `Validate` (fmt · validate · Checkov) → `Plan_Mgmt` → `Apply_Mgmt` (approval-gated
  `platform-prod` environment) → `Apply_Connectivity` (approval-gated, depends on Apply_Mgmt).
- Set the backend variables at the top (`backendSa` → the real state storage account name)
  and add approvals on the `platform-prod` ADO environment.

Everything else (state keys, ordering, OIDC-style federation) is identical to Part B.

---

## 8. Claude Code automation & guardrails

The repo ships its own `.claude/` so the rules that keep an AI agent safe travel with the
code and are reviewed like code — no reliance on individual local settings. This is
**Profile A (IaC / Terraform + Azure)** of an org-wide strategy; the same template drops into
an IDP repo (Profile B) and application repos (Profile C).

### Principles

1. **Guardrails as code, in the repo** — reviewed and versioned like any other code.
2. **Deny the irreversible, ask for the privileged, validate every edit** — the 20-hook lifecycle is the spine.
3. **Auth is injected, never stored** — CI uses OIDC; local dev uses short-lived rotating creds. Claude never sees a long-lived secret.
4. **Same shape everywhere** — the lifecycle hooks and layout are identical across repo types; only the matchers/validators differ.

### The 20-hook lifecycle

Six Claude Code lifecycle hooks (`SessionStart` → `UserPromptSubmit` → `PreToolUse` →
`PostToolUse` → `Stop` → `SessionEnd`) enforce three rules. What Claude tries → what happens:

| What Claude tries | Result |
|-------------------|--------|
| Print/read `*.tfstate`, `*.tfvars`, `az` tokens, Key Vault secret values, `ARM_CLIENT_SECRET` | **DENY** (hook 07) |
| `terraform state rm` / `force-unlock`, `az group`/`mg delete`, `--purge`, broad `rm -rf` | **DENY** (hook 06) |
| `terraform apply` / `destroy` (incl. `-auto-approve`) | **ASK** (hook 11) — reviewed plan first |
| Edit `providers.tf`, `backend.hcl`, `versions.tf`, governance/identity/MG modules, CI workflows | **ASK** (hook 08) — tenant-wide blast radius |
| Edit `.claude/settings.json`, hooks, or the creds script | **ASK** (hook 04) — config tamper guard |
| Active `az` subscription ≠ target `environments/<env>` | **ASK** (hook 05) — wrong-subscription guard |
| Any `.tf`/`.tfvars` edit | auto `terraform fmt` (13) · `tflint` (15) · `init -backend=false && validate` (16) |
| Try to end the session with an unformatted `.tf` | **BLOCK** (hook 19) — definition-of-done gate |

Verdict semantics: **DENY** = command never runs · **ASK** = host asks the human to confirm ·
**BLOCK** = hook exits 2, error returned to Claude to fix and retry · **CONTEXT/WARN** =
non-blocking info injection. Full map: `.claude/skills/infra-safety-hooks/SKILL.md`.

### Working conventions (from `CLAUDE.md`)

- Change infra through **Terraform, not imperative `az`** — `az` is for read-only inspection.
- Run `terraform fmt -recursive` before finishing — the done-gate blocks otherwise.
- One landing zone = one new tfvars file + one pipeline run; never fork module code per app.
- Respect state isolation — a change in one environment must not require re-planning another.
- Real `*.tfvars` are secrets and gitignored; only edit/commit `*.tfvars.example`.

### Test a hook

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"}}' \
  | .claude/hooks/pre-tool-use.sh
```

---

## 9. Local credentials — rotating lab SP

> CI/CD does **not** use this — pipelines authenticate with OIDC (Part B). This section is
> only for **local** work where a lab rotates a service principal every ~1 hour.

### The one thing you maintain: a single JSON file

```
[lab: showcreds] ──copy──▶ azure-lab-creds.json ──▶ azure-lab-creds.sh ──▶ az login ──▶ Terraform
 (fresh SP hourly)          (the file you feed)      (freshness + login)   (CLI cache)  (azurerm)
```

**File format** (minimal — maps directly from a lab `showcreds` output):

```json
{
  "appId": "<Azure Application Client ID>",
  "password": "<Azure Client Secret>",
  "tenant": "azurefreekmlprod.onmicrosoft.com"
}
```

- `tenant` is constant across rotations (domain or GUID both work).
- `subscription` is optional — omit and it's auto-detected from `az account show`; add
  `"subscription": "<guid>"` to pin a target.
- Each hourly rotation changes only **`appId` + `password`**.

The parser also accepts `az ad sp create-for-rbac` JSON verbatim and `KEY=VALUE` `.env` files
(`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`, and common aliases).

**Where the file goes** — `azure-lab-creds.sh` probes these in order and uses the first found:

| Priority | Path |
|----------|------|
| 1 | `$ALZ_AZURE_CREDS_FILE` (explicit — set in `.claude/hooks/config.env`) |
| 2 | `~/.azure-lab/creds.json` or `~/.azure-lab/creds.env` |
| 3 | `~/azure-lab-creds.json` / `~/azure-lab-creds.env` / `~/azure-creds.json` |
| 4 | `/mnt/c/Users/sound/azure-lab-creds.json` *(current default in use)* |
| 5 | `/mnt/c/Users/sound/Downloads/azure-lab-creds.json` |

All credential files (`*azure-lab-creds*.json/.env`, `*creds.env`, `.claude/hooks/config.env`)
are **gitignored**; only `*.example` templates are committed.

### What the automation does

1. **Locate** the first existing probe path.
2. **Parse** `appId` / `password` / `tenant` / `subscription` from JSON or `.env` (never executes the file).
3. **Freshness check** — "still good" only if `az account show` succeeds *and* last login < 50 min ago (`ALZ_CREDS_MAX_AGE`, default 3000 s).
4. **Login** — `az login --service-principal` (+ `az account set` if a subscription is given), warming the Azure CLI token cache.
5. **Propagate** — writes `~/.claude/alz/azure.env` (mode 600) with `ARM_*`/`AZURE_*` exports for anything that wants to `source` them, and stamps the login time.
6. **Terraform just works** — the `azurerm` provider falls back to Azure CLI auth, so **no `ARM_*` secret enters Claude's shell or the transcript.**

When each step fires:

| Trigger | What happens |
|---------|--------------|
| `SessionStart` hook | Warms the login at session start. |
| `PreToolUse` hook | Before **every** `terraform`/`az` command, re-checks freshness and re-logs in if stale — **this is what makes rotation self-heal.** |
| Manual | `.claude/scripts/azure-lab-creds.sh --force` — re-login now. |
| Manual (source) | `source .claude/scripts/azure-lab-creds.sh --export` — refresh **and** load `ARM_*` into the current shell. |

### Hourly rotation loop

1. In the lab, run `showcreds` (or however it surfaces the new SP).
2. Overwrite `appId` + `password` in the JSON file (keep `tenant`). Two fields.
3. Do nothing else — the next `terraform`/`az` call detects the >50-min age and re-logs in.
   To pick it up immediately, run `azure-lab-creds.sh --force`.

**Command reference:**

```bash
.claude/scripts/azure-lab-creds.sh            # refresh only if stale/logged out (safe anytime)
.claude/scripts/azure-lab-creds.sh --force    # force a re-login now (after pasting new creds)
.claude/scripts/azure-lab-creds.sh --check    # exit 0 = fresh, 1 = needs refresh
source .claude/scripts/azure-lab-creds.sh --export   # refresh AND export ARM_* into this shell
```

**Tunables** (`.claude/hooks/config.env`, gitignored — copy `config.env.example` first):

```bash
export ALZ_AZURE_CREDS_FILE="/mnt/c/Users/sound/azure-lab-creds.json"  # explicit path
export ALZ_CREDS_MAX_AGE=3000         # re-login when older than this (seconds)
export ALZ_STATE_DIR="$HOME/.claude/alz"    # where azure.env + timestamp live
```

---

## 10. Design decisions & trade-offs

- **State per environment, per app.** `mgmt`, `connectivity`, and each landing zone have
  isolated state files. Blast radius of any apply is one composition; landing zones share code
  but never state.
- **`terraform_remote_state` over hardcoding.** Spokes read hub outputs (VNet ID, firewall IP);
  connectivity reads the LA workspace ID from mgmt.
- **OIDC everywhere in CI.** The CI/CD identity uses federated credentials scoped to specific
  GitHub environments — nothing to rotate, nothing to leak.
- **Policy inheritance.** Assignments at the root MG flow to every current and future
  subscription; corp-only restrictions (deny public IP) sit at the corp MG. Online workloads
  keep public-IP capability; corp workloads are private-only by policy, not by convention.
- **Forced tunnelling.** Every spoke subnet gets a UDR sending `0.0.0.0/0` to the firewall;
  spokes use the firewall as DNS proxy so private-endpoint resolution works centrally.
- **Vending is optional.** `create_subscription = true` needs an EA/MCA billing scope; without
  one the module still handles MG placement, budgets, and tags for pre-created subscriptions.

### IP address plan

| Scope | CIDR | Notes |
|-------|------|-------|
| Hub | `10.0.0.0/24` | Split into 4 × /26: AzureFirewallSubnet, GatewaySubnet, AzureBastionSubnet, shared services |
| Spokes | `10.1.0.0/16` onwards | One /22 per app (app / data / private-endpoint subnets via `cidrsubnet`) |

Keep the full spoke supernet in the hub's `spoke_address_spaces` so firewall rules cover new
spokes without edits.

### Policy strategy

| Assignment | Scope | Effect |
|------------|-------|--------|
| Allowed locations | root | deny |
| Require Environment/Owner/CostCenter tags on RGs | root | deny |
| Inherit tags from RG | root | modify (managed identity + Tag Contributor) |
| Storage HTTPS only | root | deny |
| RG naming (custom, `rg-*`) | root | deny |
| Deny public IPs | corp MG only | deny |

### Known trade-offs

- VPN Gateway is off by default (30–45 min deploy, cost). Flip `deploy_vpn_gateway = true` for hybrid connectivity.
- Azure Firewall **Standard**, not Premium — upgrade `firewall_sku_tier` for TLS inspection / IDPS.
- Subscription vending requires EA/MCA billing-scope permissions many orgs restrict; the module degrades gracefully to managing pre-created subscriptions.

---

## 11. Operations (Step 9) & continuous improvement (Step 10)

Diagnostics stream to the central Log Analytics workspace; VM backup uses the daily GRS policy
in the Recovery Services Vault; every subscription carries a monthly budget with 50/80/100%
alerts. All changes flow through PRs with security scanning (Checkov, TFLint, Gitleaks), so
drift review (`terraform plan` on schedule), policy-compliance dashboards, and cost reviews
close the loop.

---

## 12. Extending the platform

- **ExpressRoute:** extend `modules/hub-network` with `azurerm_express_route_gateway` behind a `deploy_er_gateway` flag.
- **AKS landing zones:** create a `modules/aks-platform` consuming `spoke-network` subnet outputs; add the reserved Helm/AKS guardrail hooks (10, 14).
- **Multi-region:** instantiate `connectivity` per region with global VNet peering between hubs.
- **New app:** copy an `app-*.tfvars.example`, edit, add a new state key, run the onboarding pipeline.

---

## 13. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `terraform init` backend errors | `backend.hcl` still has `sttfstateREPLACEME` — paste the real storage account name from `bootstrap-state.sh`. |
| `connectivity` plan can't read LA workspace | `mgmt` hasn't been applied, or its state key differs — apply `mgmt` first. |
| `azure/login` fails in Actions (audience/subject) | GitHub environment names ≠ `plan`/`apply`, or `github_repository`/`github_environments` in the `identity` module don't match the repo — fix and re-apply `mgmt`. |
| `no credentials file found` (local) | Lab creds file isn't at a probed path — set `ALZ_AZURE_CREDS_FILE` or move it. |
| `az login failed — creds may be expired` | The lab rotated; the JSON still has the old SP. Re-feed the current `showcreds` values. |
| Terraform prompts for auth locally | `az account show` is empty — run `.claude/scripts/azure-lab-creds.sh --force`. |
| A `terraform apply` was blocked/asked | Expected — the Claude guardrails ASK-gate applies. Produce a reviewed plan, then confirm. |
| Provider registration errors on first apply | Run `./scripts/register-providers.sh <sub-id>` for that subscription. |

---

## 14. Appendix — variable & command reference

### `environments/mgmt` inputs (`terraform.tfvars`)

| Variable | Example | Notes |
|----------|---------|-------|
| `prefix` | `contoso` | Org short name; drives MG IDs, resource names, `<prefix>-corp` MG. |
| `org_display_name` | `Contoso` | Root MG display name. |
| `location` / `location_short` | `centralindia` / `cin` | Default region. |
| `allowed_locations` | `["centralindia","southindia"]` | Fed into the allowed-locations policy. |
| `management_subscription_id` | GUID | Core services land here (aliased provider). |
| `connectivity_subscription_id` | GUID | Hub placement. |
| `identity_subscription_id` | GUID or `null` | Optional identity sub. |
| `github_repository` | `RajeshPat87/azure-landing-zone-platform` | OIDC federation subject. |

Identity module extras: `github_environments` (default `["plan","apply"]`), `cicd_role`
(default `Contributor`).

### `environments/connectivity` inputs

`prefix`, `connectivity_subscription_id`, `hub_address_space` (`10.0.0.0/24`),
`spoke_address_spaces` (`["10.1.0.0/16","10.2.0.0/16"]`), `deploy_vpn_gateway` (bool),
`deploy_bastion` (bool), `state_storage_account_name`.

### `environments/landingzone-prod` inputs (per `app-<name>.tfvars`)

`workload`, `workload_subscription_id`, `spoke_address_space` (a `/22`), `app_owner`,
`cost_center`, `monthly_budget_amount`, `budget_start_date` (RFC3339),
`budget_contact_emails`, `state_storage_account_name`.

### Terraform command cheat-sheet

```bash
# Foundation
cd environments/mgmt         && terraform init -backend-config=backend.hcl && terraform apply
# Hub
cd environments/connectivity && terraform init -backend-config=backend.hcl && terraform apply
# App (per-app state key)
cd environments/landingzone-prod
terraform init  -backend-config=backend.hcl -backend-config="key=landingzones/<app>-prod.tfstate"
terraform apply -var-file=app-<app>.tfvars

# Hygiene (run before finishing — enforced by the done-gate)
terraform fmt -recursive
tflint --recursive --minimum-failure-severity=error
```

### Bootstrap / provider scripts

```bash
./scripts/bootstrap-state.sh <management-subscription-id> [location]   # one-time state backend
./scripts/register-providers.sh <subscription-id>                      # per-subscription providers
```
