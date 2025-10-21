terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    azurecaf = {
      source  = "aztfmod/azurecaf"
      version = "~> 1.2"
    }
  }
}

variable "project" {
  type        = string
  description = "Short project or workload code."

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", lower(var.project)))
    error_message = "project must be 2-6 lowercase letters or digits."
  }
}

variable "environment" {
  type        = string
  description = "Environment code (tst, qlt, prd)."

  validation {
    condition     = contains(["tst", "qlt", "prd"], lower(var.environment))
    error_message = "environment must be one of: tst, qlt, prd."
  }
}

variable "location" {
  type        = string
  description = "Azure location for the resource."
}

variable "resource" {
  type        = string
  description = "Logical resource type key."
}

variable "descriptor" {
  type        = string
  default     = ""
  description = "Optional descriptor appended to the resource type."
}

variable "index" {
  type        = number
  default     = 1
  description = "Sequence number for the resource instance."
}

variable "rg_version" {
  type        = number
  default     = 1
  description = "Version token used for resource groups."
}

variable "unique" {
  type        = bool
  default     = null
  description = "Force a globally unique suffix for resources that require it."
}

variable "unique_length" {
  type        = number
  default     = 4
  description = "Length of the random suffix when uniqueness is required."
}

variable "enable_azurecaf" {
  type        = bool
  default     = true
  description = "Set to false to skip the azurecaf provider and rely on deterministic fallback naming."
}

