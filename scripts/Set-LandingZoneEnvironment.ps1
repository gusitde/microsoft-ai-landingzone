[CmdletBinding()]
param(
    [Parameter()][string]$SubscriptionId,
    [Parameter()][string]$TenantId,
    [Parameter()][string]$ClientId,
    [Parameter()][string]$ClientSecret,
    [Parameter()][bool]$EnableAzureAd = $true,
    [Parameter()][bool]$DisableStorageKeyUsage = $true,
    [Parameter()][switch]$Persist,
    [Parameter()][bool]$ConfigureRemoteState = $true,
    [Parameter()][bool]$CreateResources = $true,
    [Parameter()][bool]$AssignBlobDataRole = $true,
    [Parameter()][string]$Project,
    [Parameter()][ValidateSet("tst", "qlt", "prd")][string]$Environment,
    [Parameter()][string]$Location,
    [Parameter()][string]$Descriptor,
    [Parameter()][string]$OrgPrefix = "azr",
    [Parameter()][int]$ResourceGroupVersion = 1,
    [Parameter()][int]$StorageAccountIndex = 1,
    [Parameter()][string]$StateResourceGroup,
    [Parameter()][string]$StateStorageAccount,
    [Parameter()][string]$StateContainerName = "tfstate",
    [Parameter()][string]$BackendFilePath,
    [Parameter()][switch]$RunParameterWizard
)

if (-not $BackendFilePath) {
    $BackendFilePath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "backend.tf"
}

function Set-TerraformEnvironmentVariable {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter()][switch]$Persist
    )

    Set-Item -Path ("Env:\{0}" -f $Name) -Value $Value

    if ($Persist) {
        [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    }

    $displayValue = if ($Name -match "SECRET|PASSWORD|KEY") { "***" } else { $Value }
    Write-Host "Set $Name=$displayValue" -ForegroundColor Green
}

function Read-RequiredInput {
    param(
        [Parameter()][string]$Prompt,
        [Parameter()][string]$CurrentValue
    )

    if ($CurrentValue) {
        return $CurrentValue
    }

    do {
        $inputValue = Read-Host $Prompt
    } while (-not $inputValue)

    return $inputValue
}

function Get-RegionAbbreviation {
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

function Get-TypeAbbreviation {
    param([Parameter(Mandatory = $true)][string]$ResourceType)

    $map = @{
        "resource_group"    = "rg"
        "storage_account"   = "st"
        "container_registry" = "acr"
    }

    return $map[$ResourceType] ? $map[$ResourceType] : $ResourceType
}

function New-LandingZoneName {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$Location,
        [Parameter(Mandatory = $true)][string]$ResourceType,
        [Parameter()][string]$Descriptor,
        [Parameter()][string]$OrgPrefix = "azr",
        [Parameter()][int]$Index = 1,
        [Parameter()][int]$ResourceGroupVersion = 1
    )

    $projectValue = $Project.ToLowerInvariant()
    $environmentValue = $Environment.ToLowerInvariant()
    $locationValue = Get-RegionAbbreviation -Location $Location
    $resourceAbbr = Get-TypeAbbreviation -ResourceType $ResourceType
    $prefixValue = $OrgPrefix.ToLowerInvariant()
    $descriptorValue = $Descriptor ? $Descriptor.ToLowerInvariant() : $null

    $baseParts = @($prefixValue, $projectValue, $environmentValue, $locationValue, $resourceAbbr)
    if ($descriptorValue) {
        $baseParts += $descriptorValue
    }

    $tail = if ($ResourceType -eq "resource_group") { "{0:D2}" -f $ResourceGroupVersion } else { "{0:D2}" -f $Index }
    $requiresAlphanumeric = $ResourceType -in @("storage_account", "container_registry")

    if ($requiresAlphanumeric) {
        $name = ($baseParts + $tail) -join ""
        $name = ($name -replace "[^0-9a-z]", "").ToLowerInvariant()
        if ($name.Length -gt 24) {
            $name = $name.Substring(0, 24)
        }
        return $name
    }

    $humanName = ($baseParts + $tail) -join "-"
    if ($humanName.Length -gt 64) {
        $humanName = $humanName.Substring(0, 64)
    }
    return $humanName.ToLowerInvariant()
}

function Get-PrincipalContext {
    param([string]$ClientId)

    try {
        if ($ClientId) {
            $spJson = & az ad sp show --id $ClientId --query '{objectId:id,displayName:displayName}' -o json 2>$null
            if ($LASTEXITCODE -eq 0 -and $spJson) {
                $sp = $spJson | ConvertFrom-Json
                if ($sp.objectId) {
                    return [pscustomobject]@{
                        ObjectId      = $sp.objectId
                        PrincipalType = "ServicePrincipal"
                        DisplayName   = $sp.displayName
                    }
                }
            }
        }

        $accountJson = & az account show --query '{type:user.type,name:user.name}' -o json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $accountJson) {
            return $null
        }

        $account = $accountJson | ConvertFrom-Json
        $principalId = $null
        $principalType = $account.type

        if ($principalType -eq "user") {
            $userJson = & az ad user show --id $account.name --query '{objectId:id,displayName:displayName}' -o json 2>$null
            if ($LASTEXITCODE -eq 0 -and $userJson) {
                $user = $userJson | ConvertFrom-Json
                $principalId = $user.objectId
                $displayName = $user.displayName
            }
        }
        elseif ($principalType -eq "servicePrincipal") {
            $spJson2 = & az ad sp show --id $account.name --query '{objectId:id,displayName:displayName}' -o json 2>$null
            if ($LASTEXITCODE -eq 0 -and $spJson2) {
                $sp2 = $spJson2 | ConvertFrom-Json
                $principalId = $sp2.objectId
                $displayName = $sp2.displayName
                $principalType = "ServicePrincipal"
            }
        }

        if ($principalId) {
            return [pscustomobject]@{
                ObjectId      = $principalId
                PrincipalType = if ($principalType -eq "user") { "User" } else { "ServicePrincipal" }
                DisplayName   = $displayName
            }
        }
    }
    catch {
        return $null
    }

    return $null
}

