module "naming_virtual_network" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "virtual_network"
}

module "naming_private_dns_vnet_link" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "private_dns_zone_virtual_network_link"
  descriptor  = "core"
}

module "naming_virtual_network_peering_forward" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "virtual_network_peering"
  descriptor  = "fwd"
}

module "naming_virtual_network_peering_reverse" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "virtual_network_peering"
  descriptor  = "rev"
  index       = 2
}

module "naming_network_security_group" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "network_security_group"
}

module "naming_firewall_route_table" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "route_table"
  descriptor  = "fw"
}

module "naming_firewall" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "azure_firewall"
}

module "naming_firewall_public_ip" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "public_ip_address"
  descriptor  = "fw"
}

module "naming_firewall_policy" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "firewall_policy"
}

module "naming_firewall_policy_rule_collection_group" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "firewall_policy_rule_collection_group"
}

module "naming_bastion_host" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "bastion_host"
}

module "naming_application_gateway" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "application_gateway"
}

module "naming_application_gateway_public_ip" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "public_ip_address"
  descriptor  = "appgw"
}

module "naming_application_gateway_waf_policy" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "web_application_firewall_policy"
}

module "naming_virtual_hub_connection" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  resource    = "virtual_hub_connection"
  descriptor  = "peer"
}
