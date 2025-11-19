#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Terraform startup script with interactive mode selection and pre-flight diagnostics.

.DESCRIPTION
    '4' {
        # Destroy (plan + apply destroy)
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "STEP 4: Create Destroy Plan" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        while ($true) {
            Reset-TerraformRemediationAction

            $destroyPlanOutput = & $terraformExe plan -destroy -out "destroy.tfplan" 2>&1
            $destroyPlanOutput | ForEach-Object { Write-Host $_ }
            $exitCode = $LASTEXITCODE
            Write-Host ""

            if ($exitCode -eq 0) {
                & $terraformExe show -json "destroy.tfplan" > "destroy-plan.json"
                break
            }

            Write-Host "[ERROR] Terraform destroy plan failed with exit code: $exitCode" -ForegroundColor Red

            $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $destroyPlanOutput -TerraformExe $terraformExe
            $retryAction = Get-TerraformRemediationAction

            if ($retryAction -eq 'retry-plan') {
                Write-Host "`n[RETRY] Running terraform plan -destroy again after remediation..." -ForegroundColor Cyan
                continue
            }

            if ($retryAction -eq 'ignore-error') {
                Write-Host "`nDestroy flow cancelled per user choice." -ForegroundColor Yellow
                exit 1
            }

            if (-not $guidanceShown) {
                Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
            }
            exit 1
        }

    Write-Host "`n---------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "DESTROY PLAN COMPLETE" -ForegroundColor Yellow
    Write-Host "Review output above and destroy-plan.json" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------------" -ForegroundColor Yellow

        $confirmDestroy = Read-Host "`nProceed with terraform destroy? (yes/no)"

        if ($confirmDestroy -notin @('yes', 'y', 'YES', 'Y')) {
            Write-Host "`n[INFO] Destroy cancelled. Leaving destroy.tfplan for inspection." -ForegroundColor Yellow
            exit 0
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "STEP 5: Apply Destroy Plan" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        Reset-TerraformRemediationAction
        $destroyApplyOutput = & $terraformExe apply "destroy.tfplan" 2>&1
        $destroyApplyOutput | ForEach-Object { Write-Host $_ }
        $exitCode = $LASTEXITCODE
        Write-Host ""

        if ($exitCode -eq 0) {
            Write-Host "`n============================================================" -ForegroundColor Green
            Write-Host "TERRAFORM DESTROY COMPLETE" -ForegroundColor Green
            Write-Host "============================================================`n" -ForegroundColor Green
            Write-Host "[OK] Infrastructure destroyed successfully." -ForegroundColor Green
        }
        else {
            Write-Host "[ERROR] Terraform destroy failed with exit code: $exitCode" -ForegroundColor Red

            $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $destroyApplyOutput -TerraformExe $terraformExe

            $retryAction = Get-TerraformRemediationAction

            if ($retryAction -eq 'retry-plan') {
                Write-Host "`nDestroy remediation completed. Re-run the destroy flow to continue." -ForegroundColor Yellow
                exit 1
            }

            if ($retryAction -eq 'ignore-error') {
                Write-Host "`nDestroy cancelled per user choice." -ForegroundColor Yellow
                exit 1
            }

            if (-not $guidanceShown) {
                Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
            }
            exit 1
        }
    }
    Runs Terraform initialization, validation, and optionally plan/apply based on user selection.
    Includes pre-flight checks to detect state conflicts, import requirements, and other issues.
#>

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersModulePath = Join-Path $scriptPath "modules/TerraformHelpers.psm1"

if (Test-Path $helpersModulePath) {
    Import-Module $helpersModulePath -Force
} else {
    Write-Host "[ERROR] Required module not found: $helpersModulePath" -ForegroundColor Red
    Write-Host "Please ensure TerraformHelpers.psm1 exists in scripts/modules." -ForegroundColor Yellow
    exit 1
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

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "TERRAFORM NOT FOUND - AUTOMATIC INSTALLATION" -ForegroundColor Yellow
    Write-Host "============================================================`n" -ForegroundColor Yellow

    Write-Host "No full Terraform binary detected. Would you like to download it now?" -ForegroundColor Cyan
    Write-Host "  Version: $Version" -ForegroundColor White
    Write-Host "  Install location: $InstallPath" -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "Download and install Terraform? (yes/no)"

    if ($confirm -ne 'yes' -and $confirm -ne 'y' -and $confirm -ne 'YES' -and $confirm -ne 'Y') {
    Write-Host "`n[CANCELLED] Installation cancelled." -ForegroundColor Red
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
    Write-Host "  [OK] Download complete" -ForegroundColor Green

        Write-Host "`n[2/3] Extracting Terraform..." -ForegroundColor Cyan
        $extractDir = Split-Path -Parent $InstallPath

        # Ensure the directory exists
        if (-not (Test-Path $extractDir)) {
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        }

        # Extract (this will create terraform.exe in the tools directory)
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    Write-Host "  [OK] Extraction complete" -ForegroundColor Green

        Write-Host "`n[3/3] Cleaning up..." -ForegroundColor Cyan
        Remove-Item $zipPath -Force
    Write-Host "  [OK] Cleanup complete" -ForegroundColor Green

        # Verify installation
        if (Test-Path $InstallPath) {
            Write-Host "`n============================================================" -ForegroundColor Green
            Write-Host "TERRAFORM INSTALLATION SUCCESSFUL" -ForegroundColor Green
            Write-Host "============================================================`n" -ForegroundColor Green

            $versionOutput = & $InstallPath -version 2>&1 | Select-Object -First 1
            Write-Host "Installed: $versionOutput" -ForegroundColor White
            Write-Host "Location: $InstallPath" -ForegroundColor White
            Write-Host ""
            Write-Host "ℹ This version supports WriteOnly attributes (sensitive_body) required by AzAPI provider" -ForegroundColor Cyan

            return $true
        }
        else {
            Write-Host "`n[ERROR] Installation verification failed - terraform.exe not found at expected location" -ForegroundColor Red
            return $false
        }
    }
    catch {
    Write-Host "`n[ERROR] Installation failed: $_" -ForegroundColor Red
        Write-Host "`nPlease install Terraform manually from: https://www.terraform.io/downloads" -ForegroundColor Yellow
        return $false
    }
}

function Get-LandingZoneSubscriptionId {
    param([string]$RepoRoot)

    $envCandidates = @(
        $env:TF_VAR_subscription_id,
        $env:ARM_SUBSCRIPTION_ID,
        $env:AZURE_SUBSCRIPTION_ID
    )

    foreach ($candidate in $envCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate.Trim()
        }
    }

    $azCli = Get-Command -Name az -ErrorAction SilentlyContinue
    if ($azCli) {
        $subscriptionRaw = & az account show --query "id" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($subscriptionRaw)) {
            return ($subscriptionRaw -join "").Trim()
        }
    }

    $tfvarsPath = Join-Path $RepoRoot "landingzone.defaults.auto.tfvars"
    if (-not (Test-Path $tfvarsPath)) {
        return $null
    }

    $content = Get-Content $tfvarsPath -Raw
    if ($content -match 'subscription_id\s*=\s*"([^"]+)"') {
        return $matches[1]
    }

    return $null
}

