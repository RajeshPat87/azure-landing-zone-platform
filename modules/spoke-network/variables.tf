variable "prefix" {
  type = string
}

variable "workload" {
  description = "Workload/app name used in resource names, e.g. web, data."
  type        = string
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

variable "spoke_address_space" {
  type = string
}

variable "subnets" {
  description = "Map of subnet name => { cidr, service_endpoints, delegation }."
  type = map(object({
    cidr              = string
    service_endpoints = optional(list(string), [])
    delegation        = optional(string)
  }))
}

variable "dns_servers" {
  description = "Set to [firewall_private_ip] when using Azure Firewall DNS proxy."
  type        = list(string)
  default     = []
}

variable "hub_vnet_id" {
  type = string
}

variable "hub_vnet_name" {
  type = string
}

variable "hub_resource_group_name" {
  type = string
}

variable "firewall_private_ip" {
  type = string
}

variable "use_hub_gateway" {
  description = "Route on-prem traffic via hub VPN/ER gateway."
  type        = bool
  default     = false
}

variable "private_dns_zone_names" {
  description = "Set of central private DNS zone names to link this spoke to."
  type        = set(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
