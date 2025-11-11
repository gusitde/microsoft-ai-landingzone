# Deployment Guide for Engineers

## Overview

This comprehensive deployment guide provides step-by-step instructions for engineers deploying Azure infrastructure using this Terraform repository. The guide follows a phased approach from environment setup through project closeout.

## Prerequisites

- Azure subscription with appropriate permissions
- Git installed on your local machine
- Basic understanding of Terraform and Azure concepts
- Access to the repository

---

## Phase 1: Create Developer Environment

### Step 1.1: Install Required Software

#### Install Visual Studio Code
1. Download Visual Studio Code from [https://code.visualstudio.com/](https://code.visualstudio.com/)
2. Run the installer and follow the installation wizard
3. Launch Visual Studio Code after installation

#### Install Git
1. Download Git from [https://git-scm.com/downloads](https://git-scm.com/downloads)
2. Install Git with default settings
3. Verify installation by opening a terminal and running:

  ```bash
  git --version
  ```

#### Install Terraform

1. This repo ships with a pinned Terraform binary under `tools/terraform/terraform.exe` (Windows). You can use it directly without installing globally.
2. Optional: Install Terraform from [https://www.terraform.io/downloads](https://www.terraform.io/downloads) if you prefer a global install and PATH setup.
3. Verify installation:

  ```powershell
  # Using the repo-pinned binary
  .\tools\terraform\terraform.exe --version

  # Or, if installed globally
  terraform --version
  ```

#### Install Azure CLI

1. Download Azure CLI from [https://docs.microsoft.com/en-us/cli/azure/install-azure-cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
2. Install following platform-specific instructions
3. Verify installation:

  ```bash
  az --version
  ```

### Step 1.2: Configure Visual Studio Code Extensions

Install the following VS Code extensions:

1. **HashiCorp Terraform** (by HashiCorp)
  - Open VS Code Extensions (Ctrl+Shift+X)
  - Search for "HashiCorp Terraform"
  - Click Install

2. **Azure Terraform** (by Microsoft)
  - Search for "Azure Terraform"
  - Click Install

3. **GitHub Copilot** (optional but recommended)
  - Search for "GitHub Copilot"
  - Click Install and authenticate

4. **Azure Account** (by Microsoft)
  - Search for "Azure Account"
  - Click Install

### Step 1.3: Clone the Repository

1. Open VS Code
2. Press `Ctrl+Shift+P` and select "Git: Clone"
3. Enter the repository URL
4. Select a local directory for the repository
5. Open the cloned repository in VS Code

### Step 1.4: Authenticate with Azure

1. Open a terminal in VS Code (Terminal → New Terminal)
2. Login to Azure (device code flow recommended for remote/headless sessions):
  ```powershell
  # Device code helper script (recommended)
  .\scripts\azure-login-devicecode.ps1 -TenantId "<tenant-guid>" -SubscriptionId "<subscription-guid>"

  # Or Azure CLI directly
  az login --use-device-code --tenant <tenant-guid>
  az account set --subscription "<subscription-guid>"

  # Verify your account
  az account show -o table
  ```

---

## Phase 2: Configure Terraform Environment Variables

### Step 2.1: Understand Variable Files

This repository uses Terraform variables for configuration. Key files:
- `variables.tf` - Variable definitions
- `terraform.tfvars` - Variable values (create this file)
- Environment-specific `.tfvars` files (e.g., `dev.tfvars`, `prod.tfvars`)

### Step 2.2: Create Environment Variable File

1. Navigate to the root of the repository
2. Create a new file named `terraform.tfvars`:
  ```bash
  touch terraform.tfvars
  ```

### Step 2.3: Configure Required Variables

Use the sample defaults in [`landingzone.defaults.auto.tfvars`](../../landingzone.defaults.auto.tfvars) as a reference point, then open `terraform.tfvars` and configure the core variables for your deployment. Each entry below now includes inline comments detailing the Azure-safe character set and maximum length so you stay within the Cloud Adoption Framework (CAF) boundaries enforced by [`modules/naming`](../../modules/naming/main.tf) and the variable validations in [`variables.tf`](../../variables.tf):

```hcl
# Basic configuration — sets the primary region, environment code, and workload code that drive CAF-compliant names.
location         = "eastus"  # 2-36 lowercase letters, no spaces; must match a valid Azure region short name so CAF abbreviations resolve correctly.
environment_code = "tst"     # Exactly 3 lowercase letters; allowed values are tst, qlt, or prd per the naming module validation.
project_code     = "aiops"   # 2-6 lowercase letters or digits; forms the CAF prefix applied to every resource name.

# Resource group targeting — align this with your enterprise naming standard or pre-created resource group.
resource_group_name    = "rg-aiops-tst-eus-001"  # 1-90 characters using lowercase letters, digits, hyphens, periods, parentheses, or underscores to satisfy Azure Resource Group rules.
resource_group_version = 1                       # Integer 1-99; stored as a two-digit suffix to keep resource group names unique without exceeding Azure limits.

# Governance tags — propagate required metadata for cost management and ownership.
tags = {
  Environment = "Development"     # Up to 256 printable characters; letters, numbers, spaces, and hyphens are typical for Azure tag values.
  Project     = "AI Landing Zone" # Up to 256 printable characters; use letters, numbers, spaces, or hyphens for readability in Azure portals.
  ManagedBy   = "Terraform"       # Up to 256 printable characters; letters only keeps governance scans simple.
  Owner       = "<your-email>"    # Up to 256 printable characters; email format stays within Azure tag character rules.
  CostCenter  = "<cost-center-code>" # Up to 256 printable characters; letters, numbers, and hyphens keep billing integrations consistent.
}

# Telemetry flag — required for Azure Verified Modules (AVM) usage in this repository.
enable_telemetry = true  # Boolean true/false; keep enabled to comply with AVM module requirements unless your organization has an approved exception.
```

> ℹ️ **How these variables are consumed:** The core values above flow into the reusable naming engine (`modules/naming`) and the typed variable files in the repository (for example, `variables.networking.tf`, `variables.apim.tf`). They ultimately shape resource names, determine which features deploy, and populate tags on every asset.

When you need to go beyond the baseline inputs:

- **Review built-in defaults:** The repository ships with a comprehensive [`landingzone.defaults.auto.tfvars`](../../landingzone.defaults.auto.tfvars) file that showcases recommended values for networking, API Management, bastion, firewall, and other feature toggles. Use it as a template when crafting environment-specific overrides.
- **Explore the naming helpers:** The [`modules/naming/main.tf`](../../modules/naming/main.tf) module documents allowable region abbreviations, resource-type short codes, and uniqueness controls so you can confidently adjust the inputs that compose your resource prefixes without breaking Azure naming rules.
- **Adjust feature-specific settings:** Each `variables.<domain>.tf` file (for example, [`variables.networking.tf`](../../variables.networking.tf), [`variables.apim.tf`](../../variables.apim.tf), [`variables.genai_services.tf`](../../variables.genai_services.tf)) declares additional flags and nested objects. Copy the blocks you need into `terraform.tfvars`—such as `apim_definition`, `firewall_definition`, or `genai_storage_account_definition`—and update only the properties relevant to your deployment.

### Step 2.4: Configure Backend State

1. Create or identify an Azure Storage Account for Terraform state
2. Create a `backend.tf` file:
  ```hcl
  terraform {
    backend "azurerm" {
     resource_group_name  = "rg-terraform-state"
     storage_account_name = "sttfstate<uniqueid>"
     container_name       = "tfstate"
     key                  = "ai-landing-zone.tfstate"
    }
  }
  ```

### Step 2.5: Set Environment Variables

Set sensitive values as environment variables:

**Linux/macOS:**
```bash
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export ARM_CLIENT_ID="<client-id>"          # If using Service Principal
export ARM_CLIENT_SECRET="<client-secret>"  # If using Service Principal
export ARM_TENANT_ID="<tenant-id>"
```

**Windows (PowerShell):**
```powershell
$env:ARM_SUBSCRIPTION_ID="<subscription-id>"
$env:ARM_CLIENT_ID="<client-id>"          # If using Service Principal
$env:ARM_CLIENT_SECRET="<client-secret>"  # If using Service Principal
$env:ARM_TENANT_ID="<tenant-id>"
```

### Step 2.6: Validate Configuration

Review your configuration files for:
- ✅ No hardcoded secrets
- ✅ Proper naming conventions
- ✅ Required tags present
- ✅ `enable_telemetry = true` for all AVM modules

---

## Phase 3: Deploy Infrastructure

> Preflight first: This repo includes documented “preflight validation agents” that catch most last‑minute apply issues (module wiring, provider versions, subscription readiness, quotas, policy blocks). See `AGENTS.md` → “Preflight validation agents (repo-specific)”. A summary is provided below.

### Step 3.0: Run preflight validation agents (recommended)

1) Terraform architecture validator
```powershell
# From repo root
.\tools\terraform\terraform.exe fmt -recursive
.\tools\terraform\terraform.exe init
.\tools\terraform\terraform.exe validate

# AVM checks (Windows PowerShell)
$env:PORCH_NO_TUI = 1
./avm pre-commit
git add .
git commit -m "chore: avm pre-commit"
$env:PORCH_NO_TUI = 1
./avm pr-check
```

2) Azure subscription and architecture pre-check
```powershell
./scripts/azure-login-devicecode.ps1 -TenantId "<tenant-guid>" -SubscriptionId "<subscription-guid>"

# Confirm context
az account show -o table

# Check provider registrations (register any missing)
az provider list --query "[?registrationState!='Registered'].namespace" -o table

# Quota spot checks
az vm list-usage -l <region> -o table
az network list-usages -l <region> -o table
```

3) Optional dry-run workflow checks
```powershell
# Safe drift check (no changes applied)
.\tools\terraform\terraform.exe apply -refresh-only -auto-approve

# CI-style gating
.\tools\terraform\terraform.exe plan -detailed-exitcode
```

### Step 3.1: Run the interactive startup workflow (recommended)

- Launch the guided runner from the repo root:

  ```powershell
  pwsh ./scripts/run-terraform-start-up.ps1
  ```

- Choose the option that matches your intent:

  - **[1] Plan only** – runs diagnostics, `terraform init`, and `terraform validate`, then emits `plan.tfplan`, `plan.json`, and timestamped plan artifacts without touching Azure resources.
  - **[2] Plan + Apply** – performs the same checks, pauses for plan review, and applies when you confirm. During the run it can auto-generate an Application Gateway certificate and, if a storage account blocks key-based auth, it calls the new `Invoke-StorageAccountAadRemediation` helper to grant your identity *Storage Blob Data Contributor* and sets `ARM_USE_AZUREAD=true` before retrying.
  - **[3] Apply existing plan** – validates the workspace and replays the existing `plan.tfplan` after a safety check.

- All options execute the helper module’s pre-flight diagnostics (state health, backend config, drift check, provider locks) before Terraform runs. If you prefer a manual workflow, continue with Step 3.2.

### Step 3.2: Initialize Terraform (manual path)

Navigate to the Terraform module directory, then initialize Terraform:

```powershell
.\tools\terraform\terraform.exe init
```

Verify that the command completes successfully (plugins downloaded, backend configured) before moving on.

### Step 3.3: Format and Validate Code

Run Terraform formatting to normalize HCL across modules:

```powershell
.\tools\terraform\terraform.exe fmt -recursive
```

After formatting, validate the configuration:

```powershell
.\tools\terraform\terraform.exe validate
```

Resolve any validation errors before continuing.

### Step 3.4: Run AVM pre-commit checks

**CRITICAL:** These checks are mandatory before deployment.

Windows PowerShell:

```powershell
$env:PORCH_NO_TUI = 1
./avm pre-commit
git add .
git commit -m "chore: avm pre-commit fixes"
```

Linux/macOS:

```bash
export PORCH_NO_TUI=1
./avm pre-commit
git add . && git commit -m "chore: avm pre-commit fixes"
```

### Step 3.5: Review the Terraform plan

Generate the execution plan:

```powershell
.\tools\terraform\terraform.exe plan -out=plan.tfplan
```

Inspect the plan carefully, paying attention to:

- Resources to be created
- Resources to be modified
- Resources to be destroyed (should be none for initial deployment)

Persist the plan output for documentation and downstream automation:

```powershell
# Machine-readable plan JSON for test plan generation
.\tools\terraform\terraform.exe show -json plan.tfplan > plan.json

# Archive plan artifacts
$ts = Get-Date -Format yyyy-MM-dd_HH-mm-ss
.\tools\terraform\terraform.exe show -json plan.tfplan > artifacts\plan_$ts.json
.\tools\terraform\terraform.exe show plan.tfplan > artifacts\plan_$ts.txt
```

> 💡 **Using the startup workflow?** Options [1] and [2] already create `plan.tfplan`, `plan.json`, and timestamped artifacts under `artifacts/`. Review them here before deciding to apply.

### Step 3.6: Execute the deployment

Apply the plan when you are ready:

```powershell
.\tools\terraform\terraform.exe apply plan.tfplan
```

Monitor the progress, note any warnings or errors, and capture the completion time for your deployment log.

> ⚙️ **Interactive workflow note:** Choosing option [2] in `run-terraform-start-up.ps1` runs the apply step automatically after you confirm the plan. If the storage account blocks shared keys, select remediation option **[2]** when prompted—the script calls `Invoke-StorageAccountAadRemediation` to grant Microsoft Entra Data Plane access and sets `ARM_USE_AZUREAD=true` before re-running Terraform.

### Step 3.7: Verify Deployment

1. Check Azure Portal for created resources
2. Verify resource configurations match requirements
3. Run Terraform state check:
  ```powershell
  .\tools\terraform\terraform.exe state list
  ```
4. Export outputs:
  ```powershell
  .\tools\terraform\terraform.exe output > deployment-outputs.txt
  ```

### Step 3.8: Document Deployment

Create a deployment log with:
- Deployment date and time
- Terraform version used
- Azure provider version
- Resources created (from state list)
- Output values
- Any issues encountered and resolutions

---

## Phase 4: Create Test Plan

### Step 4.1: Define Test Objectives

Document the following:
- What functionality needs to be tested
- Expected outcomes for each test
- Success criteria
- Rollback procedures if tests fail

### Step 4.2: Create Test Plan Document (automatic generation recommended)

You can auto-generate a Markdown test plan from the Terraform plan using the repo’s Python utility. It produces a table of Test Case, Test Steps, Expected Results, and Actual Results.

```powershell
# Ensure you have Python 3 available
python --version

# From repo root, generate plan.json if not already created
.\tools\terraform\terraform.exe plan -out=plan.tfplan
.\tools\terraform\terraform.exe show -json plan.tfplan > plan.json

# Run the generator
python Apps\test-plan\src\main.py plan.json

# Output file
# test-plans\test-plan-YYYY-MM-DD.md
```

Alternatively, you can generate a test plan from the current root state using the Terraform template in `Apps/test-plan/testplan`:

```powershell
terraform -chdir=Apps/test-plan init
terraform -chdir=Apps/test-plan apply -auto-approve
# Output written to: Apps\test-plan\test-plan-YYYY-MM-DD.md
```

If you prefer to write a plan manually, use the template below.

Create `test-plan.md` with the following sections:

```markdown
# Infrastructure Test Plan

## Test Environment
- Environment: [Dev/Staging/Prod]
- Deployment Date: [Date]
- Terraform Version: [Version]

## Test Scenarios

### 1. Resource Availability Tests
- [ ] All resources are deployed
- [ ] Resources are in the correct resource group
- [ ] Resources are in the correct region

### 2. Network Connectivity Tests
- [ ] Virtual networks are created
- [ ] Subnets are configured correctly
- [ ] Network security groups have correct rules

### 3. Security Tests
- [ ] RBAC roles are assigned correctly
- [ ] Managed identities are configured
- [ ] Private endpoints are operational

### 4. Compliance Tests
- [ ] All resources have required tags
- [ ] Resources follow naming conventions
- [ ] Encryption is enabled where required

### 5. Functional Tests
- [ ] AI services are accessible
- [ ] Storage accounts are operational
- [ ] Key Vault is accessible and secrets are retrievable

## Test Data
[Document any test data requirements]

## Test Execution Schedule
[Define when tests will be run]

## Rollback Plan
[Document rollback procedures if tests fail]
```

### Step 4.3: Define Test Cases

For each Azure service deployed, create specific test cases:

**Example Test Case Template:**
```markdown
## Test Case: [Service Name]

**Test ID:** TC-001
**Priority:** High/Medium/Low
**Prerequisites:** [List prerequisites]

**Test Steps:**
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected Result:**
[What should happen]

**Actual Result:**
[To be filled during execution]

**Status:** Pass/Fail/Blocked

**Notes:**
[Additional observations]
```

### Step 4.4: Prepare Test Environment

1. Ensure you have necessary permissions for testing
2. Prepare test data (if required)
3. Set up monitoring/logging to capture test results
4. Document test environment configuration

### Step 4.5: Review Test Plan

1. Review test plan with team members
2. Get approval from stakeholders
3. Make revisions based on feedback
4. Finalize and version control the test plan

---

## Phase 5: Execute Test Plan

### Step 5.1: Pre-Test Validation

1. Verify all deployed resources are healthy
2. Check Azure Service Health for any ongoing issues
3. Ensure test environment is stable
4. Backup current Terraform state:
  ```bash
  terraform state pull > terraform-state-backup.json
  ```

### Step 5.2: Execute Infrastructure Tests

#### Test 1: Resource Availability
```bash
# List all resources in resource group
az resource list --resource-group <resource-group-name> --output table

# Verify specific resource
az resource show --ids <resource-id>
```

#### Test 2: Network Connectivity
```bash
# Test virtual network
az network vnet show --name <vnet-name> --resource-group <rg-name>

# Test subnet configuration
az network vnet subnet list --vnet-name <vnet-name> --resource-group <rg-name>
```

#### Test 3: Security Configuration
```bash
# Verify RBAC assignments
az role assignment list --scope <resource-id>

# Check managed identity
az identity show --name <identity-name> --resource-group <rg-name>
```

#### Test 4: Service Functionality
```bash
# Test storage account access
az storage account show --name <storage-name> --resource-group <rg-name>

# Test Key Vault access
az keyvault secret list --vault-name <vault-name>
```

### Step 5.3: Document Test Results

For each test case, document:
- ✅ **Pass** - Test completed successfully
- ❌ **Fail** - Test did not meet expected results
- ⚠️ **Blocked** - Test could not be completed

Update your test plan with actual results.

### Step 5.4: Performance Testing

1. Monitor resource performance metrics in Azure Portal
2. Check resource utilization
3. Verify auto-scaling (if configured)
4. Document baseline performance metrics

### Step 5.5: Compliance Validation

Run compliance checks:
```bash
# Verify all resources have required tags
az resource list --query "[?tags.Environment=='<environment>']" --output table

# Check for resources without tags
az resource list --query "[?tags==null]" --output table
```

### Step 5.6: Security Scanning

1. Run Azure Security Center recommendations check
2. Review any security alerts
3. Verify encryption settings
4. Check for publicly exposed resources

### Step 5.7: Test Summary Report

Create a test summary with:
- Total tests executed
- Pass/Fail/Blocked count
- Critical issues identified
- Recommendations for remediation
- Sign-off approval

---

## Phase 6: Create As-Built Document

### Step 6.1: Generate Infrastructure Diagram

1. Use Terraform Graph to visualize infrastructure:
  ```bash
  terraform graph | dot -Tpng > infrastructure-diagram.png
  ```
2. Alternatively, use Azure Portal to export architecture diagrams
3. Create a high-level architecture diagram showing:
  - Resource groups
  - Networks and subnets
  - Key services
  - Data flows

### Step 6.2: Document Deployed Resources

Create `as-built-documentation.md`:

```markdown
# As-Built Documentation

## Deployment Overview
- **Project Name:** AI Landing Zone
- **Environment:** [Dev/Staging/Prod]
- **Deployment Date:** [Date]
- **Deployed By:** [Engineer Name]
- **Terraform Version:** [Version]
- **Azure Provider Version:** [Version]

## Architecture Overview
[Insert architecture diagram]

## Deployed Resources

### Resource Group
- **Name:** [Resource Group Name]
- **Location:** [Azure Region]
- **Tags:** [List all tags]

### Networking
- **Virtual Network:** [VNet Name]
  - Address Space: [CIDR]
  - Subnets: [List all subnets with CIDR]
- **Network Security Groups:** [List NSGs and key rules]

### Compute Resources
[List all compute resources with configurations]

### Storage Resources
- **Storage Accounts:** [List all storage accounts]
  - SKU: [Storage SKU]
  - Replication: [Replication type]
  - Access Tier: [Hot/Cool]

### AI/ML Services
[List AI services deployed]

### Security Resources
- **Key Vaults:** [List Key Vaults]
- **Managed Identities:** [List identities]
- **RBAC Assignments:** [Document role assignments]

### Monitoring and Logging
- **Log Analytics Workspace:** [Workspace details]
- **Application Insights:** [AppInsights details]
- **Diagnostic Settings:** [List resources with diagnostics enabled]

## Configuration Details

### Terraform Modules Used
[List all AVM modules with versions]

### Variable Values
[Document non-sensitive variable values]

### Outputs
```hcl
[Paste terraform output]
```

## Network Configuration
- **DNS Settings:** [DNS configuration]
- **Private Endpoints:** [List private endpoints]
- **Service Endpoints:** [List service endpoints]

## Security Configuration
- **Encryption:** [Document encryption settings]
- **Firewall Rules:** [Document firewall configurations]
- **Access Policies:** [Document access policies]

## Backup and Disaster Recovery
- **Backup Policies:** [Document backup configurations]
- **Recovery Procedures:** [Document recovery steps]

## Cost Estimation
- **Monthly Cost Estimate:** [Estimated monthly cost]
- **Cost Breakdown by Service:** [Service-wise cost breakdown]

## Known Limitations
[Document any known limitations or constraints]

## Change History
| Date | Change Description | Changed By |
|------|-------------------|------------|
| [Date] | Initial deployment | [Name] |

## Appendices

### Appendix A: Terraform Configuration Files
[Reference to configuration files in repository]

### Appendix B: Test Results
[Reference to test plan results]

### Appendix C: Access and Credentials
[Document where credentials are stored - NO ACTUAL CREDENTIALS]
```

### Step 6.3: Export Terraform State Information

```powershell
# Export state as JSON
.\tools\terraform\terraform.exe state pull > terraform-state.json

# List all resources
.\tools\terraform\terraform.exe state list > resources-list.txt

# Export resource details
.\tools\terraform\terraform.exe show > resource-details.txt
```

### Step 6.4: Capture Configuration Evidence

1. Take screenshots of key Azure Portal views
2. Export resource configurations
3. Document any manual configurations not in Terraform
4. Save all documentation in a dedicated folder

### Step 6.5: Create Runbook

Document operational procedures:

```markdown
# Operational Runbook

## Daily Operations
[Daily maintenance tasks]

## Monitoring
[What to monitor and how]

## Troubleshooting
[Common issues and solutions]

## Maintenance Procedures
[Regular maintenance tasks]

## Emergency Procedures
[What to do in case of incidents]

## Contact Information
[Support contacts and escalation paths]
```

### Step 6.6: Version and Store Documentation

1. Commit all documentation to Git:
  ```powershell
  git add docs/as-built/
  git commit -m "docs: add as-built documentation"
  git push
  ```
2. Create a tagged release:
  ```powershell
  git tag -a v1.0.0 -m "Initial deployment"
  git push origin v1.0.0
  ```
3. Archive documentation in SharePoint/document repository

---

## Phase 7: Project Closeout and Survey

### Step 7.1: Handover Preparation

#### Create Handover Package

1. **Documentation Package:**
  - As-built documentation
  - Test results
  - Runbook
  - Architecture diagrams
  - Access procedures

2. **Code Repository:**
  - Ensure all code is committed and pushed
  - Tag the final release
  - Update README.md with deployment information

3. **Knowledge Transfer Materials:**
  - Record demo/walkthrough video (optional)
  - Create FAQ document
  - Document known issues and workarounds

### Step 7.2: Conduct Handover Meeting

Schedule and conduct handover meeting with operations team:

```powershell
# Initialize
.\tools\terraform\terraform.exe init

# Format code
.\tools\terraform\terraform.exe fmt -recursive

# Validate
.\tools\terraform\terraform.exe validate

# Plan
.\tools\terraform\terraform.exe plan -out=plan.tfplan

# Apply
.\tools\terraform\terraform.exe apply plan.tfplan

# Destroy (use with caution)
.\tools\terraform\terraform.exe destroy

# Show state
.\tools\terraform\terraform.exe state list
.\tools\terraform\terraform.exe state show <resource>

# Import existing resource
.\tools\terraform\terraform.exe import <resource_type>.<name> <azure_resource_id>

# Refresh state
.\tools\terraform\terraform.exe refresh

# Output values
.\tools\terraform\terraform.exe output
```
#### Update Project Documentation

1. Update project status to "Completed"
2. Document final costs vs. budget
3. Record lessons learned
4. Archive project communications

#### Azure Resource Verification

```bash
# Final resource inventory
az resource list --resource-group <resource-group-name> --output table > final-inventory.txt

# Verify tagging compliance
az tag list --resource-id <resource-id>

# Check cost analysis
az consumption usage list --start-date <deployment-date> --end-date <current-date>
```

### Step 7.5: Project Closeout Survey

Complete the following survey to capture project insights:

```markdown
# Project Closeout Survey

## Project Information
- **Project Name:** AI Landing Zone Deployment
- **Environment:** [Dev/Staging/Prod]
- **Completion Date:** [Date]
- **Engineer Name:** [Your Name]

## Deployment Metrics
1. **Timeline:**
  - Planned Duration: [X days]
  - Actual Duration: [Y days]
  - Variance: [+/- Z days]

2. **Resources:**
  - Number of resources deployed: [Count]
  - Terraform modules used: [Count]
  - AVM modules used: [Count]

3. **Cost:**
  - Estimated Monthly Cost: $[Amount]
  - Actual Initial Cost: $[Amount]

## Quality Assessment

### Code Quality (Rate 1-5)
- [ ] 1 - Poor
- [ ] 2 - Below Average
- [ ] 3 - Average
- [ ] 4 - Good
- [ ] 5 - Excellent

**Comments:** [Explain rating]

### Documentation Quality (Rate 1-5)
- [ ] 1 - Poor
- [ ] 2 - Below Average
- [ ] 3 - Average
- [ ] 4 - Good
- [ ] 5 - Excellent

**Comments:** [Explain rating]

### Testing Coverage (Rate 1-5)
- [ ] 1 - Poor
- [ ] 2 - Below Average
- [ ] 3 - Average
- [ ] 4 - Good
- [ ] 5 - Excellent

**Comments:** [Explain rating]

## Process Evaluation

### What Went Well?
1. [Success item 1]
2. [Success item 2]
3. [Success item 3]

### What Could Be Improved?
1. [Improvement item 1]
2. [Improvement item 2]
3. [Improvement item 3]

### Challenges Faced
1. **Challenge:** [Description]
  **Resolution:** [How it was resolved]
  **Prevention:** [How to prevent in future]

2. **Challenge:** [Description]
  **Resolution:** [How it was resolved]
  **Prevention:** [How to prevent in future]

## Tool and Technology Feedback

### Terraform/AVM Experience
**What worked well:**
[Your feedback]

**What needs improvement:**
[Your feedback]

### Azure Services
**Services that met expectations:**
[List services]

**Services that had issues:**
[List services and issues]

## Lessons Learned

### Technical Lessons
1. [Lesson 1]
2. [Lesson 2]
3. [Lesson 3]

### Process Lessons
1. [Lesson 1]
2. [Lesson 2]
3. [Lesson 3]

## Recommendations

### For Future Deployments
1. [Recommendation 1]
2. [Recommendation 2]
3. [Recommendation 3]

### For This Environment
1. [Recommendation 1]
2. [Recommendation 2]
3. [Recommendation 3]

## Knowledge Transfer

### Documentation Completeness
- [ ] As-built documentation completed
- [ ] Runbook created
- [ ] Architecture diagrams completed
- [ ] Test results documented
- [ ] Handover meeting conducted

### Team Readiness
- [ ] Operations team trained
- [ ] Access handed over
- [ ] Support procedures documented
- [ ] Escalation paths defined

## Final Sign-Off

**Engineer:** [Name] - [Date]
**Signature:** ___________________

**Project Manager:** [Name] - [Date]
**Signature:** ___________________

**Operations Lead:** [Name] - [Date]
**Signature:** ___________________

## Additional Comments
[Any additional feedback or comments]
```

### Step 7.6: Archive Project Artifacts

1. **Create Project Archive:**
  ```bash
  # Create archive directory
  mkdir -p project-archive/deployment-$(date +%Y%m%d)

  # Copy documentation
  cp -r docs/ project-archive/deployment-$(date +%Y%m%d)/

  # Copy test results
  cp test-plan.md project-archive/deployment-$(date +%Y%m%d)/

  # Export final terraform state
  terraform state pull > project-archive/deployment-$(date +%Y%m%d)/final-state.json
  ```

2. **Upload to Permanent Storage:**
  - SharePoint/document repository
  - Azure Storage (with long-term retention)
  - Git repository (tagged release)

### Step 7.7: Final Cleanup

1. **Remove Temporary Resources:**
  ```bash
  # Remove any temporary files
  rm -f tfplan *.log

  # Clean up local state backups
  rm -f terraform.tfstate.backup
  ```

2. **Revoke Temporary Access:**
  - Remove any temporary service principals
  - Revoke temporary Azure RBAC assignments
  - Clean up development credentials

3. **Update Team Calendar:**
  - Remove recurring deployment meetings
  - Add operations team to monitoring alerts

### Step 7.8: Project Closure Checklist

Complete this final checklist:

- [ ] All infrastructure deployed successfully
- [ ] All tests passed
- [ ] As-built documentation completed and approved
- [ ] Handover meeting conducted
- [ ] Operations team trained
- [ ] Access transferred to operations team
- [ ] Security review completed
- [ ] Cost analysis completed
- [ ] Project closeout survey completed
- [ ] All artifacts archived
- [ ] Temporary access revoked
- [ ] Final sign-off obtained
- [ ] Project status updated in tracking system
- [ ] Lessons learned documented
- [ ] Post-implementation review scheduled (30 days)

---

## Appendix A: Useful Commands Reference

### Terraform Commands
```bash
# Initialize
terraform init

# Format code
terraform fmt -recursive

# Validate
terraform validate

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Destroy (use with caution)
terraform destroy

# Show state
terraform state list
terraform state show <resource>

# Import existing resource
terraform import <resource_type>.<name> <azure_resource_id>

# Refresh state
terraform refresh

# Output values
terraform output
```

### Azure CLI Commands
```bash
# Login
az login

# Set subscription
az account set --subscription <subscription-id>

# List resources
az resource list --resource-group <rg-name>

# Show resource
az resource show --ids <resource-id>

# Get resource ID
az resource show --name <name> --resource-group <rg> --resource-type <type> --query id -o tsv

# Export template
az group export --name <rg-name> > template.json
```

### AVM Commands
```powershell
# Windows PowerShell
$env:PORCH_NO_TUI = 1
./avm pre-commit
$env:PORCH_NO_TUI = 1
./avm pr-check
```

```bash
# Linux/macOS
export PORCH_NO_TUI=1
./avm pre-commit
export PORCH_NO_TUI=1
./avm pr-check
```

---

## Appendix B: Troubleshooting Guide

### Common Issues and Solutions

#### Issue: Terraform Init Fails
**Solution:**
```powershell
# Clear cache
Remove-Item -Recurse -Force .terraform -ErrorAction SilentlyContinue
Remove-Item .terraform.lock.hcl -ErrorAction SilentlyContinue

# Reinitialize
.\tools\terraform\terraform.exe init
```

#### Issue: State Lock Error
**Solution:**
```powershell
# Force unlock (use with caution)
.\tools\terraform\terraform.exe force-unlock <lock-id>
```

#### Issue: Azure Provider Authentication Fails
**Solution:**
```powershell
# Re-authenticate
az logout
./scripts/azure-login-devicecode.ps1 -TenantId "<tenant-guid>" -SubscriptionId "<subscription-guid>"
```

#### Issue: Storage account blocks shared key authentication
**Solution:**
- Re-run `scripts/run-terraform-start-up.ps1` and choose option **[2] Plan + Apply**.
- When the remediation prompt appears, select option **[2]** to let the script execute `Invoke-StorageAccountAadRemediation`, which grants your identity the *Storage Blob Data Contributor* role and exports `ARM_USE_AZUREAD=true` before retrying the plan or apply.
- If automation is unavailable, manually assign the role with Azure CLI (`az role assignment create --role 'Storage Blob Data Contributor' ...`) and set `ARM_USE_AZUREAD=true` in your shell before re-running Terraform.

#### Issue: Module Version Conflict
**Solution:**
- Check module version compatibility
- Update provider version constraints
- Review module documentation for breaking changes

---

## Appendix C: Emergency Procedures

### Rollback Procedure

If deployment fails critically:

1. **Do Not Panic**
2. **Document the error** (screenshots, logs)
3. **Run Terraform Destroy** (only if safe):
  ```powershell
  .\tools\terraform\terraform.exe destroy -auto-approve
  ```
4. **Restore from backup state** (if needed):
  ```powershell
  .\tools\terraform\terraform.exe state push terraform-state-backup.json
  ```
5. **Contact team lead** for support
6. **Document incident** in project log

---

## Support and Contacts

- **Azure Support:** [Azure Support Portal](https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade)
- **Terraform Support:** [Terraform Registry](https://registry.terraform.io/)
- **AVM Documentation:** [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
- **Internal Team:** [Gustavo, Assuncao gus@gusti.de]

---

## Document Version Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | [Date] | [Author] | Initial deployment guide |
Assuncao, Gustavo (GUS IT LLC)
---

**End of Deployment Guide**
