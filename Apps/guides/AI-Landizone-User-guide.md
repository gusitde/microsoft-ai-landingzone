# AI Landing Zone Terraform Startup Guide

## Purpose

This guide walks through the interactive workflow provided by `scripts/run-terraform-start-up.ps1`. Use it when you need a safe, repeatable way to run Terraform against the AI Landing Zone configuration without memorising every prerequisite command.

## Before You Start

- Confirm you can authenticate to Azure. Run `scripts/azure-login-devicecode.ps1` or `az login --use-device-code`, then set the subscription with `az account set`.
- Make sure you have access to clone the repository and the necessary Azure permissions (Owner or Contributor, plus User Access Administrator when role assignments are required).
- Run the script from the repository root (`microsoft-ai-landingzone`). The workflow assumes the pinned Terraform binary under `tools/terraform/terraform.exe` is available.
- Close any other Terraform sessions that might be holding a state lock.

## Step-by-Step Workflow

1. Open PowerShell and change to the repo root:

```powershell
Set-Location d:\microsoft\GENAI-LandingZone\microsoft-ai-landingzone
```

1. Launch the startup script:

```powershell
pwsh ./scripts/run-terraform-start-up.ps1
```

1. Respond to the Terraform version prompts.
   - If a full Terraform binary is missing or too old, the script offers to download v1.11.0 to `tools/terraform.exe` and backs up any previous copy.
   - Declining the download stops the workflow, so accept when prompted unless you already maintain Terraform elsewhere in your `PATH`.

1. Complete the Application Gateway certificate check (only appears when `landingzone.defaults.auto.tfvars` enables the gateway).
   - Choose **Generate** to call `scripts/Generate-AppGwCertificate.ps1` with the detected Key Vault and resource group.
   - Choose **Continue** to proceed without a certificate (the deployment can fail later).
   - Choose **Cancel** to exit and configure certificates manually.

1. Review the main menu and select the run mode that fits your goal:
   - **[1] Plan only** – runs diagnostics, `terraform init`, `terraform validate`, and generates `plan.tfplan` plus `plan.json` for review.
   - **[2] Plan + Apply** – does everything in option 1, shows you the plan, then applies after you confirm.
   - **[3] Apply only** – validates the workspace and applies an existing `plan.tfplan`; use this after a successful option 1 run.

1. Let the pre-flight diagnostics run.
   - The helper module checks for state locks, drift, missing provider locks, and import requirements. If issues are detected you can abort or continue knowingly.
   - When no backend metadata exists, the diagnostics automatically run `terraform init -upgrade` to bootstrap the environment.

1. Follow the prompts for the chosen mode.
   - The script echoes every Terraform command and exit code so you can copy the output into deployment logs.
   - Successful plan runs leave `plan.tfplan` and `plan.json` in the repo root. Option 2 uses the exact plan file for the subsequent apply.
   - If `terraform apply` fails, the workflow surfaces tailored remediation guidance and keeps the `plan.tfplan` file so you can retry with option 3.

1. When the script finishes, capture the artefacts and outputs you need for auditing:
   - Review `plan.json` or export additional copies with `terraform show` if required by your process.
   - Run `terraform output` to snapshot deployed values.
   - Commit or archive the generated files according to your team’s change-management practices.

## Troubleshooting Prompts

- **Storage account key authentication blocked** – Option **[1]** now calls `Enable-StorageAccountSharedKeyAccess` to toggle shared key auth on the affected storage account (and reminds you to disable it afterwards). Option **[2]** runs `Invoke-StorageAccountAadRemediation` to grant your signed-in identity the *Storage Blob Data Contributor* role and sets `ARM_USE_AZUREAD=true` before retrying Terraform.
- **Invalid count dependency** – The helper suggests running `scripts/run-terraform-targeted-apply.ps1` to stage resources in two passes.
- **Application Gateway Key Vault access denied** – Follow the inline checklist to confirm role assignments and Key Vault firewall rules before re-running the apply.
- **Saved plan is stale** – Create a fresh plan through menu option **[1]** or rerun option **[2]** to keep state and plan in sync.

## Recommended Next Steps

- Run the AVM validation workflow (`./avm pre-commit` followed by `./avm pr-check`) before raising a pull request.
- Store plan artefacts under `artifacts/` if you need long-lived audit trails. A quick command is `terraform show -json plan.tfplan > artifacts/plan_$(Get-Date -Format yyyy-MM-dd_HH-mm-ss).json`.
- Update deployment logs or runbooks with any remediation actions the script surfaced so future runs start from a known-good state.


