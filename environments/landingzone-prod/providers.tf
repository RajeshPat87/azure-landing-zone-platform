terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100"
    }
  }
  backend "azurerm" {
    # key is set per-app at init:
    # terraform init -backend-config=backend.hcl -backend-config="key=landingzones/<workload>-prod.tfstate"
  }
}

provider "azurerm" {
  subscription_id = var.workload_subscription_id
  features {}
}
