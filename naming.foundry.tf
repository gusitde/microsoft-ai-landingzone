module "naming_ai_foundry_account" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "cognitive_account"
  descriptor  = "foundry"
}
