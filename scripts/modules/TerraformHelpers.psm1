Set-StrictMode -Version Latest

$moduleBase = Split-Path -Parent $PSCommandPath
$remediationModulePath = Join-Path $moduleBase "AzureRemediation.psm1"
if (Test-Path $remediationModulePath) {
    Import-Module $remediationModulePath -Force
}

$storageKeyModulePath = Join-Path $moduleBase "StorageKeyRemediation.psm1"
if (Test-Path $storageKeyModulePath) {
    Import-Module $storageKeyModulePath -Force
}

$script:TerraformRemediationAction = $null

function Reset-TerraformRemediationAction {
    $script:TerraformRemediationAction = $null
}

function Get-TerraformRemediationAction {
    return $script:TerraformRemediationAction
}

function Set-TerraformRemediationAction {
    param([string]$Action)
    $script:TerraformRemediationAction = $Action
}

function Invoke-TerraformDiagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TerraformExe
    )

    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "PRE-FLIGHT DIAGNOSTICS" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host ""

    $issues = @()
    $warnings = @()

    Write-Host "[1/6] Checking Terraform state..." -ForegroundColor Cyan
    if (Test-Path "terraform.tfstate") {
        try {
            $stateContent = Get-Content "terraform.tfstate" -Raw | ConvertFrom-Json
            $stateVersion = $stateContent.version
            $resourceCount = if ($stateContent.resources) { $stateContent.resources.Count } else { 0 }

            Write-Host "  ✓ State file exists (version: $stateVersion, resources: $resourceCount)" -ForegroundColor Green

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

    Write-Host "[4/6] Checking for potential drift..." -ForegroundColor Cyan
    if (Test-Path "terraform.tfstate") {
        & $TerraformExe plan -refresh-only -detailed-exitcode 2>&1 | Out-Null
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

    Write-Host "[6/6] Checking provider compatibility..." -ForegroundColor Cyan
    if (Test-Path ".terraform.lock.hcl") {
        Write-Host "  ✓ Provider lock file exists" -ForegroundColor Green
        $lockContent = Get-Content ".terraform.lock.hcl" -Raw
        if ($lockContent -match 'version\s*=\s*"([^"]+)"') {
            Write-Host "  ✓ Provider versions locked" -ForegroundColor Green
        }
    }
    else {
        $warnings += "No provider lock file - versions may change unexpectedly"
        Write-Host "  ⚠ No provider lock file found" -ForegroundColor Yellow
    }

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

    if ($issues.Count -gt 0) {
        Write-Host "`n💡 RECOMMENDED ACTIONS:" -ForegroundColor Cyan

        if ($issues -match "locked") {
            Write-Host "  - Force unlock: $TerraformExe force-unlock <LOCK_ID>" -ForegroundColor White
        }
        if ($issues -match "corrupted|invalid") {
            Write-Host "  - Restore from backup: copy terraform.tfstate.backup terraform.tfstate" -ForegroundColor White
            Write-Host "  - Or pull from remote: $TerraformExe state pull > terraform.tfstate" -ForegroundColor White
        }
        if ($issues -match "import") {
            Write-Host "  - Import existing resource: $TerraformExe import <resource_type>.<name> <azure_resource_id>" -ForegroundColor White
            Write-Host "  - List resources to import: az resource list --resource-group <rg-name>" -ForegroundColor White
        }
        if ($issues -match "drift") {
            Write-Host "  - Review drift: $TerraformExe plan -refresh-only" -ForegroundColor White
            Write-Host "  - Apply refresh: $TerraformExe apply -refresh-only -auto-approve" -ForegroundColor White
        }

        Write-Host ""
        $proceed = Read-Host "Continue despite issues? (yes/no)"
        if ($proceed -notin @('yes', 'y', 'YES', 'Y')) {
            Write-Host "`n✓ Operation cancelled for safety." -ForegroundColor Yellow
            return $false
        }
    }

    return $true
}

function Get-BackendConfigurationFromFile {
    param([string]$BackendFilePath = "backend.tf")

    if (-not (Test-Path $BackendFilePath)) {
        return $null
    }

    $content = Get-Content -Path $BackendFilePath -Raw
    $fields = @('resource_group_name', 'storage_account_name', 'container_name', 'subscription_id', 'key')
    $config = [ordered]@{}

    foreach ($field in $fields) {
        $escapedField = [regex]::Escape($field)
        $pattern = "$escapedField\s*=\s*""([^""]+)"""
        $match = [regex]::Match($content, $pattern)
        if ($match.Success) {
            $config[$field] = $match.Groups[1].Value
        }
    }

    if ($config.Keys.Count -eq 0) {
        return $null
    }

    return $config
}

function Get-BackendConfigurationFromState {
    param([string]$StateMetadataPath = ".terraform/terraform.tfstate")

    if (-not (Test-Path $StateMetadataPath)) {
        return $null
    }

    try {
        $metadata = Get-Content -Path $StateMetadataPath -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }

    if (-not $metadata.backend -or -not $metadata.backend.config) {
        return $null
    }

    $fields = @('resource_group_name', 'storage_account_name', 'container_name', 'subscription_id', 'key')
    $config = [ordered]@{}

    foreach ($field in $fields) {
        $value = $metadata.backend.config.$field
        if ($value) {
            $config[$field] = $value
        }
    }

    if ($config.Keys.Count -eq 0) {
        return $null
    }

    return $config
}

function Invoke-TerraformBackendRemediation {
    param(
        [Parameter(Mandatory = $true)][string]$TerraformExe,
        [string]$BackendFilePath = "backend.tf"
    )

    $currentConfig = Get-BackendConfigurationFromFile -BackendFilePath $BackendFilePath
    $previousConfig = Get-BackendConfigurationFromState

    Write-Host ""
    Write-Host "Detected backend mismatch. Review the configurations below:" -ForegroundColor Yellow

    if ($previousConfig) {
        Write-Host "\nPrevious backend (from .terraform/terraform.tfstate):" -ForegroundColor Cyan
        foreach ($key in $previousConfig.Keys) {
            Write-Host ("  {0}: {1}" -f $key, $previousConfig[$key]) -ForegroundColor White
        }
    }
    else {
        Write-Host "\nPrevious backend metadata could not be read." -ForegroundColor Yellow
    }

    if ($currentConfig) {
        Write-Host "\nCurrent backend (from $BackendFilePath):" -ForegroundColor Cyan
        foreach ($key in $currentConfig.Keys) {
            Write-Host ("  {0}: {1}" -f $key, $currentConfig[$key]) -ForegroundColor White
        }
    }
    else {
        Write-Host "\nUnable to parse $BackendFilePath. Verify the file format." -ForegroundColor Red
    }

    while ($true) {
        Write-Host ""
        Write-Host "Choose a remediation path:" -ForegroundColor Cyan
        Write-Host "  [1] Migrate state to the new backend (terraform init -migrate-state)" -ForegroundColor White
        Write-Host "  [2] Reconfigure the working directory (terraform init -reconfigure)" -ForegroundColor White
        Write-Host "  [3] Skip automation and handle manually" -ForegroundColor White

        $choice = Read-Host "Your choice (1/2/3)"

        switch ($choice) {
            '1' {
                Write-Host "\nRunning terraform init -migrate-state..." -ForegroundColor Cyan
                $output = & $TerraformExe init -migrate-state 2>&1
                $output | ForEach-Object { Write-Host $_ }
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "\n✓ State migration succeeded." -ForegroundColor Green
                    Set-TerraformRemediationAction -Action "retry-init"
                    return $true
                }

                Write-Host "\n✗ terraform init -migrate-state failed (exit code: $LASTEXITCODE)." -ForegroundColor Red
                Write-Host "Review the output above and choose another option." -ForegroundColor Yellow
            }
            '2' {
                Write-Host "\nRunning terraform init -reconfigure..." -ForegroundColor Cyan
                $output = & $TerraformExe init -reconfigure 2>&1
                $output | ForEach-Object { Write-Host $_ }
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "\n✓ Reconfiguration succeeded." -ForegroundColor Green
                    Set-TerraformRemediationAction -Action "retry-init"
                    return $true
                }

                Write-Host "\n✗ terraform init -reconfigure failed (exit code: $LASTEXITCODE)." -ForegroundColor Red
                Write-Host "Review the output above and choose another option." -ForegroundColor Yellow
            }
            '3' {
                Write-Host "\nSkipping automated remediation. Resolve manually and rerun the command." -ForegroundColor Yellow
                Set-TerraformRemediationAction -Action "ignore-error"
                return $true
            }
            default {
                Write-Host "\nPlease enter 1, 2, or 3." -ForegroundColor Yellow
            }
        }
    }
}

