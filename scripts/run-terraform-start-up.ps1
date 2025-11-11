#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Terraform startup script with interactive mode selection and pre-flight diagnostics.

.DESCRIPTION
    Runs Terraform initialization, validation, and optionally plan/apply based on user selection.
    Includes pre-flight checks to detect state conflicts, import requirements, and other issues.
#>

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersModulePath = Join-Path $scriptPath "modules/TerraformHelpers.psm1"

if (Test-Path $helpersModulePath) {
    Import-Module $helpersModulePath -Force
} else {
    Write-Host "✗ Required module not found: $helpersModulePath" -ForegroundColor Red
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
if (-not (Test-AppGatewayCertificate -RepoRoot $repoRoot)) {
    exit 0
}

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
