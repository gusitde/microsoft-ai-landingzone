Set-StrictMode -Version Latest

function Test-AzCliAvailable {
    $azCommand = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCommand) {
        Write-Host "✗ Azure CLI (az) not found in PATH." -ForegroundColor Red
        Write-Host "Install from https://learn.microsoft.com/cli/azure/install-azure-cli or launch from an Azure-enabled shell." -ForegroundColor Yellow
        return $null
    }

    return $azCommand.Source
}

function Enable-StorageAccountSharedKeyAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SubscriptionId,
        [Parameter(Mandatory = $true)][string]$ResourceGroupName,
        [Parameter(Mandatory = $true)][string]$StorageAccountName
    )

    $azPath = Test-AzCliAvailable
    if (-not $azPath) {
        return $false
    }

    Write-Host ""
    Write-Host "Enabling shared key authentication for storage account '$StorageAccountName'..." -ForegroundColor Cyan

    $contextCheck = & $azPath "account" "show" "--subscription" $SubscriptionId "--query" "id" "--output" "tsv" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Unable to read Azure account context. Run './scripts/azure-login-devicecode.ps1' and ensure the subscription exists." -ForegroundColor Red
        Write-Host ($contextCheck | Select-Object -Last 1) -ForegroundColor Yellow
        return $false
    }

    $allowSharedKey = (& $azPath "storage" "account" "show" "--subscription" $SubscriptionId "--name" $StorageAccountName "--resource-group" $ResourceGroupName "--query" "allowSharedKeyAccess" "--output" "tsv" 2>$null).Trim()

    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Unable to query the storage account. Verify that the name and resource group are correct." -ForegroundColor Red
        return $false
    }

    if ($allowSharedKey -eq "true") {
        Write-Host "✓ Shared key authentication is already enabled." -ForegroundColor Green
        return $true
    }

    & $azPath "storage" "account" "update" "--subscription" $SubscriptionId "--name" $StorageAccountName "--resource-group" $ResourceGroupName "--allow-shared-key-access" "true" "--only-show-errors" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to enable shared key authentication. See Azure CLI output above for details." -ForegroundColor Red
        return $false
    }

    $verificationSucceeded = $false
    for ($i = 0; $i -lt 10; $i++) {
        $checkValue = (& $azPath "storage" "account" "show" "--subscription" $SubscriptionId "--name" $StorageAccountName "--resource-group" $ResourceGroupName "--query" "allowSharedKeyAccess" "--output" "tsv" 2>$null).Trim()
        if ($LASTEXITCODE -eq 0 -and $checkValue -eq "true") {
            $verificationSucceeded = $true
            break
        }
        Start-Sleep -Seconds 5
    }

    if (-not $verificationSucceeded) {
        Write-Host "✗ Shared key authentication did not report as enabled after multiple checks. Try again manually with Azure CLI." -ForegroundColor Red
        return $false
    }

    Write-Host "✓ Shared key authentication enabled successfully." -ForegroundColor Green
    Write-Host "Remember to disable it after Terraform finishes applying." -ForegroundColor Yellow
    Write-Host "  Disable-StorageAccountSharedKeyAccess -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName" -ForegroundColor White

    return $true
}

function Disable-StorageAccountSharedKeyAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SubscriptionId,
        [Parameter(Mandatory = $true)][string]$ResourceGroupName,
        [Parameter(Mandatory = $true)][string]$StorageAccountName
    )

    $azPath = Test-AzCliAvailable
    if (-not $azPath) {
        return $false
    }

    Write-Host ""
    Write-Host "Disabling shared key authentication for storage account '$StorageAccountName'..." -ForegroundColor Cyan

    & $azPath "storage" "account" "update" "--subscription" $SubscriptionId "--name" $StorageAccountName "--resource-group" $ResourceGroupName "--allow-shared-key-access" "false" "--only-show-errors" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to disable shared key authentication. Check Azure CLI output for details." -ForegroundColor Red
        return $false
    }

    Write-Host "✓ Shared key authentication disabled." -ForegroundColor Green
    return $true
}

function Get-LandingZoneRegionAbbreviation {
    param([Parameter(Mandatory = $true)][string]$Location)

    $map = @{
        "westeurope"    = "weu"
        "northeurope"   = "neu"
        "eastus"        = "eus"
        "eastus2"       = "eus2"
        "westus3"       = "wus3"
        "brazilsouth"   = "brs"
        "uksouth"       = "uks"
        "francecentral" = "frc"
        "swedencentral" = "sec"
    }

    $normalized = ($Location -replace "\s", "").ToLowerInvariant()
    return $map[$normalized] ? $map[$normalized] : $normalized
}

function New-LandingZoneStorageAccountName {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$Location,
        [Parameter()][string]$Descriptor,
        [Parameter()][string]$OrgPrefix = "azr",
        [Parameter()][int]$Index = 1
    )

    $components = @(
        $OrgPrefix.ToLowerInvariant(),
        $Project.ToLowerInvariant(),
        $Environment.ToLowerInvariant(),
        (Get-LandingZoneRegionAbbreviation -Location $Location),
        "st"
    )

    if ($Descriptor) {
        $components += $Descriptor.ToLowerInvariant()
    }

    $name = ($components + ('{0:D2}' -f $Index)) -join ""
    $name = ($name -replace "[^0-9a-z]", "").ToLowerInvariant()

    if ($name.Length -gt 24) {
        $name = $name.Substring(0, 24)
    }

    return $name
}

