# Microsoft AI Landing Zone (Terraform)

## Overview
This repository defines a composable Azure AI landing zone using Terraform and Azure Verified Modules (AVM). It provisions the shared infrastructure required to host secure, enterprise-ready generative AI workloads, including regional networking, governance controls, developer tooling, and platform services. The configuration is split into focused Terraform configuration files so that each workload area (networking, compute, security, data, monitoring, and developer experience) can be customized independently while still following the central naming and tagging policies that the landing zone enforces.

AI landing zone architectural types:

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
| `main.genai_app_resources.tf` | Opinionated defaults for Azure Container Apps environments, Log Analytics dependencies, and application plane integrations consumed by the GenAI services. |
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
- `subscription_id` (in `variables.tf`) – Optional override that pins the Azure subscription used by the `azurerm` provider when the CLI or environment cannot select it automatically.
- The feature-specific files (`variables.genai_services.tf`, `variables.networking.tf`, `variables.jumpvm.tf`, etc.) – Define nested objects where each major service can be toggled on/off (`deploy`), renamed, and customized with security, networking, SKU, and diagnostic options.

To simplify configuration:

1. Copy `landingzone.defaults.auto.tfvars` (create the file if it does not exist) and provide at least:
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

## Build the environment
The following end-to-end workflow captures the recommended steps for standing up or iterating on an environment. It expands on the earlier prerequisites so that a new operator can move from an empty workstation to a fully provisioned landing zone.

1. **Prepare your workstation**
   - **macOS (Homebrew)**
     ```bash
     brew update
     brew tap hashicorp/tap
     brew install hashicorp/tap/terraform azure-cli jq make
     ```
   - **Ubuntu/Debian**
     ```bash
     sudo apt-get update
     sudo apt-get install -y gnupg software-properties-common curl unzip make
     curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
     echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
     sudo apt-get update && sudo apt-get install -y terraform azure-cli jq
     ```
   - **Windows** – Install [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli#install-terraform), [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli-windows?tabs=azure-cli), and optionally [Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/install) to run the Bash helper scripts. PowerShell equivalents are provided when Bash is unavailable.

2. **Clone and review the repository**
   ```bash
   git clone https://github.com/<your-org>/microsoft-ai-landingzone.git
   cd microsoft-ai-landingzone
   git pull --ff-only
   ```
   Keeping your fork synchronized (`git pull --ff-only`) ensures you receive the latest module wiring, defaults, and bug fixes.

3. **Authenticate with Azure** – Sign in using the Azure CLI (or the authentication approach required by your automation environment):
   ```bash
   az login
   az account set --subscription <subscription-id>
   ```
   - If the deployment account is service-principal based, export the ARM provider environment variables (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, and optionally `ARM_SUBSCRIPTION_ID`).
   - To persist the subscription ID in a local `.tfvars`, run the helper script:
     ```bash
     ./scripts/configure-subscription.sh            # Bash
     # or
     pwsh ./scripts/configure-subscription.ps1      # PowerShell
     ```
     The script creates `landingzone.subscription.auto.tfvars` (Git ignored) with the subscription identifier so that future `terraform` commands target the correct tenant without re-exporting environment variables.

4. **Configure backend state (recommended)** – Persisting Terraform state in Azure Storage enables collaboration and reliable recovery.
   ```bash
   RESOURCE_GROUP="rg-tfstate-$(date +%y%m%d)"
   STORAGE_ACCOUNT="sttfstate$(date +%y%m%d%H%M)"
   CONTAINER_NAME="tfstate"

   az group create --name "$RESOURCE_GROUP" --location eastus
   az storage account create --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --sku Standard_LRS --encryption-services blob
   az storage container create --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT"
   ```
   Save the generated resource names and either edit the `backend` block in `terraform.tf` or provide `-backend-config` flags during `terraform init`, for example:
   ```bash
   terraform init \
     -backend-config="resource_group_name=$RESOURCE_GROUP" \
     -backend-config="storage_account_name=$STORAGE_ACCOUNT" \
     -backend-config="container_name=$CONTAINER_NAME" \
     -backend-config="key=landingzone.tfstate"
   ```
   When experimenting locally you can skip this step and allow Terraform to use the default local state file (`terraform.tfstate`).

5. **Customize variables** – Start from `landingzone.defaults.auto.tfvars` and tailor it (or create additional `.tfvars` files) per environment:
   ```hcl
   # landingzone.dev.auto.tfvars
   location         = "eastus"
   project_code     = "aihub"
   environment_code = "dev"

   networking_definition = {
     address_space = ["10.20.0.0/16"]
   }

   buildvm_definition = {
     deploy = false
   }
   ```
   - Use separate files such as `landingzone.prod.auto.tfvars` to encode production-ready SKUs and diagnostics.
   - The variable files are merged with `landingzone.subscription.auto.tfvars` so subscription context stays isolated from Git history.

6. **Install providers and modules**
   ```bash
   terraform init
   ```
   The command downloads the `azurerm`, `azapi`, `azurecaf`, `modtm`, `random`, and `time` providers together with all referenced Azure Verified Modules.

7. **Validate formatting, schema, and plan**
   ```bash
   terraform fmt -recursive
   terraform validate
   terraform plan -var-file=landingzone.dev.auto.tfvars -out=landingzone.plan
   ```
   - Use multiple `-var-file` flags to layer environment-specific settings (`-var-file=landingzone.defaults.auto.tfvars -var-file=landingzone.dev.auto.tfvars`).
   - Review the plan output carefully to confirm which optional services (Azure Firewall, Bastion, Cosmos DB, Azure AI Foundry, API Management, etc.) are being provisioned.

8. **Apply the plan**
   ```bash
   terraform apply landingzone.plan
   ```
   Terraform will create the resource group, networking fabric, security controls, platform services, and optional AI workloads defined by your configuration. If you do not need to persist the plan file, run `terraform apply` without `-out` and respond to the confirmation prompt directly.

9. **Post-deployment validation**
   - Review `terraform output` (after populating `outputs.tf` with the identifiers you care about) and share the necessary connection details with application teams.
   - Confirm private endpoints are approved, DNS zones are linked, and Azure Monitor diagnostic settings stream to the expected Log Analytics workspace.
   - Integrate the deployed resources with your platform governance tooling (policy assignments, budgets, access packages, etc.).

10. **Iterate and destroy**
    - Rerun `terraform plan` whenever you modify `.tfvars` files or upgrade module versions to preview the impact.
    - To tear down a non-production environment, run `terraform destroy -var-file=...` using the same combination of variable files you used for deployment.

For CI/CD pipelines, replicate steps 3–8 in your automation platform (GitHub Actions, Azure DevOps, etc.), using secure secret storage for sensitive inputs and leveraging `terraform init -backend-config=...` with remote state credentials.

## Contributing
Contributions are welcome. Please review `CONTRIBUTING.md`, run the AVM validation pipeline (`./avm pre-commit` and `./avm pr-check`), and ensure documentation and examples stay aligned with any code changes.

