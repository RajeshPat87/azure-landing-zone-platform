###############################################################################
# Module: subscription-vending
# Step 3 (Subscription as scale unit) + Step 8 (App Onboarding)
#
# Creates a new subscription under an EA/MCA billing scope, places it in the
# correct management group, applies budget + baseline tags. If your org cannot
# create subscriptions programmatically, set create_subscription = false and
# pass an existing subscription_id - the module will still handle MG placement,
# budget, and tagging.
###############################################################################

# New subscription via billing scope (EA / MCA)
resource "azurerm_subscription" "this" {
  count             = var.create_subscription ? 1 : 0
  subscription_name = var.subscription_name
  billing_scope_id  = var.billing_scope_id
  workload          = var.workload_type # "Production" or "DevTest"
  tags              = var.tags
}

locals {
  subscription_id = var.create_subscription ? azurerm_subscription.this[0].subscription_id : var.existing_subscription_id
}

# Place subscription in target management group
resource "azurerm_management_group_subscription_association" "this" {
  management_group_id = var.target_management_group_id
  subscription_id     = "/subscriptions/${local.subscription_id}"
}

# Budget with alert thresholds
resource "azurerm_consumption_budget_subscription" "this" {
  name            = "budget-${var.subscription_name}"
  subscription_id = "/subscriptions/${local.subscription_id}"
  amount          = var.monthly_budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThanOrEqualTo"
      threshold_type = "Actual"
      contact_emails = var.budget_contact_emails
    }
  }
}
