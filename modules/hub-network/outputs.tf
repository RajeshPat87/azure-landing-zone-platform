output "hub_resource_group_name" {
  value = azurerm_resource_group.hub.name
}

output "hub_vnet_id" {
  value = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  value = azurerm_virtual_network.hub.name
}

output "firewall_private_ip" {
  value = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  value = azurerm_public_ip.firewall.ip_address
}

output "private_dns_zone_ids" {
  value = { for k, z in azurerm_private_dns_zone.zones : k => z.id }
}
