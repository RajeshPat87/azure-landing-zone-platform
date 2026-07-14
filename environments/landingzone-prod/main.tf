###############################################################################
# Environment: landingzone-prod (App Onboarding - Step 8)
# One instance of this composition = one application landing zone.
# Copy the folder (or use a tfvars per app) to onboard the next app.
#   - Optional subscription vending (Step 3)
#   - Spoke network peered to hub with forced tunnelling (Step 5)
#   - VM backup enrolment hook + diagnostics wired to central LA (Step 9)
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

data "terraform_remote_state" "connectivity" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = "platform/connectivity.tfstate"
  }
}

# ---------------------------------------------------------------------------
# Step 3/8: subscription placement, budget, tags
# ---------------------------------------------------------------------------
module "subscription" {
  source = "../../modules/subscription-vending"

  create_subscription        = false # flip to true with billing_scope_id for full vending
  existing_subscription_id   = var.workload_subscription_id
  subscription_name          = "sub-${var.prefix}-${var.workload}-prod"
  target_management_group_id = "${var.prefix}-corp"
  monthly_budget_amount      = var.monthly_budget_amount
  budget_start_date          = var.budget_start_date
  budget_contact_emails      = var.budget_contact_emails

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Step 5: spoke network
# ---------------------------------------------------------------------------
module "spoke" {
  source = "../../modules/spoke-network"

  prefix              = var.prefix
  workload            = var.workload
  environment         = "prod"
  location            = var.location
  location_short      = var.location_short
  spoke_address_space = var.spoke_address_space

  subnets = {
    app = {
      cidr              = cidrsubnet(var.spoke_address_space, 2, 0)
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
    }
    data = {
      cidr       = cidrsubnet(var.spoke_address_space, 2, 1)
      delegation = "Microsoft.DBforPostgreSQL/flexibleServers"
    }
    pe = {
      cidr = cidrsubnet(var.spoke_address_space, 2, 2)
    }
  }

  hub_vnet_id             = data.terraform_remote_state.connectivity.outputs.hub_vnet_id
  hub_vnet_name           = data.terraform_remote_state.connectivity.outputs.hub_vnet_name
  hub_resource_group_name = data.terraform_remote_state.connectivity.outputs.hub_resource_group_name
  firewall_private_ip     = data.terraform_remote_state.connectivity.outputs.firewall_private_ip
  dns_servers             = [data.terraform_remote_state.connectivity.outputs.firewall_private_ip]

  private_dns_zone_names = [
    "privatelink.vaultcore.azure.net",
    "privatelink.postgres.database.azure.com",
  ]

  tags = local.common_tags
}

locals {
  common_tags = {
    Environment = "prod"
    Owner       = var.app_owner
    CostCenter  = var.cost_center
    Workload    = var.workload
    ManagedBy   = "terraform"
  }
}
