Set-StrictMode -Version Latest

function Invoke-StorageAccountAadRemediation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        [string]$RepoRoot = $null
    )

    Write-Host "`nAutomating Microsoft Entra ID remediation for storage account..." -ForegroundColor Cyan

    $azCommand = Get-Command -Name az -ErrorAction SilentlyContinue
    if (-not $azCommand) {
        Write-Host "✗ Azure CLI (az) not found in PATH. Install Azure CLI and retry." -ForegroundColor Red
        return $false
    }

    if (-not $RepoRoot) {
        $moduleDir = Split-Path -Parent $PSCommandPath
        $scriptsDir = Split-Path -Parent $moduleDir
        $RepoRoot = Split-Path -Parent $scriptsDir
    }

    $accountCheck = & az account show --query "id" -o tsv 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠ Azure CLI session not authenticated." -ForegroundColor Yellow
        Write-Host "  Run the login helper: .\\scripts\\azure-login-devicecode.ps1" -ForegroundColor White
        return $false
    }

    & az account set --subscription $SubscriptionId | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to switch Azure CLI context to subscription $SubscriptionId." -ForegroundColor Red
        return $false
    }

    $principalId = (& az ad signed-in-user show --query "id" -o tsv 2>&1).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $principalId) {
        if ($env:AZURE_CLIENT_ID) {
            $principalId = (& az ad sp show --id $env:AZURE_CLIENT_ID --query "id" -o tsv 2>&1).Trim()
        }
    }

    if ($LASTEXITCODE -ne 0 -or -not $principalId) {
        Write-Host "⚠ Unable to auto-detect principal object ID." -ForegroundColor Yellow
        $principalId = Read-Host "Enter the object ID that should receive Storage Blob Data Contributor"
    }

    if (-not $principalId) {
        Write-Host "✗ Principal object ID is required to continue." -ForegroundColor Red
        return $false
    }

    $storageAccountId = (& az storage account show -n $StorageAccountName -g $ResourceGroupName --query "id" -o tsv 2>&1).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $storageAccountId) {
        Write-Host "✗ Failed to resolve storage account $StorageAccountName in $ResourceGroupName." -ForegroundColor Red
        return $false
    }

    Write-Host "Assigning 'Storage Blob Data Contributor' to $principalId..." -ForegroundColor Cyan
    $existingAssignment = (& az role assignment list --assignee-object-id $principalId --scope $storageAccountId --query "[].id" -o tsv 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠ Unable to verify existing assignments; continuing with role creation." -ForegroundColor Yellow
    }

    if (-not $existingAssignment) {
        $roleCreateOutput = & az role assignment create --role "Storage Blob Data Contributor" --assignee-object-id $principalId --scope $storageAccountId 2>&1
        if ($LASTEXITCODE -ne 0 -and $roleCreateOutput -notmatch "RoleAssignmentExists") {
            Write-Host "✗ Failed to create role assignment:" -ForegroundColor Red
            Write-Host $roleCreateOutput -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "  Role assignment already exists." -ForegroundColor Yellow
    }

    $env:ARM_USE_AZUREAD = 'true'
    Write-Host "Set ARM_USE_AZUREAD= true for current session." -ForegroundColor Green
    Write-Host "✓ Microsoft Entra ID authentication configured. Re-run Terraform plan/apply." -ForegroundColor Green
    return $true
}

Export-ModuleMember -Function Invoke-StorageAccountAadRemediation