function Grant-StorageDataRoles {
    param(
        [string]$ResourceGroup,
        [string]$StorageAccount,
        [string]$ClientId,
        [bool]$AssignRole,
        [string[]]$Roles = @("Storage Blob Data Contributor")
    )

    if (-not $AssignRole) {
        return
    }

    $storageId = & az storage account show --name $StorageAccount --resource-group $ResourceGroup --query id -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $storageId) {
        Write-Warning "Unable to resolve storage account ID for role assignment."
        return
    }

    $principal = Get-PrincipalContext -ClientId $ClientId
    if (-not $principal) {
        Write-Warning "Could not determine principal for blob data role assignment."
        Write-Host "Grant Storage Blob Data Contributor manually:" -ForegroundColor Yellow
        Write-Host "  az role assignment create --role 'Storage Blob Data Contributor' --assignee <principalId> --scope $storageId" -ForegroundColor Gray
        return
    }

    foreach ($roleName in $Roles) {
        $existing = & az role assignment list --scope $storageId --assignee-object-id $principal.ObjectId --query "[?roleDefinitionName=='$roleName'] | length(@)" -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and [int]$existing -gt 0) {
            Write-Host "$roleName already assigned to $($principal.DisplayName)." -ForegroundColor Green
            continue
        }
        Write-Host "Granting $roleName to $($principal.DisplayName)..." -ForegroundColor Cyan
        try {
            & az role assignment create --scope $storageId --role $roleName --assignee-object-id $principal.ObjectId --assignee-principal-type $principal.PrincipalType --only-show-errors | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "$roleName assignment created. Allow a few minutes for propagation." -ForegroundColor Green
            }
            else {
                throw "Role assignment command failed."
            }
        }
        catch {
            Write-Warning "Failed to assign role '$roleName' automatically."
            Write-Host "Grant the role manually to unblock Terraform remote state:" -ForegroundColor Yellow
            Write-Host "  az role assignment create --role '$roleName' --assignee <principalId> --scope $storageId" -ForegroundColor Gray
        }
    }

    Write-Host "Verify access with: az storage container list --account-name $StorageAccount --auth-mode login" -ForegroundColor Yellow
    Write-Host "Queue operations may require: az storage queue list --account-name $StorageAccount --auth-mode login" -ForegroundColor Yellow
}

function Get-HclBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$BlockName
    )

    $index = $Content.IndexOf($BlockName, [System.StringComparison]::Ordinal)
    if ($index -lt 0) {
        return $null
    }

    $startBrace = $Content.IndexOf('{', $index)
    if ($startBrace -lt 0) {
        return $null
    }

    $depth = 0
    $endIndex = $null
    for ($i = $startBrace; $i -lt $Content.Length; $i++) {
        $char = $Content[$i]
        if ($char -eq '{') {
            $depth++
        }
        elseif ($char -eq '}') {
            $depth--
            if ($depth -eq 0) {
                $endIndex = $i
                break
            }
        }
    }

    if ($null -eq $endIndex) {
        return $null
    }

    $header = $Content.Substring($index, $startBrace - $index + 1)
    $innerStart = $startBrace + 1
    $innerLength = $endIndex - $startBrace - 1
    $inner = if ($innerLength -gt 0) { $Content.Substring($innerStart, $innerLength) } else { "" }
    $blockText = $Content.Substring($index, ($endIndex - $index) + 1)

    return [pscustomobject]@{
        Start = $index
        End   = $endIndex
        Header = $header
        Inner  = $inner
        Block  = $blockText
    }
}

function Set-HclBlockInner {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)]$Block,
        [Parameter(Mandatory = $true)][string]$NewInner
    )

    $before = $Content.Substring(0, $Block.Start)
    $after = $Content.Substring($Block.End + 1)
    $replacement = $Block.Header + $NewInner + '}'
    return $before + $replacement + $after
}

function Set-HclBlockText {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$BlockName,
        [Parameter(Mandatory = $true)][string]$NewBlockText
    )

    $block = Get-HclBlock -Content $Content -BlockName $BlockName
    if (-not $block) {
        return $Content
    }

    $before = $Content.Substring(0, $block.Start)
    $after = $Content.Substring($block.End + 1)
    if (-not $NewBlockText.EndsWith([Environment]::NewLine)) {
        $NewBlockText += [Environment]::NewLine
    }
    return $before + $NewBlockText + $after
}

function Get-HclPropertyValue {
    param(
        [Parameter(Mandatory = $true)][string]$BlockContent,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $pattern = "(?m)^\s*" + [regex]::Escape($PropertyName) + "\s*=\s*(?<value>[^#\r\n]*)"
    $match = [regex]::Match($BlockContent, $pattern)
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups['value'].Value.Trim()
}

function ConvertFrom-HclStringValue {
    param([string]$RawValue)

    if ($null -eq $RawValue) {
        return $null
    }

    $trimmed = $RawValue.Trim()
    if ($trimmed -eq 'null') {
        return $null
    }

    $quotedMatch = [regex]::Match($trimmed, '^"(.*)"$')
    if ($quotedMatch.Success) {
        return $quotedMatch.Groups[1].Value
    }

    return $trimmed
}

function ConvertFrom-HclBoolValue {
    param([string]$RawValue)

    if ($null -eq $RawValue) {
        return $false
    }

    $trimmed = $RawValue.Trim().ToLowerInvariant()
    return $trimmed -eq 'true'
}

function ConvertFrom-HclNumberValue {
    param([string]$RawValue)

    if ($null -eq $RawValue) {
        return $null
    }

    $trimmed = $RawValue.Trim()
    if ($trimmed -eq '') {
        return $null
    }

    return [int]$trimmed
}

function Set-HclBlockProperty {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$BlockName,
        [Parameter(Mandatory = $true)][string]$PropertyName,
        [Parameter(Mandatory = $true)][string]$NewValue
    )

    $block = Get-HclBlock -Content $Content -BlockName $BlockName
    if (-not $block) {
        return $Content
    }

    $pattern = "(?m)(^\s*" + [regex]::Escape($PropertyName) + "\s*=\s*)([^#\r\n]*)(\s*(#.*)?)"
    $propertyExists = [regex]::IsMatch($block.Inner, $pattern)
    $newInner = [regex]::Replace($block.Inner, $pattern, {
            param([System.Text.RegularExpressions.Match]$match)
            return $match.Groups[1].Value + $NewValue + $match.Groups[3].Value
        }, 1)

    if (-not $propertyExists) {
        $trimmedInner = $block.Inner.TrimEnd()
        $newline = if ($trimmedInner.EndsWith([Environment]::NewLine)) { '' } else { [Environment]::NewLine }
        $newInner = $trimmedInner + $newline + "  $PropertyName = $NewValue" + [Environment]::NewLine
    }

    $duplicatePattern = "(?m)^\s*" + [regex]::Escape($PropertyName) + "\s*=.*(?:\r?\n)?"
    $foundLine = $false
    $newInner = [regex]::Replace($newInner, $duplicatePattern, {
            param([System.Text.RegularExpressions.Match]$match)
            if ($foundLine) {
                return ''
            }
            $foundLine = $true
            return $match.Value
        })

    return Set-HclBlockInner -Content $Content -Block $block -NewInner $newInner
}

