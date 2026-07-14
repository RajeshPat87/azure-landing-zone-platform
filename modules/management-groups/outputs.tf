output "root_management_group_id" {
  value = azurerm_management_group.root.id
}

output "platform_management_group_id" {
  value = azurerm_management_group.platform.id
}

output "management_group_ids" {
  description = "Map of all management group IDs keyed by logical name."
  value = {
    root           = azurerm_management_group.root.id
    platform       = azurerm_management_group.platform.id
    management     = azurerm_management_group.management.id
    connectivity   = azurerm_management_group.connectivity.id
    identity       = azurerm_management_group.identity.id
    landing_zones  = azurerm_management_group.landing_zones.id
    corp           = azurerm_management_group.corp.id
    online         = azurerm_management_group.online.id
    sandbox        = azurerm_management_group.sandbox.id
    decommissioned = azurerm_management_group.decommissioned.id
  }
}
