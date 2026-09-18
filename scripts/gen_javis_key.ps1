<#
.SYNOPSIS
    BB_JAVIS Enterprise API Key Generator
    ระบบสร้าง Signed API Key ด้วยเทคโนโลยี HMAC-SHA256 Cryptographic Signature

.DESCRIPTION
    สร้าง API Key ที่ปลอดภัยสูง ป้องกันการปลอมแปลง 100% โดยไม่ต้องเชื่อมต่อฐานข้อมูล
    รูปแบบคีย์: bbj_<tenant>_<timestamp>_<signature>
#>

[CmdletBinding()]
param(
    [string]$Tenant = "sdpuat",
    [string]$MasterSecret = "JAVIS_SECURE_ENTERPRISE_MASTER_KEY_2026",
    [switch]$SaveToThisMachine,
    [switch]$CopyToClipboard
)

# บังคับการเข้ารหัส UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "              BB_JAVIS ENTERPRISE API KEY GENERATOR                   " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan

# 1. ทำความสะอาดชื่อ Tenant (เฉพาะ a-z, 0-9)
$cleanTenant = ($Tenant -replace "[^a-zA-Z0-9]", "").ToLower()
if ([string]::IsNullOrWhiteSpace($cleanTenant)) {
    $cleanTenant = "default"
}

# 2. คำนวณ Timestamp ในรูปแบบ Hex (Unix Epoch วินาที)
$unixTime = [int][double]::Parse((Get-Date -UFormat %s))
$timeHex = $unixTime.ToString("x8")

# 3. คำนวณ HMAC-SHA256
$payload = "$cleanTenant`:$timeHex"
$hmac = New-Object System.Security.Cryptography.HMACSHA256
$hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($MasterSecret)
$hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
$hashHex = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""
$signature = $hashHex.Substring(0, 32)

# 4. ประกอบเป็น BB_JAVIS API Key
$apiKey = "bbj_${cleanTenant}_${timeHex}_${signature}"

Write-Host "  -> Tenant Name : " -NoNewline -ForegroundColor Gray
Write-Host $cleanTenant -ForegroundColor Green
Write-Host "  -> Created At  : " -NoNewline -ForegroundColor Gray
Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor White
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Generated API Key:" -ForegroundColor Cyan
Write-Host "  $apiKey" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray

# 5. ตัวเลือกคัดลอกลง Clipboard
if ($CopyToClipboard.IsPresent) {
    try {
        Set-Clipboard -Value $apiKey
        Write-Host "  [OK] Copied API Key to Windows Clipboard!" -ForegroundColor Green
    } catch {}
}

# 6. ตัวเลือกบันทึกจำลงเครื่องนี้ทันที
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
