# Azure Landing Zone Platform

Ready-to-use Terraform platform engineering repo implementing the 10-step Azure Landing Zone blueprint: tenant foundation, management groups, subscription vending, core central services, hub-spoke networking, governance, CI/CD, and standardized app onboarding.

## Blueprint step to code mapping

| Step | Blueprint stage | Where in this repo |
|------|-----------------|--------------------|
| 1 | Azure Tenant | Prerequisite (existing tenant) + `scripts/bootstrap-state.sh` |
| 2 | Management Groups | `modules/management-groups` via `environments/mgmt` |
| 3 | Subscriptions (scale unit) | `modules/subscription-vending` |
| 4 | Core Central Services | `modules/core-services` (Log Analytics, Key Vault, RSV, Automation) + `modules/identity` (Entra groups, RBAC, OIDC SPN) |
| 5 | Networking | `modules/hub-network` (Firewall, VPN GW, Bastion, Private DNS) + `modules/spoke-network` (peering, UDR, NSG) |
| 6 | Governance | `modules/governance` (Azure Policy assignments at MG scope) |
| 7 | DevOps & Automation | `.github/workflows/platform-cicd.yml` and `pipelines/azure-pipelines.yml` |
| 8 | App Onboarding | `environments/landingzone-prod` + `.github/workflows/app-onboarding.yml` |
| 9 | Operations | Diagnostics to central LA, backup policy, budgets/alerts, Update Management hooks |
| 10 | Continuous Improvement | PR-driven change flow, Checkov/TFLint gates, plan review on every PR |

## Repository layout

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
│   ├── connectivity/            # Hub network
│   └── landingzone-prod/        # One instance per onboarded application
├── .github/workflows/           # GitHub Actions CI/CD (OIDC, plan-on-PR, gated apply)
├── pipelines/                   # Azure DevOps alternative
└── scripts/                     # State bootstrap + provider registration
```

## Deployment order

```
bootstrap-state.sh  ->  mgmt  ->  connectivity  ->  landingzone-prod (per app)
```

### 0. Prerequisites

- Owner + Microsoft.Management permissions at tenant root (`az role assignment create --role Owner --scope /` needs Global Admin elevation once)
- Azure CLI, Terraform >= 1.6
- 2 to 4 subscriptions (management, connectivity, identity, workload). Single-subscription labs work too: pass the same ID everywhere.

### 1. Bootstrap remote state

```bash
./scripts/bootstrap-state.sh <management-subscription-id> centralindia
./scripts/register-providers.sh <management-subscription-id>
```

Copy the printed storage account name into every `environments/*/backend.hcl`.

### 2. Deploy the foundation (Steps 1-4, 6)

```bash
cd environments/mgmt
cp terraform.tfvars.example terraform.tfvars   # edit values
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Creates: MG hierarchy, policy assignments, Log Analytics, Key Vault, Recovery Services Vault, Automation Account, Entra RBAC groups, and the GitHub OIDC service principal (`cicd_client_id` output -> GitHub secret `AZURE_CLIENT_ID`).

### 3. Deploy the hub (Step 5)

```bash
cd ../connectivity
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform apply
```

Creates hub VNet, Azure Firewall (with DNS proxy), optional VPN Gateway/Bastion, private DNS zones, firewall diagnostics wired to central Log Analytics.

### 4. Onboard an application (Step 8)

```bash
cd ../landingzone-prod
cp app-crm.tfvars.example app-crm.tfvars       # one tfvars per app
terraform init -backend-config=backend.hcl \
  -backend-config="key=landingzones/crm-prod.tfstate"
terraform apply -var-file=app-crm.tfvars
```

Each app gets: subscription MG placement + budget alerts, a spoke VNet peered to the hub, forced egress through Azure Firewall, baseline NSG, delegated data subnet, and private DNS links. Onboarding the next app = one new tfvars file + one pipeline run.

### 5. Wire up CI/CD (Step 7)

GitHub repo secrets:

| Secret | Value |
|--------|-------|
| `AZURE_CLIENT_ID` | `cicd_client_id` output from mgmt |
| `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | management subscription ID |

Create GitHub environments `plan` and `apply`; add required reviewers on `apply`. Auth is OIDC federated - no client secrets stored anywhere.

Flow: PR -> fmt/validate/TFLint/Checkov/Gitleaks -> plan posted as PR comment -> merge -> approval gate -> apply (mgmt first, then connectivity).

## Design decisions

- **State per environment, per app.** `mgmt`, `connectivity`, and each landing zone have isolated state files. Blast radius of any apply is one composition; landing zones share code but never state.
- **`terraform_remote_state` over hardcoding.** Spokes read hub outputs (VNet ID, firewall IP); connectivity reads the LA workspace ID from mgmt.
- **OIDC everywhere.** The CI/CD identity uses federated credentials scoped to specific GitHub environments - nothing to rotate, nothing to leak.
- **Policy inheritance.** Assignments at the root MG flow to every current and future subscription; corp-only restrictions (deny public IP) sit at the corp MG.
- **Forced tunnelling.** Every spoke subnet gets a UDR sending 0.0.0.0/0 to the firewall; spokes use the firewall as DNS proxy so private endpoint resolution works centrally.
- **Vending is optional.** `create_subscription = true` needs an EA/MCA billing scope; without one the module still handles MG placement, budgets, and tags for pre-created subscriptions.

## Operations (Step 9) and continuous improvement (Step 10)

Diagnostics stream to the central Log Analytics workspace; VM backup uses the daily GRS policy in the Recovery Services Vault; every subscription carries a monthly budget with 50/80/100% alerts. All changes flow through PRs with security scanning, so drift review (`terraform plan` on schedule), policy compliance dashboards, and cost reviews close the loop.

## Extending

- Add ExpressRoute: extend `modules/hub-network` with `azurerm_express_route_gateway` behind a `deploy_er_gateway` flag.
- Add AKS landing zones: create a `modules/aks-platform` consuming `spoke-network` subnet outputs.
- Multi-region: instantiate `connectivity` per region with global VNet peering between hubs.