function Get-LandingZoneResourceGroupName {
    param([string]$RepoRoot)

    $tfvarsPath = Join-Path $RepoRoot "landingzone.defaults.auto.tfvars"
    if (-not (Test-Path $tfvarsPath)) {
        return $null
    }

    $content = Get-Content $tfvarsPath -Raw
    if ($content -match 'resource_group_name\s*=\s*"([^"]+)"') {
        return $matches[1]
    }

    return $null
}

function Invoke-ManualDestroyCleanup {
    param([string]$RepoRoot)

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "MANUAL CLEANUP (DESTROY FAILED)" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow

    $subscriptionId = Get-LandingZoneSubscriptionId -RepoRoot $RepoRoot
    $defaultResourceGroup = Get-LandingZoneResourceGroupName -RepoRoot $RepoRoot

    if ($subscriptionId) {
        Write-Host "Using subscription context: $subscriptionId" -ForegroundColor Cyan
    }

    if ($defaultResourceGroup) {
        Write-Host "Detected resource group from defaults: $defaultResourceGroup" -ForegroundColor Cyan
    }
    else {
        Write-Host "Could not auto-detect resource group from defaults." -ForegroundColor Yellow
    }

    $rgPrompt = if ($defaultResourceGroup) {
        "Enter resource group to delete [`$defaultResourceGroup`] (leave blank to skip)"
    }
    else {
        "Enter resource group to delete (leave blank to skip)"
    }

    $resourceGroupInput = Read-Host $rgPrompt
    $resourceGroup = if ([string]::IsNullOrWhiteSpace($resourceGroupInput)) { $defaultResourceGroup } else { $resourceGroupInput.Trim() }

    if ($resourceGroup) {
        $confirmRgDelete = Read-Host "Delete Azure resource group '$resourceGroup'? (yes/no)"
        if ($confirmRgDelete -in @('yes','y','YES','Y')) {
            $azCli = Get-Command -Name az -ErrorAction SilentlyContinue
            if ($azCli) {
                $azArgs = @('group','delete','--name',$resourceGroup,'--yes','--no-wait')
                if ($subscriptionId) {
                    $azArgs += @('--subscription',$subscriptionId)
                }
                Write-Host "Invoking: az $($azArgs -join ' ')" -ForegroundColor Cyan
                $deleteOutput = & az @azArgs 2>&1
                $deleteOutput | ForEach-Object { Write-Host $_ }
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] Azure deletion request submitted (operation runs asynchronously)." -ForegroundColor Green
                }
                else {
                    Write-Host "[ERROR] Azure CLI reported an error while deleting the resource group." -ForegroundColor Red
                }
            }
            else {
                Write-Host "⚠ Azure CLI not found; skipping resource group deletion." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Skipping Azure resource group deletion." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Skipping Azure resource group deletion (no name provided)." -ForegroundColor Yellow
    }

    $stateArtifacts = @(
        "terraform.tfstate",
        "terraform.tfstate.backup",
        "plan.tfplan",
        "plan.json",
        "destroy.tfplan",
        "destroy-plan.json",
        "plan_stage1.tfplan"
    )

    $removedArtifacts = @()

    foreach ($artifact in $stateArtifacts) {
        $artifactPath = Join-Path $RepoRoot $artifact
        if (Test-Path $artifactPath) {
            Remove-Item -Path $artifactPath -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $artifactPath)) {
                $removedArtifacts += $artifact
            }
        }
    }

    $stateDirectories = @('.terraform')
    foreach ($stateDir in $stateDirectories) {
        $dirPath = Join-Path $RepoRoot $stateDir
        if (Test-Path $dirPath) {
            Remove-Item -Path $dirPath -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $dirPath)) {
                $removedArtifacts += $stateDir
            }
        }
    }

    if ($removedArtifacts.Count -gt 0) {
        Write-Host "Removed local Terraform artifacts:" -ForegroundColor Green
        foreach ($item in $removedArtifacts) {
            Write-Host "  - $item" -ForegroundColor White
        }
    }
    else {
        Write-Host "No local Terraform state artifacts were removed." -ForegroundColor Yellow
    }

    Write-Host "Manual cleanup complete. Re-run terraform init before the next deployment." -ForegroundColor Yellow
}