function ConvertTo-UInt32IP {
    param([Parameter(Mandatory = $true)][System.Net.IPAddress]$Address)

    $bytes = $Address.GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Get-CidrRange {
    param([Parameter(Mandatory = $true)][string]$Cidr)

    $cidrMatch = [regex]::Match($Cidr, '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$')
    if (-not $cidrMatch.Success) {
        return $null
    }

    $ip = [System.Net.IPAddress]::Parse($cidrMatch.Groups[1].Value)
    $prefix = [int]$cidrMatch.Groups[2].Value

    if ($prefix -lt 0 -or $prefix -gt 32) {
        return $null
    }

    $ipValue = ConvertTo-UInt32IP -Address $ip
    $mask = if ($prefix -eq 0) { 0 } else { ([uint32]::MaxValue -shl (32 - $prefix)) -band [uint32]::MaxValue }
    $start = $ipValue -band $mask
    $hostMask = ((-bnot $mask) -band [uint32]::MaxValue)
    $end = $start + $hostMask

    return [pscustomobject]@{
        Start = $start
        End   = $end
        Prefix = $prefix
    BaseAddress = $cidrMatch.Groups[1].Value
    }
}

function Test-CidrOverlap {
    param(
        [Parameter(Mandatory = $true)][string]$First,
        [Parameter(Mandatory = $true)][string]$Second
    )

    $rangeA = Get-CidrRange -Cidr $First
    $rangeB = Get-CidrRange -Cidr $Second

    if (-not $rangeA -or -not $rangeB) {
        return $false
    }

    return ($rangeA.Start -le $rangeB.End) -and ($rangeB.Start -le $rangeA.End)
}

function Test-CidrContains {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )

    $parentRange = Get-CidrRange -Cidr $Parent
    $childRange = Get-CidrRange -Cidr $Child

    if (-not $parentRange -or -not $childRange) {
        return $false
    }

    return ($childRange.Start -ge $parentRange.Start) -and ($childRange.End -le $parentRange.End)
}

function Get-SimpleTfvarsValue {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $pattern = "(?m)^\s*" + [regex]::Escape($Key) + "\s*=\s*(?<value>[^#\r\n]*)"
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups['value'].Value.Trim()
}

function Get-TagsFromContent {
    param([string]$Content)

    $pattern = '(?ms)^tags\s*=\s*{\s*(?<body>[^}]*)}\s*'
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        return $null
    }

    $body = $match.Groups['body'].Value
    $tagMatches = [regex]::Matches($body, '(?m)^\s*(?<key>[A-Za-z0-9_-]+)\s*=\s*"(?<value>[^"]*)"')
    if ($tagMatches.Count -eq 0) {
        return @{}
    }

    $tags = [ordered]@{}
    foreach ($t in $tagMatches) {
        $tags[$t.Groups['key'].Value] = $t.Groups['value'].Value
    }

    return $tags
}

function Format-TagsBlock {
    param([hashtable]$Tags)

    if (-not $Tags -or $Tags.Keys.Count -eq 0) {
        return "tags = null"
    }

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('tags = {')
    foreach ($key in $Tags.Keys) {
        $value = $Tags[$key]
        $null = $sb.AppendLine(('  {0} = "{1}"' -f $key, $value))
    }
    $null = $sb.Append('}')
    return $sb.ToString()
}

function Get-SubnetsFromBlock {
    param([string]$VnetInner)

    $subnetsBlock = Get-HclBlock -Content $VnetInner -BlockName 'subnets'
    if (-not $subnetsBlock) {
        return @{}
    }

    $subnetMatches = [regex]::Matches($subnetsBlock.Inner, "(?ms)^\s*(?<key>[A-Za-z0-9_-]+)\s*=\s*{(?<body>.*?)}")
    $result = [ordered]@{}

    foreach ($match in $subnetMatches) {
        $key = $match.Groups['key'].Value
        $body = $match.Groups['body'].Value
        $nameValue = ConvertFrom-HclStringValue (Get-HclPropertyValue -BlockContent $body -PropertyName 'name')
        $addressValue = ConvertFrom-HclStringValue (Get-HclPropertyValue -BlockContent $body -PropertyName 'address_prefix')
        $result[$key] = [ordered]@{
            map_key = $key
            name = $nameValue
            address_prefix = $addressValue
        }
    }

    return $result
}

function Format-VnetBlock {
    param(
        [Parameter(Mandatory = $true)][hashtable]$VnetConfig
    )

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('vnet_definition = {')
    $null = $sb.AppendLine(('  name          = "{0}"' -f $VnetConfig.name))
    $null = $sb.AppendLine(('  address_space = "{0}"' -f $VnetConfig.address_space))
    $null = $sb.AppendLine('  subnets = {')
    foreach ($key in $VnetConfig.subnets.Keys) {
        $subnet = $VnetConfig.subnets[$key]
        $null = $sb.AppendLine(('    {0} = {{' -f $key))
        $null = $sb.AppendLine(('      name           = "{0}"' -f $subnet.name))
        $null = $sb.AppendLine(('      address_prefix = "{0}"' -f $subnet.address_prefix))
        $null = $sb.AppendLine('    }')
    }
    $null = $sb.AppendLine('  }')
    $null = $sb.Append('}')
    return $sb.ToString()
}

