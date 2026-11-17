# BB_JAVIS Shared Cryptographic, SQL Guard & Audit Library (Pure ASCII, PowerShell 5.1 / .NET 4.x)
try { Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue } catch {}

function New-JavisRandomBytes {
    param([int]$Length = 32)
    $bytes = New-Object byte[] $Length
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return ,$bytes
}

function Get-JavisSha256Hex {
    param([string]$Text)
    if ($null -eq $Text) { $Text = "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
        return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha.Dispose()
    }
}

function Test-JavisFixedTimeEquals {
    param([byte[]]$A, [byte[]]$B)
    if ($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $A.Length; $i++) {
        $diff = $diff -bor ($A[$i] -bxor $B[$i])
    }
    return ($diff -eq 0)
}

function New-JavisRsaKeyPair {
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(2048)
    try {
        $rsa.PersistKeyInCsp = $false
        return @{
            PublicXml  = $rsa.ToXmlString($false)
            PrivateXml = $rsa.ToXmlString($true)
        }
    } finally {
        $rsa.Dispose()
    }
}

function Protect-JavisLocalSecret {
    param(
        [Parameter(Mandatory = $true)][string]$PlainText,
        [ValidateSet("CurrentUser", "LocalMachine")][string]$Scope = "CurrentUser"
    )
    $dpScope = if ($Scope -eq "LocalMachine") {
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    } else {
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, $dpScope)
    return [Convert]::ToBase64String($protected)
}

function Unprotect-JavisLocalSecret {
    param(
        [Parameter(Mandatory = $true)][string]$ProtectedBase64,
        [ValidateSet("CurrentUser", "LocalMachine")][string]$Scope = "CurrentUser"
    )
    $dpScope = if ($Scope -eq "LocalMachine") {
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    } else {
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    }
    $protected = [Convert]::FromBase64String($ProtectedBase64)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($protected, $null, $dpScope)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Protect-JavisPayload {
    param(
        [Parameter(Mandatory = $true)][string]$PlainJson,
        [Parameter(Mandatory = $true)][string]$RecipientPubXml,
        [Parameter(Mandatory = $true)][string]$SenderPrivXml,
        [Parameter(Mandatory = $true)][string]$JobId,
        [string]$TimestampUtc = ""
    )

    if ([string]::IsNullOrWhiteSpace($TimestampUtc)) {
        $TimestampUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $aesKey = New-JavisRandomBytes -Length 32
    $hmacKey = New-JavisRandomBytes -Length 32
    $iv = New-JavisRandomBytes -Length 16

    $aes = New-Object System.Security.Cryptography.AesManaged
    $aes.KeySize = 256
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $aesKey
    $aes.IV = $iv

    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainJson)
    $ctBytes = $null
    $enc = $aes.CreateEncryptor()
    try {
        $ctBytes = $enc.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    } finally {
        $enc.Dispose()
        $aes.Dispose()
    }

    # Encrypt-then-MAC: HMAC-SHA256 over (iv || ct)
    $macInput = New-Object byte[] ($iv.Length + $ctBytes.Length)
    [Buffer]::BlockCopy($iv, 0, $macInput, 0, $iv.Length)
    [Buffer]::BlockCopy($ctBytes, 0, $macInput, $iv.Length, $ctBytes.Length)

    $hmac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (,$hmacKey)
    try {
        $macBytes = $hmac.ComputeHash($macInput)
    } finally {
        $hmac.Dispose()
    }

    # Wrap (aesKey || hmacKey) with recipient RSA-2048 OAEP
    $keyBlob = New-Object byte[] 64
    [Buffer]::BlockCopy($aesKey, 0, $keyBlob, 0, 32)
    [Buffer]::BlockCopy($hmacKey, 0, $keyBlob, 32, 32)

    $rsaEnc = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsaEnc.PersistKeyInCsp = $false
        $rsaEnc.FromXmlString($RecipientPubXml)
        $ekBytes = $rsaEnc.Encrypt($keyBlob, $true)
    } finally {
        $rsaEnc.Dispose()
    }

    $ekB64 = [Convert]::ToBase64String($ekBytes)
    $ivB64 = [Convert]::ToBase64String($iv)
    $ctB64 = [Convert]::ToBase64String($ctBytes)
    $macB64 = [Convert]::ToBase64String($macBytes)

    $canonical = "2|$TimestampUtc|$JobId|$ekB64|$ivB64|$ctB64|$macB64"
    $rsaSign = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsaSign.PersistKeyInCsp = $false
        $rsaSign.FromXmlString($SenderPrivXml)
        $sigBytes = $rsaSign.SignData([System.Text.Encoding]::UTF8.GetBytes($canonical), "SHA256")
        $sigB64 = [Convert]::ToBase64String($sigBytes)
    } finally {
        $rsaSign.Dispose()
    }

    return (@{
        v      = 2
        ts     = $TimestampUtc
        job_id = $JobId
        ek     = $ekB64
        iv     = $ivB64
        ct     = $ctB64
        mac    = $macB64
        sig    = $sigB64
    } | ConvertTo-Json -Compress)
}

