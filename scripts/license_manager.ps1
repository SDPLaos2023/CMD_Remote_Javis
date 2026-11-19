<#
.SYNOPSIS
    BB_JAVIS Owner License Manager
    Issue, inspect, and revoke team license keys (JAVIS-XXXX-XXXX-XXXX).
    Requires an Owner Key (bbj_own_*) or JAVIS_MASTER_SECRET.
#>

[CmdletBinding()]
param(
    [switch]$Issue,
    [switch]$List,
    [switch]$Revoke,
    [string]$TeamUser = "",
    [int]$MaxDevices = 1,
    [int]$ExpireDays = 0,
    [string]$Note = "",
    [string]$LicenseKey = "",
    [string]$Tenant = "sdp",
    [string]$GatewayUrl = "",
    [string]$MasterSecret = ""
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}

$cryptoLib = Join-Path $PSScriptRoot "lib_javis_crypto.ps1"
if (-not (Test-Path $cryptoLib)) {
    throw "Missing required library: $cryptoLib"
}
. $cryptoLib

$configDir = Join-Path $env:LOCALAPPDATA "BB_Javis"
$configFile = Join-Path $configDir "config.json"
$localCfg = $null
if (Test-Path $configFile) {
    try { $localCfg = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

$baseUrl = if (-not [string]::IsNullOrWhiteSpace($GatewayUrl)) { $GatewayUrl.Trim().TrimEnd('/') + "/" }
    elseif (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_GATEWAY_URL)) { $env:BB_JAVIS_GATEWAY_URL.Trim().TrimEnd('/') + "/" }
    elseif ($localCfg -and $localCfg.gatewayUrl) { $localCfg.gatewayUrl.ToString().Trim().TrimEnd('/') + "/" }
    else { "https://bb-javis-gateway.apisit-yimboa.workers.dev/" }

$script:OwnerApiKey = if ($localCfg -and $localCfg.apiKey -and $localCfg.apiKey.ToString().StartsWith("bbj_own_")) {
    $localCfg.apiKey.ToString().Trim()
} else { "" }

$script:MasterHdr = if (-not [string]::IsNullOrWhiteSpace($MasterSecret)) {
    $MasterSecret.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_MASTER_SECRET)) {
    $env:BB_JAVIS_MASTER_SECRET.Trim()
} else { "" }

function Ensure-OwnerAuthorization {
    if ($script:OwnerApiKey -or $script:MasterHdr) { return }
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "       BB_JAVIS OWNER ACTIVATION REQUIRED (ONE-TIME UPGRADE)          " -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "Only the System Owner can issue or revoke Team License Keys." -ForegroundColor Gray
    Write-Host "Enter JAVIS_MASTER_SECRET once to promote this PC to Owner (bbj_own_*)." -ForegroundColor Cyan
    $sec = Read-Host "Enter JAVIS_MASTER_SECRET (min 16 chars)" -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        $rawMaster = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    if ([string]::IsNullOrWhiteSpace($rawMaster) -or $rawMaster.Trim().Length -lt 16) {
        throw "JAVIS_MASTER_SECRET must be at least 16 characters."
    }
    $cleanMaster = $rawMaster.Trim()
    $targetTenant = if ($localCfg -and $localCfg.tenantId) { $localCfg.tenantId.ToString() } else { $Tenant }
    $targetAdmin = if ($localCfg -and $localCfg.adminId) { $localCfg.adminId.ToString() } else { ($env:USERNAME -replace "[^a-zA-Z0-9-]", "").ToLower() }
    if ([string]::IsNullOrWhiteSpace($targetAdmin)) { $targetAdmin = "owner" }

    $genScript = Join-Path $PSScriptRoot "gen_javis_key.ps1"
    $mintedKey = & $genScript -Tenant $targetTenant -AdminId $targetAdmin -Role "own" -MasterSecret $cleanMaster -GatewayUrl $baseUrl -SaveToThisMachine
    if ($mintedKey -is [array]) { $mintedKey = $mintedKey[-1] }
    $script:OwnerApiKey = $mintedKey.ToString().Trim()
    $script:MasterHdr = $cleanMaster
}

function Invoke-OwnerLicenseApi {
    param(
        [string]$Path,
        [string]$Method = "GET",
        [hashtable]$Body = $null
    )
    Ensure-OwnerAuthorization
    $uri = $baseUrl + $Path.TrimStart('/')
    if ($script:MasterHdr -and -not $script:OwnerApiKey) {
        $sep = if ($uri.Contains("?")) { "&" } else { "?" }
        $uri = "$uri${sep}tenant=$([Uri]::EscapeDataString($Tenant))"
    }

    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method = $Method
    $req.Timeout = 15000
    $req.ReadWriteTimeout = 15000
    if ($script:OwnerApiKey) {
        $req.Headers["X-Javis-Key"] = $script:OwnerApiKey
    } else {
        $req.Headers["X-Master-Secret"] = $script:MasterHdr
    }

    if ($Body) {
        $json = $Body | ConvertTo-Json -Depth 4 -Compress
        $bytes = $utf8NoBom.GetBytes($json)
        $req.ContentType = "application/json; charset=utf-8"
        $req.ContentLength = $bytes.Length
        $st = $req.GetRequestStream()
        try { $st.Write($bytes, 0, $bytes.Length) } finally { $st.Close() }
    }

    try {
        $resp = $req.GetResponse()
        $rd = New-Object System.IO.StreamReader($resp.GetResponseStream(), $utf8NoBom)
        $out = $rd.ReadToEnd()
        $rd.Close(); $resp.Close()
        return ($out | ConvertFrom-Json)
    } catch [System.Net.WebException] {
        $webResp = $_.Exception.Response
        if ($webResp) {
            $rd = New-Object System.IO.StreamReader($webResp.GetResponseStream(), $utf8NoBom)
            $errRaw = $rd.ReadToEnd()
            $rd.Close(); $webResp.Close()
            $errObj = $errRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
            $msg = if ($errObj -and $errObj.message) { $errObj.message } elseif ($errObj -and $errObj.error) { $errObj.error } else { $errRaw }
            throw "License API Error: $msg"
        }
        throw $_
    }
}

