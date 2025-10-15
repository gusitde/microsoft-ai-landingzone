module "naming_ai_foundry_account" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "cognitive_account"
  descriptor  = "foundry"
}
