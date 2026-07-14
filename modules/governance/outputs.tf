output "policy_assignment_ids" {
  value = {
    allowed_locations = azurerm_management_group_policy_assignment.allowed_locations.id
    storage_https     = azurerm_management_group_policy_assignment.storage_https.id
    rg_naming         = azurerm_management_group_policy_assignment.rg_naming.id
  }
}
