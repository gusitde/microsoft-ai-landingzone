# Microsoft AI Landing Zone (Terraform)

## Overview
This repository defines a composable Azure AI landing zone using Terraform and Azure Verified Modules (AVM). It provisions the shared infrastructure required to host secure, enterprise-ready generative AI workloads, including regional networking, governance controls, developer tooling, and platform services. The configuration is split into focused Terraform configuration files so that each workload area (networking, compute, security, data, monitoring, and developer experience) can be customized independently while still following the central naming and tagging policies that the landing zone enforces.

AI landign zone archtetural types:

<img width="2323" height="1386" alt="AI-Landing-Zone-with-platform" src="https://github.com/user-attachments/assets/70afd5a4-99e6-44e2-b10b-22c9c099eee9" />
<img width="1961" height="1158" alt="AI-Landing-Zone-without-platform" src="https://github.com/user-attachments/assets/62da6994-a99e-4404-b151-c576cfce8907" />


### Key capabilities
- **Resource organization** – Creates an Azure resource group that follows Cloud Adoption Framework (CAF) naming using the bundled naming module, and applies consistent tagging across the deployment.
- **Virtual network foundation** – Builds a spoke virtual network with delegated subnets for application workloads, private endpoints, Container Apps, DevOps build resources, Bastion, Azure Firewall, and optional peering or Virtual WAN connectivity to an existing hub network.
- **Perimeter security** – Optionally deploys Azure Firewall, firewall policy rule collections, network security groups, and Bastion hosts to provide secure inbound and outbound access paths.
- **Platform monitoring** – Reuses or creates a Log Analytics workspace and wires diagnostic settings from all major services for centralized observability.
- **Generative AI services** – Delivers core data and application services for GenAI solutions such as Azure AI Foundry, Azure OpenAI/AI Search, Cosmos DB, Key Vault, Azure Container Apps, Storage accounts, Container Registry, and App Configuration, each with private connectivity and RBAC integration when enabled.
- **Developer and operations tooling** – Provides optional build and jump virtual machines that retrieve credentials from Key Vault and are constrained to dedicated subnets for administration tasks.
- **API surface exposure** – Optionally deploys Azure API Management with private endpoints to expose AI workloads securely to consumers.
- **Telemetry compliance** – Integrates the AVM telemetry helper to emit anonymous usage data required by the ecosystem (can be disabled via variables).

## Repository structure
The top-level Terraform files are organized by functional area. Some highlights include:

| Path | Purpose |
| --- | --- |
| `main.tf` | Core resource group, naming convention, and shared data sources. |
| `main.networking.tf` | Virtual network, subnets, firewalls, DNS zones, Bastion, and connectivity. |
| `main.genai_services.tf` | Key Vault, Cosmos DB, Storage, Container Apps, Container Registry, App Configuration, and supporting role assignments. |
| `main.knowledge_sources.tf` | Azure AI Search and Bing Grounding services. |
| `main.foundry.tf` | Azure AI Foundry pattern module with private endpoints and purge controls. |
| `main.apim.tf` | Azure API Management service for secure API exposure. |
| `main.build.tf` / `main.jumpvm.tf` | Optional virtual machines for DevOps build agents and secure jump access. |
| `variables*.tf` | Variable definitions grouped by feature area with extensive inline documentation. |
| `outputs.tf` | Placeholder for landing zone outputs (customize to expose IDs or endpoints). |

## Prerequisites
Before you deploy the landing zone, ensure the following:

1. **Azure subscription access** with permissions to create resource groups, networking, Key Vault, Cosmos DB, Container Apps, API Management, and AI services.
2. **Terraform CLI** version `>= 1.9, < 2.0`, matching the requirement defined in `terraform.tf`.
3. **Azure CLI** (or another authentication mechanism such as Azure PowerShell, Managed Identity, or service principal credentials) to authenticate with Azure.
4. **Remote state storage** (optional but recommended) such as Azure Storage to preserve Terraform state between runs.
5. **AVM tooling** if you plan to contribute back to the module (see `./avm` scripts and repository `AGENTS.md` for validation guidance).

## Configuration
All behavior is controlled through variables that ship with descriptive documentation. Some important entry points include:

