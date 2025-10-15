locals {
  ks_ai_search_name = coalesce(
    try(var.ks_ai_search_definition.name, null),
    module.naming_knowledge_search_service.name
  )
  ks_bing_grounding_name = coalesce(
    try(var.ks_bing_grounding_definition.name, null),
    module.naming_knowledge_bing_grounding.name
  )
}
