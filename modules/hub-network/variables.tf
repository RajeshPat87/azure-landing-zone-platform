variable "prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "location_short" {
  type    = string
  default = "cin"
}

variable "hub_address_space" {
  description = "CIDR for the hub VNet (minimum /24)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "spoke_address_spaces" {
  description = "All spoke CIDRs, used in firewall rules."
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "dns_servers" {
  type    = list(string)
  default = []
}

variable "firewall_sku_tier" {
  type    = string
  default = "Standard"
}

variable "deploy_vpn_gateway" {
  type    = bool
  default = false
}

variable "vpn_gateway_sku" {
  type    = string
  default = "VpnGw1"
}

variable "deploy_bastion" {
  type    = bool
  default = false
}

variable "private_dns_zones" {
  type = list(string)
  default = [
    "privatelink.vaultcore.azure.net",
    "privatelink.blob.core.windows.net",
    "privatelink.postgres.database.azure.com",
    "privatelink.azurecr.io",
  ]
}

variable "log_analytics_workspace_id" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