function Show-TerraformErrorGuidance {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ErrorOutput,
        [Parameter(Mandatory = $true)]
        [string]$TerraformExe
    )

    $errorText = $ErrorOutput -join "`n"
    $guidanceShown = $false

    if ($errorText -match "Backend configuration changed") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║          BACKEND CONFIGURATION CHANGE DETECTED             ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        $null = Invoke-TerraformBackendRemediation -TerraformExe $TerraformExe
        $guidanceShown = $true
    }

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

    if ($errorText -match "Invalid count argument|count value depends on resource attributes that cannot be determined until apply") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║          INVALID COUNT DEPENDENCY DETECTED                 ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "⚠ A 'count' meta-argument depends on a resource that hasn't been created yet" -ForegroundColor Yellow
        Write-Host ""

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
    Write-Host "  [4] Delete and recreate the storage account (Azure CLI helper)" -ForegroundColor White
    Write-Host "  [5] Ignore and handle manually" -ForegroundColor White
    Write-Host ""
    $remediationChoice = Read-Host "Your choice (1/2/3/4/5)"

        $subscriptionId = $null
        if ($errorText -match 'Subscription:\s*"([^"]+)"') {
            $subscriptionId = $matches[1]
        }

        $resourceGroup = $null
        if ($errorText -match 'Resource Group Name:\s*"([^"]+)"') {
            $resourceGroup = $matches[1]
        }

        $storageAccount = $null
        if ($errorText -match 'Storage Account Name:\s*"([^"]+)"') {
            $storageAccount = $matches[1]
        }

        switch ($remediationChoice) {
            '1' {
                Write-Host "`nSolution 1: Temporarily enable key-based authentication" -ForegroundColor Green
                Write-Host ""
                if (-not $subscriptionId) {
                    $subscriptionId = Read-Host "Enter the subscription ID"
                }
                if (-not $resourceGroup) {
                    $resourceGroup = Read-Host "Enter the resource group name"
                }
                if (-not $storageAccount) {
                    $storageAccount = Read-Host "Enter the storage account name"
                }

                $keyHelper = Get-Command -Name Enable-StorageAccountSharedKeyAccess -ErrorAction SilentlyContinue
                if (-not $keyHelper) {
                    Write-Host "✗ Automation module not found. Please update the repository tooling." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Run these commands manually:" -ForegroundColor Yellow
                    Write-Host "1. Enable key auth:" -ForegroundColor Cyan
                    Write-Host "   az storage account update -n $storageAccount -g $resourceGroup --subscription $subscriptionId --allow-shared-key-access true" -ForegroundColor White
                    Write-Host ""
                    Write-Host "2. Re-run apply:" -ForegroundColor Cyan
                    Write-Host "   $TerraformExe apply plan.tfplan" -ForegroundColor White
                    Write-Host ""
                    Write-Host "3. (Optional) Disable key auth after apply:" -ForegroundColor Cyan
                    Write-Host "   az storage account update -n $storageAccount -g $resourceGroup --subscription $subscriptionId --allow-shared-key-access false" -ForegroundColor White
                }
                else {
                    $enableResult = Enable-StorageAccountSharedKeyAccess -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroup -StorageAccountName $storageAccount
                    if ($enableResult) {
                        Set-TerraformRemediationAction -Action "retry-plan"
                        Write-Host "`nRe-run the Terraform step you were performing (plan/apply)." -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "`nAutomation did not complete successfully. Use the manual commands below as a fallback." -ForegroundColor Red
                        Write-Host ""
                        Write-Host "1. Enable key auth:" -ForegroundColor Cyan
                        Write-Host "   az storage account update -n $storageAccount -g $resourceGroup --subscription $subscriptionId --allow-shared-key-access true" -ForegroundColor White
                        Write-Host ""
                        Write-Host "2. Re-run apply:" -ForegroundColor Cyan
                        Write-Host "   $TerraformExe apply plan.tfplan" -ForegroundColor White
                        Write-Host ""
                        Write-Host "3. (Optional) Disable key auth after apply:" -ForegroundColor Cyan
                        Write-Host "   az storage account update -n $storageAccount -g $resourceGroup --subscription $subscriptionId --allow-shared-key-access false" -ForegroundColor White
                    }
                }
            }
            '2' {
                Write-Host "`nSolution 2: Use Microsoft Entra ID (Managed Identity) for authentication" -ForegroundColor Green

                if (-not $subscriptionId) {
                    $subscriptionId = Read-Host "Enter the subscription ID"
                }
                if (-not $resourceGroup) {
                    $resourceGroup = Read-Host "Enter the resource group name"
                }
                if (-not $storageAccount) {
                    $storageAccount = Read-Host "Enter the storage account name"
                }

                $remediationCommand = Get-Command -Name Invoke-StorageAccountAadRemediation -ErrorAction SilentlyContinue
                if (-not $remediationCommand) {
                    Write-Host "✗ Automation module not found. Please update the repository tooling." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Run these commands manually:" -ForegroundColor Yellow
                    Write-Host "1. az ad signed-in-user show --query 'id' -o tsv" -ForegroundColor White
                    Write-Host "2. az storage account show -n $storageAccount -g $resourceGroup --query 'id' -o tsv" -ForegroundColor White
                    Write-Host "3. az role assignment create --role 'Storage Blob Data Contributor' --assignee <principal-id> --scope <storage-account-id>" -ForegroundColor White
                    Write-Host "4. `$env:ARM_USE_AZUREAD = 'true'" -ForegroundColor White
                    return $true
                }

                $remediationResult = Invoke-StorageAccountAadRemediation -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroup -StorageAccountName $storageAccount
                if ($remediationResult) {
                    Set-TerraformRemediationAction -Action "retry-plan"
                    Write-Host "`nRe-run the Terraform step you were performing (plan/apply)." -ForegroundColor Yellow
                }
                else {
                    Write-Host "`n✗ Automated remediation did not complete successfully. Review the messages above and retry." -ForegroundColor Red
                }
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
            '4' {
                Write-Host "`nSolution 4: Delete and recreate the storage account via helper" -ForegroundColor Green

                if (-not $subscriptionId) {
                    $subscriptionId = Read-Host "Enter the subscription ID"
                }
                if (-not $resourceGroup) {
                    $resourceGroup = Read-Host "Enter the resource group name"
                }
                if (-not $storageAccount) {
                    $storageAccount = Read-Host "Enter the storage account name"
                }

                $recreateCommand = Get-Command -Name Invoke-StorageAccountRecreate -ErrorAction SilentlyContinue
                if (-not $recreateCommand) {
                    Write-Host "✗ Automation module not found. Please update the repository tooling." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Manual steps:" -ForegroundColor Yellow
                    Write-Host "  1. az storage account delete -n $storageAccount -g $resourceGroup --subscription $subscriptionId --yes" -ForegroundColor White
                    Write-Host "  2. az storage account create -n <new-name> -g $resourceGroup --subscription $subscriptionId --location <region> --sku Standard_LRS --kind StorageV2 --https-only true" -ForegroundColor White
                    Write-Host "  3. az storage account update -n <new-name> -g $resourceGroup --subscription $subscriptionId --allow-shared-key-access false" -ForegroundColor White
                }
                else {
                    $recreateResult = Invoke-StorageAccountRecreate -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroup -StorageAccountName $storageAccount
                    if ($recreateResult) {
                        Set-TerraformRemediationAction -Action "retry-plan"
                        Write-Host "`nStorage account recreated. Re-run the Terraform step you were performing (plan/apply)." -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "`n✗ Storage account recreation was cancelled or failed. Review the output above before retrying." -ForegroundColor Red
                    }
                }
            }
            '5' {
                Write-Host "`nIgnoring automation for this storage account error. The current Terraform command will exit so you can address it manually." -ForegroundColor Yellow
                Set-TerraformRemediationAction -Action "ignore-error"
            }
        }
        $guidanceShown = $true
    }

    if ($errorText -match "Cannot apply incomplete plan") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║          PLAN IS INCOMPLETE                                 ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "⚠ Terraform could not finish generating the plan, so the saved plan file cannot be applied." -ForegroundColor Yellow
        Write-Host "  Review the earlier errors in this run to fix the root cause, then regenerate the plan." -ForegroundColor White
        Write-Host ""
        Write-Host "Recommended next steps:" -ForegroundColor Cyan
        Write-Host "  1. Address the error that interrupted 'terraform plan' (see output above)." -ForegroundColor White
        Write-Host "  2. Re-run the plan: $TerraformExe plan -out=plan.tfplan" -ForegroundColor White
        Write-Host "  3. Apply the new plan: $TerraformExe apply plan.tfplan" -ForegroundColor White
        Write-Host ""
        Write-Host "Using the startup script? Choose option [1] to regenerate the plan, then rerun option [3] (apply existing plan) once it succeeds." -ForegroundColor Yellow
        $guidanceShown = $true
    }

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
        Write-Host "   az storage account list --resource-group <rg-name> --query '[].name'" -ForegroundColor White
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

    if ($errorText -match "Warning: Argument is deprecated|has been deprecated in favor of") {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║          DEPRECATION WARNINGS DETECTED                     ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "ℹ These are warnings, not errors - deployment can continue" -ForegroundColor Cyan
        Write-Host ""

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

function Test-AppGatewayCertificate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    Write-Host ""
    Write-Host "Checking Application Gateway certificate requirements..." -ForegroundColor Cyan

    $tfvarsPath = Join-Path $RepoRoot "landingzone.defaults.auto.tfvars"
    if (-not (Test-Path $tfvarsPath)) {
        Write-Host "  ℹ Could not find tfvars file - skipping certificate check" -ForegroundColor Gray
        return $true
    }

    $tfvarsContent = Get-Content $tfvarsPath -Raw
    $appGatewayEnabled = ($tfvarsContent -match 'app_gateway' -and $tfvarsContent -match 'deploy\s*=\s*true')

    if (-not $appGatewayEnabled) {
        Write-Host "  ✓ Application Gateway not enabled or certificate not required" -ForegroundColor Green
        return $true
    }

    if ($tfvarsContent -match 'key_vault_secret_id\s*=') {
        Write-Host "  ✓ SSL certificate configuration found" -ForegroundColor Green
        return $true
    }

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

    switch ($certChoice) {
        '1' {
            Write-Host ""
            Write-Host "Certificate generation requires:" -ForegroundColor Cyan
            Write-Host "  • Key Vault name" -ForegroundColor White
            Write-Host "  • Resource Group name" -ForegroundColor White
            Write-Host "  • Azure login (will use current session)" -ForegroundColor White
            Write-Host ""

            $kvName = $null
            if ($tfvarsContent -match 'key_vault.*name\s*=\s*"([^"]+)"') {
                $kvName = $matches[1]
            }

            $rgName = $null
            if ($tfvarsContent -match 'resource_group.*name\s*=\s*"([^"]+)"') {
                $rgName = $matches[1]
            }

            if (-not ($kvName -and $rgName)) {
                Write-Host "⚠ Could not auto-detect Key Vault and Resource Group names" -ForegroundColor Yellow
                Write-Host "  Please run manually:" -ForegroundColor White
                Write-Host '  .\scripts\Generate-AppGwCertificate.ps1 -KeyVaultName <name> -ResourceGroupName <rg>' -ForegroundColor Cyan
                return $true
            }

            Write-Host "Detected configuration:" -ForegroundColor Green
            Write-Host "  Key Vault: $kvName" -ForegroundColor White
            Write-Host "  Resource Group: $rgName" -ForegroundColor White
            Write-Host ""

            $confirm = Read-Host "Use these values? (yes/no)"
            if ($confirm -notin @('yes','y','YES','Y')) {
                return $true
            }

            $certScriptPath = Join-Path $RepoRoot "scripts\Generate-AppGwCertificate.ps1"
            if (-not (Test-Path $certScriptPath)) {
                Write-Host "✗ Certificate generation script not found at: $certScriptPath" -ForegroundColor Red
                return $true
            }

            Write-Host ""
            Write-Host "Running certificate generation script..." -ForegroundColor Cyan
            & $certScriptPath -KeyVaultName $kvName -ResourceGroupName $rgName -CertificateName "appgw-cert" -DnsName "*.example.com"

            if ($LASTEXITCODE -eq 0) {
                Write-Host ""
                Write-Host "✓ Certificate generated successfully!" -ForegroundColor Green
                Write-Host "  You can now proceed with deployment" -ForegroundColor White
            }
            else {
                Write-Host ""
                Write-Host "⚠ Certificate generation failed or was cancelled" -ForegroundColor Yellow
                Write-Host "  You may need to generate it manually or configure an existing certificate" -ForegroundColor White
            }

            Write-Host ""
            return $true
        }
        '3' {
            Write-Host ""
            Write-Host "✓ Operation cancelled. Please configure certificate and try again." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "To generate certificate manually:" -ForegroundColor Cyan
            Write-Host '  .\scripts\Generate-AppGwCertificate.ps1 -KeyVaultName <name> -ResourceGroupName <rg>' -ForegroundColor White
            return $false
        }
        default {
            Write-Host ""
            Write-Host "⚠ Continuing without certificate - deployment may fail" -ForegroundColor Yellow
            return $true
        }
    }
}

Export-ModuleMember -Function Invoke-TerraformDiagnostics, Show-TerraformErrorGuidance, Test-AppGatewayCertificate, Reset-TerraformRemediationAction, Get-TerraformRemediationAction, Invoke-TerraformBackendRemediation