function Invoke-StorageAccountRecreate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SubscriptionId,
        [Parameter(Mandatory = $true)][string]$ResourceGroupName,
        [string]$StorageAccountName,
        [string]$Location,
        [string]$Project,
        [string]$Environment,
        [string]$Descriptor,
        [string]$OrgPrefix = "azr",
        [int]$Index = 1,
        [string]$Sku = "Standard_LRS",
        [string]$Kind = "StorageV2",
        [switch]$DisableSharedKey
    )

    $azPath = Test-AzCliAvailable
    if (-not $azPath) {
        return $false
    }

    if (-not $StorageAccountName) {
        if (-not $Project) {
            $Project = Read-Host "Project code (e.g. aaaa)"
        }
        if (-not $Environment) {
            $Environment = Read-Host "Environment (e.g. tst)"
        }
        if (-not $Location) {
            $Location = Read-Host "Azure region (e.g. swedencentral)"
        }
        if (-not $Descriptor) {
            $Descriptor = Read-Host "Descriptor (e.g. genai)"
        }

        $StorageAccountName = New-LandingZoneStorageAccountName -Project $Project -Environment $Environment -Location $Location -Descriptor $Descriptor -OrgPrefix $OrgPrefix -Index $Index
        Write-Host "Using generated storage account name: $StorageAccountName" -ForegroundColor Cyan
    }

    $existingAccount = $null
    $existingAllowSharedKey = $null
    if ($StorageAccountName) {
        $existingJson = & $azPath "storage" "account" "show" "--subscription" $SubscriptionId "--name" $StorageAccountName "--resource-group" $ResourceGroupName "--query" "{name:name,location:location,kind:kind,sku:sku.name,allowSharedKeyAccess:allowSharedKeyAccess}" "--output" "json" 2>$null
        if ($LASTEXITCODE -eq 0 -and $existingJson) {
            $existingAccount = $existingJson | ConvertFrom-Json
            if ($existingAccount.location) {
                $Location = $existingAccount.location
            }
            if ($existingAccount.kind) {
                $Kind = $existingAccount.kind
            }
            if ($existingAccount.sku) {
                $Sku = $existingAccount.sku
            }
            if ($null -ne $existingAccount.allowSharedKeyAccess) {
                $existingAllowSharedKey = [bool]$existingAccount.allowSharedKeyAccess
            }
        }
    }

    if (-not $Location) {
        $Location = Read-Host "Azure region (e.g. swedencentral)"
    }

    Write-Host ""
    Write-Host "This helper will delete and recreate storage account '$StorageAccountName' in resource group '$ResourceGroupName'." -ForegroundColor Yellow
    Write-Host "Subscription : $SubscriptionId" -ForegroundColor White
    Write-Host "Resource group: $ResourceGroupName" -ForegroundColor White
    Write-Host "Location     : $Location" -ForegroundColor White
    Write-Host "Sku          : $Sku" -ForegroundColor White
    Write-Host "Kind         : $Kind" -ForegroundColor White
    Write-Host ""
    Write-Host "⚠ This operation is destructive. Existing data in the storage account will be lost." -ForegroundColor Red
    $confirm = Read-Host "Type DELETE to continue"
    if ($confirm -cne "DELETE") {
        Write-Host "✓ Operation cancelled." -ForegroundColor Yellow
        return $false
    }

    Write-Host "Deleting storage account '$StorageAccountName'..." -ForegroundColor Cyan
    & $azPath "storage" "account" "delete" "--subscription" $SubscriptionId "--name" $StorageAccountName "--resource-group" $ResourceGroupName "--yes" "--only-show-errors" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to delete storage account. Check Azure CLI output for details." -ForegroundColor Red
        return $false
    }

    for ($attempt = 0; $attempt -lt 24; $attempt++) {
        & $azPath "storage" "account" "show" "--subscription" $SubscriptionId "--name" $StorageAccountName "--resource-group" $ResourceGroupName 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) {
            break
        }
        Start-Sleep -Seconds 5
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✗ Storage account still exists after delete. Wait a few moments and retry." -ForegroundColor Red
        return $false
    }

    Write-Host "Creating storage account '$StorageAccountName'..." -ForegroundColor Cyan
    & $azPath "storage" "account" "create" "--subscription" $SubscriptionId "--name" $StorageAccountName "--resource-group" $ResourceGroupName "--location" $Location "--kind" $Kind "--sku" $Sku "--https-only" "true" "--allow-blob-public-access" "false" "--min-tls-version" "TLS1_2" "--only-show-errors" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to create storage account. Review Azure CLI output for details." -ForegroundColor Red
        return $false
    }

    $disableSharedKeyPreference = $DisableSharedKey.IsPresent
    if (-not $DisableSharedKey.IsPresent -and $existingAllowSharedKey -eq $false) {
        $disableSharedKeyPreference = $true
    }

    if ($disableSharedKeyPreference) {
        Write-Host "Disabling shared key authentication on the recreated account..." -ForegroundColor Cyan
        & $azPath "storage" "account" "update" "--subscription" $SubscriptionId "--name" $StorageAccountName "--resource-group" $ResourceGroupName "--allow-shared-key-access" "false" "--only-show-errors" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠ Unable to disable shared key authentication automatically. Please review manually." -ForegroundColor Yellow
        }
    }

    Write-Host "✓ Storage account recreated successfully." -ForegroundColor Green
    return $true
}

Export-ModuleMember -Function Enable-StorageAccountSharedKeyAccess, Disable-StorageAccountSharedKeyAccess, Invoke-StorageAccountRecreate
