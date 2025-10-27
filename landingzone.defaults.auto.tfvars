# Default deployment parameters for the AI landing zone.
# These values ensure `terraform plan` can execute without interactive prompts.
# Update them as needed to target a different environment.
#
# Uncomment and populate the subscription ID if Terraform cannot infer it from your Azure login context.
subscription_id            = "06bfa713-9d6d-44a9-8643-b39e003e136b"
location                   = "swedencentral"
project_code               = "aiops"
environment_code           = "tst"
resource_group_name        = "rg-aiops-tst-sec-001"
resource_group_version     = 1
enable_telemetry           = true
flag_platform_landing_zone = false

# Common VM sizes for West Europe deployments: Standard_B2ms, Standard_D2ads_v5, Standard_D2as_v5.
vm_size = "Standard_D2ds_v6"

vnet_definition = {
  name          = "vnet-ai-swedencentral"
  address_space = "10.0.0.0/22"
  subnets = {
    workload = {
      name           = "snet-workload"
      address_prefix = "10.0.1.0/25"
    }
  }
}

# No tags are assigned by default. Provide a map like { costcenter = "1234" } if required.
tags = null

# Remove shared access key requirements and use only OAuth authentication
genai_storage_account_definition = {
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  public_network_access_enabled   = false
}

genai_container_registry_definition = {
  zone_redundancy_enabled = false
}

# Toggle deployment of Azure Bastion. Set `deploy = false` to skip provisioning the service.
bastion_definition = {
  deploy = false
}

# Toggle deployment of Azure Firewall. Set `deploy = false` to skip provisioning the service.
firewall_definition = {
  deploy = false
}

# Default Application Gateway configuration. Update the IPs/FQDNs or names to align with your workloads.
app_gateway_definition = {
  name = "agw-aiops-tst-sec-001"

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

# API Management configuration - enables APIM deployment
apim_definition = {
  deploy                        = true
  publisher_email              = "admin@example.com"
  publisher_name               = "API Management Admin"
  sku_root                     = "Developer"
  sku_capacity                 = 1
  additional_locations         = null
  certificate                  = null
  client_certificate_enabled   = false
  hostname_configuration       = null
  min_api_version             = null
  notification_sender_email    = null
  protocols                    = null
  sign_in                      = null
  sign_up                      = null
  tags                         = null
  tenant_access               = null
}

