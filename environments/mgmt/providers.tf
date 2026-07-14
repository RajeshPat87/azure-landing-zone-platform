terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47"
    }
  }

  backend "azurerm" {
    # Values injected via -backend-config, see environments/mgmt/backend.hcl
    key = "platform/mgmt.tfstate"
  }
}

# Default provider - tenant-level operations (management groups, policy)
provider "azurerm" {
  features {}
}

# Aliased provider targeting the Management subscription for core services
provider "azurerm" {
  alias           = "management"
  subscription_id = var.management_subscription_id
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}
