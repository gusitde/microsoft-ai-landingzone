module "naming_knowledge_search_service" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "search_service"
  descriptor  = "ks"
}

module "naming_knowledge_bing_grounding" {
  source      = "./modules/naming"
  project     = var.project_code
  environment = var.environment_code
  location    = var.location
  resource    = "bing_grounding_account"
  descriptor  = "ks"
}
