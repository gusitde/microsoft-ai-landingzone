variable "location" {
  type        = string
  description = <<DESCRIPTION
Azure region where all resources should be deployed.

This specifies the primary Azure region for deploying the AI/ML landing zone infrastructure. All resources will be created in this region unless specifically configured otherwise in individual resource definitions.

**Input format:** Provide the Azure region name in lowercase without spaces. For example, enter `westeurope`.

**Sample entry:**
```
westeurope
```
DESCRIPTION
  nullable    = false
}

# This is required for most resource modules
variable "project_code" {
  type        = string
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
    condition     = can(regex("^[a-z0-9]{2,6}$", lower(var.project_code)))
    error_message = "project_code must be 2-6 lowercase letters or digits."
  }
}

variable "environment_code" {
  type        = string
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
    condition     = contains(["tst", "qlt", "prd"], lower(var.environment_code))
    error_message = "environment_code must be one of: tst, qlt, prd."
  }
}

variable "resource_group_version" {
  type        = number
  default     = 1
  description = <<DESCRIPTION
Incrementing version number applied to the resource group when generating the CAF-compliant name.

Increase this number when a resource group rename is required because the Azure Resource Manager APIs do not allow renaming resource groups once they are created.
DESCRIPTION

  validation {
    condition     = var.resource_group_version >= 1 && var.resource_group_version <= 99
    error_message = "resource_group_version must be between 1 and 99."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
  nullable    = false
}

variable "flag_platform_landing_zone" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
Flag to indicate if the platform landing zone is enabled.

If set to true, the module will deploy resources and connect to a platform landing zone hub. This enables integration with existing hub-and-spoke network architectures and centralized management services.
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
