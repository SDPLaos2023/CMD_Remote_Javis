<#
.SYNOPSIS
    BB_JAVIS Enterprise Admin API Key & RSA Identity Generator
    Generates per-Admin HMAC-SHA256 API Key and DPAPI-protected RSA-2048 keypair.
#>

[CmdletBinding()]
param(
    [string]$Tenant = "sdp",
    [string]$AdminId = "",
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

$payload = "adm:$cleanTenant`:$cleanAdmin`:$timeHex"
$hmac = New-Object System.Security.Cryptography.HMACSHA256
try {
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($MasterSecret)
    $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
    $hashHex = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
    $signature = $hashHex.Substring(0, 32)
} finally {
    $hmac.Dispose()
}

$apiKey = "bbj_adm_${cleanTenant}_${cleanAdmin}_${timeHex}_${signature}"

Write-Host "  -> Tenant      : $cleanTenant" -ForegroundColor Green
Write-Host "  -> Admin ID    : $cleanAdmin" -ForegroundColor Cyan
Write-Host "  -> Created At  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Generated Admin API Key:" -ForegroundColor Cyan
Write-Host "  $apiKey" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray

if ($CopyToClipboard.IsPresent) {
    try {
        Set-Clipboard -Value $apiKey
        Write-Host "  [OK] Copied Admin API Key to clipboard." -ForegroundColor Green
    } catch {}
}

if ($SaveToThisMachine.IsPresent) {
    $configDir = Join-Path $env:LOCALAPPDATA "BB_Javis"
    if (-not (Test-Path $configDir)) {
        $null = New-Item -ItemType Directory -Path $configDir -Force
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $privFile = Join-Path $configDir "admin_key.dpapi"
    $pubFile = Join-Path $configDir "admin_pub.xml"

    if (-not (Test-Path $privFile) -or -not (Test-Path $pubFile)) {
        $pair = New-JavisRsaKeyPair
        $encPriv = Protect-JavisLocalSecret -PlainText $pair.PrivateXml -Scope "CurrentUser"
        [System.IO.File]::WriteAllText($privFile, $encPriv, $utf8NoBom)
        [System.IO.File]::WriteAllText($pubFile, $pair.PublicXml, $utf8NoBom)
        Write-Host "  [KEYPAIR] Generated DPAPI-protected RSA-2048 Admin keypair." -ForegroundColor Green
    }

    $configFile = Join-Path $configDir "config.json"
    $existingGw = ""
    if (Test-Path $configFile) {
        try {
            $old = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($old -and $old.gatewayUrl) { $existingGw = $old.gatewayUrl }
        } catch {}
    }
    $finalGw = if (-not [string]::IsNullOrWhiteSpace($GatewayUrl)) { $GatewayUrl.Trim().TrimEnd('/') + "/" } else { $existingGw }

    $configData = @{
        apiKey     = $apiKey
        tenantId   = $cleanTenant
        adminId    = $cleanAdmin
        gatewayUrl = $finalGw
        savedAt    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    }
    [System.IO.File]::WriteAllText($configFile, ($configData | ConvertTo-Json -Depth 5), $utf8NoBom)
    Write-Host "  [SAVED] Admin profile saved to: $configFile" -ForegroundColor Green
}

Write-Host "======================================================================" -ForegroundColor DarkCyan
return $apiKey