function Unprotect-JavisPayload {
    param(
        [Parameter(Mandatory = $true)]$Envelope,
        [Parameter(Mandatory = $true)][string]$RecipientPrivXml,
        [Parameter(Mandatory = $true)][string]$ExpectedSenderPubXml,
        [Parameter(Mandatory = $true)][string]$ExpectedJobId,
        [int]$MaxSkewSec = 300
    )

    if (-not $Envelope -or $Envelope.v -ne 2) {
        throw "Unsupported or missing E2E envelope version."
    }
    if ($Envelope.job_id -ne $ExpectedJobId) {
        throw "Envelope job_id mismatch."
    }

    $tsUtc = [DateTime]::Parse($Envelope.ts).ToUniversalTime()
    $skew = [Math]::Abs(([DateTime]::UtcNow - $tsUtc).TotalSeconds)
    if ($skew -gt $MaxSkewSec) {
        throw "Envelope timestamp outside allowed clock skew (${MaxSkewSec}s)."
    }

    # Verify RSA-SHA256 sender signature before decrypting
    $canonical = "2|$($Envelope.ts)|$($Envelope.job_id)|$($Envelope.ek)|$($Envelope.iv)|$($Envelope.ct)|$($Envelope.mac)"
    $sigBytes = [Convert]::FromBase64String($Envelope.sig)
    $rsaVerify = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsaVerify.PersistKeyInCsp = $false
        $rsaVerify.FromXmlString($ExpectedSenderPubXml)
        $sigValid = $rsaVerify.VerifyData([System.Text.Encoding]::UTF8.GetBytes($canonical), "SHA256", $sigBytes)
    } finally {
        $rsaVerify.Dispose()
    }
    if (-not $sigValid) {
        throw "Invalid sender signature."
    }

    # Unwrap aesKey || hmacKey
    $ekBytes = [Convert]::FromBase64String($Envelope.ek)
    $rsaDec = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsaDec.PersistKeyInCsp = $false
        $rsaDec.FromXmlString($RecipientPrivXml)
        $keyBlob = $rsaDec.Decrypt($ekBytes, $true)
    } finally {
        $rsaDec.Dispose()
    }
    if ($keyBlob.Length -ne 64) {
        throw "Invalid wrapped key length."
    }

    $aesKey = New-Object byte[] 32
    $hmacKey = New-Object byte[] 32
    [Buffer]::BlockCopy($keyBlob, 0, $aesKey, 0, 32)
    [Buffer]::BlockCopy($keyBlob, 32, $hmacKey, 0, 32)

    $iv = [Convert]::FromBase64String($Envelope.iv)
    $ctBytes = [Convert]::FromBase64String($Envelope.ct)
    $macBytes = [Convert]::FromBase64String($Envelope.mac)

    $macInput = New-Object byte[] ($iv.Length + $ctBytes.Length)
    [Buffer]::BlockCopy($iv, 0, $macInput, 0, $iv.Length)
    [Buffer]::BlockCopy($ctBytes, 0, $macInput, $iv.Length, $ctBytes.Length)

    $hmac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (,$hmacKey)
    try {
        $expectedMac = $hmac.ComputeHash($macInput)
    } finally {
        $hmac.Dispose()
    }
    if (-not (Test-JavisFixedTimeEquals -A $macBytes -B $expectedMac)) {
        throw "HMAC authentication failed (ciphertext tampered)."
    }

    $aes = New-Object System.Security.Cryptography.AesManaged
    $aes.KeySize = 256
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $aesKey
    $aes.IV = $iv

    $dec = $aes.CreateDecryptor()
    try {
        $plainBytes = $dec.TransformFinalBlock($ctBytes, 0, $ctBytes.Length)
        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    } finally {
        $dec.Dispose()
        $aes.Dispose()
    }
}

