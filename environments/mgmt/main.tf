###############################################################################
# Environment: mgmt (Platform foundation)
# Deploys blueprint Steps 1-4 & 6: MG hierarchy, governance policies,
# core central services, identity/RBAC.
# State: dedicated key in the central tfstate storage account.
###############################################################################

module "management_groups" {
  source = "../../modules/management-groups"

  root_id           = var.prefix
  root_display_name = var.org_display_name

  management_subscription_ids   = [var.management_subscription_id]
  connectivity_subscription_ids = [var.connectivity_subscription_id]
  identity_subscription_ids     = var.identity_subscription_id == null ? [] : [var.identity_subscription_id]
}

module "governance" {
  source = "../../modules/governance"

  root_management_group_id = module.management_groups.root_management_group_id
  corp_management_group_id = module.management_groups.management_group_ids["corp"]
  allowed_locations        = var.allowed_locations
  mandatory_tags           = ["Environment", "Owner", "CostCenter"]
}

module "core_services" {
  source = "../../modules/core-services"
  providers = {
    azurerm = azurerm.management
  }

  prefix         = var.prefix
  environment    = "prod"
  location       = var.location
  location_short = var.location_short
  tags           = local.common_tags
}

module "identity" {
  source = "../../modules/identity"

  prefix                   = var.prefix
  root_management_group_id = module.management_groups.root_management_group_id
  github_repository        = var.github_repository

  rbac_groups = {
    platform_admins = {
      display_name = "sg-${var.prefix}-platform-admins"
      description  = "Owner on the Platform management group"
      role         = "Owner"
      scope        = module.management_groups.platform_management_group_id
    }
    lz_contributors = {
      display_name = "sg-${var.prefix}-lz-contributors"
      description  = "Contributor on all landing zones"
      role         = "Contributor"
      scope        = module.management_groups.management_group_ids["landing_zones"]
    }
    platform_readers = {
      display_name = "sg-${var.prefix}-readers"
      description  = "Reader at org root"
      role         = "Reader"
      scope        = module.management_groups.root_management_group_id
    }
  }
}

locals {
  common_tags = {
    Environment = "prod"
    Owner       = "platform-team"
    CostCenter  = "CC-PLATFORM"
    ManagedBy   = "terraform"
  }
}