# --- Main Script Body ---

# Move to the Terraform project folder (repo root)
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptPath
Set-Location $repoRoot

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "TERRAFORM DEPLOYMENT WORKFLOW" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

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
            Write-Host "`n[OK] Ready to proceed with Terraform operations!" -ForegroundColor Green
        }
        else {
            Write-Host "`n[ERROR] Cannot proceed without Terraform." -ForegroundColor Red
            exit 1
        }
    }
}

# Check Terraform version compatibility
Write-Host "Checking Terraform version compatibility..." -ForegroundColor Cyan
$versionCheck = Test-TerraformVersionCompatibility -TerraformExe $terraformExe -MinimumVersion "1.11.0"

if ($versionCheck.Compatible -eq $false) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "TERRAFORM VERSION INCOMPATIBILITY DETECTED" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
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
            Write-Host "[OK] Terraform upgraded successfully! Continuing with deployment..." -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "[ERROR] Upgrade failed. Cannot proceed with incompatible version." -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host ""
    Write-Host "[ERROR] Cannot proceed with Terraform v$($versionCheck.Current)" -ForegroundColor Red
        Write-Host ""
        Write-Host "To manually upgrade:" -ForegroundColor Yellow
        Write-Host "  1. Download from: https://releases.hashicorp.com/terraform/1.11.0/" -ForegroundColor White
        Write-Host "  2. Replace: $terraformExe" -ForegroundColor White
        exit 1
    }
}
elseif ($versionCheck.Compatible -eq $true) {
    Write-Host "[OK] Terraform version $($versionCheck.Current) is compatible (>= $($versionCheck.Required))" -ForegroundColor Green
}

