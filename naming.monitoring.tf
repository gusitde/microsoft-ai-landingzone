module "naming_log_analytics_workspace" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "log_analytics_workspace"
}
