# Design Notes

## Why environments are the state boundary

Each folder under `environments/` is an independently plannable/appliable root module with its own backend key. This gives:

1. Small blast radius - a bad apply in one landing zone cannot touch the hub or another app.
2. Independent cadence - network team ships hub changes without replanning every app.
3. Clear RBAC - the pipeline identity for landing zones can be scoped lower than the platform identity.

## IP address plan

| Scope | CIDR | Notes |
|-------|------|-------|
| Hub | 10.0.0.0/24 | Split into 4 x /26: AzureFirewallSubnet, GatewaySubnet, AzureBastionSubnet, shared services |
| Spokes | 10.1.0.0/16 onwards | One /22 per app (app / data / private-endpoint subnets via cidrsubnet) |

Keep the full spoke supernet in the hub's `spoke_address_spaces` so firewall rules cover new spokes without edits.

## Policy strategy

| Assignment | Scope | Effect |
|------------|-------|--------|
| Allowed locations | root | deny |
| Require Environment/Owner/CostCenter tags on RGs | root | deny |
| Inherit tags from RG | root | modify (managed identity + Tag Contributor) |
| Storage HTTPS only | root | deny |
| RG naming (custom, rg-*) | root | deny |
| Deny public IPs | corp MG only | deny |

Online workloads keep public IP capability; corp workloads are private-only by policy, not by convention.

## Known trade-offs

- VPN Gateway is off by default (30-45 min deploy, cost). Flip `deploy_vpn_gateway = true` when hybrid connectivity is needed.
- Azure Firewall Standard, not Premium - upgrade `firewall_sku_tier` for TLS inspection/IDPS.
- Subscription vending requires EA/MCA billing scope permissions that many orgs restrict; the module degrades gracefully to managing pre-created subscriptions.
