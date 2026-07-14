terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100"
    }
  }
  backend "azurerm" {
    key = "platform/connectivity.tfstate"
  }
}

provider "azurerm" {
  subscription_id = var.connectivity_subscription_id
  features {}
}
