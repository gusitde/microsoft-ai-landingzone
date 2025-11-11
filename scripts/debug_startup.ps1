#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Terraform startup script with interactive mode selection and pre-flight diagnostics.

.DESCRIPTION
    Runs Terraform initialization, validation, and optionally plan/apply based on user selection.
    Includes pre-flight checks to detect state conflicts, import requirements, and other issues.
#>

# Function to run Terraform diagnostics
function Invoke-TerraformDiagnostics {
    param(
        [string]$TerraformExe
    )

    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "PRE-FLIGHT DIAGNOSTICS" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host ""

    $issues = @()
    $warnings = @()

    # Check 1: State file exists and is valid
    Write-Host "[1/6] Checking Terraform state..." -ForegroundColor Cyan
    if (Test-Path "terraform.tfstate") {
        try {
            $stateContent = Get-Content "terraform.tfstate" -Raw | ConvertFrom-Json
            $stateVersion = $stateContent.version
            $resourceCount = if ($stateContent.resources) { $stateContent.resources.Count } else { 0 }

            Write-Host "  ✓ State file exists (version: $stateVersion, resources: $resourceCount)" -ForegroundColor Green

            # Check for empty state with existing plan
            if ($resourceCount -eq 0 -and (Test-Path "plan.tfplan")) {
                $warnings += "State is empty but a plan file exists - may need to import existing resources"
            }
        }
        catch {
            $issues += "State file exists but appears corrupted or invalid JSON"
            Write-Host "  ✗ State file is corrupted" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  ⚠ No state file found (new deployment)" -ForegroundColor Yellow
        $warnings += "No state file - this appears to be a new deployment"
    }

    # Check 2: State lock
    Write-Host "[2/6] Checking for state locks..." -ForegroundColor Cyan
    if (Test-Path ".terraform/terraform.tfstate") {
        $lockInfo = Get-Content ".terraform/terraform.tfstate" -Raw -ErrorAction SilentlyContinue
        if ($lockInfo -match '"ID":\s*"[^"]+"') {
            $issues += "State appears to be locked - another operation may be in progress"
            Write-Host "  ✗ State lock detected" -ForegroundColor Red
        }
        else {
            Write-Host "  ✓ No state locks detected" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  ✓ No state locks detected" -ForegroundColor Green
    }

    # Check 3: Backend configuration
    Write-Host "[3/6] Checking backend configuration..." -ForegroundColor Cyan
    $needsInit = $false
    if (Test-Path ".terraform/terraform.tfstate") {
        try {
            $backendState = Get-Content ".terraform/terraform.tfstate" -Raw | ConvertFrom-Json
            $backend = $backendState.backend.type
            Write-Host "  ✓ Backend configured: $backend" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠ Backend state file exists but couldn't be read" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  ⚠ No backend state found - initialization required" -ForegroundColor Yellow
        $needsInit = $true
    }

    # Auto-initialize if needed
    if ($needsInit) {
        Write-Host "`n  ↻ Running automatic initialization..." -ForegroundColor Cyan
        Write-Host "  Command: terraform init -upgrade`n" -ForegroundColor Gray

        & $TerraformExe init -upgrade
        $initExitCode = $LASTEXITCODE

        if ($initExitCode -eq 0) {
            Write-Host "`n  ✓ Terraform initialized successfully!" -ForegroundColor Green
        }
        else {
            Write-Host "`n  ✗ Terraform init failed with exit code: $initExitCode" -ForegroundColor Red
            $issues += "Failed to initialize Terraform - check configuration and credentials"
        }
    }

    # Check 4: Drift detection (if state exists)
    Write-Host "[4/6] Checking for potential drift..." -ForegroundColor Cyan
    if (Test-Path "terraform.tfstate") {
        $refreshResult = & $TerraformExe plan -refresh-only -detailed-exitcode 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-Host "  ✓ No drift detected" -ForegroundColor Green
        }
        elseif ($exitCode -eq 2) {
            $issues += "Drift detected - infrastructure has changed outside of Terraform"
            Write-Host "  ✗ Drift detected - infrastructure may have changed" -ForegroundColor Red
        }
        else {
            Write-Host "  ⚠ Unable to check for drift (may need init)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  ⚠ Skipping drift check (no state file)" -ForegroundColor Yellow
    }

    # Check 5: Resource conflicts and import requirements
    Write-Host "[5/6] Scanning for potential import requirements..." -ForegroundColor Cyan
    $planOutput = & $TerraformExe plan -no-color 2>&1
    $planText = $planOutput -join "`n"

    if ($planText -match "already exists|already been created|resource.*exists") {
        $issues += "Resources may already exist in Azure - consider using 'terraform import'"
        Write-Host "  ✗ Potential import required - resources may exist" -ForegroundColor Red
    }
    elseif ($planText -match "Error") {
        Write-Host "  ⚠ Plan had errors - check configuration" -ForegroundColor Yellow
    }
    else {
        Write-Host "  ✓ No import conflicts detected" -ForegroundColor Green
    }

    # Check 6: Provider version conflicts
    Write-Host "[6/6] Checking provider compatibility..." -ForegroundColor Cyan
    if (Test-Path ".terraform.lock.hcl") {
        Write-Host "  ✓ Provider lock file exists" -ForegroundColor Green

        # Check for version constraints
        $lockContent = Get-Content ".terraform.lock.hcl" -Raw
        if ($lockContent -match 'version\s*=\s*"([^"]+)"') {
            Write-Host "  ✓ Provider versions locked" -ForegroundColor Green
        }
    }
    else {
        $warnings += "No provider lock file - versions may change unexpectedly"
        Write-Host "  ⚠ No provider lock file found" -ForegroundColor Yellow
    }

    # Summary
    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "DIAGNOSTIC SUMMARY" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
        Write-Host "✓ No issues detected - ready to proceed!" -ForegroundColor Green
        return $true
    }

    if ($issues.Count -gt 0) {
        Write-Host "`n⚠ ISSUES FOUND ($($issues.Count)):" -ForegroundColor Red
        foreach ($issue in $issues) {
            Write-Host "  • $issue" -ForegroundColor Red
        }
    }

    if ($warnings.Count -gt 0) {
        Write-Host "`n⚠ WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
        foreach ($warning in $warnings) {
            Write-Host "  • $warning" -ForegroundColor Yellow
        }
    }

    # Remediation suggestions
    if ($issues.Count -gt 0) {
        Write-Host "`n💡 RECOMMENDED ACTIONS:" -ForegroundColor Cyan

        if ($issues -match "locked") {
            Write-Host "  - Force unlock: $($TerraformExe) force-unlock `<LOCK_ID`>" -ForegroundColor White
        }
        if ($issues -match "corrupted|invalid") {
            Write-Host "  - Restore from backup: copy terraform.tfstate.backup terraform.tfstate" -ForegroundColor White
            Write-Host "  - Or pull from remote: $($TerraformExe) state pull > terraform.tfstate" -ForegroundColor White
        }
        if ($issues -match "import") {
            Write-Host "  - Import existing resource: $($TerraformExe) import `<resource_type`>.<name> `<azure_resource_id`>" -ForegroundColor White
            Write-Host "  - List resources to import: az resource list --resource-group `<rg-name`>" -ForegroundColor White
        }
        if ($issues -match "drift") {
            Write-Host "  - Review drift: $($TerraformExe) plan -refresh-only" -ForegroundColor White
            Write-Host "  - Apply refresh: $($TerraformExe) apply -refresh-only -auto-approve" -ForegroundColor White
        }

        Write-Host "`n" -NoNewline
        $proceed = Read-Host "Continue despite issues? (yes/no)"
        if ($proceed -ne 'yes' -and $proceed -ne 'y' -and $proceed -ne 'YES' -and $proceed -ne 'Y') {
            Write-Host "`n✓ Operation cancelled for safety." -ForegroundColor Yellow
            exit 0
        }
    }

    return $true
}

# Function to test if Terraform supports full operations
function Test-TerraformCapabilities {
    param([string]$TerraformPath)

    # Check if it's a Python shim (lightweight version for CI)
    if (Test-Path $TerraformPath) {
        $firstLine = Get-Content $TerraformPath -First 1 -ErrorAction SilentlyContinue
        if ($firstLine -match "python") {
            return $false  # Python shim - limited to fmt/validate only
        }
    }

    # Try to get version (real Terraform responds to -version)
    $versionOutput = & $TerraformPath -version 2>&1
    if ($versionOutput -match "Terraform v\d+\.\d+") {
        return $true  # Real Terraform
    }

    return $false  # Unknown or limited capability
}

# Function to analyze and provide remediation for Terraform errors
function Show-TerraformErrorGuidance {
    param(
        [object]$ErrorOutput,
        [string]$TerraformExe
    )

    $errorText = $ErrorOutput -join "`n"
    $guidanceShown = $false

    # Error 1: WriteOnly Attribute Not Allowed
    if ($errorText -match "WriteOnly Attribute Not Allowed|Write-only attributes are only supported in Terraform 1.11") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║          TERRAFORM VERSION INCOMPATIBILITY DETECTED        ║" -ForegroundColor Red
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
        Write-Host "⚠ Your Terraform version is too old for this project" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Required version: 1.11.0 or higher" -ForegroundColor White
        Write-Host ""
        Write-Host "Why this matters:" -ForegroundColor Cyan
        Write-Host "  This project uses AzAPI provider features (WriteOnly attributes like 'sensitive_body')" -ForegroundColor White
        Write-Host "  that require Terraform 1.11.0 or later." -ForegroundColor White
        Write-Host ""
        Write-Host "Solution: Upgrade Terraform" -ForegroundColor Green
        Write-Host ""
        Write-Host "This script can do it for you. Re-run and accept the upgrade prompt." -ForegroundColor Yellow
        Write-Host "  powershell.exe -ExecutionPolicy Bypass -File .\scripts\run-terraform-start-up.ps1" -ForegroundColor White

        $guidanceShown = $true
    }

    # Error 2: Invalid count argument
    if ($errorText -match "Invalid count argument|count value depends on resource attributes that cannot be determined until apply") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║          INVALID COUNT DEPENDENCY DETECTED                 ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "⚠ A 'count' meta-argument depends on a resource that hasn't been created yet" -ForegroundColor Yellow
        Write-Host ""

        # Extract resource from error
        if ($errorText -match "on (module\.[^ ]+)") {
            Write-Host "Affected resource: $($matches[1])" -ForegroundColor Cyan
        }

        Write-Host ""
        Write-Host "This is a known Terraform limitation. The solution is a two-stage deployment." -ForegroundColor White
        Write-Host ""
        Write-Host "Solution: Use the targeted apply script" -ForegroundColor Green
        Write-Host ""
        Write-Host "This script will:" -ForegroundColor Cyan
        Write-Host "  1. Create the dependency resources (VNet, Key Vault, etc.)" -ForegroundColor White
        Write-Host "  2. Apply the full configuration" -ForegroundColor White
        Write-Host ""
        Write-Host "Run this command:" -ForegroundColor Yellow
        Write-Host "  .\scripts\run-terraform-targeted-apply.ps1" -ForegroundColor White

        $guidanceShown = $true
    }

    # Error 3: Application Gateway Key Vault Access Denied
    if ($errorText -match "ApplicationGatewayKeyVaultSecretAccessDenied|Access denied for KeyVault Secret") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║   APPLICATION GATEWAY KEY VAULT ACCESS DENIED DETECTED     ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "⚠ The Application Gateway's identity can't access the Key Vault certificate" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "Common causes:" -ForegroundColor Cyan
        Write-Host "  1. Missing 'Key Vault Secrets User' role for App Gateway's identity" -ForegroundColor White
        Write-Host "  2. Key Vault firewall blocking 'Azure Trusted Services'" -ForegroundColor White
        Write-Host "  3. Role assignment propagation delay (can take 5-10 minutes)" -ForegroundColor White
        Write-Host ""

        Write-Host "Solution: Verify roles and firewall, then wait" -ForegroundColor Green
        Write-Host ""
        Write-Host "1. Get App Gateway Identity ID:" -ForegroundColor Yellow
        Write-Host "   az network application-gateway show -n <app-gw-name> -g <rg-name> --query 'identity.principalId' -o tsv" -ForegroundColor White
        Write-Host ""
        Write-Host "2. Assign role (if missing):" -ForegroundColor Yellow
        Write-Host "   az role assignment create --role 'Key Vault Secrets User' --assignee-object-id <principalId> --scope /subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/<kv-name>" -ForegroundColor White
        Write-Host ""
        Write-Host "3. Check Key Vault firewall:" -ForegroundColor Yellow
        Write-Host "   az keyvault show -n <kv-name> --query 'properties.networkAcls.bypass'" -ForegroundColor White
        Write-Host "   (Should be 'AzureServices')" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "4. Wait 5-10 minutes for roles to apply, then:" -ForegroundColor Yellow
        Write-Host "   terraform apply plan.tfplan" -ForegroundColor White

        $guidanceShown = $true
    }

    # Error 4: Storage Account Key-Based Authentication Not Permitted
    if ($errorText -match "Key based authentication is not permitted|KeyBasedAuthenticationNotPermitted") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║   STORAGE ACCOUNT KEY AUTHENTICATION DISABLED DETECTED     ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "⚠ Terraform is trying to use storage keys, but they are disabled on the Storage Account" -ForegroundColor Yellow
        Write-Host "  This is a good security practice, but requires a specific workflow." -ForegroundColor White
        Write-Host ""

        Write-Host "Choose your remediation path:" -ForegroundColor Cyan
        Write-Host "  [1] Temporarily enable key auth (less secure, easiest fix)" -ForegroundColor White
        Write-Host "  [2] Use Microsoft Entra ID for auth (recommended, requires RBAC)" -ForegroundColor White
        Write-Host "  [3] Use a two-stage deployment (advanced)" -ForegroundColor White
        Write-Host ""
        $remediationChoice = Read-Host "Your choice (1/2/3)"

        switch ($remediationChoice) {
            '1' {
                Write-Host "`nSolution 1: Temporarily enable key-based authentication" -ForegroundColor Green
                Write-Host ""
                Write-Host "Run these commands:" -ForegroundColor Yellow
                Write-Host "1. Enable key auth:" -ForegroundColor Cyan
                Write-Host "   az storage account update -n <storage-account-name> -g <rg-name> --allow-shared-key-access true" -ForegroundColor White
                Write-Host ""
                Write-Host "2. Re-run apply:" -ForegroundColor Cyan
                Write-Host "   $TerraformExe apply plan.tfplan" -ForegroundColor White
                Write-Host ""
                Write-Host "3. (Optional) Disable key auth after apply:" -ForegroundColor Cyan
                Write-Host "   az storage account update -n <storage-account-name> -g <rg-name> --allow-shared-key-access false" -ForegroundColor White
            }
            '2' {
                Write-Host "`nSolution 2: Use Microsoft Entra ID (Managed Identity) for authentication" -ForegroundColor Green
                Write-Host ""
                Write-Host "This is the most secure method. Your identity needs 'Storage Blob Data Contributor' role." -ForegroundColor White
                Write-Host ""
                Write-Host "Run these commands:" -ForegroundColor Yellow
                Write-Host "1. Get your user/principal ID:" -ForegroundColor Cyan
                Write-Host "   az ad signed-in-user show --query 'id' -o tsv" -ForegroundColor White
                Write-Host ""
                Write-Host "2. Get Storage Account ID:" -ForegroundColor Cyan
                Write-Host "   az storage account show -n <storage-account-name> -g <rg-name> --query 'id' -o tsv" -ForegroundColor White
                Write-Host ""
                Write-Host "3. Assign the required role:" -ForegroundColor Cyan
                Write-Host "   az role assignment create --role 'Storage Blob Data Contributor' --assignee <your-principal-id> --scope <storage-account-id>" -ForegroundColor White
                Write-Host ""
                Write-Host "4. Set environment variable for Terraform:" -ForegroundColor Cyan
                Write-Host "   `$env:ARM_USE_AZUREAD = 'true'" -ForegroundColor White
                Write-Host ""
                Write-Host "5. Re-run apply:" -ForegroundColor Cyan
                Write-Host "   $TerraformExe apply plan.tfplan" -ForegroundColor White
            }
            '3' {
                Write-Host "`nSolution 3: Two-stage deployment" -ForegroundColor Green
                Write-Host ""
                Write-Host "This creates the storage account first, then configures it in a second step." -ForegroundColor White
                Write-Host ""
                Write-Host "Run these commands:" -ForegroundColor Yellow
                Write-Host "1. Target only the storage account:" -ForegroundColor Cyan
                Write-Host "   $TerraformExe apply -target='module.storage_account.azurerm_storage_account.this'" -ForegroundColor White
                Write-Host ""
                Write-Host "2. Run the full apply:" -ForegroundColor Cyan
                Write-Host "   $TerraformExe apply plan.tfplan" -ForegroundColor White
            }
        }
        $guidanceShown = $true
    }

    # Error 5: Missing Resource Identity After Create
    if ($errorText -match "Missing Resource Identity After Create|unexpectedly returned no resource identity") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║          MISSING RESOURCE IDENTITY DETECTED                ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "⚠ A resource was created but its identity assignment failed" -ForegroundColor Yellow
        Write-Host "  This can be a transient Azure error or a provider bug." -ForegroundColor White
        Write-Host ""

        Write-Host "Solution: Check, import, and retry" -ForegroundColor Green
        Write-Host ""
        Write-Host "1. Check if resource actually exists:" -ForegroundColor Yellow
        Write-Host "   az storage account list --resource-group `<rg-name>` --query '[].name'" -ForegroundColor White
        Write-Host ""
        Write-Host "2. If exists, import the resource:" -ForegroundColor Yellow
        Write-Host "   terraform import 'module.storage_account[0].azurerm_storage_account.this' '/subscriptions/.../resourceGroups/.../providers/Microsoft.Storage/storageAccounts/...'" -ForegroundColor White
        Write-Host ""
        Write-Host "3. If doesn't exist, this often follows the key auth error above" -ForegroundColor Yellow
        Write-Host "   Fix the key authentication issue first, then:" -ForegroundColor White
        Write-Host "   terraform apply" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "4. Check for provider bugs:" -ForegroundColor Yellow
        Write-Host "   • Review AzureRM provider changelog" -ForegroundColor White
        Write-Host "   • Consider upgrading/downgrading provider version" -ForegroundColor White
        Write-Host "   • Check GitHub issues: https://github.com/hashicorp/terraform-provider-azurerm/issues" -ForegroundColor White

        $guidanceShown = $true
    }

    # Error 6: Saved Plan is Stale
    if ($errorText -match "Saved plan is stale|plan file can no longer be applied|state was changed by another operation") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║          SAVED PLAN IS STALE                               ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "⚠ The terraform state changed after the plan was created" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "What happened:" -ForegroundColor Cyan
        Write-Host "  • Plan was created at time T1" -ForegroundColor White
        Write-Host "  • State was modified between T1 and now (manual changes, another apply, etc.)" -ForegroundColor White
        Write-Host "  • Terraform refuses to apply the outdated plan for safety" -ForegroundColor White
        Write-Host ""

        Write-Host "Common causes:" -ForegroundColor Cyan
        Write-Host "  • Another team member ran terraform apply" -ForegroundColor White
        Write-Host "  • Manual Azure Portal/CLI changes were made" -ForegroundColor White
        Write-Host "  • Previous failed apply changed some resources" -ForegroundColor White
        Write-Host "  • Concurrent terraform operations" -ForegroundColor White
        Write-Host ""

        Write-Host "Solution: Create a fresh plan" -ForegroundColor Green
        Write-Host ""
        Write-Host "Run these commands:" -ForegroundColor Yellow
        Write-Host "  terraform plan -out=plan.tfplan" -ForegroundColor White
        Write-Host "  terraform apply plan.tfplan" -ForegroundColor White
        Write-Host ""
        Write-Host "Or use this script:" -ForegroundColor Yellow
        Write-Host "  .\scripts\run-terraform-start-up.ps1" -ForegroundColor White
        Write-Host "  Choose option [2] (Plan + Apply)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "To prevent this:" -ForegroundColor Cyan
        Write-Host "  • Apply plans shortly after creating them" -ForegroundColor White
        Write-Host "  • Use remote state locking (Azure Storage backend)" -ForegroundColor White
        Write-Host "  • Coordinate with team members before applying" -ForegroundColor White

        $guidanceShown = $true
    }

    # Warning: Deprecated argument
    if ($errorText -match "Warning: Argument is deprecated|has been deprecated in favor of") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║          DEPRECATION WARNINGS DETECTED                     ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "ℹ These are warnings, not errors - deployment can continue" -ForegroundColor Cyan
        Write-Host ""

        # Extract deprecated arguments
        if ($errorText -match "metric.*has been deprecated in favor of.*enabled_metric") {
            Write-Host "Deprecation: 'metric' property in azurerm_monitor_diagnostic_setting" -ForegroundColor White
            Write-Host "  Old: metric { ... }" -ForegroundColor Red
            Write-Host "  New: enabled_metric { ... }" -ForegroundColor Green
            Write-Host "  Impact: Will break in AzureRM provider v5.0" -ForegroundColor Yellow
            Write-Host ""
        }

        Write-Host "Action:" -ForegroundColor Cyan
        Write-Host "  • These warnings won't block deployment" -ForegroundColor White
        Write-Host "  • Plan to update modules before provider v5.0" -ForegroundColor White
        Write-Host "  • Check module updates: https://registry.terraform.io/modules/Azure/" -ForegroundColor White
        Write-Host ""

        $guidanceShown = $true
    }

    return $guidanceShown
}

