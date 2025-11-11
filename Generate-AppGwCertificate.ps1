#Requires -Version 5.1
<#
.SYNOPSIS
    Generates a self-signed SSL certificate and uploads it to Azure Key Vault for Application Gateway use.

.DESCRIPTION
    This script creates a self-signed SSL certificate, exports it as a PFX file, and uploads it to Azure Key Vault.
    The certificate is specifically configured for Azure Application Gateway SSL termination.

.PARAMETER KeyVaultName
    The name of the Azure Key Vault where the certificate will be stored.

.PARAMETER CertificateName
    The name to use for the certificate in Key Vault (default: "appgw-cert").

.PARAMETER DnsName
    The DNS name(s) for the certificate (default: "*.example.com").

.PARAMETER ValidityYears
    Number of years the certificate should be valid (default: 1).

.PARAMETER CertificatePassword
    Password for the PFX certificate (default: auto-generated).

.PARAMETER ResourceGroupName
    The resource group containing the Key Vault.

.PARAMETER SubscriptionId
    Azure subscription ID (optional - uses current subscription if not specified).

.EXAMPLE
    .\Generate-AppGwCertificate.ps1 -KeyVaultName "azr-aiops-tst-sec-kv-l9b" -ResourceGroupName "rg-aiops-tst-sec-007"

.EXAMPLE
    .\Generate-AppGwCertificate.ps1 -KeyVaultName "my-keyvault" -ResourceGroupName "my-rg" -DnsName "*.mydomain.com" -ValidityYears 2

.NOTES
    Author: Azure AI Landing Zone
    Version: 1.0
    Requires: Azure CLI, PowerShell 5.1+
    
    The script will:
    1. Generate a self-signed certificate with proper settings for Application Gateway
    2. Export the certificate as a PFX file
    3. Temporarily enable Key Vault public access (if needed)
    4. Upload the certificate to Key Vault
    5. Restore original Key Vault network settings
    6. Clean up temporary files
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [string]$CertificateName = "appgw-cert",
    
    [Parameter(Mandatory = $false)]
    [string[]]$DnsName = @("*.example.com"),
    
    [Parameter(Mandatory = $false)]
    [int]$ValidityYears = 1,
    
    [Parameter(Mandatory = $false)]
    [securestring]$CertificatePassword,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Message = "",
        
        [Parameter(Mandatory = $false)]
        [string]$Color = "White"
    )
    
    Write-Host $Message -ForegroundColor $Color
}

# Function to generate a secure password (avoiding special characters that might cause issues)
function New-SecurePassword {
    param([int]$Length = 16)
    
    # Use only alphanumeric characters to avoid shell escaping issues
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz0123456789"
    $password = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $password += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $password
}

# Function to check if Azure CLI is installed and user is logged in
function Test-AzureCLI {
    try {
        $null = az account show 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Not logged in to Azure CLI"
        }
        return $true
    }
    catch {
        Write-ColorOutput "Azure CLI is not installed or you are not logged in." "Red"
        Write-ColorOutput "Please install Azure CLI and run 'az login' first." "Yellow"
        return $false
    }
}

# Function to set subscription if provided
function Set-AzureSubscription {
    param([string]$SubscriptionId)
    
    if ($SubscriptionId) {
        Write-ColorOutput "Setting Azure subscription to: $SubscriptionId" "Yellow"
        az account set --subscription $SubscriptionId
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set subscription: $SubscriptionId"
        }
    }
}

# Function to check if Key Vault exists
function Test-KeyVault {
    param(
        [string]$VaultName,
        [string]$ResourceGroup
    )
    
    Write-ColorOutput "Checking if Key Vault '$VaultName' exists..." "Yellow"
    $vault = az keyvault show --name $VaultName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0 -or $null -eq $vault) {
        throw "Key Vault '$VaultName' not found in resource group '$ResourceGroup'"
    }
    
    Write-ColorOutput "Key Vault found: $($vault.name)" "Green"
    return $vault
}

# Function to get current Key Vault network settings
function Get-KeyVaultNetworkSettings {
    param([string]$VaultName, [string]$ResourceGroup)
    
    $vault = az keyvault show --name $VaultName --resource-group $ResourceGroup | ConvertFrom-Json
    return @{
        PublicNetworkAccess = $vault.properties.publicNetworkAccess
        NetworkAcls = $vault.properties.networkAcls
    }
}

