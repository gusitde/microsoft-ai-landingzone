# Default deployment parameters for the AI landing zone.
# These values ensure `terraform plan` can execute without interactive prompts.
# Update them as needed to target a different environment.
location                 = "westeurope"
project_code             = "aiops"
environment_code         = "tst"
resource_group_name      = "rg-aiops-tst-weu-001"
resource_group_version   = 1
enable_telemetry         = true
flag_platform_landing_zone = true

vnet_definition = {
  name          = "vnet-ai-westeu"
  address_space = "10.0.0.0/16"
  subnets = {
    workload = {
      name           = "snet-workload"
      address_prefix = "10.0.1.0/24"
    }
  }
}

# No tags are assigned by default. Provide a map like { costcenter = "1234" } if required.
tags = null
