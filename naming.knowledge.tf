module "naming_knowledge_search_service" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "search_service"
  descriptor  = "ks"
}

module "naming_knowledge_bing_grounding" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "bing_grounding_account"
  descriptor  = "ks"
}
