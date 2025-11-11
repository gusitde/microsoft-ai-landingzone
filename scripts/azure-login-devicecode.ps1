#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Login to Azure using device code authentication flow.

.DESCRIPTION
    This script authenticates to Azure using the device code flow, which is useful for:
    - Headless environments
    - Remote sessions
    - Systems without a web browser
    - Multi-factor authentication scenarios

.PARAMETER TenantId
    Optional. The Azure AD tenant ID to authenticate against.

.PARAMETER SubscriptionId
    Optional. The subscription ID to set as the default after login.

.EXAMPLE
    .\azure-login-devicecode.ps1

.EXAMPLE
    .\azure-login-devicecode.ps1 -TenantId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    .\azure-login-devicecode.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -SubscriptionId "11111111-1111-1111-1111-111111111111"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to check if Azure CLI is installed
function Test-AzureCLI {
    try {
        $azVersion = az version --output json 2>$null | ConvertFrom-Json
        Write-Host "✓ Azure CLI is installed (version: $($azVersion.'azure-cli'))" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "✗ Azure CLI is not installed or not in PATH" -ForegroundColor Red
        Write-Host "Please install Azure CLI from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor Yellow
        return $false
    }
}

# Function to clear all Azure CLI session data
function Clear-AzureSession {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "Clearing Azure Session Data" -ForegroundColor Yellow
    Write-Host "========================================`n" -ForegroundColor Yellow

    try {
        # Logout from Azure CLI
        Write-Host "Logging out from all Azure accounts..." -ForegroundColor Yellow
        az logout 2>$null

        # Clear Azure CLI cache and config
        $azureConfigPath = Join-Path $env:USERPROFILE ".azure"
        if (Test-Path $azureConfigPath) {
            Write-Host "Clearing Azure CLI cache and configuration..." -ForegroundColor Yellow

            # Remove specific cache files while preserving config
            $filesToRemove = @(
                "accessTokens.json",
                "azureProfile.json",
                "msal_token_cache.bin",
                "msal_token_cache.json",
                "service_principal_entries.bin"
            )

            foreach ($file in $filesToRemove) {
                $filePath = Join-Path $azureConfigPath $file
                if (Test-Path $filePath) {
                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                    Write-Host "  ✓ Removed $file" -ForegroundColor Gray
                }
            }
        }

        Write-Host "`n✓ Azure session data cleared successfully!" -ForegroundColor Green
        Write-Host "  All subscriptions, tenants, and tokens have been removed.`n" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "`n✗ Error clearing session: $_" -ForegroundColor Red
        return $false
    }
}

# Function to perform device code login
function Invoke-AzureDeviceCodeLogin {
    param(
        [string]$TenantId,
        [string]$SubscriptionId
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Azure Device Code Authentication" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    try {
        # Build the login command
        $loginCmd = "az login --use-device-code"

        if ($TenantId) {
            $loginCmd += " --tenant $TenantId"
            Write-Host "Tenant ID: $TenantId" -ForegroundColor Yellow
        }

        Write-Host "`nInitiating device code login..." -ForegroundColor Yellow
        Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║          DEVICE CODE LOGIN INSTRUCTIONS                   ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor Green
        Write-Host "│  BROWSER URL (copy and paste):                         │" -ForegroundColor Green
        Write-Host "│                                                         │" -ForegroundColor Green
        Write-Host "│  " -NoNewline -ForegroundColor Green
        Write-Host "https://microsoft.com/devicelogin" -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host "│                                                         │" -ForegroundColor Green
        Write-Host "└─────────────────────────────────────────────────────────┘`n" -ForegroundColor Green

        Write-Host "Please wait while the device code is generated...`n" -ForegroundColor Gray

        # Execute the login command and let it display naturally
        if ($TenantId) {
            az login --use-device-code --tenant $TenantId
        }
        else {
            az login --use-device-code
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n✓ Successfully logged in to Azure!" -ForegroundColor Green

            # Get current account information
            $accountInfo = az account show --output json | ConvertFrom-Json

            Write-Host "`nCurrent Account Information:" -ForegroundColor Cyan
            Write-Host "  User: $($accountInfo.user.name)" -ForegroundColor White
            Write-Host "  Subscription: $($accountInfo.name)" -ForegroundColor White
            Write-Host "  Subscription ID: $($accountInfo.id)" -ForegroundColor White
            Write-Host "  Tenant ID: $($accountInfo.tenantId)" -ForegroundColor White

            # Set subscription if specified
            if ($SubscriptionId) {
                Write-Host "`nSetting default subscription to: $SubscriptionId" -ForegroundColor Yellow
                az account set --subscription $SubscriptionId

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✓ Subscription set successfully!" -ForegroundColor Green
                }
                else {
                    Write-Host "✗ Failed to set subscription" -ForegroundColor Red
                }
            }

            # List all available subscriptions
            Write-Host "`nAvailable Subscriptions:" -ForegroundColor Cyan
            az account list --output table

            return $true
        }
        else {
            Write-Host "`n✗ Login failed!" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "`n✗ Error during login: $_" -ForegroundColor Red
        return $false
    }
}

