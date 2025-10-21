locals {
  application_gateway_name = coalesce(
    try(var.app_gateway_definition.name, null),
    module.naming_application_gateway.name
  )
  application_gateway_role_assignments = merge(
    local.application_gateway_role_assignments_base,
    try(var.app_gateway_definition.role_assignments, {})
  )
  application_gateway_role_assignments_base = {}
  deploy_app_gateway = try(var.app_gateway_definition.deploy, true)
  app_gateway_key_vault_integration = try(var.app_gateway_definition.key_vault_integration, null)
  app_gateway_key_vault_name = try(local.app_gateway_key_vault_integration.name, null)
  app_gateway_key_vault_resource_group_name = try(local.app_gateway_key_vault_integration.resource_group_name, null)
  app_gateway_key_vault_resource_id_override = try(local.app_gateway_key_vault_integration.resource_id, null)
  app_gateway_key_vault_secret_name = try(local.app_gateway_key_vault_integration.secret_name, null)
  app_gateway_key_vault_secret_id_override = try(local.app_gateway_key_vault_integration.secret_id, null)
  app_gateway_key_vault_secret_base_uri = local.app_gateway_key_vault_name != null ? format("https://%s.vault.azure.net/secrets", local.app_gateway_key_vault_name) : null
  app_gateway_key_vault_secret_id = coalesce(
    (
      local.app_gateway_key_vault_secret_id_override != null ?
      (
        length(regexall("^https://", trimspace(local.app_gateway_key_vault_secret_id_override))) > 0 ?
        (
          length(regexall("/secrets/[^/]+/[^/]+$", trimspace(local.app_gateway_key_vault_secret_id_override))) > 0 ?
          regex_replace(trimspace(local.app_gateway_key_vault_secret_id_override), "/[^/]+$", "") :
          trimspace(local.app_gateway_key_vault_secret_id_override)
        ) :
        trimspace(local.app_gateway_key_vault_secret_id_override)
      ) :
      null
    ),
    (
      local.app_gateway_key_vault_secret_base_uri != null && local.app_gateway_key_vault_secret_name != null ?
      format("%s/%s", local.app_gateway_key_vault_secret_base_uri, trimspace(local.app_gateway_key_vault_secret_name)) :
      null
    )
  )
  app_gateway_key_vault_resource_id = coalesce(
    local.app_gateway_key_vault_resource_id_override,
    (
      local.app_gateway_key_vault_name != null && local.app_gateway_key_vault_resource_group_name != null ?
      format(
        "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.KeyVault/vaults/%s",
        data.azurerm_client_config.current.subscription_id,
        local.app_gateway_key_vault_resource_group_name,
        local.app_gateway_key_vault_name
      ) :
      null
    )
  )
  app_gateway_frontend_ports = coalesce(try(var.app_gateway_definition.frontend_ports, null), {})
  app_gateway_https_frontend_port_names = [
    for frontend in values(local.app_gateway_frontend_ports) :
    frontend.name if try(frontend.port, null) == 443
  ]
  app_gateway_ssl_certificates_input = coalesce(try(var.app_gateway_definition.ssl_certificates, null), {})
  app_gateway_sanitized_secret_ids = {
    for cert_key, cert_value in local.app_gateway_ssl_certificates_input :
    cert_key => (
      try(cert_value.key_vault_secret_id, null) != null && length(trimspace(cert_value.key_vault_secret_id)) > 0 ?
      (
        length(regexall("^https://", trimspace(cert_value.key_vault_secret_id))) > 0 ?
        (
          length(regexall("/secrets/[^/]+/[^/]+$", trimspace(cert_value.key_vault_secret_id))) > 0 ?
          regex_replace(trimspace(cert_value.key_vault_secret_id), "/[^/]+$", "") :
          trimspace(cert_value.key_vault_secret_id)
        ) :
        (
          local.app_gateway_key_vault_secret_base_uri != null ?
          format("%s/%s", local.app_gateway_key_vault_secret_base_uri, trimspace(cert_value.key_vault_secret_id)) :
          null
        )
      ) :
      local.app_gateway_key_vault_secret_id
    )
  }
  app_gateway_ssl_certificates = length(local.app_gateway_ssl_certificates_input) > 0 ? {
    for cert_key, cert_value in local.app_gateway_ssl_certificates_input :
    cert_key => merge(
      cert_value,
      local.app_gateway_sanitized_secret_ids[cert_key] != null ? {
        key_vault_secret_id = local.app_gateway_sanitized_secret_ids[cert_key]
      } : {}
    )
  } : (
    local.app_gateway_key_vault_secret_id != null ? {
      tls = {
        name                = "tls-cert"
        key_vault_secret_id = local.app_gateway_key_vault_secret_id
      }
    } : {}
  )
  app_gateway_primary_ssl_certificate_name = try(
    one([
      for cert in values(local.app_gateway_ssl_certificates) : cert.name
      if lower(cert.name) == "tls-cert"
    ]),
    try(values(local.app_gateway_ssl_certificates)[0].name, null)
  )
  app_gateway_http_listeners = {
    for listener_key, listener_value in coalesce(try(var.app_gateway_definition.http_listeners, null), {}) :
    listener_key => merge(
      listener_value,
      contains(local.app_gateway_https_frontend_port_names, try(listener_value.frontend_port_name, "")) || lower(try(listener_value.protocol, "")) == "https" ? merge(
        {
          protocol    = "Https"
          require_sni = true
        },
        local.app_gateway_primary_ssl_certificate_name != null ? {
          ssl_certificate_name = local.app_gateway_primary_ssl_certificate_name
        } : {}
      ) : {}
    )
  }
  bastion_name = coalesce(
    try(var.bastion_definition.name, null),
    module.naming_bastion_host.name
  )
  default_virtual_network_link = {
    alz_vnet_link = {
      vnetlinkname      = module.naming_private_dns_vnet_link.name
      vnetid            = module.ai_lz_vnet.resource_id
      autoregistration  = false
      resolution_policy = var.private_dns_zones.allow_internet_resolution_fallback == false ? "Default" : "NxDomainRedirect"
    }
  }
  deployed_subnets = { for subnet_name, subnet in local.subnets : subnet_name => subnet if subnet.enabled }
  firewall_name = coalesce(
    try(var.firewall_definition.name, null),
    module.naming_firewall.name
  )
  private_dns_zone_map = {
    key_vault_zone = {
      name = "privatelink.vaultcore.azure.net"
    }
    apim_zone = {
      name = "privatelink.azure-api.net"
    }
    cosmos_sql_zone = {
      name = "privatelink.documents.azure.com"
    }
    cosmos_mongo_zone = {
      name = "privatelink.mongo.cosmos.azure.com"
    }
    cosmos_cassandra_zone = {
      name = "privatelink.cassandra.cosmos.azure.com"
    }
    cosmos_gremlin_zone = {
      name = "privatelink.gremlin.cosmos.azure.com"
    }
    cosmos_table_zone = {
      name = "privatelink.table.cosmos.azure.com"
    }
    cosmos_analytical_zone = {
      name = "privatelink.analytics.cosmos.azure.com"
    }
    cosmos_postgres_zone = {
      name = "privatelink.postgres.cosmos.azure.com"
    }
    storage_blob_zone = {
      name = "privatelink.blob.core.windows.net"
    }
    storage_queue_zone = {
      name = "privatelink.queue.core.windows.net"
    }
    storage_table_zone = {
      name = "privatelink.table.core.windows.net"
    }
    storage_file_zone = {
      name = "privatelink.file.core.windows.net"
    }
    storage_dlfs_zone = {
      name = "privatelink.dfs.core.windows.net"
    }
    storage_web_zone = {
      name = "privatelink.web.core.windows.net"
    }
    ai_search_zone = {
      name = "privatelink.search.windows.net"
    }
    container_registry_zone = {
      name = "privatelink.azurecr.io"
    }
    app_configuration_zone = {
      name = "privatelink.azconfig.io"
    }
    ai_foundry_openai_zone = {
      name = "privatelink.openai.azure.com"
    }
    ai_foundry_ai_services_zone = {
      name = "privatelink.services.ai.azure.com"
    }
    ai_foundry_cognitive_services_zone = {
      name = "privatelink.cognitiveservices.azure.com"
    }
  }
  private_dns_zone_map_without_key_vault = {
    for key, value in local.private_dns_zone_map :
    key => value if key != "key_vault_zone"
  }
  private_dns_zones = local.core_flag_platform_landing_zone == true ? local.private_dns_zone_map_without_key_vault : {}
  private_dns_zones_existing = local.core_flag_platform_landing_zone == false ? { for key, value in local.private_dns_zone_map : key => {
    name        = value.name
    resource_id = "${coalesce(var.private_dns_zones.existing_zones_resource_group_resource_id, "notused")}/providers/Microsoft.Network/privateDnsZones/${value.name}" #TODO: determine if there is a more elegant way to do this while avoiding errors
    }
  } : {}
  route_table_name = module.naming_firewall_route_table.name
  subnets = {
    AzureBastionSubnet = {
      enabled          = local.core_flag_platform_landing_zone == true ? try(local.core_vnet_definition.subnets["AzureBastionSubnet"].enabled, true) : try(local.core_vnet_definition.subnets["AzureBastionSubnet"].enabled, false)
      name             = "AzureBastionSubnet"
      address_prefixes = try(local.core_vnet_definition.subnets["AzureBastionSubnet"].address_prefix, null) != null ? [local.core_vnet_definition.subnets["AzureBastionSubnet"].address_prefix] : [cidrsubnet(local.core_vnet_definition.address_space, 3, 5)]
      route_table      = null
      #network_security_group = {
      #  id = module.nsgs.resource_id
      #}
    }
    AzureFirewallSubnet = {
      enabled          = local.core_flag_platform_landing_zone == true ? try(local.core_vnet_definition.subnets["AzureFirewallSubnet"].enabled, true) : try(local.core_vnet_definition.subnets["AzureFirewallSubnet"].enabled, false)
      name             = "AzureFirewallSubnet"
      address_prefixes = try(local.core_vnet_definition.subnets["AzureFirewallSubnet"].address_prefix, null) != null ? [local.core_vnet_definition.subnets["AzureFirewallSubnet"].address_prefix] : [cidrsubnet(local.core_vnet_definition.address_space, 3, 4)]
      route_table      = null
    }
    JumpboxSubnet = {
      enabled          = local.core_flag_platform_landing_zone == true ? try(local.core_vnet_definition.subnets["JumpboxSubnet"].enabled, true) : try(local.core_vnet_definition.subnets["JumpboxSubnet"].enabled, false)
      name             = try(local.core_vnet_definition.subnets["JumpboxSubnet"].name, null) != null ? local.core_vnet_definition.subnets["JumpboxSubnet"].name : "JumpboxSubnet"
      address_prefixes = try(local.core_vnet_definition.subnets["JumpboxSubnet"].address_prefix, null) != null ? [local.core_vnet_definition.subnets["JumpboxSubnet"].address_prefix] : [cidrsubnet(local.core_vnet_definition.address_space, 4, 6)]
      route_table = local.core_flag_platform_landing_zone == true ? {
        id = module.firewall_route_table[0].resource_id
      } : null
      network_security_group = {
        id = module.nsgs.resource_id
      }
    }
    AppGatewaySubnet = {
      enabled          = true
      name             = try(local.core_vnet_definition.subnets["AppGatewaySubnet"].name, null) != null ? local.core_vnet_definition.subnets["AppGatewaySubnet"].name : "AppGatewaySubnet"
      address_prefixes = try(local.core_vnet_definition.subnets["AppGatewaySubnet"].address_prefix, null) != null ? [local.core_vnet_definition.subnets["AppGatewaySubnet"].address_prefix] : [cidrsubnet(local.core_vnet_definition.address_space, 4, 5)]
      route_table = local.core_flag_platform_landing_zone == true ? {
        id = module.firewall_route_table[0].resource_id
      } : null
      network_security_group = {
        id = module.nsgs.resource_id
      }
      delegation = [{
        name = "AppGatewaySubnetDelegation"
        service_delegation = {
          name = "Microsoft.Network/applicationGateways"
        }
      }]
    }
    APIMSubnet = {
      enabled          = true
      name             = try(local.core_vnet_definition.subnets["APIMSubnet"].name, null) != null ? local.core_vnet_definition.subnets["APIMSubnet"].name : "APIMSubnet"
      address_prefixes = try(local.core_vnet_definition.subnets["APIMSubnet"].address_prefix, null) != null ? [local.core_vnet_definition.subnets["APIMSubnet"].address_prefix] : [cidrsubnet(local.core_vnet_definition.address_space, 4, 4)]
      route_table = local.core_flag_platform_landing_zone == true ? {
        id = module.firewall_route_table[0].resource_id
      } : null
      network_security_group = {
        id = module.nsgs.resource_id
      }
    }
    AIFoundrySubnet = {
      enabled          = true
      name             = try(local.core_vnet_definition.subnets["AIFoundrySubnet"].name, null) != null ? local.core_vnet_definition.subnets["AIFoundrySubnet"].name : "AIFoundrySubnet"
      address_prefixes = try(local.core_vnet_definition.subnets["AIFoundrySubnet"].address_prefix, null) != null ? [local.core_vnet_definition.subnets["AIFoundrySubnet"].address_prefix] : [cidrsubnet(local.core_vnet_definition.address_space, 4, 3)]
      route_table = local.core_flag_platform_landing_zone == true ? {
        id = module.firewall_route_table[0].resource_id
      } : null
      network_security_group = {
        id = module.nsgs.resource_id
      }
      delegation = [{
        name = "AgentServiceDelegation"
        service_delegation = {
          name    = "Microsoft.App/environments"
          actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }]
    }
    DevOpsBuildSubnet = {
      enabled          = true
      name             = try(local.core_vnet_definition.subnets["DevOpsBuildSubnet"].name, null) != null ? local.core_vnet_definition.subnets["DevOpsBuildSubnet"].name : "DevOpsBuildSubnet"
      address_prefixes = try(local.core_vnet_definition.subnets["DevOpsBuildSubnet"].address_prefix, null) != null ? [local.core_vnet_definition.subnets["DevOpsBuildSubnet"].address_prefix] : [cidrsubnet(local.core_vnet_definition.address_space, 4, 2)]
      route_table = local.core_flag_platform_landing_zone == true ? {
        id = module.firewall_route_table[0].resource_id
      } : null
      network_security_group = {
        id = module.nsgs.resource_id
      }
    }
    ContainerAppEnvironmentSubnet = {
      delegation = [{
        name = "ContainerAppEnvironmentSubnetDelegation"
        service_delegation = {
          name = "Microsoft.App/environments"
        }
      }]
      enabled          = true
      name             = try(local.core_vnet_definition.subnets["ContainerAppEnvironmentSubnet"].name, null) != null ? local.core_vnet_definition.subnets["ContainerAppEnvironmentSubnet"].name : "ContainerAppEnvironmentSubnet"
      address_prefixes = try(local.core_vnet_definition.subnets["ContainerAppEnvironmentSubnet"].address_prefix, null) != null ? [local.core_vnet_definition.subnets["ContainerAppEnvironmentSubnet"].address_prefix] : [cidrsubnet(local.core_vnet_definition.address_space, 4, 1)]
      route_table = local.core_flag_platform_landing_zone == true ? {
        id = module.firewall_route_table[0].resource_id
      } : null
    }
    PrivateEndpointSubnet = {
      enabled          = true
      name             = try(local.core_vnet_definition.subnets["PrivateEndpointSubnet"].name, null) != null ? local.core_vnet_definition.subnets["PrivateEndpointSubnet"].name : "PrivateEndpointSubnet"
      address_prefixes = try(local.core_vnet_definition.subnets["PrivateEndpointSubnet"].address_prefix, null) != null ? [local.core_vnet_definition.subnets["PrivateEndpointSubnet"].address_prefix] : [cidrsubnet(local.core_vnet_definition.address_space, 4, 0)]
      route_table = local.core_flag_platform_landing_zone == true ? {
        id = module.firewall_route_table[0].resource_id
      } : null
      network_security_group = {
        id = module.nsgs.resource_id
      }
    }
  }
  virtual_network_links = merge(local.default_virtual_network_link, var.private_dns_zones.network_links)
  vnet_name = coalesce(
    try(local.core_vnet_definition.name, null),
    module.naming_virtual_network.name
  )
  #web_application_firewall_managed_rules = var.waf_policy_definition.managed_rules == null ? {
  #  managed_rule_set = tomap({
  #    owasp = {
  #      version = "3.2"
  #      type    = "OWASP"
  #      rule_group_override = null
  #    }
  #  })
  #} : var.waf_policy_definition.managed_rules
  web_application_firewall_policy_name = coalesce(
    try(var.waf_policy_definition.name, null),
    module.naming_application_gateway_waf_policy.name
  )
}