# Function to check Terraform version compatibility
function Test-TerraformVersionCompatibility {
    param(
        [string]$TerraformExe,
        [string]$MinimumVersion = "1.11.0"
    )

    try {
        $versionOutput = & $TerraformExe -version 2>&1 | Select-Object -First 1
        if ($versionOutput -match "Terraform v(\d+\.\d+\.\d+)") {
            $currentVersion = [version]$matches[1]
            $requiredVersion = [version]$MinimumVersion

            if ($currentVersion -lt $requiredVersion) {
                return @{
                    Compatible = $false
                    Current = $currentVersion.ToString()
                    Required = $MinimumVersion
                }
            }

            return @{
                Compatible = $true
                Current = $currentVersion.ToString()
                Required = $MinimumVersion
            }
        }
    }
    catch {
        Write-Host "⚠ Unable to determine Terraform version" -ForegroundColor Yellow
    }

    return @{
        Compatible = $null
        Current = "unknown"
        Required = $MinimumVersion
    }
}

# Function to download and install Terraform
function Install-Terraform {
    param(
        [string]$InstallPath,
        [string]$Version = "1.11.0"
    )

    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║       TERRAFORM NOT FOUND - AUTOMATIC INSTALLATION         ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Yellow

    Write-Host "No full Terraform binary detected. Would you like to download it now?" -ForegroundColor Cyan
    Write-Host "  Version: $Version" -ForegroundColor White
    Write-Host "  Install location: $InstallPath" -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "Download and install Terraform? (yes/no)"

    if ($confirm -ne 'yes' -and $confirm -ne 'y' -and $confirm -ne 'YES' -and $confirm -ne 'Y') {
        Write-Host "`n✗ Installation cancelled." -ForegroundColor Red
        Write-Host "`nTo proceed, you need to:" -ForegroundColor Yellow
        Write-Host "  1. Download Terraform from: https://www.terraform.io/downloads" -ForegroundColor White
        Write-Host "  2. Install it globally OR place terraform.exe in your PATH" -ForegroundColor White
        Write-Host "  3. Or place it at: $InstallPath" -ForegroundColor White
        return $false
    }

    try {
        Write-Host "`n[1/3] Downloading Terraform v$Version..." -ForegroundColor Cyan
        $ProgressPreference = 'SilentlyContinue'
        $url = "https://releases.hashicorp.com/terraform/$Version/terraform_${Version}_windows_amd64.zip"
        $zipPath = Join-Path $env:TEMP "terraform_${Version}.zip"

        Invoke-WebRequest -Uri $url -OutFile $zipPath -ErrorAction Stop
        Write-Host "  ✓ Download complete" -ForegroundColor Green

        Write-Host "`n[2/3] Extracting Terraform..." -ForegroundColor Cyan
        $extractDir = Split-Path -Parent $InstallPath

        # Ensure the directory exists
        if (-not (Test-Path $extractDir)) {
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        }

        # Extract (this will create terraform.exe in the tools directory)
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        Write-Host "  ✓ Extraction complete" -ForegroundColor Green

        Write-Host "`n[3/3] Cleaning up..." -ForegroundColor Cyan
        Remove-Item $zipPath -Force
        Write-Host "  ✓ Cleanup complete" -ForegroundColor Green

        # Verify installation
        if (Test-Path $InstallPath) {
            Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
            Write-Host "║       TERRAFORM INSTALLATION SUCCESSFUL                   ║" -ForegroundColor Green
            Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

            $versionOutput = & $InstallPath -version 2>&1 | Select-Object -First 1
            Write-Host "Installed: $versionOutput" -ForegroundColor White
            Write-Host "Location: $InstallPath" -ForegroundColor White
            Write-Host ""
            Write-Host "ℹ This version supports WriteOnly attributes (sensitive_body) required by AzAPI provider" -ForegroundColor Cyan

            return $true
        }
        else {
            Write-Host "`n✗ Installation verification failed - terraform.exe not found at expected location" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "`n✗ Installation failed: $_" -ForegroundColor Red
        Write-Host "`nPlease install Terraform manually from: https://www.terraform.io/downloads" -ForegroundColor Yellow
        return $false
    }
}

# Function to check if Application Gateway certificate is needed
function Test-AppGatewayCertificate {
    param(
        [string]$RepoRoot
    )
    Write-Host ""
    Write-Host "Checking Application Gateway certificate requirements..." -ForegroundColor Cyan

    # Check if App Gateway is enabled in tfvars
    $tfvarsPath = Join-Path $RepoRoot "landingzone.defaults.auto.tfvars"
    if (Test-Path $tfvarsPath) {
        $tfvarsContent = Get-Content $tfvarsPath -Raw

        # Check if app gateway is enabled
        if ($tfvarsContent -match 'app_gateway' -and $tfvarsContent -match 'deploy\s*=\s*true') {
            Write-Host "  ℹ Application Gateway deployment detected" -ForegroundColor Yellow

            # Check if certificate secret ID is configured
            if ($tfvarsContent -notmatch 'key_vault_secret_id\s*=') {
                Write-Host ""
                Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
                Write-Host "║     APPLICATION GATEWAY CERTIFICATE REQUIRED               ║" -ForegroundColor Yellow
                Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "⚠ Application Gateway is enabled but no SSL certificate is configured" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Cyan
                Write-Host "  1. Generate a self-signed certificate now (recommended for testing)" -ForegroundColor White
                Write-Host "  2. Continue without certificate (deployment may fail)" -ForegroundColor White
                Write-Host "  3. Cancel and configure manually" -ForegroundColor White
                Write-Host ""

                $certChoice = Read-Host "Your choice (1/2/3)"

                if ($certChoice -eq '1') {
                    Write-Host ""
                    Write-Host "Certificate generation requires:" -ForegroundColor Cyan
                    Write-Host "  • Key Vault name" -ForegroundColor White
                    Write-Host "  • Resource Group name" -ForegroundColor White
                    Write-Host "  • Azure login (will use current session)" -ForegroundColor White
                    Write-Host ""

                    # Extract Key Vault name from tfvars if possible
                    $kvName = $null
                    if ($tfvarsContent -match 'key_vault.*name\s*=\s*"([^"]+)"') {
                        $kvName = $matches[1]
                    }

                    # Extract Resource Group name
                    $rgName = $null
                    if ($tfvarsContent -match 'resource_group.*name\s*=\s*"([^"]+)"') {
                        $rgName = $matches[1]
                    }

                    if ($kvName -and $rgName) {
                        Write-Host "Detected configuration:" -ForegroundColor Green
                        Write-Host "  Key Vault: $kvName" -ForegroundColor White
                        Write-Host "  Resource Group: $rgName" -ForegroundColor White
                        Write-Host ""

                        $confirm = Read-Host "Use these values? (yes/no)"

                        if ($confirm -eq 'yes' -or $confirm -eq 'y' -or $confirm -eq 'YES' -or $confirm -eq 'Y') {
                            # Run certificate generation script
                            $certScriptPath = Join-Path $RepoRoot "scripts\Generate-AppGwCertificate.ps1"

                            if (Test-Path $certScriptPath) {
                                Write-Host ""
                                Write-Host "Running certificate generation script..." -ForegroundColor Cyan
                                & $certScriptPath -KeyVaultName $kvName -ResourceGroupName $rgName -CertificateName "appgw-cert" -DnsName "*.example.com"

                                if ($LASTEXITCODE -eq 0) {
                                    Write-Host ""
                                    Write-Host "✓ Certificate generated successfully!" -ForegroundColor Green
                                    Write-Host "  You can now proceed with deployment" -ForegroundColor White
                                    Write-Host ""
                                }
                                else {
                                    Write-Host ""
                                    Write-Host "⚠ Certificate generation failed or was cancelled" -ForegroundColor Yellow
                                    Write-Host "  You may need to generate it manually or configure an existing certificate" -ForegroundColor White
                                    Write-Host ""
                                }
                            }
                            else {
                                Write-Host "✗ Certificate generation script not found at: $certScriptPath" -ForegroundColor Red
                            }
                        }
                    }
                    else {
                        Write-Host "⚠ Could not auto-detect Key Vault and Resource Group names" -ForegroundColor Yellow
                        Write-Host "  Please run manually:" -ForegroundColor White
                        Write-Host "  .\scripts\Generate-AppGwCertificate.ps1 -KeyVaultName `<name>` -ResourceGroupName `<rg>`" -ForegroundColor Cyan
                    }
                }
                elseif ($certChoice -eq '3') {
                    Write-Host ""
                    Write-Host "✓ Operation cancelled. Please configure certificate and try again." -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "To generate certificate manually:" -ForegroundColor Cyan
                    Write-Host "  .\scripts\Generate-AppGwCertificate.ps1 -KeyVaultName `<name>` -ResourceGroupName `<rg>`" -ForegroundColor White
                    exit 0
                }
                else {
                    Write-Host ""
                    Write-Host "⚠ Continuing without certificate - deployment may fail" -ForegroundColor Yellow
                }

            }
            else {
                Write-Host "  ✓ SSL certificate configuration found" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  ✓ Application Gateway not enabled or certificate not required" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  ℹ Could not find tfvars file - skipping certificate check" -ForegroundColor Gray
    }
}

# --- Main Script Body ---

# Move to the Terraform project folder (repo root)
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptPath
Set-Location $repoRoot

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          TERRAFORM DEPLOYMENT WORKFLOW                    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Working directory: $repoRoot" -ForegroundColor Gray
Write-Host ""

# Determine Terraform executable path (use repo's pinned version or system)
# Check multiple possible locations
$terraformLocations = @(
    (Join-Path $repoRoot "tools\terraform\terraform.exe"),
    (Join-Path $repoRoot "tools\terraform.exe"),
    (Join-Path $repoRoot "tools\terraform")
)

$terraformExe = $null
$isLimitedShim = $false

foreach ($location in $terraformLocations) {
    if (Test-Path $location) {
        # Check if this is a full Terraform or just a shim
        if (Test-TerraformCapabilities -TerraformPath $location) {
            $terraformExe = $location
            Write-Host "Using repo Terraform: $terraformExe" -ForegroundColor Green
            break
        }
        else {
            Write-Host "⚠ Found Terraform shim at $location (limited to fmt/validate only)" -ForegroundColor Yellow
            $isLimitedShim = $true
        }
    }
}

# If not found in repo, try system PATH
if (-not $terraformExe) {
    $systemTerraform = Get-Command terraform -ErrorAction SilentlyContinue
    if ($systemTerraform) {
        if (Test-TerraformCapabilities -TerraformPath $systemTerraform.Source) {
            $terraformExe = $systemTerraform.Source
            Write-Host "Using system Terraform: $terraformExe" -ForegroundColor Yellow
        }
        else {
            Write-Host "⚠ System terraform is also a limited shim" -ForegroundColor Yellow
        }
    }

    # Final check - if still no full Terraform found
    if (-not $terraformExe) {
        if ($isLimitedShim) {
            Write-Host "`nℹ The repo contains a Python shim at tools/terraform that only supports:" -ForegroundColor Cyan
            Write-Host "  - terraform fmt -recursive (code formatting)" -ForegroundColor White
            Write-Host "  - terraform validate (syntax validation)" -ForegroundColor White
            Write-Host "`nThis shim is for CI/offline validation only." -ForegroundColor Yellow
            Write-Host ""
        }

        # Offer to download and install Terraform automatically
        $installPath = Join-Path $repoRoot "tools\terraform.exe"
        $installed = Install-Terraform -InstallPath $installPath

        if ($installed) {
            $terraformExe = $installPath
            Write-Host "`n✓ Ready to proceed with Terraform operations!" -ForegroundColor Green
        }
        else {
            Write-Host "`n✗ Cannot proceed without Terraform." -ForegroundColor Red
            exit 1
        }
    }
}

# Check Terraform version compatibility
Write-Host "Checking Terraform version compatibility..." -ForegroundColor Cyan
$versionCheck = Test-TerraformVersionCompatibility -TerraformExe $terraformExe -MinimumVersion "1.11.0"

if ($versionCheck.Compatible -eq $false) {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║          TERRAFORM VERSION INCOMPATIBILITY DETECTED        ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "⚠ Your Terraform version is too old for this project" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Current version:  $($versionCheck.Current)" -ForegroundColor White
    Write-Host "  Required version: $($versionCheck.Required) or higher" -ForegroundColor White
    Write-Host ""
    Write-Host "Why this matters:" -ForegroundColor Cyan
    Write-Host "  This project uses AzAPI provider features (WriteOnly attributes like 'sensitive_body')" -ForegroundColor White
    Write-Host "  that require Terraform 1.11.0 or later." -ForegroundColor White
    Write-Host ""
    Write-Host "Error you might see:" -ForegroundColor Yellow
    Write-Host "  'WriteOnly Attribute Not Allowed - Write-only attributes are only supported" -ForegroundColor Red
    Write-Host "   in Terraform 1.11 and later.'" -ForegroundColor Red
    Write-Host ""

    $installPath = Join-Path $repoRoot "tools\terraform.exe"
    Write-Host "Would you like to upgrade to Terraform v1.11.0 now?" -ForegroundColor Cyan
    $upgrade = Read-Host "Upgrade Terraform? (yes/no)"

    if ($upgrade -eq 'yes' -or $upgrade -eq 'y' -or $upgrade -eq 'YES' -or $upgrade -eq 'Y') {
        # Backup old version if it exists
        if (Test-Path $installPath) {
            $backupPath = "$installPath.v$($versionCheck.Current).backup"
            Write-Host "  Creating backup: $backupPath" -ForegroundColor Gray
            Copy-Item $installPath $backupPath -Force
        }

        $installed = Install-Terraform -InstallPath $installPath -Version "1.11.0"

        if ($installed) {
            $terraformExe = $installPath
            Write-Host ""
            Write-Host "✓ Terraform upgraded successfully! Continuing with deployment..." -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "✗ Upgrade failed. Cannot proceed with incompatible version." -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host ""
        Write-Host "✗ Cannot proceed with Terraform v$($versionCheck.Current)" -ForegroundColor Red
        Write-Host ""
        Write-Host "To manually upgrade:" -ForegroundColor Yellow
        Write-Host "  1. Download from: https://releases.hashicorp.com/terraform/1.11.0/" -ForegroundColor White
        Write-Host "  2. Replace: $terraformExe" -ForegroundColor White
        exit 1
    }
}
elseif ($versionCheck.Compatible -eq $true) {
    Write-Host "✓ Terraform version $($versionCheck.Current) is compatible (>= $($versionCheck.Required))" -ForegroundColor Green
}

# Check for Application Gateway certificate requirements
Test-AppGatewayCertificate -RepoRoot $repoRoot

# Ask user what they want to do
Write-Host "`n┌─────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│  What would you like to do?                             │" -ForegroundColor Cyan
Write-Host "│                                                         │" -ForegroundColor Cyan
Write-Host "│  [1] Plan only (review changes)                         │" -ForegroundColor White
Write-Host "│  [2] Plan + Apply (review then deploy)                  │" -ForegroundColor White
Write-Host "│  [3] Apply only (use existing plan.tfplan)              │" -ForegroundColor White
Write-Host "│  [Q] Quit                                               │" -ForegroundColor White
Write-Host "│                                                         │" -ForegroundColor Cyan
Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Cyan

$choice = Read-Host "`nYour choice (1/2/3/Q)"

if ($choice -eq 'Q' -or $choice -eq 'q') {
    Write-Host "`n✓ Operation cancelled." -ForegroundColor Yellow
    exit 0
}

# Validate choice
if ($choice -notin @('1', '2', '3')) {
    Write-Host "`n✗ Invalid choice. Exiting." -ForegroundColor Red
    exit 1
}

# Run diagnostics before proceeding
Invoke-TerraformDiagnostics -TerraformExe $terraformExe

# Common setup steps (always run)
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 1: Terraform Version Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
& $terraformExe -version
$exitCode = $LASTEXITCODE
Write-Host ""

if ($exitCode -ne 0) {
    Write-Host "✗ Failed to get Terraform version (exit code: $exitCode)" -ForegroundColor Red
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 2: Initialize Terraform" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
& $terraformExe init -upgrade
$exitCode = $LASTEXITCODE
Write-Host ""

if ($exitCode -ne 0) {
    Write-Host "✗ Terraform init failed with exit code: $exitCode" -ForegroundColor Red
    Write-Host "`nCommon causes:" -ForegroundColor Yellow
    Write-Host "  - Backend configuration errors" -ForegroundColor White
    Write-Host "  - Invalid provider versions" -ForegroundColor White
    Write-Host "  - Network connectivity issues" -ForegroundColor White
    Write-Host "  - Missing Azure credentials (run: .\scripts\azure-login-devicecode.ps1)" -ForegroundColor White
    Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 3: Validate Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
& $terraformExe validate
$exitCode = $LASTEXITCODE
Write-Host ""

if ($exitCode -ne 0) {
    Write-Host "✗ Terraform validation failed with exit code: $exitCode" -ForegroundColor Red
    Write-Host "`nCommon causes:" -ForegroundColor Yellow
    Write-Host "  - Syntax errors in .tf files" -ForegroundColor White
    Write-Host "  - Missing required variables" -ForegroundColor White
    Write-Host "  - Invalid resource configurations" -ForegroundColor White
    Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Validation successful!" -ForegroundColor Green

# Execute based on user choice
switch ($choice) {
    '1' {
        # Plan only
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "STEP 4: Create Terraform Plan" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        $planOutput = & $terraformExe plan -out "plan.tfplan" 2>&1
        $planOutput | ForEach-Object { Write-Host $_ }
        $exitCode = $LASTEXITCODE
        Write-Host ""

        if ($exitCode -eq 0) {
            # Check for warnings even on success
            $planOutputText = $planOutput -join "`n"
            if ($planOutputText -match "Warning:") {
                Show-TerraformErrorGuidance -ErrorOutput $planOutput -TerraformExe $terraformExe | Out-Null
            }

            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "STEP 5: Export Plan to JSON" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            & $terraformExe show -json "plan.tfplan" > "plan.json"

            Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
            Write-Host "║          TERRAFORM PLAN COMPLETE                          ║" -ForegroundColor Green
            Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
            Write-Host "Plan saved to:      " -NoNewline -ForegroundColor White
            Write-Host "plan.tfplan" -ForegroundColor Cyan
            Write-Host "JSON plan saved to: " -NoNewline -ForegroundColor White
            Write-Host "plan.json" -ForegroundColor Cyan
            Write-Host "`nTo apply this plan later, run:" -ForegroundColor Yellow
            Write-Host "  $terraformExe apply plan.tfplan" -ForegroundColor White
        }
        else {
            Write-Host "✗ Terraform plan failed with exit code: $exitCode" -ForegroundColor Red

            # Analyze errors and show guidance
            $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $planOutput -TerraformExe $terraformExe

            if (-not $guidanceShown) {
                Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
            }
            exit 1
        }
    }

    '2' {
        # Plan + Apply
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "STEP 4: Create Terraform Plan" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        $planOutput2 = & $terraformExe plan -out "plan.tfplan" 2>&1
        $planOutput2 | ForEach-Object { Write-Host $_ }
        $exitCode = $LASTEXITCODE
        Write-Host ""

        if ($exitCode -ne 0) {
            Write-Host "✗ Terraform plan failed with exit code: $exitCode" -ForegroundColor Red

            # Analyze errors and show guidance
            $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $planOutput2 -TerraformExe $terraformExe

            if (-not $guidanceShown) {
                Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
            }
            exit 1
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "STEP 5: Export Plan to JSON" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        & $terraformExe show -json "plan.tfplan" > "plan.json"

        Write-Host "`n┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "│  REVIEW THE PLAN ABOVE                                  │" -ForegroundColor Yellow
        Write-Host "│                                                         │" -ForegroundColor Yellow
        Write-Host "│  Ready to apply these changes?                          │" -ForegroundColor Yellow
        Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow

        $confirm = Read-Host "`nProceed with apply? (yes/no)"

        if ($confirm -eq 'yes' -or $confirm -eq 'y' -or $confirm -eq 'YES' -or $confirm -eq 'Y') {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "STEP 6: Apply Terraform Plan" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
            $applyOutput = & $terraformExe apply "plan.tfplan" 2>&1
            $applyOutput | ForEach-Object { Write-Host $_ }
            $exitCode = $LASTEXITCODE
            Write-Host ""

            if ($exitCode -eq 0) {
                Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
                Write-Host "║          TERRAFORM APPLY COMPLETE                         ║" -ForegroundColor Green
                Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
                Write-Host "✓ Infrastructure deployed successfully!" -ForegroundColor Green
            }
            else {
                Write-Host "✗ Terraform apply failed with exit code: $exitCode" -ForegroundColor Red

                # Analyze errors and show guidance
                $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $applyOutput -TerraformExe $terraformExe

                if (-not $guidanceShown) {
                    Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
                }
                Write-Host "`nTo retry, run option [3] to apply the existing plan," -ForegroundColor Yellow
                Write-Host "or start over with option [1] or [2]." -ForegroundColor Yellow
                exit 1
            }
        }
        else {
            Write-Host "`n✓ Apply cancelled. Plan saved for later use." -ForegroundColor Yellow
        }
    }

    '3' {
        # Apply only (existing plan)
        if (-not (Test-Path "plan.tfplan")) {
            Write-Host "`n✗ ERROR: plan.tfplan not found!" -ForegroundColor Red
            Write-Host "Please run option [1] or [2] first to create a plan." -ForegroundColor Yellow
            exit 1
        }

        Write-Host "`n┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "│  APPLY EXISTING PLAN                                    │" -ForegroundColor Yellow
        Write-Host "│                                                         │" -ForegroundColor Yellow
        Write-Host "│  This will apply the existing plan.tfplan file          │" -ForegroundColor Yellow
        Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow

        $confirm = Read-Host "`nProceed with apply? (yes/no)"

        if ($confirm -eq 'yes' -or $confirm -eq 'y' -or $confirm -eq 'YES' -or $confirm -eq 'Y') {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "STEP 4: Apply Terraform Plan" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
            $applyOutput3 = & $terraformExe apply "plan.tfplan" 2>&1
            $applyOutput3 | ForEach-Object { Write-Host $_ }
            $exitCode = $LASTEXITCODE
            Write-Host ""

            if ($exitCode -eq 0) {
                Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
                Write-Host "║          TERRAFORM APPLY COMPLETE                         ║" -ForegroundColor Green
                Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
                Write-Host "✓ Infrastructure deployed successfully!" -ForegroundColor Green
            }
            else {
                Write-Host "✗ Terraform apply failed with exit code: $exitCode" -ForegroundColor Red

                # Analyze errors and show guidance
                $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $applyOutput3 -TerraformExe $terraformExe

                if (-not $guidanceShown) {
                    Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
                }
                exit 1
            }
        }
        else {
            Write-Host "`n✓ Apply cancelled." -ForegroundColor Yellow
        }
    }
}

Write-Host "`n✓ Terraform workflow complete!" -ForegroundColor Green
