param (
    [string]$ApiKey,
    [string]$GatewayUrl,
    [string]$FirebaseUrl = "https://uat-api-agent-default-rtdb.firebaseio.com/",
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
    [int]$TimeoutSec = 300
)

# Force console output encoding to UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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
    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = $Method
    $request.Timeout = $TimeoutSec * 1000
    $request.ReadWriteTimeout = $TimeoutSec * 1000
    $request.KeepAlive = $false

    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $request.Headers["X-Javis-Key"] = $Key
        $request.Headers["Authorization"] = "Bearer " + $Key
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

# --- 1. Prompt for Secret Key if not provided ---
if ([string]::IsNullOrWhiteSpace($SecretKey)) {
    $SecretKey = Read-Host "Enter Shared Secret Key"
}
if ([string]::IsNullOrWhiteSpace($SecretKey)) {
    Write-Host "[ERROR] Shared Secret Key is empty. Aborting." -ForegroundColor Red
    return
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


# --- 4. Submit job JSON metadata payload to Firebase ---
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

Write-Host "`nPublishing job payload to cloud command board..." -ForegroundColor Yellow
try {
    $putUrl = $BaseUrl + "jobs/$SecretKey/$jobId.json"
    $null = Invoke-FirebaseHttp -Uri $putUrl -Method "PUT" -Body $jobBody -TimeoutSec 15
    Write-Host "[SUCCESS] Published successfully! Job ID: $jobId (Timeout: ${TimeoutSec}s)" -ForegroundColor Green
}
catch {
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
$script:checkUrl = $BaseUrl + "jobs/$SecretKey/$jobId.json"
$script:isReceiveFileJob = $isReceiveFileJob
$script:OutputDir = $OutputDir

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

# ดักจับ Ctrl+C เพื่อส่งสัญญาณ Emergency Abort ไปยังเครื่องเป้าหมาย
$senderCancelHandler = [ConsoleCancelEventHandler]{
    param($s, $e)
    Write-Host "`n`n[EMERGENCY ABORT] User requested stop! Sending abort signal to remote agent..." -ForegroundColor Red
    try {
        $abortUrl = $script:checkUrl.Replace(".json", "/abort.json")
        $null = Invoke-FirebaseHttp -Uri $abortUrl -Method "PUT" -Body "true" -TimeoutSec 5
        Write-Host "[SUCCESS] Abort signal sent to Cloud board." -ForegroundColor Green
    } catch {}
}
try { [Console]::add_CancelKeyPress($senderCancelHandler) } catch {}

# Main Listening Engine: Dual-Engine SSE Push Receiver
try {
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSec -and -not $script:completed) {
        try {
            $request = [System.Net.HttpWebRequest]::Create($script:checkUrl)
            $request.Accept = "text/event-stream"
            if (-not [string]::IsNullOrWhiteSpace($script:JavisApiKey)) {
                $request.Headers["X-Javis-Key"] = $script:JavisApiKey
                $request.Headers["Authorization"] = "Bearer " + $script:JavisApiKey
            }
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
                $jsonRaw = Invoke-FirebaseHttp -Uri $script:checkUrl -Method "GET" -TimeoutSec 5
                if (-not [string]::IsNullOrEmpty($jsonRaw) -and $jsonRaw -ne "null") {
                    $statusCheck = ConvertFrom-Json -InputObject $jsonRaw -ErrorAction SilentlyContinue
                    if ($statusCheck) {
                        $isFinished = Process-JobStatusObject -statusCheck $statusCheck
                        if ($isFinished) { $completed = $true; break }
                    }
                }
            } catch {}
            if ($completed) { break }
            Start-Sleep -Milliseconds 100
        }
    }
}
finally {
    try { [Console]::remove_CancelKeyPress($senderCancelHandler) } catch {}
}

if (-not $script:completed) {
    Write-Host "`n`n[WARNING] Listening timed out or no agent pulled the job." -ForegroundColor Red
}
