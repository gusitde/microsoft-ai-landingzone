module "naming_log_analytics_workspace" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  org_prefix = local.core_naming_prefix
  resource    = "log_analytics_workspace"
}
