<# :
@echo off
title CMD_Remote Command Sender
cd /d "%~dp0"
if exist "%~dp0send_remote_command.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0send_remote_command.ps1" %*
    exit /b %ERRORLEVEL%
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[scriptblock]::Create((Get-Content -Encoding UTF8 '%~f0') -join `"`n`"); & $s %*"
exit /b %ERRORLEVEL%
#>
param (
    [string]$ApiKey,
    [string]$GatewayUrl,
    [string]$FirebaseUrl = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x32, 0x2e, 0x2e, 0x2a, 0x29, 0x60, 0x75, 0x75, 0x2f, 0x3b, 0x2e, 0x77, 0x3b, 0x2a, 0x33, 0x77, 0x3b, 0x3d, 0x3f, 0x34, 0x2e, 0x77, 0x3e, 0x3f, 0x3c, 0x3b, 0x2f, 0x36, 0x2e, 0x77, 0x28, 0x2e, 0x3e, 0x38, 0x74, 0x3c, 0x33, 0x28, 0x3f, 0x38, 0x3b, 0x29, 0x3f, 0x33, 0x35, 0x74, 0x39, 0x35, 0x37, 0x75) | ForEach-Object { [byte]($_ -bxor 0x5a) })))",
    [string]$FirebaseAuthToken = "$([System.Text.Encoding]::UTF8.GetString([byte[]](@(0x3c, 0x6d, 0x0a, 0x29, 0x03, 0x2a, 0x0d, 0x69, 0x00, 0x1c, 0x11, 0x0a, 0x6b, 0x11, 0x1e, 0x3d, 0x39, 0x3e, 0x0c, 0x68, 0x3e, 0x1c, 0x0a, 0x2e, 0x3e, 0x3b, 0x32, 0x11, 0x3c, 0x38, 0x32, 0x6b, 0x10, 0x12, 0x6c, 0x32, 0x6d, 0x16, 0x63, 0x6e) | ForEach-Object { [byte]($_ -bxor 0x5a) })))",
    [string]$SecretKey,
    [string]$Mode,
    [string]$JobId,
    [string]$ConnectionString,
    [string]$DbName,
    [string]$SqlQuery,
    [string]$SqlFile,
    [string]$OutputDir,
    [string]$LocalPath,
    [string]$RemotePath,
    [string]$ExecutionMode = "turbo",
    [int]$TimeoutSec = 300,
    [switch]$List,
    [string]$TargetHost,
    [string]$TargetIp,
    [switch]$PurgeOffline
)

# Force console output encoding to UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# จัดการ Token ยืนยันสิทธิ์ฐานข้อมูล Firebase RTDB
if ([string]::IsNullOrWhiteSpace($FirebaseAuthToken)) {
    if (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_AUTH_TOKEN)) {
        $FirebaseAuthToken = $env:BB_JAVIS_AUTH_TOKEN.Trim()
    }
}
$script:FirebaseAuthToken = $FirebaseAuthToken

# Enable TLS 1.2 security protocol and connection pool limit
try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 128
    [System.Net.ServicePointManager]::Expect100Continue = $false
    [System.Net.ServicePointManager]::MaxServicePointIdleTime = 5000
} catch {}
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# กำหนด BaseUrl สำหรับ Gateway / Command Board
$BaseUrl = if (-not [string]::IsNullOrWhiteSpace($GatewayUrl)) { $GatewayUrl } else { $FirebaseUrl }
if ($BaseUrl -notlike "*/") {
    $BaseUrl = $BaseUrl + "/"
}

# ฟังก์ชันจัดการ API Key ประจำเครื่อง (Local Machine Persistence)
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

    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "                  BB_JAVIS ENTERPRISE AUTHENTICATION                  " -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "  [!] ไม่พบ API Key บนเครื่องนี้ ($configFile)" -ForegroundColor Yellow
    Write-Host "  ระบบจะบันทึกจำไว้ในเครื่องนี้อัตโนมัติ เพื่อให้ท่านไม่ต้องพิมพ์ซ้ำในครั้งต่อไป" -ForegroundColor Gray
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
    
    $inputKey = Read-Host "  กรุณาระบุ BB_JAVIS API Key (เช่น bbj_sdpuat_...)"
    if ([string]::IsNullOrWhiteSpace($inputKey)) {
        Write-Host "  [!] ไม่ได้ระบุ API Key - กำลังทำงานในโหมด Default Guest Profile" -ForegroundColor DarkYellow
        $inputKey = "bbj_guest_00000000_00000000000000000000000000000000"
    } else {
        $inputKey = $inputKey.Trim()
        try {
            if (-not (Test-Path $configDir)) { $null = New-Item -ItemType Directory -Path $configDir -Force }
            $saveObj = @{
                apiKey = $inputKey
                savedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                machine = $env:COMPUTERNAME
            }
            $json = $saveObj | ConvertTo-Json
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($configFile, $json, $utf8NoBom)
            Write-Host "  [SAVED] บันทึก API Key ลงเครื่องเรียบร้อยแล้ว!" -ForegroundColor Green
        } catch {}
    }
    Write-Host "======================================================================`n" -ForegroundColor DarkCyan
    return $inputKey
}

$script:JavisApiKey = Get-OrPromptJavisApiKey -ArgKey $ApiKey

# Native .NET HTTP Client Helper (Zero-Dependency 100% พร้อมแนบ X-Javis-Key)
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



Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " CMD_Remote Command Sender (AI and DB Mode)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Load last connection profile for convenience
$profilePath = Join-Path $env:TEMP "cmd_remote_db_profile.json"
$defaultConn = ""
if (Test-Path $profilePath) {
    try {
        $profileData = Get-Content $profilePath -Raw | ConvertFrom-Json
        $defaultConn = $profileData.ConnectionString
    } catch {}
}

# --- Fleet Presence & Device Discovery Helper ---
function Get-RegisteredDevices {
    param([string]$TargetBaseUrl)
    
    $devUrl = $TargetBaseUrl + "devices.json"
    $devList = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $raw = Invoke-FirebaseHttp -Uri $devUrl -Method "GET" -TimeoutSec 5
        if (-not [string]::IsNullOrWhiteSpace($raw) -and $raw.Trim() -ne "null" -and $raw.Trim().StartsWith("{")) {
            $data = ConvertFrom-Json -InputObject $raw.Trim() -ErrorAction SilentlyContinue
            if ($data -and $data -is [System.Management.Automation.PSCustomObject]) {
                $nowUtc = [DateTime]::UtcNow
                foreach ($prop in $data.PSObject.Properties) {
                    $d = $prop.Value
                    if ($d) {
                        $pin = $(if ($d.pin) { $d.pin.ToString() } else { $prop.Name })
                        $hostname = $(if ($d.hostname) { $d.hostname.ToString() } else { "Unknown" })
                        $customName = $(if ($d.custom_name) { $d.custom_name.ToString() } else { $hostname })
                        $displayName = $(if ($customName -and $customName -ne $hostname) { "$customName ($hostname)" } else { $hostname })
                        $localIp = $(if ($d.local_ip) { $d.local_ip.ToString() } else { "-" })
                        $publicIp = $(if ($d.public_ip) { $d.public_ip.ToString() } else { "-" })
                        $os = $(if ($d.os_version) { $d.os_version.ToString() } else { "Windows" })
                        $isSvc = $(if ($d.service_mode) { $true } else { $false })
                        $lastHbStr = $d.last_heartbeat

                        $ageSec = 0
                        $lastSeenText = "Just now"
                        $hasValidHb = $false
                        if ($lastHbStr) {
                            try {
                                $dt = [DateTime]::Parse($lastHbStr).ToUniversalTime()
                                $diff = $nowUtc - $dt
                                $ageSec = [int]$diff.TotalSeconds
                                $hasValidHb = $true
                                if ($ageSec -lt 60) {
                                    $lastSeenText = "${ageSec}s ago"
                                } elseif ($ageSec -lt 3600) {
                                    $lastSeenText = "$([int]($ageSec/60))m ago"
                                } elseif ($ageSec -lt 86400) {
                                    $lastSeenText = "$([int]($ageSec/3600))h ago"
                                } else {
                                    $lastSeenText = "$([int]($ageSec/86400))d ago"
                                }
                            } catch {}
                        }

                        # ลบเครื่อง Offline ที่ค้างนานเกิน 24 ชั่วโมง (86400s) ออกจาก Cloud อัตโนมัติ (Housekeeping)
                        if ($hasValidHb -and $ageSec -gt 86400) {
                            try {
                                $delDevUrl = $TargetBaseUrl + "devices/$pin.json"
                                $null = Invoke-FirebaseHttp -Uri $delDevUrl -Method "DELETE" -TimeoutSec 3
                            } catch {}
                            continue
                        }

                        $isOnline = ($d.status -eq "online" -and $ageSec -le 75)
                        $statusText = $(if ($isOnline) { "ONLINE" } else { "OFFLINE" })
                        $typeText = $(if ($isSvc) { "Service" } else { "Temp" })

                        $devList.Add([PSCustomObject]@{
                            PIN = $pin
                            Status = $statusText
                            IsOnline = $isOnline
                            Type = $typeText
                            Hostname = $hostname
                            CustomName = $customName
                            DisplayName = $displayName
                            LocalIP = $localIp
                            PublicIP = $publicIp
                            OS = $os
                            AgeSec = $ageSec
                            LastSeen = $lastSeenText
                        })
                    }
                }
            }
        }
    } catch {}
    return $devList
}

