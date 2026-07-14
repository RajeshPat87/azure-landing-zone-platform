output "management_group_ids" {
  value = module.management_groups.management_group_ids
}

output "log_analytics_workspace_id" {
  value = module.core_services.log_analytics_workspace_id
}

output "key_vault_uri" {
  value = module.core_services.key_vault_uri
}

output "cicd_client_id" {
  value = module.identity.cicd_client_id
}
