module "naming_container_app_environment" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "container_app_environment"
}
