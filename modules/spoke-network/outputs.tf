output "spoke_vnet_id" {
  value = azurerm_virtual_network.spoke.id
}

output "spoke_resource_group_name" {
  value = azurerm_resource_group.spoke.name
}

output "subnet_ids" {
  value = { for k, s in azurerm_subnet.subnets : k => s.id }
}