locals {
  region_abbr = {
    westeurope    = "weu"
    northeurope   = "neu"
    eastus        = "eus"
    eastus2       = "eus2"
    westus3       = "wus3"
    brazilsouth   = "brs"
    uksouth       = "uks"
    francecentral = "frc"
    swedencentral = "sec"
  }

  type_abbr = {
    application_gateway                            = "appgw"
    api_management                                 = "apim"
    app_configuration                              = "appcfg"
    azure_firewall                                 = "afw"
    azure_firewall_ip_configuration                = "afwip"
    bastion_host                                   = "bast"
    bing_grounding_account                         = "bing"
    cognitive_account                              = "cog"
    cosmosdb_account                               = "cosmos"
    container_app_environment                      = "cae"
    container_registry                             = "acr"
    firewall_policy                                = "fwpol"
    firewall_policy_rule_collection_group          = "fwrcg"
    web_application_firewall_policy                = "wafp"
    key_vault                                      = "kv"
    linux_virtual_machine                          = "vm"
    log_analytics_workspace                        = "law"
    managed_disk                                   = "disk"
    network_interface                              = "nic"
    network_interface_ip_configuration              = "ipcfg"
    network_security_group                         = "nsg"
    os_disk                                        = "osdisk"
    public_ip_address                              = "pip"
    private_endpoint                               = "pe"
    private_dns_zone_virtual_network_link          = "pdzlnk"
    resource_group                                 = "rg"
    route_table                                    = "rt"
    search_service                                 = "srch"
    service_plan                                   = "asp"
    storage_account                                = "st"
    subnet                                         = "snet"
    virtual_network_peering                        = "peer"
    virtual_hub_connection                         = "vhc"
    virtual_machine                                 = "vm"
    virtual_network                                = "vnet"
    windows_virtual_machine                        = "vm"
  }

  type_to_azurerm = {
    application_gateway                   = "azurerm_application_gateway"
    api_management                        = "azurerm_api_management"
    app_configuration                     = "azurerm_app_configuration"
    azure_firewall                        = "azurerm_firewall"
    bastion_host                          = "azurerm_bastion_host"
    bing_grounding_account                = "azurerm_resource_group"
    cognitive_account                     = "azurerm_cognitive_account"
    container_app_environment             = "azurerm_container_app_environment"
    container_registry                    = "azurerm_container_registry"
    cosmosdb_account                      = "azurerm_cosmosdb_account"
    firewall_policy                       = "azurerm_firewall_policy"
    firewall_policy_rule_collection_group = "general"
    web_application_firewall_policy       = "azurerm_web_application_firewall_policy"
    key_vault                             = "azurerm_key_vault"
    linux_virtual_machine                 = "azurerm_linux_virtual_machine"
    log_analytics_workspace               = "azurerm_log_analytics_workspace"
    managed_disk                          = "azurerm_managed_disk"
    network_interface                     = "azurerm_network_interface"
    network_interface_ip_configuration     = "azurerm_network_interface"
    network_security_group                = "azurerm_network_security_group"
    os_disk                               = "azurerm_managed_disk"
    public_ip_address                     = "azurerm_public_ip"
    private_endpoint                      = "azurerm_private_endpoint"
    private_dns_zone_virtual_network_link = "azurerm_private_dns_zone_virtual_network_link"
    resource_group                        = "azurerm_resource_group"
    route_table                           = "azurerm_route_table"
    search_service                        = "azurerm_search_service"
    service_plan                          = "azurerm_service_plan"
    storage_account                       = "azurerm_storage_account"
    subnet                                = "azurerm_subnet"
    virtual_network_peering              = "azurerm_virtual_network_peering"
    virtual_hub_connection               = "azurerm_virtual_hub_connection"
    virtual_machine                      = "azurerm_virtual_machine"
    virtual_network                       = "azurerm_virtual_network"
    windows_virtual_machine               = "azurerm_windows_virtual_machine"
  }

  needs_unique = toset([
    "app_configuration",
    "cognitive_account",
    "container_registry",
    "cosmosdb_account",
    "search_service",
    "storage_account"
  ])

  project = lower(var.project)
  env     = lower(var.environment)
  region  = lookup(local.region_abbr, lower(var.location), lower(var.location))
  rshort  = lookup(local.type_abbr, var.resource, var.resource)

  base_parts = compact([
    "azr",
    local.project,
    local.env,
    local.region,
    local.rshort,
    var.descriptor != "" ? lower(var.descriptor) : null
  ])

  tail       = var.resource == "resource_group" ? [format("%02d", var.rg_version)] : [format("%02d", var.index)]
  human_name = join("-", concat(local.base_parts, local.tail))

  unique_auto = var.unique == null ? contains(local.needs_unique, var.resource) : var.unique

  # Provide a deterministic fallback name that honours the base naming
  # convention even if the azurecaf provider cannot generate a value.
  fallback_base   = lower(replace(join("", concat(local.base_parts, local.tail)), "[^0-9a-z]", ""))
  fallback_length = length(local.fallback_base) < 63 ? length(local.fallback_base) : 63

  use_azurecaf = var.enable_azurecaf
}

data "azurecaf_name" "this" {
  count = local.use_azurecaf ? 1 : 0

  name          = local.human_name
  resource_type = lookup(local.type_to_azurerm, var.resource, "azurerm_resource_group")
  separator     = "-"
  clean_input   = true
  random_length = local.unique_auto ? var.unique_length : 0
}

locals {
  azurecaf_result = local.use_azurecaf && length(data.azurecaf_name.this) > 0 ? data.azurecaf_name.this[0].result : null
  azurecaf_parts  = local.azurecaf_result != null ? split("-", local.azurecaf_result) : []
  azurecaf_without_prefix = local.azurecaf_result != null ? (
    length(local.azurecaf_parts) > 1 ?
    join("-", slice(local.azurecaf_parts, 1, length(local.azurecaf_parts))) :
    (
      startswith(local.azurecaf_result, local.rshort) && length(local.azurecaf_result) > length(local.rshort) ?
      substr(local.azurecaf_result, length(local.rshort), length(local.azurecaf_result) - length(local.rshort)) :
      local.azurecaf_result
    )
  ) : null
  azurecaf_cleaned = local.azurecaf_without_prefix != null && local.azurecaf_without_prefix != "" ? local.azurecaf_without_prefix : local.azurecaf_result
}

output "name" {
  value = coalesce(local.azurecaf_cleaned, substr(local.fallback_base, 0, local.fallback_length))
}
