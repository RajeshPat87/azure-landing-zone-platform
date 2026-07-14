variable "prefix" {
  type    = string
  default = "contoso"
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "location_short" {
  type    = string
  default = "cin"
}

variable "connectivity_subscription_id" {
  type = string
}

variable "hub_address_space" {
  type    = string
  default = "10.0.0.0/24"
}

variable "spoke_address_spaces" {
  type    = list(string)
  default = ["10.1.0.0/16"]
}

variable "firewall_sku_tier" {
  type    = string
  default = "Standard"
}

variable "deploy_vpn_gateway" {
  type    = bool
  default = false
}

variable "deploy_bastion" {
  type    = bool
  default = false
}

variable "state_resource_group_name" {
  type    = string
  default = "rg-tfstate-prod-cin"
}

variable "state_storage_account_name" {
  type = string
}

variable "state_container_name" {
  type    = string
  default = "tfstate"
}
