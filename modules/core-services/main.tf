###############################################################################
# Module: core-services
# Step 4 of the Landing Zone blueprint - Central shared services
#   - Log Analytics workspace + solutions   (Monitoring)
#   - Azure Key Vault                        (Key Management)
#   - Recovery Services Vault                (Backup & DR)
#   - Azure Automation Account               (Patching / runbooks)
#   - Diagnostic & DDoS plan (optional)
###############################################################################

resource "azurerm_resource_group" "management" {
  name     = "rg-${var.prefix}-mgmt-${var.environment}-${var.location_short}"
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Monitoring: Log Analytics
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.management.location
  resource_group_name = azurerm_resource_group.management.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_log_analytics_solution" "solutions" {
  for_each = toset(var.la_solutions)

  solution_name         = each.value
  location              = azurerm_resource_group.management.location
  resource_group_name   = azurerm_resource_group.management.name
  workspace_resource_id = azurerm_log_analytics_workspace.this.id
  workspace_name        = azurerm_log_analytics_workspace.this.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/${each.value}"
  }
}

# ---------------------------------------------------------------------------
# Key Management: Key Vault (RBAC mode, purge protection on)
# ---------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                          = "kv-${var.prefix}-${var.environment}-${var.location_short}"
  location                      = azurerm_resource_group.management.location
  resource_group_name           = azurerm_resource_group.management.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = var.kv_public_access

  network_acls {
    default_action = var.kv_public_access ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Backup & DR: Recovery Services Vault + default VM policy
# ---------------------------------------------------------------------------
resource "azurerm_recovery_services_vault" "this" {
  name                = "rsv-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.management.location
  resource_group_name = azurerm_resource_group.management.name
  sku                 = "Standard"
  soft_delete_enabled = true
  storage_mode_type   = "GeoRedundant"
  tags                = var.tags
}

resource "azurerm_backup_policy_vm" "daily" {
  name                = "bkpol-vm-daily"
  resource_group_name = azurerm_resource_group.management.name
  recovery_vault_name = azurerm_recovery_services_vault.this.name
  timezone            = var.backup_timezone

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 30
  }

  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
}

# ---------------------------------------------------------------------------
# Automation Account (Update Management / runbooks), linked to LA
# ---------------------------------------------------------------------------
resource "azurerm_automation_account" "this" {
  name                = "aa-${var.prefix}-${var.environment}-${var.location_short}"
  location            = azurerm_resource_group.management.location
  resource_group_name = azurerm_resource_group.management.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_log_analytics_linked_service" "automation" {
  resource_group_name = azurerm_resource_group.management.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  read_access_id      = azurerm_automation_account.this.id
}