# Check for Application Gateway certificate requirements
if (-not (Test-AppGatewayCertificate -RepoRoot $repoRoot)) {
    exit 0
}

# Ask user what they want to do
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "What would you like to do?" -ForegroundColor Cyan
Write-Host "  [1] Plan only (review changes)" -ForegroundColor White
Write-Host "  [2] Plan + Apply (review then deploy)" -ForegroundColor White
Write-Host "  [3] Apply only (use existing plan.tfplan)" -ForegroundColor White
Write-Host "  [4] Destroy (plan + apply destroy)" -ForegroundColor White
Write-Host "  [Q] Quit" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

$choice = Read-Host "`nYour choice (1/2/3/4/Q)"

if ($choice -eq 'Q' -or $choice -eq 'q') {
    Write-Host "`n[INFO] Operation cancelled." -ForegroundColor Yellow
    exit 0
}

# Validate choice
if ($choice -notin @('1', '2', '3', '4')) {
    Write-Host "`n[ERROR] Invalid choice. Exiting." -ForegroundColor Red
    exit 1
}

# Run diagnostics before proceeding
if (-not (Invoke-TerraformDiagnostics -TerraformExe $terraformExe)) {
    exit 0
}

# Common setup steps (always run)
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 1: Terraform Version Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
& $terraformExe -version
$exitCode = $LASTEXITCODE
Write-Host ""

