# Application Gateway SSL Certificate Management

This directory contains tools for managing SSL certificates for Azure Application Gateway deployments in the AI Landing Zone.

## Overview

The Application Gateway requires an SSL certificate stored in Azure Key Vault for HTTPS termination. This automated solution ensures certificates are properly generated and uploaded before Application Gateway deployment.

## Files

### `Generate-AppGwCertificate.ps1`
Main PowerShell script that:
- Generates self-signed SSL certificates optimized for Application Gateway
- Handles Azure Key Vault network access requirements
- Uploads certificates securely to Key Vault
- Cleans up temporary files and local certificates
- Provides comprehensive error handling and logging

### `Certificate-Examples.ps1`
Example usage patterns and documentation for different deployment scenarios.

## Quick Start

### Basic Usage (Current Environment)
```powershell
.\Generate-AppGwCertificate.ps1 `
    -KeyVaultName "azr-aiops-tst-sec-kv-l9b" `
    -ResourceGroupName "rg-aiops-tst-sec-007"
```

### Custom Domain
```powershell
.\Generate-AppGwCertificate.ps1 `
    -KeyVaultName "your-keyvault" `
    -ResourceGroupName "your-rg" `
    -DnsName "*.yourdomain.com" `
    -CertificateName "custom-cert" `
    -ValidityYears 2
```

## Prerequisites

1. **Azure CLI**: Install and login (`az login`)
2. **PowerShell 5.1+**: Windows PowerShell or PowerShell Core
3. **Permissions**: Key Vault Administrator role or equivalent
4. **Network Access**: Script handles Key Vault network settings automatically

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `KeyVaultName` | Yes | - | Azure Key Vault name |
| `ResourceGroupName` | Yes | - | Resource group containing Key Vault |
| `CertificateName` | No | "appgw-cert" | Certificate name in Key Vault |
| `DnsName` | No | "*.example.com" | DNS names for certificate |
| `ValidityYears` | No | 1 | Certificate validity period |
| `CertificatePassword` | No | Auto-generated | PFX password (secure) |
| `SubscriptionId` | No | Current | Azure subscription ID |

## Integration with Terraform

The certificate name must match the Terraform configuration:

```hcl
# In locals.networking.tf
app_gateway_key_vault_default_secret_name = "appgw-cert"
```

After certificate generation, Terraform Application Gateway deployments will automatically use the certificate from Key Vault.

## Security Features

- **Secure Password Generation**: Auto-generates strong passwords for PFX files
- **Network Isolation**: Temporarily enables Key Vault access only when needed
- **Cleanup**: Removes certificates from local certificate store after upload
- **Least Privilege**: Uses existing Azure CLI authentication context

## Certificate Properties

Generated certificates include:
- **Algorithm**: RSA 2048-bit keys
- **Hash**: SHA-256
- **Usage**: Digital Signature, Key Encipherment
- **Format**: PKCS#12 (PFX) for Key Vault storage
- **Subject**: CN=first DNS name
- **Extensions**: Subject Alternative Names for all DNS names

## Troubleshooting

### Common Issues

1. **Azure CLI Not Logged In**
   ```
   Solution: Run 'az login' first
   ```

2. **Key Vault Not Found**
   ```
   Solution: Verify Key Vault name and resource group
   ```

3. **Permission Denied**
   ```
   Solution: Ensure you have Key Vault Administrator role
   ```

4. **Network Access Issues**
   ```
   Solution: Script handles this automatically by temporarily enabling public access
   ```

### Error Codes

- **Exit Code 0**: Success
- **Exit Code 1**: Error occurred (check output for details)

## Advanced Usage

### Multiple DNS Names
```powershell
-DnsName "*.domain.com","*.api.domain.com","*.app.domain.com"
```

### Production Environment
```powershell
.\Generate-AppGwCertificate.ps1 `
    -KeyVaultName "prod-kv" `
    -ResourceGroupName "prod-rg" `
    -SubscriptionId "prod-subscription-id" `
    -CertificateName "prod-ssl" `
    -DnsName "*.company.com" `
    -ValidityYears 3
```

### Custom Password
```powershell
$securePassword = ConvertTo-SecureString "YourPassword123!" -AsPlainText -Force
.\Generate-AppGwCertificate.ps1 `
    -KeyVaultName "your-kv" `
    -ResourceGroupName "your-rg" `
    -CertificatePassword $securePassword
```

## Automation and CI/CD

The script is designed for automation and can be integrated into CI/CD pipelines:

```yaml
# Azure DevOps Pipeline Example
- task: PowerShell@2
  displayName: 'Generate Application Gateway Certificate'
  inputs:
    filePath: 'Generate-AppGwCertificate.ps1'
    arguments: |
      -KeyVaultName "$(keyVaultName)" 
      -ResourceGroupName "$(resourceGroupName)"
      -CertificateName "$(certificateName)"
      -DnsName "$(dnsNames)"
```

## Maintenance

### Certificate Renewal

Run the script again with the same parameters to update/renew certificates:

```powershell
# This will overwrite the existing certificate
.\Generate-AppGwCertificate.ps1 -KeyVaultName "your-kv" -ResourceGroupName "your-rg"
```

### Monitoring Expiration

Check certificate expiration in Azure Portal or via Azure CLI:

```bash
az keyvault certificate show --vault-name "your-kv" --name "appgw-cert" --query "attributes.expires"
```

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the script output for detailed error messages
3. Ensure all prerequisites are met
4. Verify Azure permissions and network connectivity