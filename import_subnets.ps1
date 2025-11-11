# Import all existing subnets for Application Gateway deployment
Write-Host "Starting subnet imports..." -ForegroundColor Green

$subscriptionId = "06bfa713-9d6d-44a9-8643-b39e003e136b"
$resourceGroup = "rg-aiops-tst-sec-007"
$vnetName = "vnet-ai-swedencentral"

# Define subnets to import
$subnets = @(
    "AppGatewaySubnet",
    "DevOpsBuildSubnet", 
    "APIMSubnet",
    "AIFoundrySubnet",
    "PrivateEndpointSubnet",
    "ContainerAppEnvironmentSubnet"
)

foreach ($subnet in $subnets) {
    Write-Host "Importing subnet: $subnet" -ForegroundColor Yellow
    
    $resourceAddress = "module.ai_lz_vnet.module.subnet[`"$subnet`"].azapi_resource.subnet"
    $resourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Network/virtualNetworks/$vnetName/subnets/$subnet"
    
    try {
        terraform.exe import $resourceAddress $resourceId
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Successfully imported: $subnet" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to import: $subnet" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "❌ Error importing $subnet`: $_" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 2
}

Write-Host "Subnet import process completed!" -ForegroundColor Green