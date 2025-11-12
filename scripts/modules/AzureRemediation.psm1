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

    $principalId = $null
    $principalIdRaw = & az ad signed-in-user show --query "id" -o tsv 2>&1
    if ($LASTEXITCODE -eq 0 -and $principalIdRaw) {
        $principalId = ($principalIdRaw -join "" ).Trim()
    }

    if (-not $principalId -and $env:AZURE_CLIENT_ID) {
        $principalIdRaw = & az ad sp show --id $env:AZURE_CLIENT_ID --query "id" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $principalIdRaw) {
            $principalId = ($principalIdRaw -join "" ).Trim()
        }
    }

    if (-not $principalId) {
        Write-Host "⚠ Unable to auto-detect principal object ID." -ForegroundColor Yellow
        $principalId = Read-Host "Enter the object ID that should receive Storage Blob Data Contributor"
    }

    if (-not $principalId) {
        Write-Host "✗ Principal object ID is required to continue." -ForegroundColor Red
        return $false
    }

    $storageAccountId = $null
    $storageAccountRaw = & az storage account show -n $StorageAccountName -g $ResourceGroupName --query "id" -o tsv 2>&1
    if ($LASTEXITCODE -eq 0 -and $storageAccountRaw) {
        $storageAccountId = ($storageAccountRaw -join "" ).Trim()
    }

    if (-not $storageAccountId) {
        Write-Host "✗ Failed to resolve storage account $StorageAccountName in $ResourceGroupName." -ForegroundColor Red
        return $false
    }

    $requiredRoles = @("Storage Blob Data Contributor", "Storage Queue Data Contributor")
    foreach ($roleName in $requiredRoles) {
        Write-Host "Assigning '$roleName' to $principalId..." -ForegroundColor Cyan
        $existingAssignment = $null
        $existingAssignmentRaw = & az role assignment list --assignee-object-id $principalId --scope $storageAccountId --query "[?roleDefinitionName=='$roleName'].id" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $existingAssignmentRaw) {
            $existingAssignment = ($existingAssignmentRaw -join "" ).Trim()
        }
        elseif ($LASTEXITCODE -ne 0) {
            Write-Host "⚠ Unable to verify existing assignments for $roleName; continuing with role creation." -ForegroundColor Yellow
        }

        if (-not $existingAssignment) {
            $roleCreateOutput = & az role assignment create --role $roleName --assignee-object-id $principalId --scope $storageAccountId 2>&1
            if ($LASTEXITCODE -ne 0 -and $roleCreateOutput -notmatch "RoleAssignmentExists") {
                Write-Host "✗ Failed to create role assignment for ${roleName}:" -ForegroundColor Red
                Write-Host $roleCreateOutput -ForegroundColor Red
                return $false
            }
        }
        else {
            Write-Host "  Role assignment '$roleName' already exists." -ForegroundColor Yellow
        }
    }

    $env:ARM_USE_AZUREAD = 'true'
    $env:TF_AZURERM_DISABLE_STORAGE_KEY_USAGE = 'true'
    Write-Host "Set ARM_USE_AZUREAD= true for current session." -ForegroundColor Green
    Write-Host "Set TF_AZURERM_DISABLE_STORAGE_KEY_USAGE= true to prefer data-plane OAuth." -ForegroundColor Green
    Write-Host "✓ Microsoft Entra ID authentication configured. Re-run Terraform plan/apply." -ForegroundColor Green
    return $true
}

Export-ModuleMember -Function Invoke-StorageAccountAadRemediation
