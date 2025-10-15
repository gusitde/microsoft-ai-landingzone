locals {
  build_vm_name = coalesce(
    try(var.buildvm_definition.name, null),
    module.naming_build_virtual_machine.name
  )
}
