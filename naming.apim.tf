module "naming_apim" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  org_prefix = local.core_naming_prefix
  resource    = "api_management"
}
