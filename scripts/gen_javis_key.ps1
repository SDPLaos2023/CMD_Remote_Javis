<#
.SYNOPSIS
    BB_JAVIS Enterprise API Key Generator
    Generates HMAC-SHA256 Signed API Keys

.DESCRIPTION
    High-security stateless API Key generator without requiring database queries.
    Format: bbj_<tenant>_<timestamp>_<signature>
#>

[CmdletBinding()]
param(
    [string]$Tenant = "sdpuat",
    [string]$MasterSecret = "JAVIS_SECURE_ENTERPRISE_MASTER_KEY_2026",
    [switch]$SaveToThisMachine,
    [switch]$CopyToClipboard
)

# Force UTF-8 Encoding
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "              BB_JAVIS ENTERPRISE API KEY GENERATOR                   " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan

# 1. Clean Tenant name (a-z, 0-9 only)
$cleanTenant = ($Tenant -replace "[^a-zA-Z0-9]", "").ToLower()
if ([string]::IsNullOrWhiteSpace($cleanTenant)) {
    $cleanTenant = "default"
}

# 2. Compute Hex Unix Epoch timestamp
$unixTime = [int][double]::Parse((Get-Date -UFormat %s))
$timeHex = $unixTime.ToString("x8")

# 3. Compute HMAC-SHA256 signature
$payload = "$cleanTenant`:$timeHex"
$hmac = New-Object System.Security.Cryptography.HMACSHA256
$hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($MasterSecret)
$hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
$hashHex = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
$signature = $hashHex.Substring(0, 32)

# 4. Assemble BB_JAVIS API Key
$apiKey = "bbj_${cleanTenant}_${timeHex}_${signature}"

Write-Host "  -> Tenant Name : " -NoNewline -ForegroundColor Gray
Write-Host $cleanTenant -ForegroundColor Green
Write-Host "  -> Created At  : " -NoNewline -ForegroundColor Gray
Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor White
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Generated API Key:" -ForegroundColor Cyan
Write-Host "  $apiKey" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray

# 5. Optional Clipboard Copy
if ($CopyToClipboard.IsPresent) {
    try {
        Set-Clipboard -Value $apiKey
        Write-Host "  [OK] Copied API Key to Windows Clipboard!" -ForegroundColor Green
    } catch {}
}

# 6. Optional Local Machine Persistence
if ($SaveToThisMachine.IsPresent) {
    $configDir = Join-Path $env:LOCALAPPDATA "BB_Javis"
    if (-not (Test-Path $configDir)) {
        $null = New-Item -ItemType Directory -Path $configDir -Force
    }
    $configFile = Join-Path $configDir "config.json"
    
    $configData = @{
        apiKey = $apiKey
        tenantId = $cleanTenant
        savedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        generatedBy = "gen_javis_key.ps1"
    }
    
    $json = $configData | ConvertTo-Json -Depth 5
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configFile, $json, $utf8NoBom)
    Write-Host "  [SAVED] Saved API Key to local profile: $configFile" -ForegroundColor Green
}

Write-Host "======================================================================" -ForegroundColor DarkCyan
return $apiKey
