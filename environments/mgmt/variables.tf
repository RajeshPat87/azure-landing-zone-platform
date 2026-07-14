variable "prefix" {
  type    = string
  default = "contoso"
}

variable "org_display_name" {
  type    = string
  default = "Contoso"
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "location_short" {
  type    = string
  default = "cin"
}

variable "allowed_locations" {
  type    = list(string)
  default = ["centralindia", "southindia"]
}

variable "management_subscription_id" {
  type = string
}

variable "connectivity_subscription_id" {
  type = string
}

variable "identity_subscription_id" {
  type    = string
  default = null
}

variable "github_repository" {
  type    = string
  default = "your-org/azure-landing-zone-platform"
}
