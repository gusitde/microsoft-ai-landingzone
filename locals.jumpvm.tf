locals {
  jump_vm_name = coalesce(
    try(var.jumpvm_definition.name, null),
    module.naming_jump_virtual_machine.name
  )

  jump_vm_sequence_raw = can(regex("\\d+$", local.jump_vm_name)) ? regex("\\d+$", local.jump_vm_name) : "01"
  jump_vm_sequence_number = can(tonumber(local.jump_vm_sequence_raw)) ? tonumber(local.jump_vm_sequence_raw) : 1
  jump_vm_sequence        = format("%02d", local.jump_vm_sequence_number)

  # Windows computer names are limited to 15 characters. Use a deterministic
  # pattern of <prefix><proj4><env><jmp><##> to stay within the limit while still
  # conveying the workload context.
  jump_vm_computer_name = lower(substr(
    format(
      "%s%s%s%s%s",
      substr(local.core_naming_prefix, 0, 3),
      substr(local.core_project_code, 0, 4),
      substr(local.core_environment_code, 0, 3),
      "jmp",
      local.jump_vm_sequence
    ),
    0,
    15
  ))
}
