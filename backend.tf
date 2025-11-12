terraform {
  backend "azurerm" {
    resource_group_name   = "azr-aabb-tst-sec-rg-01"
    storage_account_name  = "azraabbtstsecst01"
    container_name        = "tfstate"
    subscription_id      = "06bfa713-9d6d-44a9-8643-b39e003e136b"
    key                   = "ai-landing-zone.tfstate"
    use_azuread_auth      = true
  }
}