function Test-JavisReadOnlySql {
    param([string]$Sql)
    if ([string]::IsNullOrWhiteSpace($Sql)) { return $false }

    # Strip single-quoted string literals, block comments, and line comments cleanly
    $stripped = [regex]::Replace($Sql, "'(?:''|[^'])*'", " '' ")
    $stripped = [regex]::Replace($stripped, "/\*[\s\S]*?\*/", " ")
    $stripped = [regex]::Replace($stripped, "--[^\r\n]*", " ")
    $stripped = $stripped.Trim()

    if ([string]::IsNullOrWhiteSpace($stripped)) { return $false }

    # Allow at most one trailing semicolon; reject stacked batches
    $noTrailing = $stripped.TrimEnd(';').Trim()
    if ($noTrailing.Contains(";")) { return $false }

    # Must begin with SELECT or WITH
    if ($noTrailing -notmatch "^(?i)(SELECT|WITH)\b") { return $false }

    # Block mutating / procedural / dangerous statements
    $forbidden = "\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|EXEC|EXECUTE|INTO|GRANT|REVOKE|DENY|BACKUP|RESTORE|DBCC|SHUTDOWN|RECONFIGURE|OPENROWSET|OPENDATASOURCE|BULK)\b|\b(xp_|sp_)[a-zA-Z0-9_]+"
    if ($noTrailing -match $forbidden) { return $false }

    return $true
}

function Protect-JavisPiiTable {
    param(
        $Rows,
        [switch]$RawData
    )
    if ($null -eq $Rows) { return @() }
    $rowList = @($Rows)
    if ($RawData.IsPresent -or $rowList.Count -eq 0) {
        return ,$rowList
    }

    $sensitivePattern = "(?i)(password|pwd|pass|secret|token|apikey|api_key|salt|hash|pin|otp|citizen|national_id|id_card|passport|phone|mobile|tel|email|mail|bank|account_no|card_no|cvv|address|salary|tax_id)"
    $maskedRows = [System.Collections.Generic.List[object]]::new()

    foreach ($r in $rowList) {
        if ($null -eq $r) { continue }
        $copy = [ordered]@{}
        foreach ($prop in $r.PSObject.Properties) {
            $name = $prop.Name
            $val = $prop.Value
            if ($name -match $sensitivePattern -and $null -ne $val -and -not [string]::IsNullOrEmpty($val.ToString())) {
                $s = $val.ToString()
                if ($s.Length -gt 4) {
                    $copy[$name] = "***" + $s.Substring($s.Length - 2)
                } else {
                    $copy[$name] = "***REDACTED***"
                }
            } else {
                $copy[$name] = $val
            }
        }
        $maskedRows.Add([PSCustomObject]$copy)
    }

    return ,($maskedRows.ToArray())
}

function Add-JavisAuditEntry {
    param(
        [Parameter(Mandatory = $true)][string]$AuditDir,
        [Parameter(Mandatory = $true)][string]$JobId,
        [Parameter(Mandatory = $true)][string]$AdminId,
        [Parameter(Mandatory = $true)][string]$Mode,
        [string]$DbProfile = "",
        [string]$CommandText = "",
        [int]$ExitCode = 0,
        [int]$RowsAffected = 0
    )
    if (-not (Test-Path $AuditDir)) {
        $null = New-Item -ItemType Directory -Path $AuditDir -Force
    }
    $ym = [DateTime]::UtcNow.ToString("yyyy-MM")
    $auditFile = Join-Path $AuditDir "audit_$ym.jsonl"
    $prevHash = "GENESIS"
    $seq = 1
    if (Test-Path $auditFile) {
        $lastLine = Get-Content $auditFile -Tail 1 -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($lastLine)) {
            try {
                $lastObj = $lastLine | ConvertFrom-Json
                if ($lastObj -and $lastObj.entry_hash) {
                    $prevHash = $lastObj.entry_hash
                    $seq = [int]$lastObj.seq + 1
                }
            } catch {}
        }
    }
    $tsUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $cmdSha = Get-JavisSha256Hex -Text $CommandText
    $bodyForHash = "$seq|$tsUtc|$JobId|$AdminId|$Mode|$DbProfile|$cmdSha|$ExitCode|$RowsAffected|$prevHash"
    $entryHash = Get-JavisSha256Hex -Text $bodyForHash

    $entry = @{
        seq            = $seq
        ts_utc         = $tsUtc
        job_id         = $JobId
        admin_id       = $AdminId
        mode           = $Mode
        db_profile     = $DbProfile
        command_sha256 = $cmdSha
        exit_code      = $ExitCode
        rows_affected  = $RowsAffected
        prev_hash      = $prevHash
        entry_hash     = $entryHash
    } | ConvertTo-Json -Compress

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $sw = New-Object System.IO.StreamWriter($auditFile, $true, $utf8NoBom)
    try {
        $sw.WriteLine($entry)
    } finally {
        $sw.Dispose()
    }
    return $entryHash
}

