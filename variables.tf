variable "location" {
  type        = string
  default     = null
  description = <<DESCRIPTION
Azure region where all resources should be deployed.

This specifies the primary Azure region for deploying the AI/ML landing zone infrastructure. All resources will be created in this region unless specifically configured otherwise in individual resource definitions.

**Input format:** Provide the Azure region name in lowercase without spaces. For example, enter `westeurope`.

**Sample entry:**
```
westeurope
```
DESCRIPTION
  nullable    = true
}

# This is required for most resource modules
variable "project_code" {
  type        = string
  default     = null
  description = <<DESCRIPTION
Short code that identifies the workload or project (2-6 lowercase alphanumeric characters).

This value is used as part of the central naming convention that is applied to every resource created by the landing zone. The
value should be stable for the lifetime of the deployment so that resource names remain consistent.

**Input format:** Use 2-6 lowercase letters or digits with no spaces or special characters.

**Sample entry:**
```
aiops
```
DESCRIPTION

  validation {
    condition     = var.project_code == null || can(regex("^[a-z0-9]{2,6}$", lower(var.project_code)))
    error_message = "project_code must be 2-6 lowercase letters or digits."
  }
}

variable "environment_code" {
  type        = string
  default     = null
  description = <<DESCRIPTION
Environment discriminator for the landing zone (for example tst, qlt, prd).

The environment code participates in the centralized naming scheme and should map to the organisation's release lifecycle nomenclature.

**Input format:** Enter one of the supported three-letter environment codes in lowercase (for example `tst`, `qlt`, or `prd`).

**Sample entry:**
```
tst
```
DESCRIPTION

  validation {
    condition     = var.environment_code == null || contains(["tst", "qlt", "prd"], lower(var.environment_code))
    error_message = "environment_code must be one of: tst, qlt, prd."
  }
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = <<DESCRIPTION
The name of the resource group where all landing zone resources are deployed.

This value must follow your organisation's naming conventions and align with the location, project code, and environment code.
The provided default matches the built-in defaults (`project_code = aiops`, `environment_code = tst`, and `location = westeurope`).

**Default value:** `rg-aiops-tst-weu-001`. Update this if you need to deploy into an existing resource group with a different name.

**Input format:** Provide the full Azure resource group name in lowercase using hyphens (for example `rg-aiops-tst-weu-001`).

**Sample entry:**
```
rg-aiops-tst-weu-001
```
DESCRIPTION
  nullable    = true
}

variable "resource_group_version" {
  type        = number
  default     = null
  description = <<DESCRIPTION
Incrementing version number applied to the resource group when generating the CAF-compliant name.

Increase this number when a resource group rename is required because the Azure Resource Manager APIs do not allow renaming resource groups once they are created.
DESCRIPTION

  validation {
    condition     = var.resource_group_version == null || (var.resource_group_version >= 1 && var.resource_group_version <= 99)
    error_message = "resource_group_version must be between 1 and 99."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = null
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
  nullable    = true
}

variable "subscription_id" {
  type        = string
  default     = null
  description = <<DESCRIPTION
Optional Azure subscription ID that Terraform should target when running this module.

Provide this value if the deployment environment cannot rely on the Azure CLI, environment variables, or managed identity to
select the subscription automatically. Supplying the subscription ID avoids errors such as
`subscription ID could not be determined and was not specified` during provider initialization.

Leave the value unset (or `null`) to continue using the ambient Azure authentication context.
DESCRIPTION
  nullable    = true

  validation {
    condition     = var.subscription_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", trimspace(var.subscription_id)))
    error_message = "subscription_id must be a valid GUID in the format 00000000-0000-0000-0000-000000000000."
  }
}

variable "flag_platform_landing_zone" {
  type        = bool
  default     = null
  description = <<DESCRIPTION
Flag to indicate if the platform landing zone is enabled. Default is false.

If set to true, the module will deploy platform resources like VMs, firewall, bastion, and connect to a platform landing zone hub. This enables integration with existing hub-and-spoke network architectures and centralized management services.

If set to false (default), only core AI services will be deployed without platform infrastructure components.
DESCRIPTION
}

variable "vm_size" {
  type        = string
  default     = "Standard_B2ms"
  description = <<DESCRIPTION
Azure virtual machine size used for workloads deployed by this landing zone.

The default `Standard_B2ms` SKU is broadly available in West Europe. Alternative balanced options you can consider include `Standard_D2ads_v5` and `Standard_D2as_v5` if capacity constraints require a change.
DESCRIPTION
}

variable "tags" {
  type        = map(string)
  default     = null
  description = <<DESCRIPTION
Map of tags to be assigned to all resources created by this module.

Tags are key-value pairs that help organize and manage Azure resources. These tags will be applied to all resources created by the module, enabling consistent resource governance, cost tracking, and operational management across the AI/ML landing zone infrastructure.
DESCRIPTION
}
