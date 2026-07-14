###############################################################################
# Module: management-groups
# Step 2 of the Landing Zone blueprint - Management Group hierarchy
#
#  Tenant Root Group
#  └── <root_id> (e.g. "contoso")
#      ├── platform
#      │   ├── management
#      │   ├── connectivity
#      │   └── identity
#      ├── landing-zones
#      │   ├── corp
#      │   └── online
#      ├── sandbox
#      └── decommissioned
###############################################################################

resource "azurerm_management_group" "root" {
  name                       = var.root_id
  display_name               = var.root_display_name
  parent_management_group_id = var.tenant_root_group_id
}

# ---------------------------------------------------------------------------
# Platform
# ---------------------------------------------------------------------------
resource "azurerm_management_group" "platform" {
  name                       = "${var.root_id}-platform"
  display_name               = "Platform"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "management" {
  name                       = "${var.root_id}-management"
  display_name               = "Management"
  parent_management_group_id = azurerm_management_group.platform.id
  subscription_ids           = var.management_subscription_ids
}

resource "azurerm_management_group" "connectivity" {
  name                       = "${var.root_id}-connectivity"
  display_name               = "Connectivity"
  parent_management_group_id = azurerm_management_group.platform.id
  subscription_ids           = var.connectivity_subscription_ids
}

resource "azurerm_management_group" "identity" {
  name                       = "${var.root_id}-identity"
  display_name               = "Identity"
  parent_management_group_id = azurerm_management_group.platform.id
  subscription_ids           = var.identity_subscription_ids
}

# ---------------------------------------------------------------------------
# Landing Zones
# ---------------------------------------------------------------------------
resource "azurerm_management_group" "landing_zones" {
  name                       = "${var.root_id}-landingzones"
  display_name               = "Landing Zones"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "corp" {
  name                       = "${var.root_id}-corp"
  display_name               = "Corp (internal workloads)"
  parent_management_group_id = azurerm_management_group.landing_zones.id
  subscription_ids           = var.corp_subscription_ids
}

resource "azurerm_management_group" "online" {
  name                       = "${var.root_id}-online"
  display_name               = "Online (internet-facing workloads)"
  parent_management_group_id = azurerm_management_group.landing_zones.id
  subscription_ids           = var.online_subscription_ids
}

# ---------------------------------------------------------------------------
# Sandbox & Decommissioned
# ---------------------------------------------------------------------------
resource "azurerm_management_group" "sandbox" {
  name                       = "${var.root_id}-sandbox"
  display_name               = "Sandbox"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "decommissioned" {
  name                       = "${var.root_id}-decommissioned"
  display_name               = "Decommissioned"
  parent_management_group_id = azurerm_management_group.root.id
}
