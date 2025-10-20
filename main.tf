module "naming_resource_group" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "resource_group"
  rg_version  = local.core_resource_group_version
}

resource "azurerm_resource_group" "this" {
  location = local.core_location
  name     = local.core_resource_group_name
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