if ($exitCode -ne 0) {
    Write-Host "[ERROR] Failed to get Terraform version (exit code: $exitCode)" -ForegroundColor Red
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STEP 2: Initialize Terraform" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Reset-TerraformRemediationAction
while ($true) {
    $initOutput = & $terraformExe init -upgrade 2>&1
    $initOutput | ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    Write-Host ""

    if ($exitCode -eq 0) {
        break
    }

    Write-Host "[ERROR] Terraform init failed with exit code: $exitCode" -ForegroundColor Red
    Write-Host "`nCommon causes:" -ForegroundColor Yellow
    Write-Host "  - Backend configuration errors" -ForegroundColor White
    Write-Host "  - Invalid provider versions" -ForegroundColor White
    Write-Host "  - Network connectivity issues" -ForegroundColor White
    Write-Host "  - Missing Azure credentials (run: .\scripts\azure-login-devicecode.ps1)" -ForegroundColor White

    $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $initOutput -TerraformExe $terraformExe
    $retryAction = Get-TerraformRemediationAction

    if ($retryAction -eq 'retry-init') {
        Write-Host "`n[RETRY] Running terraform init again after remediation..." -ForegroundColor Cyan
        Reset-TerraformRemediationAction
        continue
    }

    if ($retryAction -eq 'ignore-error') {
        Write-Host "`nInit cancelled per user choice." -ForegroundColor Yellow
        exit 1
    }

    if (-not $guidanceShown) {
        Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
    }

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
    Write-Host "[ERROR] Terraform validation failed with exit code: $exitCode" -ForegroundColor Red
    Write-Host "`nCommon causes:" -ForegroundColor Yellow
    Write-Host "  - Syntax errors in .tf files" -ForegroundColor White
    Write-Host "  - Missing required variables" -ForegroundColor White
    Write-Host "  - Invalid resource configurations" -ForegroundColor White
    Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] Validation successful!" -ForegroundColor Green

# Execute based on user choice
switch ($choice) {
    '1' {
        # Plan only
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "STEP 4: Create Terraform Plan" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        while ($true) {
            Reset-TerraformRemediationAction

            $planOutput = & $terraformExe plan -out "plan.tfplan" 2>&1
            $planOutput | ForEach-Object { Write-Host $_ }
            $exitCode = $LASTEXITCODE
            Write-Host ""

            if ($exitCode -eq 0) {
                $planOutputText = $planOutput -join "`n"
                if ($planOutputText -match "Warning:") {
                    Show-TerraformErrorGuidance -ErrorOutput $planOutput -TerraformExe $terraformExe | Out-Null
                }

                Write-Host "`n========================================" -ForegroundColor Cyan
                Write-Host "STEP 5: Export Plan to JSON" -ForegroundColor Cyan
                Write-Host "========================================" -ForegroundColor Cyan
                & $terraformExe show -json "plan.tfplan" > "plan.json"

                Write-Host "`n============================================================" -ForegroundColor Green
                Write-Host "TERRAFORM PLAN COMPLETE" -ForegroundColor Green
                Write-Host "============================================================`n" -ForegroundColor Green
                Write-Host "Plan saved to:      " -NoNewline -ForegroundColor White
                Write-Host "plan.tfplan" -ForegroundColor Cyan
                Write-Host "JSON plan saved to: " -NoNewline -ForegroundColor White
                Write-Host "plan.json" -ForegroundColor Cyan
                Write-Host "`nTo apply this plan later, run:" -ForegroundColor Yellow
                Write-Host "  $terraformExe apply plan.tfplan" -ForegroundColor White
                break
            }

            Write-Host "[ERROR] Terraform plan failed with exit code: $exitCode" -ForegroundColor Red

            $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $planOutput -TerraformExe $terraformExe
            $retryAction = Get-TerraformRemediationAction

            if ($retryAction -eq 'retry-plan') {
                Write-Host "`n[RETRY] Running terraform plan again after remediation..." -ForegroundColor Cyan
                continue
            }

            if ($retryAction -eq 'ignore-error') {
                Write-Host "`nPlan cancelled per user choice." -ForegroundColor Yellow
                exit 1
            }

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
        while ($true) {
            Reset-TerraformRemediationAction

            $planOutput2 = & $terraformExe plan -out "plan.tfplan" 2>&1
            $planOutput2 | ForEach-Object { Write-Host $_ }
            $exitCode = $LASTEXITCODE
            Write-Host ""

            if ($exitCode -eq 0) {
                break
            }

            Write-Host "[ERROR] Terraform plan failed with exit code: $exitCode" -ForegroundColor Red

            $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $planOutput2 -TerraformExe $terraformExe
            $retryAction = Get-TerraformRemediationAction

            if ($retryAction -eq 'retry-plan') {
                Write-Host "`n[RETRY] Running terraform plan again after remediation..." -ForegroundColor Cyan
                continue
            }

            if ($retryAction -eq 'ignore-error') {
                Write-Host "`nPlan cancelled per user choice." -ForegroundColor Yellow
                exit 1
            }

            if (-not $guidanceShown) {
                Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
            }
            exit 1
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "STEP 5: Export Plan to JSON" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        & $terraformExe show -json "plan.tfplan" > "plan.json"

    Write-Host "`n---------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "REVIEW THE PLAN ABOVE" -ForegroundColor Yellow
    Write-Host "Ready to apply these changes?" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------------" -ForegroundColor Yellow

        $confirm = Read-Host "`nProceed with apply? (yes/no)"

        if ($confirm -eq 'yes' -or $confirm -eq 'y' -or $confirm -eq 'YES' -or $confirm -eq 'Y') {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "STEP 6: Apply Terraform Plan" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
            Reset-TerraformRemediationAction
            $applyOutput = & $terraformExe apply "plan.tfplan" 2>&1
            $applyOutput | ForEach-Object { Write-Host $_ }
            $exitCode = $LASTEXITCODE
            Write-Host ""

            if ($exitCode -eq 0) {
                Write-Host "`n============================================================" -ForegroundColor Green
                Write-Host "TERRAFORM APPLY COMPLETE" -ForegroundColor Green
                Write-Host "============================================================`n" -ForegroundColor Green
                Write-Host "[OK] Infrastructure deployed successfully!" -ForegroundColor Green
            }
            else {
                Write-Host "[ERROR] Terraform apply failed with exit code: $exitCode" -ForegroundColor Red

                # Analyze errors and show guidance
                $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $applyOutput -TerraformExe $terraformExe

                $retryAction = Get-TerraformRemediationAction

                if ($retryAction -eq 'retry-plan') {
                    Write-Host "`nRemediation complete. Re-run option [1] or [2] to generate a fresh plan." -ForegroundColor Yellow
                    exit 1
                }

                if ($retryAction -eq 'ignore-error') {
                    Write-Host "`nApply cancelled per user choice." -ForegroundColor Yellow
                    exit 1
                }

                if (-not $guidanceShown) {
                    Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
                }
                Write-Host "`nTo retry, run option [3] to apply the existing plan," -ForegroundColor Yellow
                Write-Host "or start over with option [1] or [2]." -ForegroundColor Yellow
                exit 1
            }
        }
        else {
            Write-Host "`n[INFO] Apply cancelled. Plan saved for later use." -ForegroundColor Yellow
        }
    }

    '3' {
        # Apply only (existing plan)
        if (-not (Test-Path "plan.tfplan")) {
            Write-Host "`n[ERROR] plan.tfplan not found!" -ForegroundColor Red
            Write-Host "Please run option [1] or [2] first to create a plan." -ForegroundColor Yellow
            exit 1
        }

    Write-Host "`n-----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "APPLY EXISTING PLAN" -ForegroundColor Yellow
    Write-Host "This will apply the existing plan.tfplan file" -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------------" -ForegroundColor Yellow

        $confirm = Read-Host "`nProceed with apply? (yes/no)"

        if ($confirm -eq 'yes' -or $confirm -eq 'y' -or $confirm -eq 'YES' -or $confirm -eq 'Y') {
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "STEP 4: Apply Terraform Plan" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
            Reset-TerraformRemediationAction
            $applyOutput3 = & $terraformExe apply "plan.tfplan" 2>&1
            $applyOutput3 | ForEach-Object { Write-Host $_ }
            $exitCode = $LASTEXITCODE
            Write-Host ""

            if ($exitCode -eq 0) {
                Write-Host "`n============================================================" -ForegroundColor Green
                Write-Host "TERRAFORM APPLY COMPLETE" -ForegroundColor Green
                Write-Host "============================================================`n" -ForegroundColor Green
                Write-Host "[OK] Infrastructure deployed successfully!" -ForegroundColor Green
            }
            else {
                Write-Host "[ERROR] Terraform apply failed with exit code: $exitCode" -ForegroundColor Red

                # Analyze errors and show guidance
                $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $applyOutput3 -TerraformExe $terraformExe

                $retryAction = Get-TerraformRemediationAction

                if ($retryAction -eq 'retry-plan') {
                    Write-Host "`nImport completed. Re-run option [1] or [2] to refresh the plan before applying again." -ForegroundColor Yellow
                    exit 1
                }

                if ($retryAction -eq 'ignore-error') {
                    Write-Host "`nApply cancelled per user choice." -ForegroundColor Yellow
                    exit 1
                }

                if (-not $guidanceShown) {
                    Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
                }
                exit 1
            }
        }
        else {
            Write-Host "`n[INFO] Apply cancelled." -ForegroundColor Yellow
        }
    }

    '4' {
        # Destroy (plan + apply destroy)
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "STEP 4: Create Destroy Plan" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        while ($true) {
            Reset-TerraformRemediationAction

            $destroyPlanOutput = & $terraformExe plan -destroy -out "destroy.tfplan" 2>&1
            $destroyPlanOutput | ForEach-Object { Write-Host $_ }
            $exitCode = $LASTEXITCODE
            Write-Host ""

            if ($exitCode -eq 0) {
                & $terraformExe show -json "destroy.tfplan" > "destroy-plan.json"
                break
            }

            Write-Host "[ERROR] Terraform destroy plan failed with exit code: $exitCode" -ForegroundColor Red

            $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $destroyPlanOutput -TerraformExe $terraformExe
            $retryAction = Get-TerraformRemediationAction

            if ($retryAction -eq 'retry-plan') {
                Write-Host "`n[RETRY] Running terraform plan -destroy again after remediation..." -ForegroundColor Cyan
                continue
            }

            if ($retryAction -eq 'ignore-error') {
                Write-Host "`nDestroy flow cancelled per user choice." -ForegroundColor Yellow
                exit 1
            }

            if (-not $guidanceShown) {
                Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
            }
            exit 1
        }

    Write-Host "`n---------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "DESTROY PLAN COMPLETE" -ForegroundColor Yellow
    Write-Host "Review output above and destroy-plan.json" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------------" -ForegroundColor Yellow

        $confirmDestroy = Read-Host "`nProceed with terraform destroy? (yes/no)"

        if ($confirmDestroy -notin @('yes', 'y', 'YES', 'Y')) {
            Write-Host "`n[INFO] Destroy cancelled. Leaving destroy.tfplan for inspection." -ForegroundColor Yellow
            exit 0
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "STEP 5: Apply Destroy Plan" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        $destroyApplyOutput = & $terraformExe apply "destroy.tfplan" 2>&1
        $destroyApplyOutput | ForEach-Object { Write-Host $_ }
        $exitCode = $LASTEXITCODE
        Write-Host ""

        if ($exitCode -eq 0) {
            Write-Host "`n============================================================" -ForegroundColor Green
            Write-Host "TERRAFORM DESTROY COMPLETE" -ForegroundColor Green
            Write-Host "============================================================`n" -ForegroundColor Green
            Write-Host "[OK] Infrastructure destroyed successfully." -ForegroundColor Green
        }
        else {
            Write-Host "[ERROR] Terraform destroy failed with exit code: $exitCode" -ForegroundColor Red

            $guidanceShown = Show-TerraformErrorGuidance -ErrorOutput $destroyApplyOutput -TerraformExe $terraformExe

            if (-not $guidanceShown) {
                Write-Host "`nCheck the error messages above for details." -ForegroundColor Yellow
            }

            $cleanupChoice = Read-Host "`nRun manual cleanup to delete the resource group and local Terraform state files? (yes/no)"
            if ($cleanupChoice -in @('yes','y','YES','Y')) {
                Invoke-ManualDestroyCleanup -RepoRoot $repoRoot
            }
            exit 1
        }
    }
}

Write-Host "`n[OK] Terraform workflow complete!" -ForegroundColor Green