function Get-LandingZoneDefaults {
    param([string]$Content)

    $config = [ordered]@{}

    $config.subscription_id = ConvertFrom-HclStringValue (Get-SimpleTfvarsValue -Content $Content -Key 'subscription_id')
    $config.location = ConvertFrom-HclStringValue (Get-SimpleTfvarsValue -Content $Content -Key 'location')
    $config.project_code = ConvertFrom-HclStringValue (Get-SimpleTfvarsValue -Content $Content -Key 'project_code')
    $config.environment_code = ConvertFrom-HclStringValue (Get-SimpleTfvarsValue -Content $Content -Key 'environment_code')
    $config.naming_prefix = ConvertFrom-HclStringValue (Get-SimpleTfvarsValue -Content $Content -Key 'naming_prefix')
    $config.resource_group_name = ConvertFrom-HclStringValue (Get-SimpleTfvarsValue -Content $Content -Key 'resource_group_name')
    $config.resource_group_version = ConvertFrom-HclNumberValue (Get-SimpleTfvarsValue -Content $Content -Key 'resource_group_version')
    $config.enable_telemetry = ConvertFrom-HclBoolValue (Get-SimpleTfvarsValue -Content $Content -Key 'enable_telemetry')
    $config.flag_platform_landing_zone = ConvertFrom-HclBoolValue (Get-SimpleTfvarsValue -Content $Content -Key 'flag_platform_landing_zone')
    $config.vm_size = ConvertFrom-HclStringValue (Get-SimpleTfvarsValue -Content $Content -Key 'vm_size')

        $config.tags = Get-TagsFromContent -Content $Content

    $vnetBlock = Get-HclBlock -Content $Content -BlockName 'vnet_definition'
    if ($vnetBlock) {
        $config.vnet_definition = [ordered]@{}
    $config.vnet_definition.name = ConvertFrom-HclStringValue (Get-HclPropertyValue -BlockContent $vnetBlock.Inner -PropertyName 'name')
    $config.vnet_definition.address_space = ConvertFrom-HclStringValue (Get-HclPropertyValue -BlockContent $vnetBlock.Inner -PropertyName 'address_space')
        $config.vnet_definition.subnets = Get-SubnetsFromBlock -VnetInner $vnetBlock.Inner
    }

    $storageBlock = Get-HclBlock -Content $Content -BlockName 'genai_storage_account_definition'
    if ($storageBlock) {
        $config.genai_storage_account_definition = [ordered]@{
            shared_access_key_enabled       = ConvertFrom-HclBoolValue (Get-HclPropertyValue -BlockContent $storageBlock.Inner -PropertyName 'shared_access_key_enabled')
            default_to_oauth_authentication = ConvertFrom-HclBoolValue (Get-HclPropertyValue -BlockContent $storageBlock.Inner -PropertyName 'default_to_oauth_authentication')
            public_network_access_enabled   = ConvertFrom-HclBoolValue (Get-HclPropertyValue -BlockContent $storageBlock.Inner -PropertyName 'public_network_access_enabled')
        }
    }

    $acrBlock = Get-HclBlock -Content $Content -BlockName 'genai_container_registry_definition'
    if ($acrBlock) {
        $config.genai_container_registry_definition = [ordered]@{
            zone_redundancy_enabled = ConvertFrom-HclBoolValue (Get-HclPropertyValue -BlockContent $acrBlock.Inner -PropertyName 'zone_redundancy_enabled')
        }
    }

    $bastionBlock = Get-HclBlock -Content $Content -BlockName 'bastion_definition'
    if ($bastionBlock) {
        $config.bastion_definition = [ordered]@{
            deploy = ConvertFrom-HclBoolValue (Get-HclPropertyValue -BlockContent $bastionBlock.Inner -PropertyName 'deploy')
        }
    }

    $firewallBlock = Get-HclBlock -Content $Content -BlockName 'firewall_definition'
    if ($firewallBlock) {
        $config.firewall_definition = [ordered]@{
            deploy = ConvertFrom-HclBoolValue (Get-HclPropertyValue -BlockContent $firewallBlock.Inner -PropertyName 'deploy')
        }
    }

    $appGwBlock = Get-HclBlock -Content $Content -BlockName 'app_gateway_definition'
    if ($appGwBlock) {
        $config.app_gateway_definition = [ordered]@{
            deploy = ConvertFrom-HclBoolValue (Get-HclPropertyValue -BlockContent $appGwBlock.Inner -PropertyName 'deploy')
        }
    }

    return $config
}

function Read-StringValue {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$Current,
        [scriptblock]$Validate,
        [switch]$AllowEmpty
    )

    while ($true) {
        $prompt = if ($Current) { "$Label [$Current]" } else { $Label }
        $userInput = Read-Host $prompt

        if ([string]::IsNullOrWhiteSpace($userInput)) {
            if (-not $Current -and -not $AllowEmpty) {
                Write-Host "Value is required." -ForegroundColor Yellow
                continue
            }
            return $Current
        }

        if ($Validate) {
            $isValid = & $Validate $userInput
            if (-not $isValid) {
                Write-Host "Input did not pass validation. Try again." -ForegroundColor Yellow
                continue
            }
        }

        return $userInput
    }
}

function Read-BoolValue {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [bool]$Current
    )

    while ($true) {
        $defaultHint = if ($Current) { 'Y/n' } else { 'y/N' }
        $response = Read-Host "$Label ($defaultHint)"
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $Current
        }

        switch ($response.ToLowerInvariant()) {
            { $_ -in @('y', 'yes') } { return $true }
            { $_ -in @('n', 'no') } { return $false }
            default { Write-Host "Please answer yes or no." -ForegroundColor Yellow }
        }
    }
}

function Read-IntValue {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$Current,
        [scriptblock]$Validate
    )

    while ($true) {
        $response = Read-Host "$Label [$Current]"
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $Current
        }

        if (-not [int]::TryParse($response, [ref]([int]$null))) {
            Write-Host "Please enter a valid integer." -ForegroundColor Yellow
            continue
        }

        $value = [int]$response
        if ($Validate) {
            $isValid = & $Validate $value
            if (-not $isValid) {
                Write-Host "Input did not pass validation. Try again." -ForegroundColor Yellow
                continue
            }
        }

        return $value
    }
}

