param(
  [string]$ProjectDir = "D:\microsoft\GENAI-LandingZone\microsoft-ai-landingzone",
  [string]$TerraformPath = "D:\tools\terraform\terraform.exe",
  [string]$PlanFile = "plan.tfplan",
  [string]$VarFile = $null,
  [string]$Workspace = $null,
  [switch]$Apply,
  [switch]$AutoApprove
)

$ErrorActionPreference = "Stop"
$sw = [Diagnostics.Stopwatch]::StartNew()

function Exec($File, $Args) {
  Write-Host "`n> $File $($Args -join ' ')" -ForegroundColor Cyan
  & $File @Args
  $code = $LASTEXITCODE
  if ($null -eq $code) { $code = 0 }
  if ($code -ne 0) {
    throw "Command failed ($code): $File $($Args -join ' ')"
  }
}

try {
  if (-not (Test-Path $TerraformPath)) { throw "Terraform not found at '$TerraformPath'." }
  if (-not (Test-Path $ProjectDir))    { throw "ProjectDir '$ProjectDir' not found." }

  Set-Location $ProjectDir
  Write-Host "Working dir: $(Get-Location)" -ForegroundColor Green

  # Quick sanity
  Exec $TerraformPath @("-version")

  if ($Workspace) {
    $current = & $TerraformPath workspace show 2>$null
    if ($LASTEXITCODE -ne 0 -or $current -ne $Workspace) {
      & $TerraformPath workspace select $Workspace 2>$null
      if ($LASTEXITCODE -ne 0) { Exec $TerraformPath @("workspace","new",$Workspace) }
    }
  }

  Exec $TerraformPath @("init","-upgrade")
  Exec $TerraformPath @("validate","-no-color")

  $planArgs = @("plan","-out",$PlanFile)
  if ($VarFile) {
    if (-not (Test-Path $VarFile)) { throw "-VarFile '$VarFile' not found." }
    $planArgs += @("-var-file",$VarFile)
  } else {
    $tfvars = Get-ChildItem -Recurse -Include *.tfvars -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($tfvars) {
      Write-Host "Using var-file: $($tfvars.FullName)" -ForegroundColor Yellow
      $planArgs += @("-var-file",$tfvars.FullName)
    }
  }

  Exec $TerraformPath $planArgs
  Write-Host "`nPlan saved: $PlanFile" -ForegroundColor Green

  if ($Apply) {
    $applyArgs = @("apply",$PlanFile)
    if ($AutoApprove) { $applyArgs += "-auto-approve" }
    Exec $TerraformPath $applyArgs
    Write-Host "Apply complete." -ForegroundColor Green
  } else {
    Write-Host "To apply: terraform apply $PlanFile" -ForegroundColor Yellow
  }
}
catch {
  Write-Error $_.Exception.Message
  exit 1
}
finally {
  $sw.Stop(); Write-Host "Total time: $([int]$sw.Elapsed.TotalSeconds)s"
}
