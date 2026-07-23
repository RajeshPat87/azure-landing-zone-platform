###############################################################################
# Module: governance
# Step 6 of the Landing Zone blueprint - Azure Policy assignments
# Assigned at management group scope so all child subscriptions inherit.
###############################################################################

locals {
  builtin = {
    allowed_locations      = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    require_tag_on_rg      = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
    inherit_tag_from_rg    = "/providers/Microsoft.Authorization/policyDefinitions/cd3aa116-8754-49c9-a813-ad46512ece54"
    deny_public_ip         = "/providers/Microsoft.Authorization/policyDefinitions/6c112d4e-5bc7-47ae-a041-ea2d9dccd749"
    storage_https_only     = "/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9"
    sql_tde_enabled        = "/providers/Microsoft.Authorization/policyDefinitions/86a912f6-9a06-4e26-b447-11b16ba8659f"
    audit_vm_managed_disks = "/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d"
    deploy_defender_plan   = "/providers/Microsoft.Authorization/policyDefinitions/689f7782-ef2c-4270-a6d0-7664869076bd"
    no_classic_resources   = "/providers/Microsoft.Authorization/policyDefinitions/37e0d2fe-28a5-43d6-a273-67d37d1f5606"
  }
}

# ---------------------------------------------------------------------------
# Allowed locations - root scope
# ---------------------------------------------------------------------------
resource "azurerm_management_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  display_name         = "Allowed resource locations"
  management_group_id  = var.root_management_group_id
  policy_definition_id = local.builtin.allowed_locations

  parameters = jsonencode({
    listOfAllowedLocations = { value = var.allowed_locations }
  })
}

# ---------------------------------------------------------------------------
# Mandatory tags on resource groups - root scope
# ---------------------------------------------------------------------------
resource "azurerm_management_group_policy_assignment" "require_tags" {
  for_each = toset(var.mandatory_tags)

  name                 = "require-tag-${lower(each.value)}"
  display_name         = "Require '${each.value}' tag on resource groups"
  management_group_id  = var.root_management_group_id
  policy_definition_id = local.builtin.require_tag_on_rg

  parameters = jsonencode({
    tagName = { value = each.value }
  })
}

# ---------------------------------------------------------------------------
# Inherit tags from resource group (modify effect => needs identity)
# ---------------------------------------------------------------------------
resource "azurerm_management_group_policy_assignment" "inherit_tags" {
  for_each = toset(var.mandatory_tags)

  name                 = "inherit-tag-${lower(each.value)}"
  display_name         = "Inherit '${each.value}' tag from resource group"
  management_group_id  = var.root_management_group_id
  policy_definition_id = local.builtin.inherit_tag_from_rg
  location             = var.allowed_locations[0]

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    tagName = { value = each.value }
  })
}

resource "azurerm_role_assignment" "inherit_tags_contributor" {
  for_each = azurerm_management_group_policy_assignment.inherit_tags

  scope                = var.root_management_group_id
  role_definition_name = "Tag Contributor"
  principal_id         = each.value.identity[0].principal_id
}

# ---------------------------------------------------------------------------
# Security baseline - root scope
# ---------------------------------------------------------------------------
resource "azurerm_management_group_policy_assignment" "storage_https" {
  name                 = "storage-https-only"
  display_name         = "Secure transfer to storage accounts enabled"
  management_group_id  = var.root_management_group_id
  policy_definition_id = local.builtin.storage_https_only
}

resource "azurerm_management_group_policy_assignment" "no_classic" {
  name                 = "no-classic-resources"
  display_name         = "Audit classic (ASM) resources"
  management_group_id  = var.root_management_group_id
  policy_definition_id = local.builtin.no_classic_resources
}

# ---------------------------------------------------------------------------
# Deny Public IPs - corp landing zone scope only
# (online workloads are allowed internet-facing endpoints)
# ---------------------------------------------------------------------------
resource "azurerm_management_group_policy_assignment" "deny_public_ip_corp" {
  count = var.corp_management_group_id == null ? 0 : 1

  name                 = "deny-public-ip"
  display_name         = "Deny public IP addresses (Corp)"
  management_group_id  = var.corp_management_group_id
  policy_definition_id = local.builtin.deny_public_ip
}

# ---------------------------------------------------------------------------
# Custom policy: enforce naming convention on resource groups
# ---------------------------------------------------------------------------
resource "azurerm_policy_definition" "rg_naming" {
  name                = "enforce-rg-naming"
  display_name        = "Resource groups must match rg-<workload>-<env>-<region> pattern"
  policy_type         = "Custom"
  mode                = "All"
  management_group_id = var.root_management_group_id

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Resources/subscriptions/resourceGroups" },
        { not = { field = "name", match = "rg-*" } }
      ]
    }
    then = { effect = "deny" }
  })
}

resource "azurerm_management_group_policy_assignment" "rg_naming" {
  name                 = "enforce-rg-naming"
  display_name         = "Enforce resource group naming convention"
  management_group_id  = var.root_management_group_id
  policy_definition_id = azurerm_policy_definition.rg_naming.id
}