function Test-CidrNotation {
    param([string]$CidrValue)

    if (Get-CidrRange -Cidr $CidrValue) {
        return $true
    }

    Write-Host "Value must be a valid IPv4 CIDR (e.g. 10.0.0.0/22)." -ForegroundColor Yellow
    return $false
}

function Test-AzureNetworkConflict {
    param(
        [Parameter(Mandatory = $true)][string]$AddressSpace,
        [string]$SubscriptionId
    )

    $azCli = Get-Command -Name az -ErrorAction SilentlyContinue
    if (-not $azCli) {
        Write-Host "Azure CLI not found. Skipping subscription-wide address space validation." -ForegroundColor Yellow
        return $false
    }

    $azArgs = @('network', 'vnet', 'list', '--query', '[].{name:name,addressSpace:addressSpace,resourceGroup:resourceGroup}', '-o', 'json')
    if ($SubscriptionId) {
        $azArgs += @('--subscription', $SubscriptionId)
    }

    $json = & az @azArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Unable to query existing virtual networks. Error:" -ForegroundColor Yellow
        $json | ForEach-Object { Write-Host $_ -ForegroundColor DarkYellow }
        return $false
    }

    $vnets = $null
    try {
        $vnets = $json | ConvertFrom-Json
    }
    catch {
        Write-Host "Failed to parse Azure CLI output. Skipping overlap validation." -ForegroundColor Yellow
        return $false
    }

    if (-not $vnets) {
        return $false
    }

    foreach ($vnet in $vnets) {
        if (-not $vnet.addressSpace) { continue }
        foreach ($space in $vnet.addressSpace) {
            if (Test-CidrOverlap -First $AddressSpace -Second $space) {
                Write-Host "Address space $AddressSpace overlaps with VNet '$($vnet.name)' in resource group '$($vnet.resourceGroup)'." -ForegroundColor Red
                return $true
            }
        }
    }

    return $false
}

