---
description: ' Azure Verified Modules (AVM) and Terraform'
applyTo: '**/*.terraform, **/*.tf, **/*.tfvars, **/*.tfstate, **/*.tflint.hcl, **/*.tf.json, **/*.tfvars.json'
---

# Azure Verified Modules (AVM) Terraform

## Overview

Azure Verified Modules (AVM) are pre-built, tested, and validated Terraform and Bicep modules that follow Azure best practices. Use these modules to create, update, or review Azure Infrastructure as Code (IaC) with confidence.

## Custom Instructions for GitHub Copilot Agents

**IMPORTANT**: When GitHub Copilot Agent or GitHub Copilot Coding Agent is working on this repository, the following local unit tests MUST be executed to comply with PR checks. Failure to run these tests will cause PR validation failures:

```bash
PORCH_NO_TUI=1 ./avm pre-commit
git add . && git commit -m "chore: avm pre-commit"
PORCH_NO_TUI=1 ./avm pr-check
```

These commands must be run before any pull request is created or updated to ensure compliance with the Azure Verified Modules standards and prevent CI/CD pipeline failures.
More details on the AVM process can be found in the [Azure Verified Modules Contribution documentation](https://azure.github.io/Azure-Verified-Modules/contributing/terraform/testing/).

**Failure to run these tests will cause PR validation failures and prevent successful merges.**

## Module Discovery

### Terraform Registry

- Search for "avm" + resource name
- Filter by "Partner" tag to find official AVM modules
- Example: Search "avm storage account" → filter by Partner

### Official AVM Index

- **Terraform Resources**: `https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-resource-modules/`
- **Terraform Patterns**: `https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-pattern-modules/`
- **Bicep Resources**: `https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/`
- **Bicep Patterns**: `https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-pattern-modules/`

## Terraform Module Usage

### From Examples

1. Copy the example code from the module documentation
2. Replace `source = "../../"` with `source = "Azure/avm-res-{service}-{resource}/azurerm"`
3. Add `version = "1.0.0"` (use latest available)
4. Set `enable_telemetry = true`

### From Scratch

1. Copy the Provision Instructions from module documentation
2. Configure required and optional inputs
3. Pin the module version
4. Enable telemetry

### Example Usage

```hcl
module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.1.0"

  enable_telemetry    = true
  location            = "East US"
  name                = "mystorageaccount"
  resource_group_name = "my-rg"

  # Additional configuration...
}
```

## Naming Conventions

### Module Types

- **Resource Modules**: `Azure/avm-res-{service}-{resource}/azurerm`
  - Example: `Azure/avm-res-storage-storageaccount/azurerm`
- **Pattern Modules**: `Azure/avm-ptn-{pattern}/azurerm`
  - Example: `Azure/avm-ptn-aks-enterprise/azurerm`
- **Utility Modules**: `Azure/avm-utl-{utility}/azurerm`
  - Example: `Azure/avm-utl-regions/azurerm`

### Service Naming

- Use kebab-case for services and resources
- Follow Azure service names (e.g., `storage-storageaccount`, `network-virtualnetwork`)

## Version Management

### Check Available Versions

- Endpoint: `https://registry.terraform.io/v1/modules/Azure/{module}/azurerm/versions`
- Example: `https://registry.terraform.io/v1/modules/Azure/avm-res-storage-storageaccount/azurerm/versions`

### Version Pinning Best Practices

- For providers: use pessimistic version constraints for minor version: `version = "~> 1.0"`
- For modules: Pin to specific versions: `version = "1.2.3"`

## Module Sources

### Terraform Registry

- **URL Pattern**: `https://registry.terraform.io/modules/Azure/{module}/azurerm/latest`
- **Example**: `https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm/latest`

### GitHub Repository

- **URL Pattern**: `https://github.com/Azure/terraform-azurerm-avm-{type}-{service}-{resource}`
- **Examples**:
  - Resource: `https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount`
  - Pattern: `https://github.com/Azure/terraform-azurerm-avm-ptn-aks-enterprise`

## Development Best Practices

### Module Usage

- ✅ **Always** pin module versions
- ✅ **Start** with official examples from module documentation
- ✅ **Review** all inputs and outputs before implementation
- ✅ **Enable** telemetry: `enable_telemetry = true`
- ✅ **Use** AVM utility modules for common patterns

### Code Quality

- ✅ **Always** run `terraform fmt` after making changes
- ✅ **Always** run `terraform validate` after making changes
- ✅ **Use** meaningful variable names and descriptions
- ✅ **Use** snake_case
- ✅ **Add** proper tags and metadata
- ✅ **Document** complex configurations

### Validation Requirements

Before creating or updating any pull request:

```bash
# Format code
terraform fmt -recursive

# Validate syntax
terraform validate

# AVM-specific validation (MANDATORY)
export PORCH_NO_TUI=1
./avm pre-commit
<commit any changes>
./avm pr-check
```

## Preflight validation agents (repo-specific)

To avoid last-minute issues during `terraform apply`, use these agents before opening a PR or running a deployment pipeline. They are designed for Windows PowerShell and this repository layout.

### 1) Terraform architecture validator agent

Purpose: Validate module wiring, provider versions, and generate a plan artifact for review.

- Inputs
  - Working directory: repo root (`microsoft-ai-landingzone`)
  - Optional: Azure login (see login agent below)
- Steps (PowerShell)
  - Ensure Terraform is available (either in PATH or `tools/terraform/terraform.exe`).
  - Run format and validation
    - `terraform fmt -recursive`
    - `terraform init` (add `-upgrade` when bumping providers/modules)
    - `terraform validate`
  - Run AVM checks (mandatory for PRs)
    - PowerShell: `$env:PORCH_NO_TUI = 1; ./avm pre-commit; git add .; git commit -m "chore: avm pre-commit"`
    - PowerShell: `$env:PORCH_NO_TUI = 1; ./avm pr-check`
  - Create plan artifacts
    - `terraform plan -out=plan.tfplan`
    - `terraform show -json plan.tfplan > artifacts/plan_$(Get-Date -Format yyyy-MM-dd_HH-mm-ss).json`
    - Optionally also emit a human plan: `terraform show plan.tfplan > artifacts/plan_$(Get-Date -Format yyyy-MM-dd_HH-mm-ss).txt`
- Success criteria
  - `terraform validate` passes
  - AVM pre-commit and pr-check pass
  - Plan succeeds and expected create/update/destroy counts are acceptable

Tips

- Prefer pinned module and provider versions (see Version Management above).
- If you maintain multiple subscriptions or regions, test with `-var-file` inputs representing each environment.


### 2) Azure subscription and architecture pre-check agent

Purpose: Verify subscription readiness and Azure-side architecture prerequisites that commonly break applies.

- Inputs
  - TenantId, SubscriptionId, target regions
- Steps (PowerShell/Azure CLI)
  - Login using device code (this repo provides a helper)
    - `./scripts/azure-login-devicecode.ps1 -TenantId <tenantId> -SubscriptionId <subscriptionId>`
  - Confirm subscription context
    - `az account show -o table`
  - Provider registration (common culprits: Microsoft.Network, Microsoft.ContainerService, Microsoft.KeyVault, Microsoft.OperationalInsights)
    - `az provider list --query "[?registrationState!='Registered'].namespace" -o table`
    - Register missing: `az provider register --namespace <ProviderNs>`
  - Quotas and capacity checks (per target region)
    - Compute: `az vm list-usage -l <region> -o table`
    - Public IPs: `az network list-usages -l <region> -o table`
    - General: review Service Quotas in Azure Portal for the subscription
  - Naming collisions and resource existence
    - Resource groups: `az group show -n <rgName>` (should not pre-exist unless intended)
    - DNS zones, Public IP DNS labels, Key Vault names are globally unique—validate early
  - Policy and RBAC sanity
    - Ensure your principal has Owner/Contributor + User Access Administrator as needed for role/assignment creation
    - Check assignment scope restrictions and policy denials for your target RG/subscription
  - TLS and certificate prerequisites
    - If using Application Gateway or HTTPS endpoints, review `SSL-Certificate-README.md` and confirm certificate files/permissions
- Success criteria
  - Required providers Registered
  - Adequate quota for planned SKUs
  - No policy blocks for resource types being deployed

### 3) Deployment workflow dry-run agent

Purpose: Smoke-test the end-to-end workflow, catch state/permissions issues, and fail fast in CI.

- Steps (PowerShell)
  - Optional drift check (safe): `terraform apply -refresh-only -auto-approve`
  - Exit-code based plan for CI gating: `terraform plan -detailed-exitcode`
    - Exit code 0: no changes; 2: changes present; 1: error
  - Validate state backend settings (this repo uses local state by default). Avoid concurrent applies; for team use, migrate to a remote backend (Azure Storage) as a follow-up.
- Success criteria
  - Refresh-only apply succeeds
  - `-detailed-exitcode` used to gate unintended changes in pipelines

### 4) Test plan generator agent (from plan)

Purpose: Produce a human-reviewable test plan with test cases, steps, expected results, and a column for actual results based on the Terraform plan output.

Two supported options in this repo:

1. Python generator (recommended)
   - Path: `Apps/test-plan/src/main.py`
   - Steps
     - `terraform plan -out=plan.tfplan`
     - `terraform show -json plan.tfplan > plan.json`
     - `python Apps/test-plan/src/main.py plan.json`
   - Output: `test-plans/test-plan-YYYY-MM-DD.md`

2. Terraform template (reads root state)
   - Path: `Apps/test-plan/testplan`
   - Steps
     - `terraform -chdir=Apps/test-plan init`
     - `terraform -chdir=Apps/test-plan apply -auto-approve`
   - Output: `Apps/test-plan/test-plan-YYYY-MM-DD.md`

The generated document includes for each resource: Test Case, Test Steps, Expected Results, and Actual Results. Attach the plan artifacts from step 1 to the PR for full traceability.

### 5) Login helper agent

Use `scripts/azure-login-devicecode.ps1` to authenticate via device code when a browser-based login is not convenient. Examples:

```powershell
# Basic login
./scripts/azure-login-devicecode.ps1

# Specify tenant and subscription
./scripts/azure-login-devicecode.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -SubscriptionId "11111111-1111-1111-1111-111111111111"
```

### 5a) Application Gateway certificate generator

Purpose: Generate and upload self-signed SSL certificates for Application Gateway testing.

Use `scripts/Generate-AppGwCertificate.ps1` to create certificates when deploying Application Gateway:

```powershell
# Basic usage (auto-integrated into startup script)
# The startup script will detect if App Gateway is enabled and prompt for certificate generation

# Manual usage
./scripts/Generate-AppGwCertificate.ps1 -KeyVaultName "azr-aiops-tst-sec-kv-l9b" -ResourceGroupName "rg-aiops-tst-sec-007"

# Custom DNS and validity
./scripts/Generate-AppGwCertificate.ps1 -KeyVaultName "my-kv" -ResourceGroupName "my-rg" -DnsName "*.mydomain.com" -ValidityYears 2
```

**Automatic detection** (built into `run-terraform-start-up.ps1`):

- Scans `landingzone.defaults.auto.tfvars` for App Gateway configuration
- Detects if `deploy = true` for Application Gateway
- Checks if SSL certificate (`key_vault_secret_id`) is configured
- If missing, offers to generate self-signed certificate automatically
- Attempts to auto-detect Key Vault and Resource Group names from tfvars
- Prompts for confirmation before running certificate generation

**Features**:

- Generates self-signed certificates with proper Application Gateway settings
- Temporarily enables Key Vault public access if needed
- Uploads certificate to Key Vault
- Restores original Key Vault network settings
- Cleans up local certificate store and temporary files

### 6) Error handler agent (built-in)

Purpose: Automatically detect and provide remediation guidance for common Terraform errors.

The `run-terraform-start-up.ps1` script includes automatic error detection and remediation for:

#### A) WriteOnly Attribute Not Allowed

- **Detection**: Scans for "WriteOnly Attribute Not Allowed" or "Write-only attributes are only supported in Terraform 1.11"
- **Cause**: Terraform version < 1.11.0 (AzAPI provider requires WriteOnly attributes for `sensitive_body`)
- **Remediation**:
  - Script automatically detects version mismatch at startup
  - Offers to download and install Terraform 1.11.0
  - Creates backup of old version
  - Updates default download version to 1.11.0

#### B) Invalid count argument

- **Detection**: Scans for "Invalid count argument" or "count value depends on resource attributes that cannot be determined until apply"
- **Cause**: `count` depends on resources not yet created (e.g., Key Vault ID)
- **Remediation**:
  - Displays affected resources and file locations
  - Recommends automated two-stage deployment script
  - Provides manual commands for targeted apply
  - Script: `.\scripts\run-terraform-targeted-apply.ps1`
    - Stage 1: Creates dependency resources (VNet, Key Vault, etc.)
    - Stage 2: Applies full configuration

#### C) Argument is deprecated

- **Detection**: Scans for "Warning: Argument is deprecated" (e.g., `metric` → `enabled_metric`)
- **Cause**: Using deprecated AzureRM provider arguments
- **Impact**: Warnings only - deployment continues, but will break in future provider versions
- **Remediation**:
  - Explains the deprecation and timeline (e.g., AzureRM v5.0)
  - Shows old vs new syntax
  - Recommends updating modules before major provider upgrades

#### D) Application Gateway Key Vault Access Denied

- **Detection**: Scans for "ApplicationGatewayKeyVaultSecretAccessDenied" or "Access denied for KeyVault Secret"
- **Cause**: App Gateway managed identity doesn't have access to Key Vault certificate
- **Common issues**:
  - Missing role assignment (Key Vault Secrets User/Officer)
  - Key Vault firewall not allowing trusted Microsoft services
  - Role propagation delay (5-10 minutes)
- **Remediation**:
  - Shows commands to verify role assignments
  - Provides Key Vault firewall check commands
  - Explains how to manually assign roles
  - Suggests waiting for role propagation

#### E) Storage Account Key-Based Authentication Not Permitted

- **Detection**: Scans for "Key based authentication is not permitted" or "KeyBasedAuthenticationNotPermitted"
- **Cause**: Storage Account has `shared_access_key_enabled = false` but Terraform tries to use keys
- **Impact**: Terraform cannot create containers, blobs, or tables
- **Remediation**:
  - Option 1: Enable key-based auth (less secure)
  - Option 2: Use Microsoft Entra ID authentication (recommended)
  - Option 3: Two-stage deployment approach
  - Explains managed identity and RBAC setup

#### F) Missing Resource Identity After Create

- **Detection**: Scans for "Missing Resource Identity After Create" or "unexpectedly returned no resource identity"
- **Cause**: Resource created but identity assignment failed (provider bug or transient error)
- **Remediation**:
  - Check if resource actually exists with Azure CLI
  - Import resource if it exists
  - Often follows storage key auth error - fix that first
  - Suggests provider version troubleshooting

#### G) Saved Plan is Stale

- **Detection**: Scans for "Saved plan is stale" or "plan file can no longer be applied"
- **Cause**: Terraform state changed after plan was created (manual changes, concurrent operations, previous partial apply)
- **Common scenarios**:
  - Another team member ran terraform apply
  - Manual changes via Azure Portal or CLI
  - Previous failed apply modified some resources
  - Concurrent terraform operations
- **Remediation**:
  - Create fresh plan and apply immediately
  - Use remote state locking (Azure Storage backend)
  - Coordinate with team before applying
  - Apply plans shortly after creating them

**Usage**:

```powershell
# Error handlers run automatically during plan/apply
.\scripts\run-terraform-start-up.ps1

# For count dependency errors, use the targeted apply helper
.\scripts\run-terraform-targeted-apply.ps1
```

## CI usage hints

- Use `terraform plan -detailed-exitcode` to signal pipelines when changes are detected.
- Persist `plan.tfplan` and `artifacts/plan_*.json` as build artifacts for review.
- Run AVM checks as a dedicated job before plan/apply.
- For multi-env flows, parameterize `-var-file` and subscription context per stage.

## Tool Integration

### Use Available Tools

- **Deployment Guidance**: Use `azure_get_deployment_best_practices` tool
- **Service Documentation**: Use `microsoft.docs.mcp` tool for Azure service-specific guidance
- **Schema Information**: Use `query_azapi_resource_schema` & `query_azapi_resource_document` to query AzAPI resources and schemas.
- **Provider resources and resource schemas**: Use `list_terraform_provider_items` & `query_terraform_schema` to query azurerm resource schema.

### GitHub Copilot Integration

When working with AVM repositories:

1. Always check for existing modules before creating new resources
2. Use the official examples as starting points
3. Run all validation tests before committing
4. Document any customizations or deviations from examples

## Common Patterns

### Resource Group Module

```hcl
module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.1.0" # use latest

  enable_telemetry = true
  location         = var.location
  name            = var.resource_group_name
}
```

### Virtual Network Module

```hcl
module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.1.0" # use latest

  enable_telemetry    = true
  location            = module.resource_group.location
  name                = var.vnet_name
  resource_group_name = module.resource_group.name
  address_space       = ["10.0.0.0/16"]
}
```

## Troubleshooting

### Common Issues

1. **Version Conflicts**: Always check compatibility between module and provider versions
2. **Missing Dependencies**: Ensure all required resources are created first
3. **Validation Failures**: Run AVM validation tools before committing
4. **Documentation**: Always refer to the latest module documentation

### Support Resources

- **AVM Documentation**: `https://azure.github.io/Azure-Verified-Modules/`
- **GitHub Issues**: Report issues in the specific module's GitHub repository
- **Community**: Azure Terraform Provider GitHub discussions

## Compliance Checklist

Before submitting any AVM-related code:

- [ ] Module version is pinned
- [ ] Telemetry is enabled
- [ ] Code is formatted (`terraform fmt`)
- [ ] Code is validated (`terraform validate`)
- [ ] AVM pre-commit checks pass (`./avm pre-commit`)
- [ ] AVM PR checks pass (`./avm pr-check`)
- [ ] Documentation is updated
- [ ] Examples are tested and working
