provider "azurerm" {
  features {}

  subscription_id = var.subscription_id != null ? lower(trimspace(var.subscription_id)) : null
}
