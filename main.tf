module "naming_resource_group" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "resource_group"
  rg_version  = var.resource_group_version
}

resource "azurerm_resource_group" "this" {
  location = var.location
  name     = module.naming_resource_group.name
  tags     = var.tags
}

# used to randomize resource names that are globally unique
resource "random_string" "name_suffix" {
  length  = 4
  special = false
  upper   = false
}

data "azurerm_client_config" "current" {}

module "avm_utl_regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.5.2"

  recommended_filter = false
}