function Show-FleetTable {
    param($Devices)

    Write-Host ""
    Write-Host "==================================================================================================================" -ForegroundColor DarkCyan
    Write-Host "                           BB_JAVIS FLEET MANAGEMENT - DEVICE STATUS & PRESENCE                           " -ForegroundColor Yellow
    Write-Host "==================================================================================================================" -ForegroundColor DarkCyan
    Write-Host ((" {0,-4} {1,-6} {2,-9} {3,-9} {4,-24} {5,-16} {6,-16} {7,-12}" -f "No.", "PIN", "STATUS", "TYPE", "COMPUTER NAME", "LOCAL IP", "PUBLIC IP", "LAST SEEN")) -ForegroundColor DarkGray
    Write-Host "------------------------------------------------------------------------------------------------------------------" -ForegroundColor DarkGray

    if (-not $Devices -or $Devices.Count -eq 0) {
        Write-Host "  [!] ไม่พบอุปกรณ์ที่ลงทะเบียนในระบบ (สามารถป้อน PIN สั่งการได้โดยตรง)" -ForegroundColor DarkYellow
        Write-Host "==================================================================================================================" -ForegroundColor DarkCyan
        return
    }

    $idx = 1
    foreach ($d in $Devices) {
        $noStr = "[$idx]"
        $pinStr = $d.PIN
        $statStr = $d.Status
        $typeStr = $d.Type
        $hostStr = $(if ($d.DisplayName.Length -gt 24) { $d.DisplayName.Substring(0, 22) + ".." } else { $d.DisplayName })
        $locIp = $(if ($d.LocalIP.Length -gt 16) { $d.LocalIP.Substring(0, 14) + ".." } else { $d.LocalIP })
        $pubIp = $(if ($d.PublicIP.Length -gt 16) { $d.PublicIP.Substring(0, 14) + ".." } else { $d.PublicIP })
        $lastSeen = $d.LastSeen

        Write-Host (" {0,-4} " -f $noStr) -NoNewline -ForegroundColor White
        Write-Host ("{0,-6} " -f $pinStr) -NoNewline -ForegroundColor Yellow

        if ($d.IsOnline) {
            Write-Host ("{0,-9} " -f $statStr) -NoNewline -ForegroundColor Green
        } else {
            Write-Host ("{0,-9} " -f $statStr) -NoNewline -ForegroundColor DarkGray
        }

        Write-Host ("{0,-9} " -f $typeStr) -NoNewline -ForegroundColor Cyan
        Write-Host ("{0,-24} " -f $hostStr) -NoNewline -ForegroundColor Cyan
        Write-Host ("{0,-16} " -f $locIp) -NoNewline -ForegroundColor Gray
        Write-Host ("{0,-16} " -f $pubIp) -NoNewline -ForegroundColor Gray
        Write-Host ("{0,-12}" -f $lastSeen) -ForegroundColor $(if ($d.IsOnline) { "Green" } else { "DarkGray" })
        $idx++
    }
    Write-Host "==================================================================================================================" -ForegroundColor DarkCyan
}

# --- Handle -PurgeOffline flag ---
if ($PurgeOffline.IsPresent) {
    Write-Host "`n[FLEET PURGE] กำลังค้นหาและล้างเครื่องสถานะ OFFLINE ทั้งหมด..." -ForegroundColor Yellow
    $allDevs = Get-RegisteredDevices -TargetBaseUrl $BaseUrl
    $purgedCount = 0
    foreach ($d in $allDevs) {
        if (-not $d.IsOnline) {
            try {
                $delUrl = $BaseUrl + "devices/$($d.PIN).json"
                $null = Invoke-FirebaseHttp -Uri $delUrl -Method "DELETE" -TimeoutSec 5
                $purgedCount++
                Write-Host "  -> Purged offline device: $($d.DisplayName) (PIN: $($d.PIN))" -ForegroundColor Gray
            } catch {}
        }
    }
    Write-Host "[SUCCESS] ล้างเครื่อง Offline ออกจาก Cloud เรียบร้อยแล้ว (รวม: $purgedCount เครื่อง)`n" -ForegroundColor Green
    return
}

# --- Handle -List flag ---
if ($List.IsPresent -or $Mode -eq "List") {
    $devs = Get-RegisteredDevices -TargetBaseUrl $BaseUrl
    Show-FleetTable -Devices $devs
    return
}

# --- Handle -TargetHost flag ---
if (-not [string]::IsNullOrWhiteSpace($TargetHost) -and [string]::IsNullOrWhiteSpace($SecretKey)) {
    $devs = Get-RegisteredDevices -TargetBaseUrl $BaseUrl
    $targetTrim = $TargetHost.Trim().ToLower()
    $matched = $devs | Where-Object { 
        ($_.Hostname.ToLower() -eq $targetTrim -or ($_.CustomName -and $_.CustomName.ToLower() -eq $targetTrim)) -and $_.IsOnline 
    }
    if (-not $matched) {
        $matched = $devs | Where-Object { 
            ($_.Hostname.ToLower() -like "*$targetTrim*" -or ($_.CustomName -and $_.CustomName.ToLower() -like "*$targetTrim*")) -and $_.IsOnline 
        }
    }
    if ($matched) {
        $SecretKey = ($matched | Select-Object -First 1).PIN
        Write-Host "`n[AUTO-TARGET] พบเครื่อง '$($matched[0].DisplayName)' กำลัง ONLINE -> กำหนด PIN: [ $SecretKey ]" -ForegroundColor Green
    } else {
        Write-Host "`n[ERROR] ไม่พบเครื่องที่มีชื่อหรือ Alias '$TargetHost' ที่กำลังออนไลน์อยู่ในระบบ!" -ForegroundColor Red
        return
    }
}

# --- Handle -TargetIp flag ---
if (-not [string]::IsNullOrWhiteSpace($TargetIp) -and [string]::IsNullOrWhiteSpace($SecretKey)) {
    $devs = Get-RegisteredDevices -TargetBaseUrl $BaseUrl
    $ipTrim = $TargetIp.Trim()
    $matched = $devs | Where-Object { ($_.LocalIP -eq $ipTrim -or $_.PublicIP -eq $ipTrim) -and $_.IsOnline }
    if ($matched) {
        $SecretKey = ($matched | Select-Object -First 1).PIN
        Write-Host "`n[AUTO-TARGET] พบเครื่อง IP '$ipTrim' ($($matched[0].DisplayName)) กำลัง ONLINE -> กำหนด PIN: [ $SecretKey ]" -ForegroundColor Green
    } else {
        Write-Host "`n[ERROR] ไม่พบเครื่องที่มีหมายเลข IP '$TargetIp' ที่กำลังออนไลน์อยู่ในระบบ!" -ForegroundColor Red
        return
    }
}