# Main script execution
Write-Host "Azure Device Code Authentication Script" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

# Check if Azure CLI is installed
if (-not (Test-AzureCLI)) {
    exit 1
}

# Check if already logged in
Write-Host "`nChecking current authentication status..." -ForegroundColor Yellow
$existingSession = $false
try {
    $currentAccount = az account show --output json 2>$null | ConvertFrom-Json
    if ($currentAccount) {
        $existingSession = $true
        Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║          EXISTING AZURE SESSION DETECTED                  ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

        Write-Host "Current Login Information:" -ForegroundColor Cyan
        Write-Host "  User:         " -NoNewline -ForegroundColor White
        Write-Host "$($currentAccount.user.name)" -ForegroundColor Yellow
        Write-Host "  Subscription: " -NoNewline -ForegroundColor White
        Write-Host "$($currentAccount.name)" -ForegroundColor Yellow
        Write-Host "  Subscription ID: " -NoNewline -ForegroundColor White
        Write-Host "$($currentAccount.id)" -ForegroundColor Yellow
        Write-Host "  Tenant ID:    " -NoNewline -ForegroundColor White
        Write-Host "$($currentAccount.tenantId)" -ForegroundColor Yellow

        Write-Host "`n" -NoNewline
        Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
        Write-Host "│  What would you like to do?                             │" -ForegroundColor Cyan
        Write-Host "│                                                         │" -ForegroundColor Cyan
        Write-Host "│  [K] Keep current session and exit                     │" -ForegroundColor White
        Write-Host "│  [N] Start NEW session (clear all data and re-login)   │" -ForegroundColor White
        Write-Host "│                                                         │" -ForegroundColor Cyan
        Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Cyan

        $response = Read-Host "`nYour choice (K/N)"

        if ($response -eq 'K' -or $response -eq 'k' -or [string]::IsNullOrWhiteSpace($response)) {
            Write-Host "`n✓ Keeping current session." -ForegroundColor Green
            Write-Host "No changes made to your Azure login.`n" -ForegroundColor Gray
            exit 0
        }
        elseif ($response -eq 'N' -or $response -eq 'n') {
            Write-Host "`n⚠ Starting new session..." -ForegroundColor Yellow
            Write-Host "This will clear ALL Azure session data (subscriptions, tenants, tokens)`n" -ForegroundColor Yellow

            $confirm = Read-Host "Are you sure? (yes/no)"
            if ($confirm -eq 'yes' -or $confirm -eq 'y' -or $confirm -eq 'YES' -or $confirm -eq 'Y') {
                if (-not (Clear-AzureSession)) {
                    Write-Host "`n✗ Failed to clear session. Please try manually: az logout" -ForegroundColor Red
                    exit 1
                }
                # Session cleared successfully, continue to login below
                Write-Host "Proceeding with new login...`n" -ForegroundColor Green
            }
            else {
                Write-Host "`n✓ Operation cancelled. Keeping current session." -ForegroundColor Yellow
                exit 0
            }
        }
        else {
            Write-Host "`n✗ Invalid choice. Exiting without changes." -ForegroundColor Red
            exit 1
        }
    }
}
catch {
    Write-Host "✓ No active Azure session found. Proceeding with new login...`n" -ForegroundColor Yellow
}

# Perform device code login
$loginSuccess = Invoke-AzureDeviceCodeLogin -TenantId $TenantId -SubscriptionId $SubscriptionId

if ($loginSuccess) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Authentication completed successfully!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Authentication failed!" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red
    exit 1
}