function Split-JavisSqlStatements {
    param([string]$Sql)
    $list = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($Sql)) { return ,($list.ToArray()) }

    $sb = New-Object System.Text.StringBuilder
    $inSingleQuote = $false
    $inLineComment = $false
    $inBlockComment = $false
    $len = $Sql.Length

    for ($i = 0; $i -lt $len; $i++) {
        $ch = $Sql[$i]
        $next = if ($i + 1 -lt $len) { $Sql[$i + 1] } else { [char]0 }

        if ($inLineComment) {
            [void]$sb.Append($ch)
            if ($ch -eq "`n") { $inLineComment = $false }
            continue
        }
        if ($inBlockComment) {
            [void]$sb.Append($ch)
            if ($ch -eq '*' -and $next -eq '/') {
                [void]$sb.Append('/')
                $i++
                $inBlockComment = $false
            }
            continue
        }
        if ($inSingleQuote) {
            [void]$sb.Append($ch)
            if ($ch -eq "'" -and $next -eq "'") {
                [void]$sb.Append("'")
                $i++
            } elseif ($ch -eq "'") {
                $inSingleQuote = $false
            }
            continue
        }

        if ($ch -eq '-' -and $next -eq '-') {
            [void]$sb.Append("--")
            $i++
            $inLineComment = $true
            continue
        }
        if ($ch -eq '/' -and $next -eq '*') {
            [void]$sb.Append("/*")
            $i++
            $inBlockComment = $true
            continue
        }
        if ($ch -eq "'") {
            [void]$sb.Append($ch)
            $inSingleQuote = $true
            continue
        }
        if ($ch -eq ';') {
            $seg = $sb.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($seg)) { $list.Add($seg) }
            [void]$sb.Clear()
            continue
        }
        [void]$sb.Append($ch)
    }

    $tail = $sb.ToString().Trim()
    if (-not [string]::IsNullOrWhiteSpace($tail)) { $list.Add($tail) }
    return $list.ToArray()
}

function Resolve-JavisAutoMode {
    param(
        [string]$Text = "",
        [switch]$HasLocalPort,
        [switch]$RawData
    )
    if ($HasLocalPort.IsPresent) {
        return @{
            Mode            = "Tunnel"
            FallbackMode    = "Query"
            Statements      = @()
            RequiresConfirm = $false
            Reason          = "Explicit local port requested for direct TCP/SSMS access"
        }
    }

    $stmts = @(Split-JavisSqlStatements -Sql $Text)
    if ($stmts.Count -gt 0) {
        $allReadOnly = $true
        foreach ($s in $stmts) {
            if (-not (Test-JavisReadOnlySql -Sql $s)) {
                $allReadOnly = $false
                break
            }
        }
        if ($allReadOnly) {
            if ($stmts.Count -ge 4) {
                return @{
                    Mode            = "Tunnel"
                    FallbackMode    = "Query"
                    Statements      = $stmts
                    RequiresConfirm = $false
                    Reason          = "Batch of $($stmts.Count) read queries (>= 4 threshold); Tunnel preferred with Query fallback"
                }
            }
            return @{
                Mode            = "Query"
                FallbackMode    = ""
                Statements      = $stmts
                RequiresConfirm = $false
                Reason          = "1-3 Read-Only SQL queries; Query lane is fastest and enforces PII masking"
            }
        }

        if ($Text -match "(?is)^\s*(?:--[^\r\n]*\s+|/\*[\s\S]*?\*/\s*)*(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|EXEC|EXECUTE|GRANT|REVOKE|BACKUP|RESTORE)\b") {
            return @{
                Mode            = "SqlExec"
                FallbackMode    = ""
                Statements      = $stmts
                RequiresConfirm = $true
                Reason          = "Write/procedural SQL detected; routing to SqlExec with confirmation gate"
            }
        }
    }

    return @{
        Mode            = "PowerShell"
        FallbackMode    = ""
        Statements      = @()
        RequiresConfirm = $false
        Reason          = "Non-SQL command detected; routing to PowerShell"
    }
}
