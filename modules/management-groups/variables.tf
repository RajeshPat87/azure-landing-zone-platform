variable "root_id" {
  description = "Short org prefix used as the root management group ID (e.g. contoso)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.root_id))
    error_message = "root_id must be 2-20 chars, lowercase alphanumeric or hyphens."
  }
}

variable "root_display_name" {
  description = "Display name of the org root management group."
  type        = string
}

variable "tenant_root_group_id" {
  description = "Resource ID of the tenant root group. Leave null to nest under tenant root."
  type        = string
  default     = null
}

variable "management_subscription_ids" {
  type    = list(string)
  default = []
}

variable "connectivity_subscription_ids" {
  type    = list(string)
  default = []
}

variable "identity_subscription_ids" {
  type    = list(string)
  default = []
}

variable "corp_subscription_ids" {
  type    = list(string)
  default = []
}

variable "online_subscription_ids" {
  type    = list(string)
  default = []
}
