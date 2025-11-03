param(
  [string]$ProjectDir    = "D:\microsoft\GENAI-LandingZone\microsoft-ai-landingzone",
  [string]$TerraformPath = "D:\tools\terraform\terraform.exe",
  [string]$PlanFile      = "plan.out",
  [switch]$Apply,                 # add -Apply to actually deploy
  [switch]$AutoApprove,           # add with -Apply to skip prompt
  [string]$VarFile = $null,       # e.g. .\env\dev.tfvars
  [string]$Workspace = $null      # e.g. dev / prod
)

$ErrorActionPreference = "Stop"
$ts = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
$Artifacts = Join-Path $ProjectDir "artifacts"
New-Item -ItemType Directory -Path $Artifacts -Force | Out-Null

function Exec([string]$File, [string[]]$Arguments) {
  Write-Host "`n> $File $($Arguments -join ' ')" -ForegroundColor Cyan
  & $File @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $File $($Arguments -join ' ')" }
}

# --- 0) Pre-checks ---
if (-not (Test-Path $TerraformPath)) { throw "Terraform not found at '$TerraformPath'." }
if (-not (Test-Path $ProjectDir))    { throw "ProjectDir '$ProjectDir' not found." }
Set-Location $ProjectDir

# --- 1) (Optional) workspace ---
if ($Workspace) {
  & $TerraformPath workspace select $Workspace 2>$null
  if ($LASTEXITCODE -ne 0) { Exec $TerraformPath @("workspace","new",$Workspace) }
}

# --- 2) init / validate ---
Exec $TerraformPath @("init","-upgrade")
Exec $TerraformPath @("validate","-no-color")

# --- 3) plan (binary) ---
$planArgs = @("plan","-out=$PlanFile")
if ($VarFile) {
  if (-not (Test-Path $VarFile)) { throw "-VarFile '$VarFile' not found." }
  $planArgs += @("-var-file",$VarFile)
}
Exec $TerraformPath $planArgs

# --- 4) export plan JSON (pre-apply) ---
$PlanJson = Join-Path $Artifacts ("plan_$ts.json")
# Capture and save plan JSON (pre-apply)
$planJsonContent = & $TerraformPath show -json $PlanFile
$planJsonContent | Set-Content -Encoding UTF8 $PlanJson
Write-Host "Saved pre-apply plan JSON: $PlanJson" -ForegroundColor Green
# --- 5) apply (optional) ---
if ($Apply) {
  $applyArgs = @("apply",$PlanFile)
  if ($AutoApprove) { $applyArgs += "-auto-approve" }
  Exec $TerraformPath $applyArgs
  Write-Host "Apply completed." -ForegroundColor Green
} else {
  Write-Host "Skipping apply (run with -Apply to deploy)." -ForegroundColor Yellow
}

# --- 6) export post-deploy artifacts ---
# Current state JSON (as-built source of truth)
$StateJson = Join-Path $Artifacts ("state_$ts.json")
$stateJsonContent = & $TerraformPath show -json
$stateJsonContent | Set-Content -Encoding UTF8 $StateJson
Write-Host "Saved post-apply state JSON: $StateJson" -ForegroundColor Green

# Outputs as JSON (handy for test plans & pipelines)
$OutputsJson = Join-Path $Artifacts ("outputs_$ts.json")
$OutputsJson = Join-Path $Artifacts ("outputs_$ts.json")
$outputsContent = $null
$outputsContent = & $TerraformPath output -json 2>&1
if ($LASTEXITCODE -eq 0 -and $outputsContent) {
  $outputsContent | Set-Content -Encoding UTF8 $OutputsJson
  Write-Host "Saved outputs JSON: $OutputsJson" -ForegroundColor Green
} elseif ($LASTEXITCODE -ne 0) {
  Write-Host "Error running 'terraform output -json': $outputsContent" -ForegroundColor Yellow
}
# Graph (DOT) for architecture diagrams (optional PNG if Graphviz exists)
$GraphDot = Join-Path $Artifacts ("graph_$ts.dot")
& $TerraformPath graph | Set-Content -Encoding UTF8 $GraphDot
try {
  if (-not $stateJsonContent) { throw "State JSON content is empty or invalid." }
  $state = $stateJsonContent | ConvertFrom-Json
  $resources = @()
  if ($state.values -and $state.values.root_module) {
    if ($state.values.root_module.resources) { $resources += $state.values.root_module.resources }
    if ($state.values.root_module.child_modules) {
      foreach ($cm in $state.values.root_module.child_modules) {
        if ($cm.resources) { $resources += $cm.resources }
      }
    }
  }
  $byType = $resources | Group-Object type | Sort-Object Count -Descending

  $lines = @()
  $lines += "# As-Built Report ($ts)"
  $lines += ""
  $lines += "## Summary"
  $lines += "- Workspace: $Workspace"
  $lines += "- Plan file: $PlanFile"
  $lines += "- Pre-apply plan JSON: $(Split-Path $PlanJson -Leaf)"
  $lines += "- Post-apply state JSON: $(Split-Path $StateJson -Leaf)"
  if (Test-Path $OutputsJson) { $lines += "- Outputs JSON: $(Split-Path $OutputsJson -Leaf)" }
  $lines += "- Graph: $(Split-Path $GraphDot -Leaf)"
  $lines += ""
  $lines += "## Resource Inventory"
  foreach ($g in $byType) {
    $lines += "- **$($g.Name)**: $($g.Count)"
  }
  $lines += ""
  $lines += "## Key Outputs"
  if (Test-Path $OutputsJson) {
    $outs = Get-Content $OutputsJson | ConvertFrom-Json
    foreach ($k in $outs.PSObject.Properties.Name) {
      $outputObj = $outs.$k
      $val = $null
      if ($outputObj.PSObject.Properties.Match('value')) {
        $val = $outputObj.value
        if ($val -is [array]) { $val = ($val -join ', ') }
      } else {
        $val = "<no value property>"
      }
      $lines += "- **$k**: $val"
    }
  } else {
    $lines += "_No outputs declared._"
  }
  $AsBuiltMd = Join-Path $Artifacts ("as-built_$ts.md")
  $lines | Set-Content -Encoding UTF8 $AsBuiltMd
  Write-Host "Saved As-Built Markdown: $AsBuiltMd" -ForegroundColor Green
} catch {
  Write-Host "As-Built generation skipped (parse issue): $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`nArtifacts folder:`n$Artifacts" -ForegroundColor Cyan
Write-Host "Done."
