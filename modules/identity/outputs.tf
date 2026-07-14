output "cicd_client_id" {
  description = "Use as AZURE_CLIENT_ID secret in GitHub."
  value       = azuread_application.cicd.client_id
}

output "group_object_ids" {
  value = { for k, g in azuread_group.groups : k => g.object_id }
}