# --- 1. Interactive Device Selection or Prompt for Secret Key ---
while ([string]::IsNullOrWhiteSpace($SecretKey)) {
    $devs = Get-RegisteredDevices -TargetBaseUrl $BaseUrl
    if ($devs -and $devs.Count -gt 0) {
        Show-FleetTable -Devices $devs
        $exampleName = if ($devs[0].CustomName) { $devs[0].CustomName } else { $devs[0].Hostname }
        Write-Host "  คำแนะนำการสั่งการ:" -ForegroundColor Yellow
        Write-Host "   - พิมพ์หมายเลขข้อ [1-$($devs.Count)] เพื่อเลือกสั่งงานเครื่องนั้นทันที" -ForegroundColor White
        Write-Host "   - หรือพิมพ์ชื่อเครื่อง (เช่น $exampleName) หรือ IP เพื่อค้นหาอัตโนมัติ" -ForegroundColor White
        Write-Host "   - หรือพิมพ์ PIN 4 หลักตรงๆ" -ForegroundColor White
        Write-Host "   - กด [N] เปลี่ยนชื่อเครื่อง (Rename / Set Alias) | [D] ลบเครื่อง | [R] รีเฟรช | [Q] ออก" -ForegroundColor Gray
        Write-Host "------------------------------------------------------------------------------------------------------------------" -ForegroundColor DarkGray
        
        $sel = Read-Host "ระบุตัวเลือก [1-$($devs.Count)], ชื่อเครื่อง, IP, หรือ PIN"
        if ([string]::IsNullOrWhiteSpace($sel)) { continue }
        $sel = $sel.Trim()

        if ($sel -eq "Q" -or $sel -eq "q") {
            Write-Host "ยกเลิกคำสั่งเรียบร้อยแล้ว`n" -ForegroundColor Yellow
            return
        }

        if ($sel -eq "R" -or $sel -eq "r") {
            Write-Host "กำลังรีเฟรชข้อมูล..." -ForegroundColor Cyan
            continue
        }

        if ($sel -eq "N" -or $sel -eq "n") {
            Write-Host "`n[RENAME/ALIAS] โหมดเปลี่ยนชื่อเครื่อง (Set Custom Host Name / Alias)" -ForegroundColor Yellow
            $targetInput = Read-Host "ระบุหมายเลขข้อ [1-$($devs.Count)] หรือ PIN ของเครื่องที่ต้องการเปลี่ยนชื่อ"
            if (-not [string]::IsNullOrWhiteSpace($targetInput)) {
                $targetInput = $targetInput.Trim()
                $targetDev = $null
                $tNum = 0
                if ([int]::TryParse($targetInput, [ref]$tNum) -and $tNum -ge 1 -and $tNum -le $devs.Count) {
                    $targetDev = $devs[$tNum - 1]
                } else {
                    $targetDev = $devs | Where-Object { $_.PIN -eq $targetInput } | Select-Object -First 1
                }

                if ($targetDev) {
                    $newAlias = Read-Host "ระบุชื่อใหม่สำหรับเครื่อง '$($targetDev.DisplayName)'"
                    if (-not [string]::IsNullOrWhiteSpace($newAlias)) {
                        $newAlias = $newAlias.Trim()
                        Write-Host "[RENAME] กำลังส่งคำสั่งเปลี่ยนชื่อเครื่องเป็น '$newAlias' ไปยัง PIN [ $($targetDev.PIN) ]..." -ForegroundColor Cyan
                        try {
                            $jobId = "alias_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
                            $jobPayload = @{
                                id = $jobId
                                command = "@SET_ALIAS $newAlias"
                                type = "powershell"
                                status = "pending"
                                created_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                            } | ConvertTo-Json
                            $jobUrl = $BaseUrl + "jobs/$($targetDev.PIN).json"
                            $null = Invoke-FirebaseHttp -Uri $jobUrl -Method "PUT" -Body $jobPayload -TimeoutSec 10
                            Write-Host "[SUCCESS] ส่งคำสั่งเปลี่ยนชื่อเรียบร้อยแล้ว! กำลังรอ Agent อัปเดต Cloud..." -ForegroundColor Green
                            Start-Sleep -Seconds 2
                        } catch {
                            Write-Host "[ERROR] ไม่สามารถส่งคำสั่งเปลี่ยนชื่อได้: $_" -ForegroundColor Red
                        }
                    } else {
                        Write-Host "[CANCEL] ไม่ได้ระบุชื่อใหม่ ยกเลิกการเปลี่ยนชื่อ" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "[ERROR] ไม่พบอุปกรณ์ที่ระบุ" -ForegroundColor Red
                }
            }
            continue
        }

        if ($sel -eq "D" -or $sel -eq "d") {
            Write-Host "`n[KICK/DELETE] โหมดลบอุปกรณ์ออกจาก Cloud" -ForegroundColor Yellow
            $delInput = Read-Host "ระบุหมายเลขข้อ [1-$($devs.Count)] หรือ PIN ที่ต้องการลบ"
            if (-not [string]::IsNullOrWhiteSpace($delInput)) {
                $delInput = $delInput.Trim()
                $targetDev = $null
                $delNum = 0
                if ([int]::TryParse($delInput, [ref]$delNum) -and $delNum -ge 1 -and $delNum -le $devs.Count) {
                    $targetDev = $devs[$delNum - 1]
                } else {
                    $targetDev = $devs | Where-Object { $_.PIN -eq $delInput } | Select-Object -First 1
                }

                if ($targetDev) {
                    try {
                        $delDevUrl = $BaseUrl + "devices/$($targetDev.PIN).json"
                        $delJobUrl = $BaseUrl + "jobs/$($targetDev.PIN).json"
                        $null = Invoke-FirebaseHttp -Uri $delDevUrl -Method "DELETE" -TimeoutSec 5
                        $null = Invoke-FirebaseHttp -Uri $delJobUrl -Method "DELETE" -TimeoutSec 5
                        Write-Host "[SUCCESS] เตะและลบเครื่อง '$($targetDev.DisplayName)' (PIN: $($targetDev.PIN)) ออกจากระบบเรียบร้อยแล้ว!" -ForegroundColor Green
                    } catch {
                        Write-Host "[ERROR] ไม่สามารถลบข้อมูลอุปกรณ์ได้: $_" -ForegroundColor Red
                    }
                } else {
                    Write-Host "[ERROR] ไม่พบอุปกรณ์ที่ระบุ" -ForegroundColor Red
                }
            }
            continue
        }

        # ตรวจสอบว่าเป็นหมายเลขข้อ 1..N หรือไม่
        $pickNum = 0
        if ([int]::TryParse($sel, [ref]$pickNum) -and $pickNum -ge 1 -and $pickNum -le $devs.Count) {
            $chosen = $devs[$pickNum - 1]
            $SecretKey = $chosen.PIN
            Write-Host "`n[SELECTED] เลือกเครื่อง [$pickNum] : $($chosen.DisplayName) -> PIN: [ $SecretKey ]" -ForegroundColor Green
            break
        }

        # ตรวจสอบว่าตรงกับชื่อเครื่องหรือ Custom Name หรือไม่
        $byHost = $devs | Where-Object { 
            $_.Hostname.ToLower() -eq $sel.ToLower() -or 
            ($_.CustomName -and $_.CustomName.ToLower() -eq $sel.ToLower()) -or 
            $_.Hostname.ToLower() -like "*$($sel.ToLower())*" -or 
            ($_.CustomName -and $_.CustomName.ToLower() -like "*$($sel.ToLower())*") 
        }
        if ($byHost) {
            $chosen = $byHost | Select-Object -First 1
            $SecretKey = $chosen.PIN
            Write-Host "`n[SELECTED] จับคู่ชื่อเครื่อง '$($chosen.DisplayName)' -> PIN: [ $SecretKey ]" -ForegroundColor Green
            break
        }

        # ตรวจสอบว่าตรงกับ IP หรือไม่
        $byIp = $devs | Where-Object { $_.LocalIP -eq $sel -or $_.PublicIP -eq $sel }
        if ($byIp) {
            $chosen = $byIp | Select-Object -First 1
            $SecretKey = $chosen.PIN
            Write-Host "`n[SELECTED] จับคู่ IP '$sel' ($($chosen.DisplayName)) -> PIN: [ $SecretKey ]" -ForegroundColor Green
            break
        }

        # หรือใส่ PIN ตรงๆ 4 หลัก
        if ($sel.Length -ge 4 -and $sel -match '^\d+$') {
            $SecretKey = $sel
            Write-Host "`n[MANUAL] ระบุ PIN โดยตรง: [ $SecretKey ]" -ForegroundColor Green
            break
        }

        Write-Host "[!] ตัวเลือกไม่ถูกต้อง กรุณาระบุใหม่" -ForegroundColor Yellow
    } else {
        Write-Host "`n[INFO] ไม่พบอุปกรณ์ในระบบ Fleet หรือยังไม่มีเครื่องใดออนไลน์" -ForegroundColor Yellow
        $SecretKey = Read-Host "กรุณาระบุ Remote Secret Key (PIN 4 หลัก)"
        if ([string]::IsNullOrWhiteSpace($SecretKey)) {
            Write-Host "[ERROR] ไม่ได้ระบุ Secret Key ยกเลิกการทำงาน" -ForegroundColor Red
            return
        }
        $SecretKey = $SecretKey.Trim()
        break
    }
}

if ($BaseUrl -notlike "*/") {
    $BaseUrl = $BaseUrl + "/"
}

# --- 2. Prompt for operation mode if invalid ---
$validModes = @("PowerShell", "Query", "Backup", "Download", "Upload", "Cancel")
if ([string]::IsNullOrWhiteSpace($Mode) -or $validModes -notcontains $Mode) {
    Write-Host "`nSelect Operation Mode:" -ForegroundColor Yellow
    Write-Host "[1] PowerShell Command Mode (Standard)" -ForegroundColor White
    Write-Host "[2] SQL Server Query Mode (Returns JSON)" -ForegroundColor White
    Write-Host "[3] SQL Server Backup Mode (Base64 file retrieval)" -ForegroundColor White
    Write-Host "[4] File Download Mode (Download directory/file)" -ForegroundColor White
    Write-Host "[5] File Upload Mode (Upload directory/file)" -ForegroundColor White
    Write-Host "[6] Emergency Cancel Mode (Abort running job)" -ForegroundColor Red
    $modeChoice = Read-Host "Select option [1-6] (Default is 1)"
    if ($modeChoice -eq "2") {
        $Mode = "Query"
    } elseif ($modeChoice -eq "3") {
        $Mode = "Backup"
    } elseif ($modeChoice -eq "4") {
        $Mode = "Download"
    } elseif ($modeChoice -eq "5") {
        $Mode = "Upload"
    } elseif ($modeChoice -eq "6") {
        $Mode = "Cancel"
    } else {
        $Mode = "PowerShell"
    }
}

# --- Emergency Cancel Mode Handler ---
if ($Mode -eq "Cancel") {
    Write-Host "`n[EMERGENCY CANCEL] Locating active job on Secret Key: $SecretKey..." -ForegroundColor Yellow
    $targetJobId = $JobId
    if (-not $targetJobId) {
        $queryUrl = $BaseUrl + "jobs/$SecretKey.json"
        $jsonRaw = Invoke-FirebaseHttp -Uri $queryUrl -Method "GET" -TimeoutSec 5
        if ($jsonRaw -and $jsonRaw.Trim() -ne "null") {
            $jobsObj = ConvertFrom-Json -InputObject $jsonRaw -ErrorAction SilentlyContinue
            if ($jobsObj) {
                foreach ($prop in $jobsObj.PSObject.Properties) {
                    if ($prop.Value -and ($prop.Value.status -eq "running" -or $prop.Value.status -eq "pending")) {
                        $targetJobId = $prop.Name
                        break
                    }
                }
            }
        }
    }
    if ($targetJobId) {
        Write-Host "Sending abort signal to Job ID: $targetJobId..." -ForegroundColor Red
        $abortUrl = $BaseUrl + "jobs/$SecretKey/$targetJobId/abort.json"
        $null = Invoke-FirebaseHttp -Uri $abortUrl -Method "PUT" -Body "true" -TimeoutSec 5
        Write-Host "[SUCCESS] Emergency abort signal sent successfully to $targetJobId!" -ForegroundColor Green
    } else {
        Write-Host "[INFO] No pending or running job found for Secret Key $SecretKey." -ForegroundColor Yellow
    }
    return
}

# --- 3. Build script payload according to the mode ---
$finalScript = ""
$isReceiveFileJob = $false

if ($Mode -eq "PowerShell") {
    # Standard command execution
    if ([string]::IsNullOrWhiteSpace($SqlQuery)) {
        if (-not [string]::IsNullOrWhiteSpace($SqlFile) -and (Test-Path $SqlFile)) {
            $SqlQuery = Get-Content $SqlFile -Encoding UTF8 -Raw
        } else {
            $SqlQuery = Read-Host "`nEnter PowerShell command to execute"
        }
    }
    if ([string]::IsNullOrWhiteSpace($SqlQuery)) {
        Write-Host "[WARNING] Command is empty. Aborting." -ForegroundColor Yellow
        return
    }
    $finalScript = $SqlQuery
}
elseif ($Mode -eq "Query") {
    # SQL query mode (Outputs JSON)
    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        if ($defaultConn) {
            Write-Host "`nEnter Connection String (Press Enter to use default: $defaultConn)" -ForegroundColor Yellow
            $ConnectionString = Read-Host "Connection String"
            if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
                $ConnectionString = $defaultConn
            }
        } else {
            $ConnectionString = Read-Host "`nEnter SQL Server Connection String"
        }
    }
    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        Write-Host "[ERROR] Connection String is empty. Aborting." -ForegroundColor Red
        return
    }
    
    # Save connection string profile
    @{ ConnectionString = $ConnectionString } | ConvertTo-Json | Out-File $profilePath -Encoding utf8 -Force

    $sqlContent = ""
    if ([string]::IsNullOrWhiteSpace($SqlQuery)) {
        if (-not [string]::IsNullOrWhiteSpace($SqlFile) -and (Test-Path $SqlFile)) {
            $sqlContent = Get-Content $SqlFile -Encoding UTF8 -Raw
        } else {
            Write-Host "`nSelect SQL Script Source:" -ForegroundColor Yellow
            Write-Host "[1] Enter SQL script directly" -ForegroundColor White
            Write-Host "[2] Load from SQL file (.sql)" -ForegroundColor White
            $sqlChoice = Read-Host "Select option [1-2]"
            if ($sqlChoice -eq "2") {
                $sqlPath = Read-Host "Enter path to .sql file"
                if (Test-Path $sqlPath) {
                    $sqlContent = Get-Content $sqlPath -Encoding UTF8 -Raw
                } else {
                    Write-Host "[ERROR] SQL file not found." -ForegroundColor Red
                    return
                }
            } else {
                $sqlContent = Read-Host "Enter SQL command (e.g. SELECT @@VERSION)"
            }
        }
    } else {
        $sqlContent = $SqlQuery
    }

    if ([string]::IsNullOrWhiteSpace($sqlContent)) {
        Write-Host "[ERROR] SQL command is empty." -ForegroundColor Red
        return
    }

    # Escape single quotes for PowerShell string literal compatibility
    $escapedConn = $ConnectionString.Replace("'", "''")
    $escapedSql = $sqlContent.Replace("'", "''")

    # Generate ADO.NET query execution script
    $finalScript = @"