function Read-Tags {
    param($CurrentTags)

    $currentDescription = if ($CurrentTags -and $CurrentTags.Count -gt 0) {
            ($CurrentTags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        } else {
            'none'
        }

    Write-Host "Current tags: $currentDescription" -ForegroundColor Cyan
    $tagInput = Read-Host "Enter tags as key=value pairs separated by commas (leave blank to keep, type 'clear' to remove)"

    if ([string]::IsNullOrWhiteSpace($tagInput)) {
        return $CurrentTags
    }

    if ($tagInput.ToLowerInvariant() -eq 'clear') {
        return $null
    }

    $pairs = $tagInput.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($pairs.Count -eq 0) {
        return $CurrentTags
    }

    $result = [ordered]@{}
    foreach ($pair in $pairs) {
        $kv = $pair.Split('=', 2)
        if ($kv.Count -ne 2) {
            Write-Host "Invalid tag entry '$pair'. Expected key=value." -ForegroundColor Yellow
            return $CurrentTags
        }
        $key = $kv[0].Trim()
        $value = $kv[1].Trim()
        if (-not $key) {
            Write-Host "Tag key cannot be empty." -ForegroundColor Yellow
            return $CurrentTags
        }
        $result[$key] = $value
    }

    return $result
}

function Test-SubnetsWithinAddressSpace {
    param(
        [Parameter(Mandatory = $true)][string]$AddressSpace,
        [Parameter(Mandatory = $true)][hashtable]$Subnets
    )

    foreach ($subnet in $Subnets.Values) {
        if (-not (Test-CidrContains -Parent $AddressSpace -Child $subnet.address_prefix)) {
            Write-Host "Subnet prefix $($subnet.address_prefix) is not contained within VNet address space $AddressSpace." -ForegroundColor Red
            return $false
        }
    }

    $subnetList = $Subnets.Values
    for ($i = 0; $i -lt $subnetList.Count; $i++) {
        for ($j = $i + 1; $j -lt $subnetList.Count; $j++) {
            if (Test-CidrOverlap -First $subnetList[$i].address_prefix -Second $subnetList[$j].address_prefix) {
                Write-Host "Subnet prefixes $($subnetList[$i].address_prefix) and $($subnetList[$j].address_prefix) overlap." -ForegroundColor Red
                return $false
            }
        }
    }

    return $true
}

function Invoke-TerraformParameterWizard {
    param([string]$RepoRoot)

    $resolvedRoot = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
            Split-Path -Parent $PSScriptRoot
        } else {
            $RepoRoot
        }

    $configPath = Join-Path $resolvedRoot 'landingzone.defaults.auto.tfvars'
    if (-not (Test-Path $configPath)) {
        Write-Host "Cannot find landingzone.defaults.auto.tfvars at $configPath" -ForegroundColor Red
        return
    }

    $content = Get-Content -Raw -Path $configPath
    $config = Get-LandingZoneDefaults -Content $content

    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          TERRAFORM PARAMETER WIZARD                       ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    Write-Host "Press Enter to keep the current value shown in brackets." -ForegroundColor Gray

    $config.subscription_id = Read-StringValue -Label 'Subscription ID (leave blank to keep null and use env vars)' -Current $config.subscription_id -AllowEmpty
    $config.location = Read-StringValue -Label 'Azure region' -Current $config.location -Validate { param($value) return ($value -match '^[a-z0-9]+$') }
    $config.project_code = Read-StringValue -Label 'Project code (2-6 lowercase alphanumerics)' -Current $config.project_code -Validate {
            param($value)
            if ($value -match '^[a-z0-9]{2,6}$') { return $true }
            Write-Host 'Project code must be 2-6 lowercase letters or digits.' -ForegroundColor Yellow
            return $false
        }
    $config.environment_code = Read-StringValue -Label 'Environment code (tst|qlt|prd)' -Current $config.environment_code -Validate {
            param($value)
            if ($value.ToLowerInvariant() -in @('tst','qlt','prd')) { return $true }
            Write-Host 'Environment code must be tst, qlt, or prd.' -ForegroundColor Yellow
            return $false
        }
    $config.naming_prefix = Read-StringValue -Label 'Naming prefix' -Current $config.naming_prefix -AllowEmpty
    $config.resource_group_name = Read-StringValue -Label 'Resource group name' -Current $config.resource_group_name -Validate {
            param($value)
            if ($value -match '^[a-z0-9-]+$') { return $true }
            Write-Host 'Resource group name should use lowercase letters, numbers, and hyphens.' -ForegroundColor Yellow
            return $false
        }
    $config.resource_group_version = Read-IntValue -Label 'Resource group version' -Current $config.resource_group_version -Validate {
            param($value)
            return $value -ge 1 -and $value -le 99
        }
    $config.enable_telemetry = Read-BoolValue -Label 'Enable telemetry' -Current $config.enable_telemetry
    $config.flag_platform_landing_zone = Read-BoolValue -Label 'Flag platform landing zone' -Current $config.flag_platform_landing_zone
    $config.vm_size = Read-StringValue -Label 'Default VM size' -Current $config.vm_size -AllowEmpty

    $config.tags = Read-Tags -CurrentTags $config.tags

    if ($config.vnet_definition) {
    Write-Host "`n--- Virtual network configuration ---" -ForegroundColor Cyan
    $config.vnet_definition.name = Read-StringValue -Label 'VNet name' -Current $config.vnet_definition.name -Validate {
                param($value)
                return ($value -match '^[a-zA-Z0-9-]+$')
            }

        while ($true) {
            $candidate = Read-StringValue -Label 'VNet address space (CIDR)' -Current $config.vnet_definition.address_space -Validate { param($value) Test-CidrNotation -CidrValue $value }
            $subscriptionId = if ($config.subscription_id) { $config.subscription_id } elseif ($env:ARM_SUBSCRIPTION_ID) { $env:ARM_SUBSCRIPTION_ID } else { $null }
            $hasConflict = Test-AzureNetworkConflict -AddressSpace $candidate -SubscriptionId $subscriptionId
            if ($hasConflict) {
                $retry = Read-BoolValue -Label 'Conflict detected. Enter a different address space?' -Current $true
                if ($retry) {
                    continue
                }
            }
            $config.vnet_definition.address_space = $candidate
            break
        }

        foreach ($key in $config.vnet_definition.subnets.Keys) {
            $subnet = $config.vnet_definition.subnets[$key]
            $subnet.name = Read-StringValue -Label "Subnet '$key' display name" -Current $subnet.name -Validate {
                    param($value)
                    return ($value -match '^[a-zA-Z0-9-]+$')
                }
            while ($true) {
                $candidate = Read-StringValue -Label "Subnet '$key' address prefix" -Current $subnet.address_prefix -Validate { param($value) Test-CidrNotation -CidrValue $value }
                $subnet.address_prefix = $candidate
                if (Test-SubnetsWithinAddressSpace -AddressSpace $config.vnet_definition.address_space -Subnets $config.vnet_definition.subnets) {
                    break
                }
                Write-Host 'Subnet configuration invalid. Please re-enter values.' -ForegroundColor Yellow
            }
        }
    }

    if ($config.genai_storage_account_definition) {
    Write-Host "`n--- GenAI storage account options ---" -ForegroundColor Cyan
    $config.genai_storage_account_definition.shared_access_key_enabled = Read-BoolValue -Label 'Enable shared access keys' -Current $config.genai_storage_account_definition.shared_access_key_enabled
    $config.genai_storage_account_definition.default_to_oauth_authentication = Read-BoolValue -Label 'Default to OAuth authentication' -Current $config.genai_storage_account_definition.default_to_oauth_authentication
    $config.genai_storage_account_definition.public_network_access_enabled = Read-BoolValue -Label 'Enable public network access' -Current $config.genai_storage_account_definition.public_network_access_enabled
    }

    if ($config.genai_container_registry_definition) {
    Write-Host "`n--- Container registry options ---" -ForegroundColor Cyan
    $config.genai_container_registry_definition.zone_redundancy_enabled = Read-BoolValue -Label 'Enable zone redundancy for ACR' -Current $config.genai_container_registry_definition.zone_redundancy_enabled
    }

    if ($config.bastion_definition) {
    $config.bastion_definition.deploy = Read-BoolValue -Label 'Deploy Azure Bastion' -Current $config.bastion_definition.deploy
    }

    if ($config.firewall_definition) {
    $config.firewall_definition.deploy = Read-BoolValue -Label 'Deploy Azure Firewall' -Current $config.firewall_definition.deploy
    }

    if ($config.app_gateway_definition) {
    $config.app_gateway_definition.deploy = Read-BoolValue -Label 'Deploy Application Gateway' -Current $config.app_gateway_definition.deploy
    }

    $updated = $content

    $subscriptionValue = if ($config.subscription_id) { ('"{0}"' -f $config.subscription_id) } else { 'null' }
    $subscriptionLine = ('subscription_id            = {0} # Provide subscription_id via TF_VAR_subscription_id / ARM_SUBSCRIPTION_ID or update locally.' -f $subscriptionValue)
    $updated = [regex]::Replace($updated, '(?m)^subscription_id\s*=.*$', $subscriptionLine)

    $updated = [regex]::Replace($updated, '(?m)^location\s*=.*$', ('location                   = "{0}"' -f $config.location))
    $updated = [regex]::Replace($updated, '(?m)^project_code\s*=.*$', ('project_code               = "{0}"' -f $config.project_code))
    $updated = [regex]::Replace($updated, '(?m)^environment_code\s*=.*$', ('environment_code           = "{0}"' -f $config.environment_code))
    $updated = [regex]::Replace($updated, '(?m)^naming_prefix\s*=.*$', ('naming_prefix              = "{0}" # Change this to replace the default "azr" prefix applied to every generated resource name.' -f $config.naming_prefix))
    $updated = [regex]::Replace($updated, '(?m)^resource_group_name\s*=.*$', ('resource_group_name        = "{0}"' -f $config.resource_group_name))
    $updated = [regex]::Replace($updated, '(?m)^resource_group_version\s*=.*$', ('resource_group_version     = {0}' -f $config.resource_group_version))
    $updated = [regex]::Replace($updated, '(?m)^enable_telemetry\s*=.*$', ('enable_telemetry           = {0}' -f ($(if ($config.enable_telemetry) { 'true' } else { 'false' }))))
    $updated = [regex]::Replace($updated, '(?m)^flag_platform_landing_zone\s*=.*$', ('flag_platform_landing_zone = {0}' -f ($(if ($config.flag_platform_landing_zone) { 'true' } else { 'false' }))))
    $updated = [regex]::Replace($updated, '(?m)^vm_size\s*=.*$', ('vm_size = "{0}"' -f $config.vm_size))

    $tagsBlock = Format-TagsBlock -Tags $config.tags
    $updated = [regex]::Replace($updated, "(?ms)^tags\s*=\s*(?:null|{.*?})", $tagsBlock)

    if ($config.vnet_definition) {
    $updated = Set-HclBlockText -Content $updated -BlockName 'vnet_definition' -NewBlockText (Format-VnetBlock -VnetConfig $config.vnet_definition)
    }

    if ($config.genai_storage_account_definition) {
        $updated = Set-HclBlockProperty -Content $updated -BlockName 'genai_storage_account_definition' -PropertyName 'shared_access_key_enabled' -NewValue $(if ($config.genai_storage_account_definition.shared_access_key_enabled) { 'true' } else { 'false' })
        $updated = Set-HclBlockProperty -Content $updated -BlockName 'genai_storage_account_definition' -PropertyName 'default_to_oauth_authentication' -NewValue $(if ($config.genai_storage_account_definition.default_to_oauth_authentication) { 'true' } else { 'false' })
        $updated = Set-HclBlockProperty -Content $updated -BlockName 'genai_storage_account_definition' -PropertyName 'public_network_access_enabled' -NewValue $(if ($config.genai_storage_account_definition.public_network_access_enabled) { 'true' } else { 'false' })
    }

    if ($config.genai_container_registry_definition) {
        $updated = Set-HclBlockProperty -Content $updated -BlockName 'genai_container_registry_definition' -PropertyName 'zone_redundancy_enabled' -NewValue $(if ($config.genai_container_registry_definition.zone_redundancy_enabled) { 'true' } else { 'false' })
    }

    if ($config.bastion_definition) {
        $updated = Set-HclBlockProperty -Content $updated -BlockName 'bastion_definition' -PropertyName 'deploy' -NewValue $(if ($config.bastion_definition.deploy) { 'true' } else { 'false' })
    }

    if ($config.firewall_definition) {
        $updated = Set-HclBlockProperty -Content $updated -BlockName 'firewall_definition' -PropertyName 'deploy' -NewValue $(if ($config.firewall_definition.deploy) { 'true' } else { 'false' })
    }

    if ($config.app_gateway_definition) {
        $updated = Set-HclBlockProperty -Content $updated -BlockName 'app_gateway_definition' -PropertyName 'deploy' -NewValue $(if ($config.app_gateway_definition.deploy) { 'true' } else { 'false' })
    }

    if ($updated -ne $content) {
        Set-Content -Path $configPath -Value $updated -Encoding UTF8
    Write-Host "`nUpdated landingzone.defaults.auto.tfvars" -ForegroundColor Green
    }
    else {
    Write-Host "`nNo changes were made." -ForegroundColor Yellow
    }
}

