module "naming_genai_key_vault" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "key_vault"
  descriptor  = "genai"
}

module "naming_genai_cosmos_account" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "cosmosdb_account"
  descriptor  = "genai"
}

module "naming_genai_storage_account" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "storage_account"
  descriptor  = "genai"
}

module "naming_genai_storage_account_private_endpoints" {
  for_each    = var.genai_storage_account_definition.endpoint_types != null ? var.genai_storage_account_definition.endpoint_types : toset([])
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "private_endpoint"
  descriptor  = "genai-${lower(each.value)}"
  index       = 1
}

module "naming_genai_container_registry" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "container_registry"
  descriptor  = "genai"
}

module "naming_genai_app_configuration" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "app_configuration"
  descriptor  = "genai"
}
