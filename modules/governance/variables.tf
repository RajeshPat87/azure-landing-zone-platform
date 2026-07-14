variable "root_management_group_id" {
  description = "Resource ID of the org root management group."
  type        = string
}

variable "corp_management_group_id" {
  description = "Resource ID of the Corp landing zone management group (deny-public-IP scope)."
  type        = string
  default     = null
}

variable "allowed_locations" {
  description = "Regions where resources may be deployed."
  type        = list(string)
  default     = ["centralindia", "southindia"]
}

variable "mandatory_tags" {
  description = "Tags that must exist on every resource group."
  type        = list(string)
  default     = ["Environment", "Owner", "CostCenter"]
}
