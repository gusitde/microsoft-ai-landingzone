locals {
  cae_log_analytics_workspace_resource_id            = var.container_app_environment_definition.log_analytics_workspace_resource_id != null ? var.container_app_environment_definition.log_analytics_workspace_resource_id : module.log_analytics_workspace[0].resource_id
  container_app_environment_default_role_assignments = {}
  container_app_environment_name = coalesce(
    try(var.container_app_environment_definition.name, null),
    module.naming_container_app_environment.name
  )
  container_app_environment_role_assignments = merge(
    local.container_app_environment_default_role_assignments,
    var.container_app_environment_definition.role_assignments
  )
}
