<# :
@echo off
title CMD_Remote Command Sender
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[scriptblock]::Create((Get-Content -Encoding UTF8 '%~f0') -join \"`n\"); & $s %*"
exit /b
#>
param (
    [string]$FirebaseUrl = "https://uat-api-agent-default-rtdb.firebaseio.com/",
    [string]$SecretKey,
    [string]$Mode,
    [string]$ConnectionString,
    [string]$DbName,
    [string]$SqlQuery,
    [string]$SqlFile,
    [string]$OutputDir,
    [string]$LocalPath,
    [string]$RemotePath,
    [int]$TimeoutSec = 300
)

# Force console output encoding to UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Enable TLS 1.2 security protocol
try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# --- Auto check and download curl.exe if missing ---
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
    
    Write-Host "[PRE-CHECK] curl.exe is missing. Downloading automatically to TEMP..." -ForegroundColor Yellow
    $downloadUrl = "https://raw.githubusercontent.com/SDPLaos2023/CMD_Remote/main/curl.exe"
    
    try {
        $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempCurlPath -TimeoutSec 45 -UserAgent $userAgent
        if (Test-Path $tempCurlPath) {
            Write-Host "[SUCCESS] curl.exe downloaded and installed successfully to TEMP!" -ForegroundColor Green
        } else {
            throw "Downloaded file is empty or corrupted."
        }
    }
    catch {
        Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
        Write-Host "[HINT] Please download curl.exe manually and place it in your Windows TEMP directory ($env:TEMP)." -ForegroundColor Yellow
    }
}

Ensure-CurlInstalled

# Resolve curl path
$curlPath = "curl.exe"
$hasGlobalCurl = $null
try { $hasGlobalCurl = Get-Command curl.exe -ErrorAction SilentlyContinue } catch {}
if (-not $hasGlobalCurl) {
    $curlPath = Join-Path $env:TEMP "curl.exe"
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

# --- 1. Prompt for Secret Key if not provided ---
if ([string]::IsNullOrWhiteSpace($SecretKey)) {
    $SecretKey = Read-Host "Enter Shared Secret Key"
}
if ([string]::IsNullOrWhiteSpace($SecretKey)) {
    Write-Host "[ERROR] Shared Secret Key is empty. Aborting." -ForegroundColor Red
    return
}

if ($FirebaseUrl -notlike "*/") {
    $FirebaseUrl = $FirebaseUrl + "/"
}

# --- 2. Prompt for operation mode if invalid ---
$validModes = @("PowerShell", "Query", "Backup", "Download", "Upload")
if ([string]::IsNullOrWhiteSpace($Mode) -or $validModes -notcontains $Mode) {
    Write-Host "`nSelect Operation Mode:" -ForegroundColor Yellow
    Write-Host "[1] PowerShell Command Mode (Standard)" -ForegroundColor White
    Write-Host "[2] SQL Server Query Mode (Returns JSON)" -ForegroundColor White
    Write-Host "[3] SQL Server Backup Mode (Base64 file retrieval)" -ForegroundColor White
    Write-Host "[4] File Download Mode (Download directory/file)" -ForegroundColor White
    Write-Host "[5] File Upload Mode (Upload directory/file)" -ForegroundColor White
    $modeChoice = Read-Host "Select option [1-5] (Default is 1)"
    if ($modeChoice -eq "2") {
        $Mode = "Query"
    } elseif ($modeChoice -eq "3") {
        $Mode = "Backup"
    } elseif ($modeChoice -eq "4") {
        $Mode = "Download"
    } elseif ($modeChoice -eq "5") {
        $Mode = "Upload"
    } else {
        $Mode = "PowerShell"
    }
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
`$FirebaseUrl = "$FirebaseUrl"
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
`$FirebaseUrl = "$FirebaseUrl"
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


# --- 4. Submit job JSON metadata payload to Firebase ---
$jobId = "job-" + [Guid]::NewGuid().ToString().Substring(0, 8)
$jobBody = @{
    secret_key = $SecretKey
    script_content = $finalScript
    status = "pending"
    created_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
} | ConvertTo-Json -Compress

$tempJsonFile = Join-Path $env:TEMP "sender_payload_temp.json"

Write-Host "`nPublishing job payload to cloud command board..." -ForegroundColor Yellow
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tempJsonFile, $jobBody, $utf8NoBom)
    $putUrl = $FirebaseUrl + "jobs/$SecretKey/$jobId.json"
    $null = & $curlPath -s -L -k -X PUT -H "Content-Type: application/json" -d "@$tempJsonFile" $putUrl
    if (Test-Path $tempJsonFile) { Remove-Item $tempJsonFile -Force }
    Write-Host "[SUCCESS] Published successfully! Job ID: $jobId" -ForegroundColor Green
}
catch {
    if (Test-Path $tempJsonFile) { Remove-Item $tempJsonFile -Force }
    Write-Host "[ERROR] Failed to connect to Firebase: $_" -ForegroundColor Red
    return
}