function Invoke-IssueLicenseFlow {
    param([string]$User, [int]$MaxDev, [int]$ExpDays, [string]$NoteText)
    if ([string]::IsNullOrWhiteSpace($User)) {
        $User = (Read-Host "Enter Teammate Name / Admin ID (e.g. somchai)").Trim()
    }
    if ([string]::IsNullOrWhiteSpace($User)) { throw "TeamUser is required." }

    $res = Invoke-OwnerLicenseApi -Path "admin/licenses/issue" -Method "POST" -Body @{
        team_user   = $User
        max_devices = $MaxDev
        expire_days = $ExpDays
        note        = $NoteText
    }

    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "                BB_JAVIS TEAM LICENSE KEY ISSUED                      " -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "  -> License Key : " -NoNewline -ForegroundColor Gray
    Write-Host $res.license_key -ForegroundColor Yellow
    Write-Host "  -> Team User   : $($res.team_user) (Tenant: $($res.tenant))" -ForegroundColor White
    Write-Host "  -> Max Devices : $($res.max_devices)" -ForegroundColor Cyan
    if ($res.expires_at -gt 0) {
        $dt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$res.expires_at).ToLocalTime().ToString("yyyy-MM-dd HH:mm")
        Write-Host "  -> Expires At  : $dt" -ForegroundColor White
    } else {
        Write-Host "  -> Expires At  : Lifetime (until revoked)" -ForegroundColor White
    }
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    try {
        Set-Clipboard -Value $res.license_key
        Write-Host "[OK] License Key copied to clipboard. Send this key to $($res.team_user)." -ForegroundColor Green
    } catch {}
}

function Invoke-ListLicensesFlow {
    $res = Invoke-OwnerLicenseApi -Path "admin/licenses" -Method "GET"
    if (-not $res.licenses -or $res.licenses.Count -eq 0) {
        Write-Host "`nNo team licenses issued yet for tenant '$($res.tenant)'." -ForegroundColor Yellow
        return
    }
    $rows = $res.licenses | ForEach-Object {
        $expStr = if ($_.expires_at -gt 0) {
            [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$_.expires_at).ToLocalTime().ToString("yyyy-MM-dd")
        } else { "Lifetime" }
        $machList = if ($_.machines -and $_.machines.Count -gt 0) {
            ($_.machines | ForEach-Object { $_.machine_name }) -join ", "
        } else { "-" }
        [PSCustomObject]@{
            LicenseKey = $_.license_key
            TeamUser   = $_.team_user
            Status     = $_.status.ToUpper()
            Devices    = "$($_.used_devices)/$($_.max_devices)"
            Expires    = $expStr
            Machines   = $machList
            Note       = $_.note
        }
    }
    $rows | Format-Table -AutoSize
}

function Invoke-RevokeLicenseFlow {
    param([string]$Code)
    if ([string]::IsNullOrWhiteSpace($Code)) {
        Invoke-ListLicensesFlow
        $Code = (Read-Host "Enter License Key to REVOKE (JAVIS-XXXX-XXXX-XXXX)").Trim()
    }
    if ([string]::IsNullOrWhiteSpace($Code)) { return }
    $res = Invoke-OwnerLicenseApi -Path "admin/licenses/revoke" -Method "POST" -Body @{ license_key = $Code }
    Write-Host "[REVOKED] $($res.license_key) disabled. Blocked admins: $($res.revoked_admins -join ', ')" -ForegroundColor Yellow
}

if ($Issue.IsPresent) {
    Invoke-IssueLicenseFlow -User $TeamUser -MaxDev $MaxDevices -ExpDays $ExpireDays -NoteText $Note
    return
}
if ($List.IsPresent) {
    Invoke-ListLicensesFlow
    return
}
if ($Revoke.IsPresent) {
    Invoke-RevokeLicenseFlow -Code $LicenseKey
    return
}

# Interactive Owner Menu
Ensure-OwnerAuthorization
while ($true) {
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "               BB_JAVIS OWNER LICENSE MANAGER                         " -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "  [1] Issue New License Key for Teammate" -ForegroundColor Green
    Write-Host "  [2] List All Issued Licenses" -ForegroundColor Cyan
    Write-Host "  [3] Revoke License Key" -ForegroundColor Red
    Write-Host "  [Q] Quit" -ForegroundColor Gray
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    $choice = (Read-Host "Select action").Trim().ToUpper()
    if ($choice -eq "Q") { break }
    elseif ($choice -eq "1") {
        $u = (Read-Host "Teammate name (e.g. somchai)").Trim()
        $mdRaw = (Read-Host "Max Dev PCs [Default: 1]").Trim()
        $md = if ($mdRaw -match "^\d+$" -and [int]$mdRaw -ge 1) { [int]$mdRaw } else { 1 }
        $edRaw = (Read-Host "Expire after days [Default: 0 = Lifetime]").Trim()
        $ed = if ($edRaw -match "^\d+$") { [int]$edRaw } else { 0 }
        $nt = (Read-Host "Note (optional)").Trim()
        Invoke-IssueLicenseFlow -User $u -MaxDev $md -ExpDays $ed -NoteText $nt
    }
    elseif ($choice -eq "2") {
        Invoke-ListLicensesFlow
    }
    elseif ($choice -eq "3") {
        Invoke-RevokeLicenseFlow -Code ""
    }
}
