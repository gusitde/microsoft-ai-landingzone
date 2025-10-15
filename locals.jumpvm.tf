locals {
  jump_vm_name = coalesce(
    try(var.jumpvm_definition.name, null),
    module.naming_jump_virtual_machine.name
  )
}
