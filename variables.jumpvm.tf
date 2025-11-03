variable "jumpvm_definition" {
  type = object({
    deploy           = optional(bool, true)
    name             = optional(string)
    sku              = optional(string)
    tags             = optional(map(string), {})
    enable_telemetry = optional(bool, true)
  })
  default     = {}
  description = <<DESCRIPTION
Configuration object for the Jump VM to be created for managing the implementation services.

- `name` - (Optional) The name of the Jump VM. If not provided, a name will be generated.
- The underlying Windows computer name is automatically generated using the
  `<prefix><proj4><env><jmp><##>` pattern to satisfy the 15-character limit; override the
  module input only if the resulting computer name still respects this constraint.
- `sku` - (Optional) The VM size/SKU for the Jump VM. Defaults to the `vm_size` variable when not specified.
- `tags` - (Optional) Map of tags to assign to the Jump VM.
- `enable_telemetry` - (Optional) Whether telemetry is enabled for the Jump VM module. Default is true.
DESCRIPTION
}