`$ConnectionString = '$escapedConn'
`$Sql = '$escapedSql'

try {
    `$connection = New-Object System.Data.SqlClient.SqlConnection(`$ConnectionString)
    `$connection.Open()
    `$command = `$connection.CreateCommand()
    `$command.CommandText = `$Sql
    
    `$adapter = New-Object System.Data.SqlClient.SqlDataAdapter(`$command)
    `$dataset = New-Object System.Data.DataSet
    `$adapter.Fill(`$dataset) | Out-Null
    
    `$table = `$dataset.Tables[0]
    if (`$table) {
        `$resultJson = ConvertTo-Json -InputObject `$table -Depth 3 -Compress
        Write-Output `$resultJson
    } else {
        Write-Output '{"status":"success","message":"Command executed successfully. No records returned."}'
    }
} catch {
    `$errPayload = @{
        status = "failed"
        error_type = "SQL_QUERY_ERROR"
        message = `$_.Exception.Message
    } | ConvertTo-Json -Compress
    Write-Error `$errPayload
    exit 1
} finally {
    if (`$connection -and `$connection.State -eq "Open") {
        `$connection.Close()
    }
}
"@
}
elseif ($Mode -eq "Backup") {
    $isReceiveFileJob = $true
    
    # SQL database backup mode
    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        if ($defaultConn) {
            Write-Host "`nEnter Connection String (Press Enter to use default: $defaultConn)" -ForegroundColor Yellow
            $ConnectionString = Read-Host "Connection String"
            if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
                $ConnectionString = $defaultConn
            }
        } else {
            $ConnectionString = Read-Host "`nEnter SQL Server Connection String"
        }
    }
    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        Write-Host "[ERROR] Connection String is empty." -ForegroundColor Red
        return
    }

    # Save connection string profile
    @{ ConnectionString = $ConnectionString } | ConvertTo-Json | Out-File $profilePath -Encoding utf8 -Force

    if ([string]::IsNullOrWhiteSpace($DbName)) {
        $DbName = Read-Host "`nEnter Database name to Backup (e.g. TestDB)"
    }
    if ([string]::IsNullOrWhiteSpace($DbName)) {
        Write-Host "[ERROR] Database name is empty." -ForegroundColor Red
        return
    }

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Read-Host "`nEnter output directory to save Backup file (e.g. D:\BackupDb)"
        if ([string]::IsNullOrWhiteSpace($OutputDir)) {
            $OutputDir = $env:USERPROFILE
        }
    }

    # Escape single quotes
    $escapedConn = $ConnectionString.Replace("'", "''")

    # Generate ADO.NET database backup and zip compression script
    $finalScript = @"
