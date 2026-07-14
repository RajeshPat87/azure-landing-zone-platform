variable "prefix" {
  description = "Org/workload prefix, e.g. contoso."
  type        = string
}

variable "environment" {
  description = "Environment name, e.g. prod."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "centralindia"
}

variable "location_short" {
  description = "Short region code used in names, e.g. cin."
  type        = string
  default     = "cin"
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "la_solutions" {
  description = "Log Analytics solutions to enable."
  type        = list(string)
  default     = ["SecurityInsights", "VMInsights", "ChangeTracking"]
}

variable "kv_public_access" {
  description = "Allow public network access to Key Vault (set false + private endpoint for prod)."
  type        = bool
  default     = true
}

variable "backup_timezone" {
  type    = string
  default = "India Standard Time"
}

variable "tags" {
  type    = map(string)
  default = {}
}
