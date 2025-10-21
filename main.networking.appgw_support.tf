// Supporting resources for the Application Gateway TLS certificate and networking dependencies.

resource "azurerm_user_assigned_identity" "appgw_uami" {
  count = local.deploy_app_gateway ? 1 : 0

  name                = "uami-azr-tapai-tst-weu-appgw"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  count = local.deploy_app_gateway && local.app_gateway_key_vault_resource_id != null ? 1 : 0

  scope                = local.app_gateway_key_vault_resource_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw_uami[count.index].principal_id
}

resource "azurerm_private_dns_zone" "kv" {
  count = local.core_flag_platform_landing_zone ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_link" {
  count = local.core_flag_platform_landing_zone ? 1 : 0

  name                  = "pdzlnk-kv-weu"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.kv[count.index].name
  virtual_network_id    = module.ai_lz_vnet.resource_id
}

resource "azurerm_private_endpoint" "kv" {
  count = local.core_flag_platform_landing_zone && local.app_gateway_key_vault_resource_id != null ? 1 : 0

  name                = "pe-kv-aiops-tst-weu-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.ai_lz_vnet.subnets["PrivateEndpointSubnet"].resource_id

  private_service_connection {
    name                           = "psc-kv-aiops-tst-weu-001"
    private_connection_resource_id = local.app_gateway_key_vault_resource_id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv[count.index].id]
  }
}