`$ConnectionString = '$escapedConn'
`$DbName = "$DbName"
`$FirebaseUrl = "$BaseUrl"
`$SecretKey = "$SecretKey"
`$JobId = "`$env:CMD_REMOTE_JOB_ID"
`$curlPath = "`$env:CMD_REMOTE_CURL_PATH"

try {
    Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction Stop
} catch {
    [Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
}

function Update-Progress {
    param (
        [string]`$Phase
    )
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$body = @{
        progress_phase = `$Phase
        last_heartbeat = `$timestamp
    } | ConvertTo-Json -Compress
    
    if (`$JobId -and `$curlPath) {
        `$updateUrl = "`$($FirebaseUrl)jobs/`$($SecretKey)/`$($JobId).json"
        `$null = & `$curlPath -s -L -k -X PATCH -H "Content-Type: application/json" -d `$body `$updateUrl
    }
}

function Compress-BackupFile {
    param (
        [string]`$SourceFile,
        [string]`$ZipFile
    )
    `$zipStream = [System.IO.File]::Create(`$ZipFile)
    `$archive = New-Object System.IO.Compression.ZipArchive(`$zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    `$entry = `$archive.CreateEntry([System.IO.Path]::GetFileName(`$SourceFile))
    `$writer = `$entry.Open()
    
    `$reader = [System.IO.File]::OpenRead(`$SourceFile)
    `$buffer = New-Object byte[] 81920
    while ((`$read = `$reader.Read(`$buffer, 0, `$buffer.Length)) -gt 0) {
        `$writer.Write(`$buffer, 0, `$read)
    }
    
    `$reader.Close()
    `$writer.Close()
    `$archive.Dispose()
    `$zipStream.Close()
}

`$BackupFolder = `$env:TEMP
`$BackupPath = Join-Path `$BackupFolder "`$($DbName)_`$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"
`$ZipPath = [System.IO.Path]::ChangeExtension(`$BackupPath, ".zip")

try {
    Update-Progress -Phase "SQL Backup In-Progress"
    `$connection = New-Object System.Data.SqlClient.SqlConnection(`$ConnectionString)
    `$connection.Open()
    `$command = `$connection.CreateCommand()
    `$command.CommandText = "BACKUP DATABASE [`$DbName] TO DISK = '`$BackupPath' WITH FORMAT, INIT;"
    `$command.ExecuteNonQuery() | Out-Null
    `$connection.Close()

    Update-Progress -Phase "Zip Compression In-Progress"
    if (Test-Path `$ZipPath) { Remove-Item `$ZipPath -Force }
    Compress-BackupFile -SourceFile `$BackupPath -ZipFile `$ZipPath

    Update-Progress -Phase "Base64 Encoding In-Progress"
    `$bytes = [System.IO.File]::ReadAllBytes(`$ZipPath)
    `$base64 = [Convert]::ToBase64String(`$bytes)

    Update-Progress -Phase "Uploading Result"
    `$resPayload = @{
        status = "completed"
        file_name = [System.IO.Path]::GetFileName(`$ZipPath)
        file_data = `$base64
    } | ConvertTo-Json -Compress
    
    Write-Output "---FILE_DATA_START---"
    Write-Output `$resPayload
    Write-Output "---FILE_DATA_END---"
} catch {
    `$errPayload = @{
        status = "failed"
        error_type = "SQL_BACKUP_ERROR"
        message = `$_.Exception.Message
    } | ConvertTo-Json -Compress
    Write-Error `$errPayload
    exit 1
} finally {
    if (Test-Path `$BackupPath) { Remove-Item `$BackupPath -Force }
    if (Test-Path `$ZipPath) { Remove-Item `$ZipPath -Force }
}
"@
}
elseif ($Mode -eq "Download") {
    $isReceiveFileJob = $true
    
    # File download mode
    if ([string]::IsNullOrWhiteSpace($RemotePath)) {
        $RemotePath = Read-Host "`nEnter path to Remote file/directory (Remote Path)"
    }
    if ([string]::IsNullOrWhiteSpace($RemotePath)) {
        Write-Host "[ERROR] Remote Path is empty." -ForegroundColor Red
        return
    }

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Read-Host "`nEnter output directory to save Downloaded file (e.g. D:\BackupDb)"
        if ([string]::IsNullOrWhiteSpace($OutputDir)) {
            $OutputDir = $env:USERPROFILE
        }
    }

    # Generate remote file zip compression and Base64 transfer script
    $finalScript = @"
`$RemotePath = '$RemotePath'
`$FirebaseUrl = "$BaseUrl"
`$SecretKey = "$SecretKey"
`$JobId = "`$env:CMD_REMOTE_JOB_ID"
`$curlPath = "`$env:CMD_REMOTE_CURL_PATH"
`$ZipPath = Join-Path `$env:TEMP 'download_temp.zip'

