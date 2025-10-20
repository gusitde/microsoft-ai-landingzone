module "naming_container_app_environment" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "container_app_environment"
}
