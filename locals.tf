locals {
  paired_region = [for region in module.avm_utl_regions.regions : region if(lower(region.name) == lower(azurerm_resource_group.this.location) || (lower(region.display_name) == lower(azurerm_resource_group.this.location)))][0].paired_region_name
  #paired_region_zones        = local.paired_region_zones_lookup != null ? local.paired_region_zones_lookup : []
  #paired_region_zones_lookup = [for region in module.avm_utl_regions.regions : region if(lower(region.name) == lower(local.paired_region) || (lower(region.display_name) == lower(local.paired_region)))][0].zones
  region_zones        = local.region_zones_lookup != null ? local.region_zones_lookup : []
  region_zones_lookup = [for region in module.avm_utl_regions.regions : region if(lower(region.name) == lower(azurerm_resource_group.this.location) || (lower(region.display_name) == lower(azurerm_resource_group.this.location)))][0].zones

  # Region abbreviations mapping
  region_abbreviations = {
    "westeurope"    = "weu"
    "swedencentral" = "sec"
    "eastus"        = "eus"
    "eastus2"       = "eus2"
    "westus"        = "wus"
    "westus2"       = "wus2"
    "northeurope"   = "neu"
    "southeastasia" = "sea"
  }

  region_code = lookup(local.region_abbreviations, lower(azurerm_resource_group.this.location), "unk")
}
