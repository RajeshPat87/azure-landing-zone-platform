###############################################################################
# Module: identity
# Step 4 (Identity & Security) of the Landing Zone blueprint
#   - Entra ID security groups per persona
#   - RBAC role assignments at management group scope
#   - Workload identity (SPN + federated credential) for CI/CD (OIDC, no secrets)
###############################################################################

# ---------------------------------------------------------------------------
# Entra ID groups
# ---------------------------------------------------------------------------
resource "azuread_group" "groups" {
  for_each = var.rbac_groups

  display_name     = each.value.display_name
  security_enabled = true
  description      = each.value.description
}

# ---------------------------------------------------------------------------
# RBAC at management group scope
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "group_roles" {
  for_each = var.rbac_groups

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azuread_group.groups[each.key].object_id
}

# ---------------------------------------------------------------------------
# CI/CD workload identity - GitHub Actions OIDC federation
# ---------------------------------------------------------------------------
resource "azuread_application" "cicd" {
  display_name = "spn-${var.prefix}-platform-cicd"
}

resource "azuread_service_principal" "cicd" {
  client_id = azuread_application.cicd.client_id
}

resource "azuread_application_federated_identity_credential" "github" {
  for_each = toset(var.github_environments)

  application_id = azuread_application.cicd.id
  display_name   = "github-${each.value}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:environment:${each.value}"
}

resource "azurerm_role_assignment" "cicd_owner" {
  scope                = var.root_management_group_id
  role_definition_name = var.cicd_role
  principal_id         = azuread_service_principal.cicd.object_id
}
