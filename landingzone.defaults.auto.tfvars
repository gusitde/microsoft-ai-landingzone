# Default deployment parameters for the AI landing zone.
# These values ensure `terraform plan` can execute without interactive prompts.
# Update them as needed to target a different environment.
#
# Uncomment and populate the subscription ID if Terraform cannot infer it from your Azure login context.
# subscription_id = "00000000-0000-0000-0000-000000000000"
location                 = "westeurope"
project_code             = "aiops"
environment_code         = "tst"
resource_group_name      = "rg-aiops-tst-weu-001"
resource_group_version   = 1
enable_telemetry         = true
flag_platform_landing_zone = true

# Common VM sizes for West Europe deployments: Standard_B2ms, Standard_D2ads_v5, Standard_D2as_v5.
vm_size = "Standard_D2ds_v6"

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

# Toggle deployment of Azure Bastion. Set `deploy = false` to skip provisioning the service.
bastion_definition = {
  deploy = true
}

# Default Application Gateway configuration. Update the IPs/FQDNs or names to align with your workloads.
app_gateway_definition = {
  name = "agw-aiops-tst-weu-001"

  backend_address_pools = {
    default = {
      name         = "be-default"
      ip_addresses = ["10.0.1.4"]
    }
  }

  backend_http_settings = {
    default = {
      name     = "be-https"
      port     = 443
      protocol = "Https"
    }
  }

  frontend_ports = {
    https = {
      name = "port-443"
      port = 443
    }
  }

  http_listeners = {
    https = {
      name                 = "https-listener"
      frontend_port_name   = "port-443"
      protocol             = "Https"
      ssl_certificate_name = "tls-cert"
      require_sni          = false
    }
  }

  request_routing_rules = {
    https = {
      name                       = "https-routing-rule"
      rule_type                  = "Basic"
      http_listener_name         = "https-listener"
      backend_address_pool_name  = "be-default"
      backend_http_settings_name = "be-https"
      priority                   = 10
    }
  }
}