# --- 5. Start listening loop (Firebase SSE Push Engine + Graceful Polling Fallback) ---
Write-Host "`nListening and waiting for CMD_Remote Agent response (Firebase SSE Push Engine)..." -ForegroundColor Yellow
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:completed = $false

$script:lastHeartbeatValue = ""
$script:lastActiveTime = [DateTime]::Now
$script:lastPhase = ""

$script:printedStdoutLen = 0
$script:printedStderrLen = 0
$script:printedRunningHeader = $false
$script:checkUrl = $FirebaseUrl + "jobs/$SecretKey/$jobId.json"
$script:isReceiveFileJob = $isReceiveFileJob
$script:OutputDir = $OutputDir
$script:curlPath = $curlPath

function Process-JobStatusObject {
    param([PSCustomObject]$statusCheck)
    if (-not $statusCheck) { return $false }
    
    $status = $statusCheck.status
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
            [System.Console]::Write($newStdout)
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
            [System.Console]::Write($newStderr)
            $script:printedStderrLen = $stderrVal.Length
            $script:lastActiveTime = [DateTime]::Now
        }
    }
    
    if ($status -eq "completed" -or $status -eq "failed") {
        Write-Host "`n`n==========================================" -ForegroundColor Green
        Write-Host "CMD_Remote Output Report (Status: $status)" -ForegroundColor Green
        Write-Host "==========================================" -ForegroundColor Green
        
        if (-not $script:isReceiveFileJob) {
            $stdoutVal = $statusCheck.stdout
            if ($stdoutVal -and $stdoutVal.Length -gt $script:printedStdoutLen) {
                $newStdout = $stdoutVal.Substring($script:printedStdoutLen)
                Write-Host -NoNewline $newStdout -ForegroundColor Gray
                [System.Console]::Write($newStdout)
            }
            $stderrVal = $statusCheck.stderr
            if ($stderrVal -and $stderrVal.Length -gt $script:printedStderrLen) {
                $newStderr = $stderrVal.Substring($script:printedStderrLen)
                Write-Host -NoNewline $newStderr -ForegroundColor DarkRed
                [System.Console]::Write($newStderr)
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
        
        $null = & $script:curlPath -s -L -k -X DELETE $script:checkUrl
        $script:completed = $true
        return $true
    }
    
    return $false
}

# Main Listening Engine: Dual-Engine SSE Push Receiver
while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSec -and -not $script:completed) {
    try {
        $request = [System.Net.HttpWebRequest]::Create($script:checkUrl)
        $request.Accept = "text/event-stream"
        $remTimeout = [Math]::Max(5000, [int](($TimeoutSec - $stopwatch.Elapsed.TotalSeconds) * 1000))
        $request.Timeout = $remTimeout
        $request.ReadWriteTimeout = $remTimeout
        
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        
        $dataBuffer = [System.Text.StringBuilder]::new()
        
        while (-not $reader.EndOfStream -and -not $script:completed) {
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
                                    if ($isFinished) { $completed = $true; break }
                                }
                            }
                        } catch {}
                    }
                }
            }
        }
        $response.Close()
        if ($completed) { break }
    }
    catch {
        # Fallback polling check if SSE connection drops
        try {
            $jsonRaw = & $script:curlPath -s -L -k $script:checkUrl
            if (-not [string]::IsNullOrEmpty($jsonRaw) -and $jsonRaw -ne "null") {
                $statusCheck = ConvertFrom-Json -InputObject $jsonRaw -ErrorAction SilentlyContinue
                if ($statusCheck) {
                    $isFinished = Process-JobStatusObject -statusCheck $statusCheck
                    if ($isFinished) { $completed = $true; break }
                }
            }
        } catch {}
        if ($completed) { break }
        Start-Sleep -Seconds 1
    }
}

if (-not $script:completed) {
    Write-Host "`n`n[WARNING] Listening timed out or no agent pulled the job." -ForegroundColor Red
}
