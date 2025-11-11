param([string]$FilePath)

$errors = @()
$content = Get-Content $FilePath -Raw
[void][System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)

if ($errors.Count -gt 0) {
    Write-Host "Syntax errors found:" -ForegroundColor Red
    $errors | ForEach-Object {
        Write-Host ""
        Write-Host "Line $($_.Token.StartLine), Column $($_.Token.StartColumn):" -ForegroundColor Yellow
        Write-Host "  $($_.Message)" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "OK - No syntax errors found" -ForegroundColor Green
    exit 0
}
