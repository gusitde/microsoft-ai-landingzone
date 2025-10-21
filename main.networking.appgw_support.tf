// Supporting resources for the Application Gateway TLS certificate and networking dependencies.
data "azurerm_key_vault" "appgw_kv" {
  name                = "kv-aiops-tst-weu-001"
  resource_group_name = "azr-tapai-tst-weu-rg-001"
}

data "azurerm_key_vault_secret" "appgw_cert" {
  name         = "appgw-cert"
  key_vault_id = data.azurerm_key_vault.appgw_kv.id
}

locals {
  appgw_cert_versionless_secret_id = trimsuffix(
    data.azurerm_key_vault_secret.appgw_cert.id,
    "/${data.azurerm_key_vault_secret.appgw_cert.version}"
  )
}

resource "azurerm_user_assigned_identity" "appgw_uami" {
  count = local.deploy_app_gateway ? 1 : 0

  name                = "uami-azr-tapai-tst-weu-appgw"
  resource_group_name = "azr-tapai-tst-weu-rg-001"
  location            = "westeurope"
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  count = local.deploy_app_gateway ? 1 : 0

  scope                = data.azurerm_key_vault.appgw_kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw_uami[count.index].principal_id
}

resource "azurerm_private_dns_zone" "kv" {
  count = local.core_flag_platform_landing_zone ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = "azr-tapai-tst-weu-rg-001"
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_link" {
  count = local.core_flag_platform_landing_zone ? 1 : 0

  name                  = "pdzlnk-kv-weu"
  resource_group_name   = "azr-tapai-tst-weu-rg-001"
  private_dns_zone_name = azurerm_private_dns_zone.kv[count.index].name
  virtual_network_id    = module.ai_lz_vnet.resource_id
}

resource "azurerm_private_endpoint" "kv" {
  count = local.core_flag_platform_landing_zone ? 1 : 0

  name                = "pe-kv-aiops-tst-weu-001"
  location            = "westeurope"
  resource_group_name = "azr-tapai-tst-weu-rg-001"
  subnet_id           = module.ai_lz_vnet.subnets["PrivateEndpointSubnet"].resource_id

  private_service_connection {
    name                           = "psc-kv-aiops-tst-weu-001"
    private_connection_resource_id = data.azurerm_key_vault.appgw_kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv[count.index].id]
  }
}
