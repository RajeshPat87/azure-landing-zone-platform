variable "create_subscription" {
  description = "true = create via billing scope; false = use existing_subscription_id."
  type        = bool
  default     = false
}

variable "subscription_name" {
  type = string
}

variable "billing_scope_id" {
  description = "EA enrollment account or MCA invoice section billing scope ID."
  type        = string
  default     = null
}

variable "existing_subscription_id" {
  type    = string
  default = null
}

variable "workload_type" {
  type    = string
  default = "Production"
}

variable "target_management_group_id" {
  description = "Management group ID (name segment, not full resource ID) to place the subscription in."
  type        = string
}

variable "monthly_budget_amount" {
  type    = number
  default = 1000
}

variable "budget_start_date" {
  description = "First day of a month, RFC3339, e.g. 2026-08-01T00:00:00Z."
  type        = string
}

variable "budget_contact_emails" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
