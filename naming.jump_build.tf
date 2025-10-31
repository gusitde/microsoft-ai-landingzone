module "naming_jump_virtual_machine" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  org_prefix = local.core_naming_prefix
  resource    = "virtual_machine"
  descriptor  = "jump"
}

module "naming_jump_network_interface" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  org_prefix = local.core_naming_prefix
  resource    = "network_interface"
  descriptor  = "jump"
}

module "naming_jump_ip_configuration" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  org_prefix = local.core_naming_prefix
  resource    = "network_interface_ip_configuration"
  descriptor  = "jump"
}

module "naming_build_virtual_machine" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  org_prefix = local.core_naming_prefix
  resource    = "virtual_machine"
  descriptor  = "build"
  index       = 2
}

module "naming_build_network_interface" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  org_prefix = local.core_naming_prefix
  resource    = "network_interface"
  descriptor  = "build"
}

module "naming_build_ip_configuration" {
  source      = "./modules/naming"
  project     = local.core_project_code
  environment = local.core_environment_code
  location    = local.core_location
  org_prefix = local.core_naming_prefix
  resource    = "network_interface_ip_configuration"
  descriptor  = "build"
}
