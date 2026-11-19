<#
.SYNOPSIS
    BB_JAVIS Enterprise Admin API Key & RSA Identity Generator
    Generates per-Admin HMAC-SHA256 API Key and DPAPI-protected RSA-2048 keypair.
#>

[CmdletBinding()]
param(
    [string]$Tenant = "sdp",
    [string]$AdminId = "",
    [ValidateSet("adm", "own")][string]$Role = "adm",
    [string]$ApiKey = "",
    [string]$MasterSecret = "",
    [string]$GatewayUrl = "",
    [switch]$SaveToThisMachine,
    [switch]$CopyToClipboard
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$cryptoLib = Join-Path $PSScriptRoot "lib_javis_crypto.ps1"
if (-not (Test-Path $cryptoLib)) {
    throw "Missing required library: $cryptoLib"
}
. $cryptoLib

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "         BB_JAVIS ZERO-TRUST ADMIN KEY & IDENTITY GENERATOR           " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan

if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $saved = Save-JavisAdminProfile -ApiKey $ApiKey -GatewayUrl $GatewayUrl
    Write-Host "  -> Role        : $($saved.Role)" -ForegroundColor Cyan
    Write-Host "  -> Tenant      : $($saved.TenantId)" -ForegroundColor Green
    Write-Host "  -> Admin ID    : $($saved.AdminId)" -ForegroundColor Cyan
    Write-Host "  [SAVED] Admin profile saved to: $($saved.ConfigFile)" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    return $ApiKey.Trim()
}

$cleanTenant = ($Tenant -replace "[^a-zA-Z0-9]", "").ToLower()
if ([string]::IsNullOrWhiteSpace($cleanTenant)) { $cleanTenant = "default" }

if ([string]::IsNullOrWhiteSpace($AdminId)) {
    $AdminId = $env:USERNAME
}
$cleanAdmin = ($AdminId -replace "[^a-zA-Z0-9-]", "").ToLower()
if ([string]::IsNullOrWhiteSpace($cleanAdmin)) { $cleanAdmin = "admin" }

if ([string]::IsNullOrWhiteSpace($MasterSecret)) {
    if (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_MASTER_SECRET)) {
        $MasterSecret = $env:BB_JAVIS_MASTER_SECRET.Trim()
    } else {
        $sec = Read-Host "Enter JAVIS_MASTER_SECRET (min 16 chars)" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            $MasterSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

if ([string]::IsNullOrWhiteSpace($MasterSecret) -or $MasterSecret.Length -lt 16) {
    throw "MasterSecret must be at least 16 characters."
}

$unixTime = [int][double]::Parse((Get-Date -UFormat %s))
$timeHex = $unixTime.ToString("x8")

$payload = "${Role}:$cleanTenant`:$cleanAdmin`:$timeHex"
$hmac = New-Object System.Security.Cryptography.HMACSHA256
try {
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($MasterSecret)
    $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
    $hashHex = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
    $signature = $hashHex.Substring(0, 32)
} finally {
    $hmac.Dispose()
}

$apiKey = "bbj_${Role}_${cleanTenant}_${cleanAdmin}_${timeHex}_${signature}"

Write-Host "  -> Role        : $Role" -ForegroundColor Cyan
Write-Host "  -> Tenant      : $cleanTenant" -ForegroundColor Green
Write-Host "  -> Admin ID    : $cleanAdmin" -ForegroundColor Cyan
Write-Host "  -> Created At  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Generated API Key:" -ForegroundColor Cyan
Write-Host "  $apiKey" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray

if ($CopyToClipboard.IsPresent) {
    try {
        Set-Clipboard -Value $apiKey
        Write-Host "  [OK] Copied API Key to clipboard." -ForegroundColor Green
    } catch {}
}

if ($SaveToThisMachine.IsPresent) {
    $saved = Save-JavisAdminProfile -ApiKey $apiKey -GatewayUrl $GatewayUrl
    if ($saved.CreatedKeypair) {
        Write-Host "  [KEYPAIR] Generated DPAPI-protected RSA-2048 Admin keypair." -ForegroundColor Green
    }
    Write-Host "  [SAVED] Profile saved to: $($saved.ConfigFile)" -ForegroundColor Green
}

Write-Host "======================================================================" -ForegroundColor DarkCyan
return $apiKey
