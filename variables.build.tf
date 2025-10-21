#TODO: Review how this VM will be used and what configurations should be included. (Should this be a scale set instead?)
variable "buildvm_definition" {
  type = object({
    deploy           = optional(bool, true)
    name             = optional(string)
    sku              = optional(string)
    tags             = optional(map(string), {})
    enable_telemetry = optional(bool, true)
  })
  default     = {}
  description = <<DESCRIPTION
Configuration object for the Build VM to be created for managing the implementation services.

- `deploy` - (Optional) Deploy the build vm. Default is true.
- `name` - (Optional) The name of the Build VM. If not provided, a name will be generated.
- `sku` - (Optional) The VM size/SKU for the Build VM. Defaults to the `vm_size` variable when not specified.
- `tags` - (Optional) Map of tags to assign to the Build VM.
- `enable_telemetry` - (Optional) Whether telemetry is enabled for the Build VM module. Default is true.
DESCRIPTION
}