- `variables.tf` – Sets global values such as `location`, `project_code`, `environment_code`, `tags`, and feature flags for telemetry and platform landing zone integration.
- The feature-specific files (`variables.genai_services.tf`, `variables.networking.tf`, `variables.jumpvm.tf`, etc.) – Define nested objects where each major service can be toggled on/off (`deploy`), renamed, and customized with security, networking, SKU, and diagnostic options.

To simplify configuration:

1. Copy `terraform.tfvars` (create the file if it does not exist) and provide at least:
   ```hcl
   location         = "eastus"
   project_code     = "aihub"
   environment_code = "tst"
   tags = {
     costCenter = "12345"
     owner      = "ai-platform-team"
   }
   ```
2. Add or override the nested objects that align with the services you want to deploy. For example, to disable the build VM you can set `buildvm_definition = { deploy = false }`, or to supply an existing Log Analytics workspace specify `law_definition = { resource_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.OperationalInsights/workspaces/..." }`.
3. Store any sensitive values (such as custom role assignment principal IDs) in secure variable files or use environment variables to avoid committing secrets.

### Default values for non-interactive runs

The repository includes defaults so that `terraform plan` and `terraform apply` can run without prompting for input:

| Variable | Default | Notes |
| --- | --- | --- |
| `location` | `westeurope` | Set in `landingzone.defaults.auto.tfvars` to target the sample region. |
| `project_code` | `aiops` | Used for CAF-compliant naming of all resources. |
| `environment_code` | `tst` | Drives environment-specific naming and tagging. |
| `resource_group_name` | `rg-aiops-tst-weu-001` | Matches the default naming convention for the sample environment. |
| `waf_policy_definition.managed_rules` | OWASP 3.2 | The WAF policy ships with an OWASP 3.2 managed rule set in Prevention mode. |
| `app_gateway_definition` | WAF_v2 HTTPS listener with placeholder backend `10.0.1.4` | Provides a fully populated Application Gateway configuration so Terraform does not prompt for required fields. Update the backend IPs/FQDNs to match your workloads. |

These defaults are safe starting points for evaluation. Adjust them (or override them in your own `.tfvars` file) before deploying to production so that the Application Gateway routes traffic to the correct services and aligns with your organisation's standards.

## Step-by-step deployment
Follow this sequence to stand up the landing zone:

1. **Clone the repository**
   ```bash
   git clone https://github.com/<your-org>/microsoft-ai-landingzone.git
   cd microsoft-ai-landingzone
   ```
2. **Install dependencies** – Ensure Terraform and the Azure CLI meet the prerequisites above, then sign in:
   ```bash
   az login
   az account set --subscription <subscription-id>
   ```
3. **Configure backend (optional)** – If using remote state, create the storage account/container and update a `backend` block in `terraform {}` or supply `-backend-config` values during `terraform init`.
4. **Review the default variables** – The repository ships with `landingzone.defaults.auto.tfvars`, which pre-populates a CAF-aligned test deployment (West Europe, `aiops` project code, `tst` environment, and the sample VNet). Update this file or provide your own `.tfvars` to target a different environment.
5. **Initialize Terraform**
   ```bash
   terraform init
   ```
   This downloads the required providers (`azurerm`, `azapi`, `azurecaf`, `modtm`, `random`, `time`) and AVM modules referenced in the configuration.
6. **Review the configuration**
   ```bash
   terraform fmt -recursive
   terraform validate
   terraform plan -out landingzone.plan
   ```
   Use the plan output to confirm which optional components (firewall, Bastion, Cosmos DB, etc.) will deploy based on your variable selections.
7. **Apply the landing zone**
   ```bash
   terraform apply landingzone.plan
   ```
   Terraform will create the resource group, networking fabric, security controls, platform services, and optional AI workloads defined by your configuration.
8. **Post-deployment tasks** – Record key outputs (update `outputs.tf` to emit IDs or endpoints you rely on), integrate the deployed resources with your platform governance tooling, and, if you enabled Azure AI Foundry or API Management, onboard application teams to the new services.

To destroy the environment later, run `terraform destroy` using the same variable set.

## Contributing
Contributions are welcome. Please review `CONTRIBUTING.md`, run the AVM validation pipeline (`./avm pre-commit` and `./avm pr-check`), and ensure documentation and examples stay aligned with any code changes.