if ($TenantId) {
    Set-TerraformEnvironmentVariable -Name "ARM_TENANT_ID" -Value $TenantId -Persist:$Persist
}

if ($ClientId) {
    Set-TerraformEnvironmentVariable -Name "ARM_CLIENT_ID" -Value $ClientId -Persist:$Persist
}

if ($ClientSecret) {
    Set-TerraformEnvironmentVariable -Name "ARM_CLIENT_SECRET" -Value $ClientSecret -Persist:$Persist
}

if ($EnableAzureAd) {
    Set-TerraformEnvironmentVariable -Name "ARM_USE_AZUREAD" -Value "true" -Persist:$Persist
}

if ($DisableStorageKeyUsage) {
    Set-TerraformEnvironmentVariable -Name "TF_AZURERM_DISABLE_STORAGE_KEY_USAGE" -Value "true" -Persist:$Persist
}

if ($RunParameterWizard) {
    Invoke-TerraformParameterWizard -RepoRoot $repoRoot
}

if ($ConfigureRemoteState) {
    if (-not $SubscriptionId) {
        $SubscriptionId = Read-RequiredInput -Prompt "Enter Azure subscription ID" -CurrentValue $null
    }

    if (-not $SubscriptionId) {
        throw "SubscriptionId is required when ConfigureRemoteState is enabled."
    }

    $az = Get-Command az -ErrorAction SilentlyContinue
    if (-not $az) {
        throw "Azure CLI (az) is required to configure remote state."
    }

    if ([string]::IsNullOrWhiteSpace($OrgPrefix)) {
        throw "OrgPrefix cannot be empty."
    }
    $OrgPrefix = $OrgPrefix.ToLowerInvariant()

    $Project = Read-RequiredInput -Prompt "Enter project code (2-6 characters)" -CurrentValue $Project
    $Project = $Project.ToLowerInvariant()
    if ($Project -notmatch '^[a-z0-9]{2,6}$') {
        throw "Project code must be 2-6 lowercase letters or digits."
    }

    $Environment = Read-RequiredInput -Prompt "Enter environment code (tst|qlt|prd)" -CurrentValue $Environment
    $Environment = $Environment.ToLowerInvariant()
    if ($Environment -notin @("tst", "qlt", "prd")) {
        throw "Environment must be one of: tst, qlt, prd."
    }

    $Location = Read-RequiredInput -Prompt "Enter Azure region (e.g. eastus)" -CurrentValue $Location
    $Location = ($Location -replace "\s", "").ToLowerInvariant()

    if ($ResourceGroupVersion -lt 1) {
        throw "ResourceGroupVersion must be greater than or equal to 1."
    }

    if ($StorageAccountIndex -lt 1) {
        throw "StorageAccountIndex must be greater than or equal to 1."
    }

    if (-not $Descriptor) {
        $descriptorInput = Read-Host "Optional descriptor (press Enter to skip)"
        $Descriptor = [string]::IsNullOrWhiteSpace($descriptorInput) ? $null : $descriptorInput
    }

    if ($Descriptor) {
        $Descriptor = $Descriptor.ToLowerInvariant()
    }

    if (-not $StateResourceGroup) {
        $generatedRg = New-LandingZoneName -Project $Project -Environment $Environment -Location $Location -ResourceType "resource_group" -Descriptor $Descriptor -OrgPrefix $OrgPrefix -ResourceGroupVersion $ResourceGroupVersion
        $rgResponse = Read-Host "Use generated resource group '$generatedRg'? (Y/n)"
        if ($rgResponse -match '^(n|no)$') {
            $StateResourceGroup = Read-RequiredInput -Prompt "Enter the resource group name for Terraform state" -CurrentValue $null
        } else {
            $StateResourceGroup = $generatedRg
        }
    }

    if (-not $StateStorageAccount) {
        $generatedStorage = New-LandingZoneName -Project $Project -Environment $Environment -Location $Location -ResourceType "storage_account" -Descriptor $Descriptor -OrgPrefix $OrgPrefix -Index $StorageAccountIndex
        if ($generatedStorage.Length -lt 3) {
            throw "Generated storage account name is too short. Provide StorageAccountIndex or explicit name."
        }
        $stResponse = Read-Host "Use generated storage account '$generatedStorage'? (Y/n)"
        if ($stResponse -match '^(n|no)$') {
            $StateStorageAccount = Read-RequiredInput -Prompt "Enter the storage account name for Terraform state" -CurrentValue $null
        } else {
            $StateStorageAccount = $generatedStorage
        }
    }

    if ([string]::IsNullOrWhiteSpace($StateResourceGroup)) {
        throw "Resource group name cannot be empty."
    }
    $StateResourceGroup = $StateResourceGroup.ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($StateStorageAccount)) {
        throw "Storage account name cannot be empty."
    }
    $StateStorageAccount = $StateStorageAccount.ToLowerInvariant()

    if ($StateStorageAccount.Length -lt 3 -or $StateStorageAccount.Length -gt 24 -or ($StateStorageAccount -match "[^0-9a-z]")) {
        throw "Storage account name must be 3-24 characters, lowercase alphanumeric only."
    }

    if (-not $StateContainerName) {
        $StateContainerName = "tfstate"
    }
    $StateContainerName = $StateContainerName.ToLowerInvariant()
    if ($StateContainerName -notmatch '^[a-z0-9-]{3,63}$') {
        throw "Container name must be 3-63 characters (letters, numbers, dashes)."
    }

    & az account set --subscription $SubscriptionId | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set Azure subscription context."
    }

    & az account show --query "id" -o tsv | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI session not authenticated. Run ./scripts/azure-login-devicecode.ps1 and retry."
    }

    if ($CreateResources) {
        $rgExistsOutput = & az group exists --name $StateResourceGroup
        $rgExists = ($rgExistsOutput | Out-String).Trim().ToLowerInvariant()
        if ($rgExists -ne "true") {
            Write-Host "Creating resource group $StateResourceGroup..." -ForegroundColor Cyan
            & az group create --name $StateResourceGroup --location $Location --only-show-errors | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create resource group $StateResourceGroup."
            }
        }

        & az storage account show --name $StateStorageAccount --resource-group $StateResourceGroup --only-show-errors | Out-Null
        $storageExists = $LASTEXITCODE -eq 0
        if (-not $storageExists) {
            Write-Host "Creating storage account $StateStorageAccount..." -ForegroundColor Cyan
            & az storage account create --name $StateStorageAccount --resource-group $StateResourceGroup --location $Location --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false --min-tls-version TLS1_2 --https-only true --only-show-errors | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create storage account $StateStorageAccount."
            }
        }

        $containerCheck = & az storage container exists --name $StateContainerName --account-name $StateStorageAccount --auth-mode login --query "exists" -o tsv
        if ((($containerCheck | Out-String).Trim().ToLowerInvariant()) -ne "true") {
            Write-Host "Creating blob container $StateContainerName..." -ForegroundColor Cyan
            & az storage container create --name $StateContainerName --account-name $StateStorageAccount --auth-mode login --public-access off --only-show-errors | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create container $StateContainerName."
            }
        }
    }

    Grant-StorageDataRoles -ResourceGroup $StateResourceGroup -StorageAccount $StateStorageAccount -ClientId $ClientId -AssignRole $AssignBlobDataRole -Roles @("Storage Blob Data Contributor", "Storage Queue Data Contributor")

    $backendDirectory = Split-Path -Parent $BackendFilePath
    if (-not (Test-Path -Path $backendDirectory)) {
        New-Item -Path $backendDirectory -ItemType Directory -Force | Out-Null
    }

    $backendLines = @(
        'terraform {',
        '  backend "azurerm" {',
        "    resource_group_name   = `"$StateResourceGroup`"",
        "    storage_account_name  = `"$StateStorageAccount`"",
        "    container_name        = `"$StateContainerName`""
    )

    if ($SubscriptionId) {
        $backendLines += "    subscription_id      = `"$SubscriptionId`""
    }

    if ($TenantId) {
        $backendLines += "    tenant_id             = `"$TenantId`""
    }

    $backendLines += "    key                   = `"ai-landing-zone.tfstate`""

    if ($EnableAzureAd) {
        $backendLines += "    use_azuread_auth      = true"
    }

    $backendLines += '  }'
    $backendLines += '}'

    $backendContent = ($backendLines -join [Environment]::NewLine) + [Environment]::NewLine

    $existingContent = if (Test-Path -Path $BackendFilePath) { Get-Content -Path $BackendFilePath -Raw } else { $null }
    if ($existingContent -ne $backendContent) {
        Set-Content -Path $BackendFilePath -Value $backendContent -Encoding UTF8
        $backendFileName = Split-Path -Leaf $BackendFilePath
        Write-Host "Configured $backendFileName for Azure Storage remote state." -ForegroundColor Green
    } else {
        Write-Host "Existing backend configuration already matches requested settings." -ForegroundColor Green
    }
}

if ($SubscriptionId) {
    Set-TerraformEnvironmentVariable -Name "ARM_SUBSCRIPTION_ID" -Value $SubscriptionId -Persist:$Persist
}

Write-Host "Environment variables updated for Terraform deployment." -ForegroundColor Cyan