try {
    Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction Stop
} catch {
    [Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
}

function Update-Progress {
    param (
        [string]`$Phase
    )
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$body = @{
        progress_phase = `$Phase
        last_heartbeat = `$timestamp
    } | ConvertTo-Json -Compress
    
    if (`$JobId -and `$curlPath) {
        `$updateUrl = "`$($FirebaseUrl)jobs/`$($SecretKey)/`$($JobId).json"
        `$null = & `$curlPath -s -L -k -X PATCH -H "Content-Type: application/json" -d `$body `$updateUrl
    }
}

try {
    Update-Progress -Phase "Checking Target Resource"
    if (-not (Test-Path `$RemotePath)) {
        throw "Target file or folder not found: `$RemotePath"
    }

    Update-Progress -Phase "Zip Compression In-Progress"
    if (Test-Path `$ZipPath) { Remove-Item `$ZipPath -Force }
    
    if (Test-Path `$RemotePath -PathType Container) {
        [System.IO.Compression.ZipFile]::CreateFromDirectory(`$RemotePath, `$ZipPath)
    } else {
        `$zipStream = [System.IO.File]::Create(`$ZipPath)
        `$archive = New-Object System.IO.Compression.ZipArchive(`$zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
        `$entryName = [System.IO.Path]::GetFileName(`$RemotePath)
        `$entry = `$archive.CreateEntry(`$entryName)
        `$writer = `$entry.Open()
        `$reader = [System.IO.File]::OpenRead(`$RemotePath)
        `$buffer = New-Object byte[] 81920
        while ((`$read = `$reader.Read(`$buffer, 0, `$buffer.Length)) -gt 0) {
            `$writer.Write(`$buffer, 0, `$read)
        }
        `$reader.Close()
        `$writer.Close()
        `$archive.Dispose()
        `$zipStream.Close()
    }

    Update-Progress -Phase "Base64 Encoding In-Progress"
    `$bytes = [System.IO.File]::ReadAllBytes(`$ZipPath)
    `$base64 = [Convert]::ToBase64String(`$bytes)

    Update-Progress -Phase "Uploading Result File"
    `$resPayload = @{
        status = "completed"
        file_name = [System.IO.Path]::GetFileName(`$RemotePath) + ".zip"
        file_data = `$base64
    } | ConvertTo-Json -Compress
    
    Write-Output "---FILE_DATA_START---"
    Write-Output `$resPayload
    Write-Output "---FILE_DATA_END---"
} catch {
    `$errPayload = @{
        status = "failed"
        error_type = "DOWNLOAD_ERROR"
        message = `$_.Exception.Message
    } | ConvertTo-Json -Compress
    Write-Error `$errPayload
    exit 1
} finally {
    if (Test-Path `$ZipPath) { Remove-Item `$ZipPath -Force }
}
"@
}
elseif ($Mode -eq "Upload") {
    # File upload mode
    if ([string]::IsNullOrWhiteSpace($LocalPath)) {
        $LocalPath = Read-Host "`nEnter path to Local file/directory (Local Path)"
    }
    if ([string]::IsNullOrWhiteSpace($LocalPath) -or -not (Test-Path $LocalPath)) {
        Write-Host "[ERROR] Local source file or folder not found." -ForegroundColor Red
        return
    }

    if ([string]::IsNullOrWhiteSpace($RemotePath)) {
        $RemotePath = Read-Host "`nEnter path to Remote target (Remote Path)"
    }
    if ([string]::IsNullOrWhiteSpace($RemotePath)) {
        Write-Host "[ERROR] Remote Path is empty." -ForegroundColor Red
        return
    }

    # Perform local compression
    Write-Host "`nCompressing local payload..." -ForegroundColor Yellow
    $tempZipPath = Join-Path $env:TEMP ("upload_" + [Guid]::NewGuid().ToString().Substring(0, 8) + ".zip")
    
    try {
        Add-Type -AssemblyName "System.IO.Compression.FileSystem"
    } catch {}

    try {
        if (Test-Path $LocalPath -PathType Container) {
            [System.IO.Compression.ZipFile]::CreateFromDirectory($LocalPath, $tempZipPath)
        } else {
            $zipStream = [System.IO.File]::Create($tempZipPath)
            $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
            $entryName = [System.IO.Path]::GetFileName($LocalPath)
            $entry = $archive.CreateEntry($entryName)
            $writer = $entry.Open()
            $reader = [System.IO.File]::OpenRead($LocalPath)
            $buffer = New-Object byte[] 81920
            while (($read = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $writer.Write($buffer, 0, $read)
            }
            $reader.Close()
            $writer.Close()
            $archive.Dispose()
            $zipStream.Close()
        }

        # Size guardrail validation
        $zipSize = (Get-Item $tempZipPath).Length
        if ($zipSize -gt 150MB) {
            if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
            Write-Host "[ERROR] Zip file size is $([Math]::Round($zipSize/1MB, 2))MB, which exceeds Firebase safety limit of 150MB! Aborting upload." -ForegroundColor Red
            return
        }

        Write-Host "Encoding payload to Base64 String..." -ForegroundColor Yellow
        $bytes = [System.IO.File]::ReadAllBytes($tempZipPath)
        $base64 = [Convert]::ToBase64String($bytes)
    }
    catch {
        Write-Host "[ERROR] Failed to compress and package files: $_" -ForegroundColor Red
        if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
        return
    }
    finally {
        if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
    }

    # Generate remote retrieval and extraction script
    $finalScript = @"
`$RemotePath = '$RemotePath'
`$Base64Data = '$base64'
`$ZipPath = Join-Path `$env:TEMP 'upload_temp.zip'
`$tempExtractDir = Join-Path `$env:TEMP ("extract_" + [Guid]::NewGuid().ToString().Substring(0, 8))

try {
    `$bytes = [Convert]::FromBase64String(`$Base64Data)
    [System.IO.File]::WriteAllBytes(`$ZipPath, `$bytes)
    
    `$remoteDir = Split-Path `$RemotePath
    if (-not (Test-Path `$remoteDir)) {
        `$null = New-Item -ItemType Directory -Path `$remoteDir -Force
    }
    
    try { Add-Type -AssemblyName "System.IO.Compression.FileSystem" } catch {}
    if (Test-Path `$tempExtractDir) { Remove-Item `$tempExtractDir -Force -Recurse }
    [System.IO.Compression.ZipFile]::ExtractToDirectory(`$ZipPath, `$tempExtractDir)
    
    `$extractedFiles = Get-ChildItem `$tempExtractDir
    if (`$extractedFiles.Count -eq 1 -and (Test-Path `$RemotePath -PathType Leaf -ErrorAction SilentlyContinue)) {
        if (Test-Path `$RemotePath) { Remove-Item `$RemotePath -Force }
        Copy-Item `$extractedFiles[0].FullName `$RemotePath -Force
    } else {
        Copy-Item (Join-Path `$tempExtractDir "*") `$remoteDir -Force -Recurse
    }
    Write-Output "Upload and file deployment completed successfully!"
} catch {
    Write-Error "Deployment failed: `$_.Exception.Message"
    exit 1
} finally {
    if (Test-Path `$ZipPath) { Remove-Item `$ZipPath -Force }
    if (Test-Path `$tempExtractDir) { Remove-Item `$tempExtractDir -Force -Recurse }
}
"@
}


# --- 4. Submit & Monitor Job with AI Intelligent Watchdog ---
$maxRetries = 1
$retryAttempt = 0
$agentRestartDone = $false
$finalJobSuccess = $false

# ดักจับ Ctrl+C เพื่อส่งสัญญาณ Emergency Abort ไปยังเครื่องเป้าหมาย
$senderCancelHandler = [ConsoleCancelEventHandler]{
    param($s, $e)
    Write-Host "`n`n[EMERGENCY ABORT] User requested stop! Sending abort signal to remote agent..." -ForegroundColor Red
    try {
        if (-not [string]::IsNullOrWhiteSpace($script:checkUrl)) {
            $abortUrl = $script:checkUrl.Replace(".json", "/abort.json")
            $null = Invoke-FirebaseHttp -Uri $abortUrl -Method "PUT" -Body "true" -TimeoutSec 5
            Write-Host "[SUCCESS] Abort signal sent to Cloud board." -ForegroundColor Green
        }
    } catch {}
}
try { [Console]::add_CancelKeyPress($senderCancelHandler) } catch {}

try {
    while ($retryAttempt -le $maxRetries -and -not $finalJobSuccess) {
        $jobId = "job-" + [Guid]::NewGuid().ToString().Substring(0, 8)
        $jobBody = @{
            secret_key = $SecretKey
            script_content = $finalScript
            status = "pending"
            execution_mode = $ExecutionMode
            created_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            timeout_sec = $TimeoutSec
            abort = $false
        } | ConvertTo-Json -Compress

        $attemptLabel = if ($retryAttempt -gt 0) { " (Auto-Retry $retryAttempt/$maxRetries)" } else { "" }
        Write-Host "`nPublishing job payload to cloud command board$attemptLabel..." -ForegroundColor Yellow
        try {
            $putUrl = $BaseUrl + "jobs/$SecretKey/$jobId.json"
            $null = Invoke-FirebaseHttp -Uri $putUrl -Method "PUT" -Body $jobBody -TimeoutSec 15
            Write-Host "[SUCCESS] Published successfully! Job ID: $jobId (Timeout: ${TimeoutSec}s)" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] Failed to connect to Firebase: $_" -ForegroundColor Red
            return
        }

        # ตัวแปรสถานะและการเฝ้าระวัง Watchdog
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $script:completed = $false
        $script:jobStartTime = [DateTime]::Now
        $script:lastActiveTime = [DateTime]::Now
        $script:lastHeartbeatValue = ""
        $script:lastPhase = ""
        $script:currentStatus = "pending"
        $script:hangDetected = $false
        $script:hangReason = ""

        $script:printedStdoutLen = 0
        $script:printedStderrLen = 0
        $script:printedRunningHeader = $false
        $script:checkUrl = $BaseUrl + "jobs/$SecretKey/$jobId.json"
        $script:isReceiveFileJob = $isReceiveFileJob
        $script:OutputDir = $OutputDir

        # ฟังก์ชันตรวจสอบความค้าง (AI Intelligent Watchdog)
        function Test-JobHangs {
            $now = [DateTime]::Now

            # 1. ตรวจสอบ Pending Hang: หากคำสั่งยังเป็น pending นานเกิน 20 วินาที
            if ($script:currentStatus -eq "pending") {
                $pendingSec = ($now - $script:jobStartTime).TotalSeconds
                if ($pendingSec -ge 20) {
                    $script:hangDetected = $true
                    $script:hangReason = "Pending Timeout ($([int]$pendingSec)s > 20s - ไม่พบ Agent รับงาน)"
                    return $true
                }
            }
            # 2. ตรวจสอบ Running Hang: หากสถานะเป็น running แต่นิ่งสนิทไร้ Heartbeat และไร้ Output นานเกิน 30 วินาที
            elseif ($script:currentStatus -eq "running") {
                $silentSec = ($now - $script:lastActiveTime).TotalSeconds
                if ($silentSec -ge 30) {
                    $script:hangDetected = $true
                    $script:hangReason = "Running Stalled ($([int]$silentSec)s > 30s - คำสั่งหรือ Thread นิ่งสนิทไร้ Heartbeat)"
                    return $true
                }
            }
            return $false
        }

        # ประมวลผล Object สถานะ
        function Process-JobStatusObject {
            param([PSCustomObject]$statusCheck)
            if (-not $statusCheck) { return $false }
            
            $status = $statusCheck.status
            if ($status) { $script:currentStatus = $status }
            $currentHeartbeat = $statusCheck.last_heartbeat
            $currentPhase = $statusCheck.progress_phase
            
            if ($currentHeartbeat -and $currentHeartbeat -ne $script:lastHeartbeatValue) {
                $script:lastHeartbeatValue = $currentHeartbeat
                $script:lastActiveTime = [DateTime]::Now
            }
            
            if ($currentPhase -and $currentPhase -ne $script:lastPhase) {
                $script:lastPhase = $currentPhase
                Write-Host "`n[Phase Status]: $script:lastPhase" -ForegroundColor Cyan
                $script:lastActiveTime = [DateTime]::Now
            }
            
            if (-not $script:isReceiveFileJob) {
                $stdoutVal = $statusCheck.stdout
                if ($stdoutVal -and $stdoutVal.Length -gt $script:printedStdoutLen) {
                    if (-not $script:printedRunningHeader) {
                        Write-Host "`n[Console Outputs (Real-time)]:" -ForegroundColor White
                        $script:printedRunningHeader = $true
                    }
                    $newStdout = $stdoutVal.Substring($script:printedStdoutLen)
                    Write-Host -NoNewline $newStdout -ForegroundColor Gray
                    $script:printedStdoutLen = $stdoutVal.Length
                    $script:lastActiveTime = [DateTime]::Now
                }
                
                $stderrVal = $statusCheck.stderr
                if ($stderrVal -and $stderrVal.Length -gt $script:printedStderrLen) {
                    if (-not $script:printedRunningHeader) {
                        Write-Host "`n[Console Outputs (Real-time)]:" -ForegroundColor White
                        $script:printedRunningHeader = $true
                    }
                    $newStderr = $stderrVal.Substring($script:printedStderrLen)
                    Write-Host -NoNewline $newStderr -ForegroundColor DarkRed
                    $script:printedStderrLen = $stderrVal.Length
                    $script:lastActiveTime = [DateTime]::Now
                }
            }
            
            if ($status -eq "completed" -or $status -eq "failed" -or $status -eq "cancelled") {
                Write-Host "`n`n==========================================" -ForegroundColor Green
                Write-Host "CMD_Remote Output Report (Status: $status)" -ForegroundColor Green
                Write-Host "==========================================" -ForegroundColor Green
                
                if (-not $script:isReceiveFileJob) {
                    $stdoutVal = $statusCheck.stdout
                    if ($stdoutVal -and $stdoutVal.Length -gt $script:printedStdoutLen) {
                        $newStdout = $stdoutVal.Substring($script:printedStdoutLen)
                        Write-Host -NoNewline $newStdout -ForegroundColor Gray
                    }
                    $stderrVal = $statusCheck.stderr
                    if ($stderrVal -and $stderrVal.Length -gt $script:printedStderrLen) {
                        $newStderr = $stderrVal.Substring($script:printedStderrLen)
                        Write-Host -NoNewline $newStderr -ForegroundColor DarkRed
                    }
                }
                
                if ($script:isReceiveFileJob -and $status -eq "completed") {
                    if ($statusCheck.stdout -match '---FILE_DATA_START---[\r\n]+(?<json>[\s\S]+?)[\r\n]+---FILE_DATA_END---') {
                        $jsonRaw = $Matches['json'].Trim()
                        try {
                            $payload = ConvertFrom-Json -InputObject $jsonRaw
                            $fileName = $payload.file_name
                            $fileData = $payload.file_data
                            
                            if (-not (Test-Path $script:OutputDir)) {
                                $null = New-Item -ItemType Directory -Path $script:OutputDir -Force
                            }
                            $zipPath = Join-Path $script:OutputDir $fileName
                            $bakPath = Join-Path $script:OutputDir ([System.IO.Path]::GetFileNameWithoutExtension($fileName))
                            
                            Write-Host "`n[FILE RETRIEVAL] Decoding Base64 data..." -ForegroundColor Yellow
                            $bytes = [Convert]::FromBase64String($fileData)
                            [System.IO.File]::WriteAllBytes($zipPath, $bytes)
                            
                            Write-Host "[ARCHIVE EXTRACT] Extracting archive file..." -ForegroundColor Yellow
                            try {
                                Add-Type -AssemblyName "System.IO.Compression.FileSystem"
                            } catch {}
                            
                            if (Test-Path $bakPath) { Remove-Item $bakPath -Force -Recurse }
                            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $script:OutputDir)
                            
                            if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
                            
                            Write-Host "[SUCCESS] File retrieved and decoded successfully!" -ForegroundColor Green
                            Write-Host "Output Path: $bakPath" -ForegroundColor White
                        }
                        catch {
                            Write-Host "[ERROR] Decoding or extraction failed: $_" -ForegroundColor Red
                        }
                    } else {
                        Write-Host "[ERROR] Missing payload data key." -ForegroundColor Red
                    }
                }
                
                Write-Host "`nCompleted at: $($statusCheck.completed_at)" -ForegroundColor Gray
                Write-Host "Exit Code: $($statusCheck.exit_code)" -ForegroundColor Gray
                Write-Host "==========================================" -ForegroundColor Green
                
                try {
                    $null = Invoke-FirebaseHttp -Uri $script:checkUrl -Method "DELETE" -TimeoutSec 5
                } catch {}
                $script:completed = $true
                return $true
            }
            
            return $false
        }

        # เริ่มต้นลูปฟังผลลัพธ์ (Dual-Engine SSE Push + Watchdog Monitor)
        Write-Host "`nListening for agent response (AI Watchdog Active)..." -ForegroundColor Yellow
        
        while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSec -and -not $script:completed -and -not $script:hangDetected) {
            # ตรวจสอบ Watchdog ก่อนเริ่มรอบ
            if (Test-JobHangs) { break }

            try {
                $finalStreamUrl = $script:checkUrl
                if (-not [string]::IsNullOrWhiteSpace($script:FirebaseAuthToken)) {
                    $sep = if ($finalStreamUrl.Contains("?")) { "&" } else { "?" }
                    if ($finalStreamUrl -notmatch "[?&]auth=") {
                        $finalStreamUrl = "$finalStreamUrl${sep}auth=$script:FirebaseAuthToken"
                    }
                }
                $request = [System.Net.HttpWebRequest]::Create($finalStreamUrl)
                $request.Accept = "text/event-stream"
                if (-not [string]::IsNullOrWhiteSpace($script:JavisApiKey)) {
                    $request.Headers["X-Javis-Key"] = $script:JavisApiKey
                    if ($script:checkUrl -notlike "$BaseUrl*") {
                        $request.Headers["Authorization"] = "Bearer " + $script:JavisApiKey
                    }
                }
                $remTimeout = [Math]::Max(5000, [int](($TimeoutSec - $stopwatch.Elapsed.TotalSeconds) * 1000))
                $request.Timeout = $remTimeout
                $request.ReadWriteTimeout = $remTimeout
                
                $response = $request.GetResponse()
                $stream = $response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                $dataBuffer = [System.Text.StringBuilder]::new()
                
                while (-not $reader.EndOfStream -and -not $script:completed -and -not $script:hangDetected) {
                    if (Test-JobHangs) { break }

                    $line = $reader.ReadLine()
                    if ($null -eq $line) { break }
                    
                    if ($line.StartsWith("data: ")) {
                        $null = $dataBuffer.AppendLine($line.Substring(6))
                    }
                    elseif ($line -eq "") {
                        if ($dataBuffer.Length -gt 0) {
                            $rawJson = $dataBuffer.ToString().Trim()
                            [void]$dataBuffer.Clear()
                            
                            if ($rawJson -and $rawJson -ne "null") {
                                try {
                                    $sseObj = ConvertFrom-Json -InputObject $rawJson -ErrorAction SilentlyContinue
                                    if ($sseObj) {
                                        $targetObj = if ($sseObj.data) { $sseObj.data } else { $sseObj }
                                        if ($targetObj -is [System.Management.Automation.PSCustomObject] -and $targetObj.status) {
                                            $isFinished = Process-JobStatusObject -statusCheck $targetObj
                                            if ($isFinished) { break }
                                        }
                                    }
                                } catch {}
                            }
                        }
                    }
                }
                $response.Close()
                if ($script:completed -or $script:hangDetected) { break }
            }
            catch {
                # Fallback Polling
                if (Test-JobHangs) { break }
                try {
                    $jsonRaw = Invoke-FirebaseHttp -Uri $script:checkUrl -Method "GET" -TimeoutSec 5
                    if (-not [string]::IsNullOrEmpty($jsonRaw) -and $jsonRaw -ne "null") {
                        $statusCheck = ConvertFrom-Json -InputObject $jsonRaw -ErrorAction SilentlyContinue
                        if ($statusCheck) {
                            $isFinished = Process-JobStatusObject -statusCheck $statusCheck
                            if ($isFinished) { break }
                        }
                    }
                } catch {}
                if ($script:completed -or $script:hangDetected) { break }
                Start-Sleep -Milliseconds 300
            }
        }

        # การจัดการผลลัพธ์ของรอบนี้
        if ($script:completed) {
            $finalJobSuccess = $true
            break
        }

        if ($script:hangDetected) {
            Write-Host "`n======================================================================" -ForegroundColor Yellow
            Write-Host " [AI WATCHDOG] ตรวจพบคำสั่งไม่ตอบสนอง: $script:hangReason" -ForegroundColor Yellow
            Write-Host "======================================================================" -ForegroundColor Yellow
            Write-Host "  -> กำลังส่ง Emergency Abort ยกเลิกคำสั่งเดิม (Job ID: $jobId)..." -ForegroundColor Red
            try {
                $abortUrl = $script:checkUrl.Replace(".json", "/abort.json")
                $null = Invoke-FirebaseHttp -Uri $abortUrl -Method "PUT" -Body "true" -TimeoutSec 5
                $null = Invoke-FirebaseHttp -Uri $script:checkUrl -Method "DELETE" -TimeoutSec 5
            } catch {}

            if ($retryAttempt -lt $maxRetries) {
                $retryAttempt++
                Write-Host "  -> เริ่มต้นส่งคำสั่งซ้ำอัตโนมัติรอบที่ $retryAttempt/$maxRetries (Auto-Retry)..." -ForegroundColor Cyan
                Write-Host "======================================================================`n" -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                continue
            } else {
                # กรณีค้างซ้ำหลัง Retry ครบแล้ว ➔ ดำเนินการ Escalation สั่ง Agent Auto-Restart
                if (-not $agentRestartDone) {
                    $agentRestartDone = $true
                    Write-Host "  -> [ESCALATION] ตรวจพบคำสั่งยังคงค้างหลัง Retry! กำลังสั่ง Auto-Restart Agent..." -ForegroundColor Red
                    Write-Host "  -> ส่งคำสั่งพิเศษ In-Place Reset (คงรหัส PIN เดิม: [ $SecretKey ])..." -ForegroundColor Yellow
                    
                    $rstJobId = "job-rst-" + [Guid]::NewGuid().ToString().Substring(0, 8)
                    $rstBody = @{
                        secret_key = $SecretKey
                        script_content = "__JAVIS_SYSTEM_RESTART__"
                        status = "pending"
                        execution_mode = "turbo"
                        created_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        timeout_sec = 30
                        abort = $false
                    } | ConvertTo-Json -Compress
                    
                    try {
                        $rstUrl = $BaseUrl + "jobs/$SecretKey/$rstJobId.json"
                        $null = Invoke-FirebaseHttp -Uri $rstUrl -Method "PUT" -Body $rstBody -TimeoutSec 10
                        Write-Host "  -> ส่งสัญญาณ Auto-Restart สำเร็จ! รอให้ Agent รีเซ็ตเครื่อง 5 วินาที..." -ForegroundColor Green
                    } catch {
                        Write-Host "  -> [WARNING] ไม่สามารถส่งสัญญาณ Auto-Restart: $_" -ForegroundColor DarkYellow
                    }
                    
                    Start-Sleep -Seconds 5
                    
                    Write-Host "  -> ดำเนินการส่งคำสั่งจริงใหม่อีกครั้งหลัง Agent รีเซ็ตเสร็จสิ้น..." -ForegroundColor Cyan
                    Write-Host "======================================================================`n" -ForegroundColor Yellow
                    $retryAttempt = 0
                    $maxRetries = 0 # ให้รอบนี้เป็น Final Attempt หลัง Restart
                    continue
                } else {
                    Write-Host "`n[AI WATCHDOG] ยุติการทำงาน: ระบบพยายาม Auto-Retry และ Restart Agent แล้วแต่ยังไม่ตอบสนอง" -ForegroundColor Red
                    Write-Host "กรุณาตรวจสอบเซิร์ฟเวอร์ปลายทาง หรือตรวจสอบ PIN: [ $SecretKey ]" -ForegroundColor Yellow
                    break
                }
            }
        }
    }
}
finally {
    try { [Console]::remove_CancelKeyPress($senderCancelHandler) } catch {}
}

if (-not $finalJobSuccess -and -not $script:hangDetected) {
    Write-Host "`n`n[WARNING] Listening timed out or no agent pulled the job." -ForegroundColor Red
}
