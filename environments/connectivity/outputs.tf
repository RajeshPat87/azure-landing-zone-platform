output "hub_vnet_id" {
  value = module.hub_network.hub_vnet_id
}

output "hub_vnet_name" {
  value = module.hub_network.hub_vnet_name
}

output "hub_resource_group_name" {
  value = module.hub_network.hub_resource_group_name
}

output "firewall_private_ip" {
  value = module.hub_network.firewall_private_ip
}
