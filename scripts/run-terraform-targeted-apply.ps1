#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Terraform targeted apply helper for handling count dependency issues.

.DESCRIPTION
    Two-stage deployment to handle "Invalid count argument" errors.
    Stage 1: Creates dependency resources (networking, key vault, etc.)
    Stage 2: Applies full configuration with all dependent resources.

.EXAMPLE
    .\run-terraform-targeted-apply.ps1

.NOTES
    Use this when you encounter errors like:
    "The count value depends on resource attributes that cannot be determined until apply"
#>

# Move to repo root
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptPath
Set-Location $repoRoot

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          TERRAFORM TARGETED DEPLOYMENT                    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "This script performs a two-stage deployment to handle count dependencies." -ForegroundColor White
Write-Host ""

# Find Terraform executable
$terraformLocations = @(
    (Join-Path $repoRoot "tools\terraform\terraform.exe"),
    (Join-Path $repoRoot "tools\terraform.exe"),
    (Join-Path $repoRoot "tools\terraform")
)

$terraformExe = $null
foreach ($location in $terraformLocations) {
    if (Test-Path $location) {
        $terraformExe = $location
        break
    }
}

if (-not $terraformExe) {
    $systemTerraform = Get-Command terraform -ErrorAction SilentlyContinue
    if ($systemTerraform) {
        $terraformExe = $systemTerraform.Source
    }
    else {
        Write-Host "✗ Terraform not found!" -ForegroundColor Red
        Write-Host "Please run: .\scripts\run-terraform-start-up.ps1" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Using Terraform: $terraformExe" -ForegroundColor Gray
Write-Host ""

# Stage 1: Targeted resources
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║          STAGE 1: CREATE DEPENDENCY RESOURCES              ║" -ForegroundColor Yellow
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

Write-Host "This stage will create resources that other resources depend on:" -ForegroundColor Cyan
Write-Host "  • Virtual networks and subnets" -ForegroundColor White
Write-Host "  • Key vaults" -ForegroundColor White
Write-Host "  • Core infrastructure" -ForegroundColor White
Write-Host ""

$targets = @(
    "azurerm_resource_group.this",
    "module.ai_lz_vnet",
    "module.avm_res_keyvault_vault",
    "azurerm_user_assigned_identity.appgw_uami"
)

Write-Host "Target resources:" -ForegroundColor Cyan
foreach ($target in $targets) {
    Write-Host "  • $target" -ForegroundColor White
}
Write-Host ""
Write-Host "These targets will create:" -ForegroundColor Gray
Write-Host "  - Resource group" -ForegroundColor White
Write-Host "  - Virtual network and subnets" -ForegroundColor White
Write-Host "  - Key Vault (needed for App Gateway)" -ForegroundColor White
Write-Host "  - App Gateway managed identity" -ForegroundColor White
Write-Host ""

$proceed1 = Read-Host "Proceed with Stage 1? (yes/no)"
if ($proceed1 -ne 'yes' -and $proceed1 -ne 'y' -and $proceed1 -ne 'YES' -and $proceed1 -ne 'Y') {
    Write-Host "✗ Operation cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n[Stage 1] Planning targeted resources..." -ForegroundColor Cyan
$targetArgs = $targets | ForEach-Object { "-target=$_" }
& $terraformExe plan @targetArgs -out="plan_stage1.tfplan"
$exitCode1 = $LASTEXITCODE

if ($exitCode1 -ne 0) {
    Write-Host "`n✗ Stage 1 plan failed with exit code: $exitCode1" -ForegroundColor Red
    exit 1
}

Write-Host "`n[Stage 1] Applying targeted resources..." -ForegroundColor Cyan
& $terraformExe apply plan_stage1.tfplan
$exitCode2 = $LASTEXITCODE

if ($exitCode2 -ne 0) {
    Write-Host "`n✗ Stage 1 apply failed with exit code: $exitCode2" -ForegroundColor Red
    exit 1
}

Write-Host "`n✓ Stage 1 complete!" -ForegroundColor Green
Write-Host ""

# Stage 2: Full deployment
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║          STAGE 2: FULL DEPLOYMENT                          ║" -ForegroundColor Yellow
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

Write-Host "This stage will apply the complete configuration:" -ForegroundColor Cyan
Write-Host "  • All remaining resources" -ForegroundColor White
Write-Host "  • Resources with count dependencies" -ForegroundColor White
Write-Host "  • Final infrastructure state" -ForegroundColor White
Write-Host ""

$proceed2 = Read-Host "Proceed with Stage 2 (full deployment)? (yes/no)"
if ($proceed2 -ne 'yes' -and $proceed2 -ne 'y' -and $proceed2 -ne 'YES' -and $proceed2 -ne 'Y') {
    Write-Host "✗ Stage 2 cancelled. Stage 1 resources have been created." -ForegroundColor Yellow
    Write-Host "You can run Stage 2 later with: $terraformExe plan -out=plan.tfplan && $terraformExe apply plan.tfplan" -ForegroundColor White
    exit 0
}

Write-Host "`n[Stage 2] Planning full configuration..." -ForegroundColor Cyan
& $terraformExe plan -out="plan.tfplan"
$exitCode3 = $LASTEXITCODE

if ($exitCode3 -ne 0) {
    Write-Host "`n✗ Stage 2 plan failed with exit code: $exitCode3" -ForegroundColor Red
    Write-Host "`nThe dependency resources were created successfully, but the full plan failed." -ForegroundColor Yellow
    Write-Host "Review the errors above and fix any issues before running Stage 2 again." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n[Stage 2] Applying full configuration..." -ForegroundColor Cyan
& $terraformExe apply plan.tfplan
$exitCode4 = $LASTEXITCODE

if ($exitCode4 -ne 0) {
    Write-Host "`n✗ Stage 2 apply failed with exit code: $exitCode4" -ForegroundColor Red
    exit 1
}

# Export final plan
Write-Host "`n[Final] Exporting plan artifacts..." -ForegroundColor Cyan
& $terraformExe show -json plan.tfplan > plan.json

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║          TARGETED DEPLOYMENT COMPLETE                     ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

Write-Host "✓ Stage 1: Dependency resources created" -ForegroundColor Green
Write-Host "✓ Stage 2: Full configuration deployed" -ForegroundColor Green
Write-Host ""
Write-Host "Artifacts saved:" -ForegroundColor Cyan
Write-Host "  • plan_stage1.tfplan (Stage 1 plan)" -ForegroundColor White
Write-Host "  • plan.tfplan (Stage 2 plan)" -ForegroundColor White
Write-Host "  • plan.json (Final plan JSON)" -ForegroundColor White
Write-Host ""
