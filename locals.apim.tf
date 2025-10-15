locals {
  apim_default_role_assignments = {}
  apim_name = coalesce(
    try(var.apim_definition.name, null),
    module.naming_apim.name
  )
  apim_role_assignments = merge(
    local.apim_default_role_assignments,
    try(var.apim_definition.role_assignments, {})
  )
}
