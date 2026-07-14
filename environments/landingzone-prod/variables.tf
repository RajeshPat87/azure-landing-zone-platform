variable "prefix" {
  type    = string
  default = "contoso"
}

variable "workload" {
  description = "Application/workload short name, e.g. crm."
  type        = string
}

variable "workload_subscription_id" {
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
  description = "Unique /22 or /24 per app, must be listed in hub spoke_address_spaces."
  type        = string
}

variable "app_owner" {
  type = string
}

variable "cost_center" {
  type = string
}

variable "monthly_budget_amount" {
  type    = number
  default = 500
}

variable "budget_start_date" {
  type = string
}

variable "budget_contact_emails" {
  type    = list(string)
  default = []
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
