locals {
  log_analytics_workspace_name = coalesce(
    try(var.law_definition.name, null),
    module.naming_log_analytics_workspace.name
  )
}

