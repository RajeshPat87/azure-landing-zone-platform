###############################################################################
# Environment: connectivity (Hub network)
# Deploys blueprint Step 5: hub VNet, Azure Firewall, optional VPN GW/Bastion,
# private DNS. Reads mgmt state for the Log Analytics workspace ID.
###############################################################################

data "terraform_remote_state" "mgmt" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = "platform/mgmt.tfstate"
  }
}

module "hub_network" {
  source = "../../modules/hub-network"

  prefix               = var.prefix
  environment          = "prod"
  location             = var.location
  location_short       = var.location_short
  hub_address_space    = var.hub_address_space
  spoke_address_spaces = var.spoke_address_spaces

  firewall_sku_tier  = var.firewall_sku_tier
  deploy_vpn_gateway = var.deploy_vpn_gateway
  deploy_bastion     = var.deploy_bastion

  log_analytics_workspace_id = data.terraform_remote_state.mgmt.outputs.log_analytics_workspace_id

  tags = {
    Environment = "prod"
    Owner       = "platform-team"
    CostCenter  = "CC-PLATFORM"
    ManagedBy   = "terraform"
  }
}
