output "resource_group_name" {
  value = azurerm_resource_group.management.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.this.name
}

output "key_vault_id" {
  value = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "recovery_vault_id" {
  value = azurerm_recovery_services_vault.this.id
}

output "vm_backup_policy_id" {
  value = azurerm_backup_policy_vm.daily.id
}
