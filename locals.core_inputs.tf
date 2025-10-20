locals {
  default_location                 = "westeurope"
  default_project_code             = "aiops"
  default_environment_code         = "tst"
  default_resource_group_name      = "rg-aiops-tst-weu-001"
  default_resource_group_version   = 1
  default_enable_telemetry         = true
  default_flag_platform_landing_zone = true
  default_vnet_definition = {
    name                             = "vnet-ai-westeu"
    address_space                    = "10.0.0.0/16"
    ddos_protection_plan_resource_id = null
    dns_servers                      = []
    subnets = {
      workload = {
        name           = "snet-workload"
        address_prefix = "10.0.1.0/24"
      }
    }
    vnet_peering_configuration = {
      peer_vnet_resource_id                = null
      firewall_ip_address                  = null
      name                                 = null
      allow_forwarded_traffic              = true
      allow_gateway_transit                = true
      allow_virtual_network_access         = true
      create_reverse_peering               = true
      reverse_allow_forwarded_traffic      = false
      reverse_allow_gateway_transit        = false
      reverse_allow_virtual_network_access = true
      reverse_name                         = null
      reverse_use_remote_gateways          = false
      use_remote_gateways                  = false
    }
    vwan_hub_peering_configuration = {
      peer_vwan_hub_resource_id = null
    }
  }

  core_location = coalesce(var.location != null ? trimspace(var.location) : null, local.default_location)
  core_project_code = coalesce(var.project_code != null ? lower(trimspace(var.project_code)) : null, local.default_project_code)
  core_environment_code = coalesce(var.environment_code != null ? lower(trimspace(var.environment_code)) : null, local.default_environment_code)
  core_resource_group_version = coalesce(var.resource_group_version, local.default_resource_group_version)
  core_resource_group_name = coalesce(var.resource_group_name != null ? trimspace(var.resource_group_name) : null, local.default_resource_group_name)
  core_enable_telemetry = coalesce(var.enable_telemetry, local.default_enable_telemetry)
  core_flag_platform_landing_zone = coalesce(var.flag_platform_landing_zone, local.default_flag_platform_landing_zone)
  core_tags = var.tags

  empty_vnet_definition = {
    name                             = null
    address_space                    = null
    ddos_protection_plan_resource_id = null
    dns_servers                      = null
    subnets                          = {}
    vnet_peering_configuration       = null
    vwan_hub_peering_configuration   = null
  }

  requested_vnet_definition              = var.vnet_definition != null ? var.vnet_definition : local.empty_vnet_definition
  requested_vnet_subnets                 = try(local.requested_vnet_definition.subnets, {})
  requested_vnet_peering_configuration   = try(local.requested_vnet_definition.vnet_peering_configuration, {})
  requested_vwan_hub_configuration       = try(local.requested_vnet_definition.vwan_hub_peering_configuration, {})
  requested_dns_servers                  = try(local.requested_vnet_definition.dns_servers, null)

  sanitized_vnet_peering_configuration = local.requested_vnet_peering_configuration != null ? local.requested_vnet_peering_configuration : {}
  sanitized_vwan_hub_configuration     = local.requested_vwan_hub_configuration != null ? local.requested_vwan_hub_configuration : {}
  sanitized_dns_servers                = local.requested_dns_servers != null ? local.requested_dns_servers : local.default_vnet_definition.dns_servers

  core_vnet_definition = merge(
    local.default_vnet_definition,
    local.requested_vnet_definition,
    {
      dns_servers = local.sanitized_dns_servers,
      subnets = merge(
        local.default_vnet_definition.subnets,
        local.requested_vnet_subnets
      ),
      vnet_peering_configuration = merge(
        local.default_vnet_definition.vnet_peering_configuration,
        local.sanitized_vnet_peering_configuration
      ),
      vwan_hub_peering_configuration = merge(
        local.default_vnet_definition.vwan_hub_peering_configuration,
        local.sanitized_vwan_hub_configuration
      )
    }
  )
}