# Function to temporarily enable Key Vault public access
function Enable-KeyVaultPublicAccess {
    param([string]$VaultName, [string]$ResourceGroup)
    
    Write-ColorOutput "Temporarily enabling public access to Key Vault..." "Yellow"
    az keyvault update --name $VaultName --resource-group $ResourceGroup --public-network-access "Enabled" | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to enable public access to Key Vault"
    }
    
    # Wait a moment for the change to propagate
    Start-Sleep -Seconds 10
}

# Function to restore Key Vault network settings
function Restore-KeyVaultNetworkSettings {
    param(
        [string]$VaultName,
        [string]$ResourceGroup,
        [hashtable]$OriginalSettings
    )
    
    Write-ColorOutput "Restoring Key Vault network settings..." "Yellow"
    
    if ($OriginalSettings.PublicNetworkAccess -eq "Disabled") {
        az keyvault update --name $VaultName --resource-group $ResourceGroup --public-network-access "Disabled" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "Warning: Failed to restore Key Vault network settings" "Yellow"
        }
    }
}

# Function to create self-signed certificate
function New-SelfSignedAppGwCertificate {
    param(
        [string[]]$DnsNames,
        [int]$ValidityYears,
        [string]$CertName
    )
    
    Write-ColorOutput "Creating self-signed certificate for DNS names: $($DnsNames -join ', ')" "Yellow"
    
    # Create certificate with proper settings for Application Gateway
    $cert = New-SelfSignedCertificate `
        -DnsName $DnsNames `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyUsage KeyEncipherment, DigitalSignature `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears($ValidityYears) `
        -Subject "CN=$($DnsNames[0])" `
        -FriendlyName "Application Gateway SSL Certificate - $CertName"
    
    Write-ColorOutput "Certificate created with thumbprint: $($cert.Thumbprint)" "Green"
    return $cert
}

# Function to export certificate to PFX
function Export-CertificateToPfx {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [securestring]$Password,
        [string]$FilePath
    )
    
    Write-ColorOutput "Exporting certificate to PFX file: $FilePath" "Yellow"
    
    try {
        # Export with specific flags to ensure compatibility with Key Vault
        Export-PfxCertificate -Cert $Certificate -FilePath $FilePath -Password $Password -ChainOption EndEntityCertOnly -CryptoAlgorithmOption AES256_SHA256 | Out-Null
        
        if (-not (Test-Path $FilePath)) {
            throw "Failed to export certificate to PFX file"
        }
        
        # Verify the PFX file can be read
        try {
            $testCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($FilePath, $Password)
            $testCert.Dispose()
            Write-ColorOutput "Certificate exported successfully and verified" "Green"
        }
        catch {
            throw "PFX file verification failed: $($_.Exception.Message)"
        }
    }
    catch {
        throw "Failed to export certificate: $($_.Exception.Message)"
    }
}

# Function to upload certificate to Key Vault
function Import-CertificateToKeyVault {
    param(
        [string]$VaultName,
        [string]$CertName,
        [string]$PfxFilePath,
        [securestring]$Password
    )
    
    Write-ColorOutput "Uploading certificate to Key Vault: $VaultName" "Yellow"
    
    # Convert secure string to plain text for Azure CLI
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    try {
        # Since we're using only alphanumeric passwords now, no escaping needed
        $result = az keyvault certificate import `
            --vault-name $VaultName `
            --name $CertName `
            --file $PfxFilePath `
            --password $plainPassword 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to upload certificate to Key Vault: $result"
        }
        
        $certInfo = $result | ConvertFrom-Json
        Write-ColorOutput "Certificate uploaded successfully!" "Green"
        Write-ColorOutput "Certificate ID: $($certInfo.id)" "Cyan"
        Write-ColorOutput "Certificate expires: $($certInfo.attributes.expires)" "Cyan"
        
        return $certInfo
    }
    finally {
        # Clear the password variable
        $plainPassword = $null
    }
}

# Function to clean up certificate from local store
function Remove-LocalCertificate {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    
    Write-ColorOutput "Cleaning up local certificate..." "Yellow"
    
    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "CurrentUser")
        $store.Open("ReadWrite")
        $store.Remove($Certificate)
        $store.Close()
        Write-ColorOutput "Local certificate removed from certificate store" "Green"
    }
    catch {
        Write-ColorOutput "Warning: Could not remove certificate from local store: $($_.Exception.Message)" "Yellow"
    }
}

# Main script execution
try {
    Write-ColorOutput "=== Azure Application Gateway SSL Certificate Generator ===" "Cyan"
    Write-ColorOutput ""
    
    # Check prerequisites
    if (-not (Test-AzureCLI)) {
        exit 1
    }
    
    # Set subscription if provided
    Set-AzureSubscription -SubscriptionId $SubscriptionId
    
    # Generate password if not provided
    if (-not $CertificatePassword) {
        $passwordString = New-SecurePassword -Length 24
        $CertificatePassword = ConvertTo-SecureString $passwordString -AsPlainText -Force
        Write-ColorOutput "Generated secure password for certificate" "Green"
        Write-ColorOutput "Password length: 24 characters (alphanumeric only)" "Cyan"
    }
    
    # Check if Key Vault exists
    $vault = Test-KeyVault -VaultName $KeyVaultName -ResourceGroup $ResourceGroupName
    
    # Get current network settings
    $originalNetworkSettings = Get-KeyVaultNetworkSettings -VaultName $KeyVaultName -ResourceGroup $ResourceGroupName
    
    # Check if we need to enable public access
    $needsPublicAccess = $originalNetworkSettings.PublicNetworkAccess -eq "Disabled"
    
    if ($needsPublicAccess) {
        Enable-KeyVaultPublicAccess -VaultName $KeyVaultName -ResourceGroup $ResourceGroupName
    }
    
    # Generate certificate
    $certificate = New-SelfSignedAppGwCertificate -DnsNames $DnsName -ValidityYears $ValidityYears -CertName $CertificateName
    
    # Verify certificate was created properly
    Write-ColorOutput "Verifying certificate properties..." "Yellow"
    Write-ColorOutput "Subject: $($certificate.Subject)" "Cyan"
    Write-ColorOutput "Issuer: $($certificate.Issuer)" "Cyan"
    Write-ColorOutput "Valid from: $($certificate.NotBefore)" "Cyan"
    Write-ColorOutput "Valid until: $($certificate.NotAfter)" "Cyan"
    Write-ColorOutput "Has private key: $($certificate.HasPrivateKey)" "Cyan"
    
    # Export to PFX
    $pfxPath = Join-Path $env:TEMP "$CertificateName.pfx"
    Export-CertificateToPfx -Certificate $certificate -Password $CertificatePassword -FilePath $pfxPath
    
    try {
        # Upload to Key Vault
        $uploadedCert = Import-CertificateToKeyVault -VaultName $KeyVaultName -CertName $CertificateName -PfxFilePath $pfxPath -Password $CertificatePassword
        
        Write-ColorOutput ""
        Write-ColorOutput "=== Certificate Details ===" "Cyan"
        Write-ColorOutput "Certificate Name: $CertificateName" "White"
        Write-ColorOutput "DNS Names: $($DnsName -join ', ')" "White"
        Write-ColorOutput "Valid Until: $($certificate.NotAfter)" "White"
        Write-ColorOutput "Thumbprint: $($certificate.Thumbprint)" "White"
        Write-ColorOutput "Key Vault: $KeyVaultName" "White"
        Write-ColorOutput ""
        Write-ColorOutput "Certificate is ready for Application Gateway use!" "Green"
        
    }
    finally {
        # Clean up PFX file
        if (Test-Path $pfxPath) {
            Remove-Item $pfxPath -Force
            Write-ColorOutput "Temporary PFX file cleaned up" "Green"
        }
        
        # Restore Key Vault network settings
        if ($needsPublicAccess) {
            Restore-KeyVaultNetworkSettings -VaultName $KeyVaultName -ResourceGroup $ResourceGroupName -OriginalSettings $originalNetworkSettings
        }
        
        # Clean up local certificate
        Remove-LocalCertificate -Certificate $certificate
    }
    
    Write-ColorOutput ""
    Write-ColorOutput "=== Script completed successfully! ===" "Green"
    
}
catch {
    Write-ColorOutput ""
    Write-ColorOutput "=== Error occurred ===" "Red"
    Write-ColorOutput $_.Exception.Message "Red"
    Write-ColorOutput ""
    
    # Try to restore Key Vault settings on error
    if ($needsPublicAccess -and $originalNetworkSettings) {
        try {
            Restore-KeyVaultNetworkSettings -VaultName $KeyVaultName -ResourceGroup $ResourceGroupName -OriginalSettings $originalNetworkSettings
        }
        catch {
            Write-ColorOutput "Warning: Could not restore Key Vault network settings" "Yellow"
        }
    }
    
    exit 1
}