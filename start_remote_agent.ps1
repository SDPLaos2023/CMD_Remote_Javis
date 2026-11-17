param (
    [string]$GatewayUrl = "",
    [string]$DeviceName = "",
    [string]$Mode = "temp",
    [switch]$AsService,
    [switch]$InstallService,
    [switch]$UninstallService,
    [switch]$ConfigureDbProfile,
    [string]$DbProfileName = "",
    [string]$DbConnectionString = "",
    [int]$PollIntervalSec = 3,
    [double]$IdleTimeoutMinutes = 300
)

$ErrorActionPreference = "Stop"

try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 128
    [System.Net.ServicePointManager]::Expect100Continue = $false
    [System.Net.ServicePointManager]::MaxServicePointIdleTime = 5000
} catch {}

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
} catch {}

# __BEGIN_JAVIS_LIB__
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

function Test-JavisIdleTimeoutExpired {
    <#
    .SYNOPSIS
    Returns $true when a temporary-mode agent has exceeded its inactivity budget with no active tunnels.
    #>
    param(
        [bool]$IsFixedService,
        [double]$IdleTimeoutMinutes,
        [DateTime]$LastActivityUtc,
        [int]$ActiveTunnelCount = 0,
        [DateTime]$NowUtc = [DateTime]::UtcNow
    )
    if ($IsFixedService -or $IdleTimeoutMinutes -le 0) { return $false }
    if ($ActiveTunnelCount -gt 0) { return $false }
    return (($NowUtc - $LastActivityUtc).TotalMinutes -ge $IdleTimeoutMinutes)
}

# BB_JAVIS Native WebSocket-to-TCP Tunnel Library (Pure ASCII, PowerShell 5.1 / .NET 4.5+)

function Get-JavisCscPath {
    $csc64 = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (Test-Path $csc64) { return $csc64 }
    $csc32 = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
    if (Test-Path $csc32) { return $csc32 }
    throw "csc.exe (.NET Framework 4.x) not found."
}

function Ensure-JavisTunnelExe {
    param([Parameter(Mandatory = $true)][string]$BinDir)
    if (-not (Test-Path $BinDir)) {
        $null = New-Item -ItemType Directory -Path $BinDir -Force
    }
    $exePath = Join-Path $BinDir "BBJavisTunnel.exe"
    $csPath = Join-Path $BinDir "BBJavisTunnel.cs"

    $csSource = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace BBJavisTunnel
{
    class Program
    {
        static int Main(string[] args)
        {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | (SecurityProtocolType)768 | (SecurityProtocolType)192;
            if (args.Length >= 5 && args[0] == "server")
            {
                int wsPort = int.Parse(args[1]);
                string targetHost = args[2];
                int targetPort = int.Parse(args[3]);
                string token = args[4];
                int ttlSec = args.Length >= 6 ? int.Parse(args[5]) : 1800;
                return RunServer(wsPort, targetHost, targetPort, token, ttlSec);
            }
            if (args.Length >= 4 && args[0] == "client")
            {
                int localPort = int.Parse(args[1]);
                string wssUrl = args[2];
                string token = args[3];
                return RunClient(localPort, wssUrl, token);
            }
            int legacyPort;
            if (args.Length >= 4 && int.TryParse(args[0], out legacyPort))
            {
                string targetHost = args[1];
                int targetPort = int.Parse(args[2]);
                string token = args[3];
                int ttlSec = args.Length >= 5 ? int.Parse(args[4]) : 1800;
                return RunServer(legacyPort, targetHost, targetPort, token, ttlSec);
            }
            Console.Error.WriteLine("Usage: BBJavisTunnel.exe server <wsPort> <targetHost> <targetPort> <token> [ttlSec]");
            Console.Error.WriteLine("       BBJavisTunnel.exe client <localPort> <wssUrl> <token>");
            return 2;
        }

        static bool ConstantTimeEquals(string a, string b)
        {
            if (a == null || b == null) return false;
            byte[] ba = Encoding.UTF8.GetBytes(a);
            byte[] bb = Encoding.UTF8.GetBytes(b);
            if (ba.Length != bb.Length) return false;
            int diff = 0;
            for (int i = 0; i < ba.Length; i++) diff |= (ba[i] ^ bb[i]);
            return diff == 0;
        }

        static int RunServer(int wsPort, string targetHost, int targetPort, string expectedToken, int ttlSec)
        {
            if (targetHost != "127.0.0.1" && targetHost.ToLowerInvariant() != "localhost")
            {
                Console.Error.WriteLine("Target host restricted to loopback.");
                return 3;
            }

            TcpListener listener = new TcpListener(IPAddress.Loopback, wsPort);
            listener.Start();
            Console.WriteLine("LISTENING 127.0.0.1:" + wsPort);
            Console.Out.Flush();

            using (Timer ttlTimer = new Timer(_ => { try { listener.Stop(); } catch {} Environment.Exit(0); }, null, ttlSec * 1000, Timeout.Infinite))
            {
                while (true)
                {
                    try
                    {
                        TcpClient wsTcp = listener.AcceptTcpClient();
                        wsTcp.NoDelay = true;
                        Thread t = new Thread(() => HandleServerClient(wsTcp, targetHost, targetPort, expectedToken));
                        t.IsBackground = true;
                        t.Start();
                    }
                    catch
                    {
                        break;
                    }
                }
            }
            return 0;
        }

        static void HandleServerClient(TcpClient wsTcp, string targetHost, int targetPort, string expectedToken)
        {
            TcpClient dbTcp = null;
            try
            {
                NetworkStream wsStream = wsTcp.GetStream();
                string headersRaw = ReadHttpHeaders(wsStream);
                if (string.IsNullOrEmpty(headersRaw)) { wsTcp.Close(); return; }

                string wsKey = null;
                string authHeader = null;
                foreach (string line in headersRaw.Split(new[] { "\r\n" }, StringSplitOptions.RemoveEmptyEntries))
                {
                    int idx = line.IndexOf(':');
                    if (idx <= 0) continue;
                    string name = line.Substring(0, idx).Trim().ToLowerInvariant();
                    string val = line.Substring(idx + 1).Trim();
                    if (name == "sec-websocket-key") wsKey = val;
                    else if (name == "authorization") authHeader = val;
                }

                string supplied = "";
                if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
                {
                    supplied = authHeader.Substring(7).Trim();
                }

                if (string.IsNullOrEmpty(wsKey) || !ConstantTimeEquals(supplied, expectedToken))
                {
                    byte[] unauth = Encoding.ASCII.GetBytes("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    wsStream.Write(unauth, 0, unauth.Length);
                    wsStream.Flush();
                    wsTcp.Close();
                    return;
                }

                string acceptVal;
                using (SHA1 sha1 = SHA1.Create())
                {
                    byte[] hash = sha1.ComputeHash(Encoding.ASCII.GetBytes(wsKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"));
                    acceptVal = Convert.ToBase64String(hash);
                }

                byte[] handshake = Encoding.ASCII.GetBytes(
                    "HTTP/1.1 101 Switching Protocols\r\n" +
                    "Upgrade: websocket\r\n" +
                    "Connection: Upgrade\r\n" +
                    "Sec-WebSocket-Accept: " + acceptVal + "\r\n\r\n");
                wsStream.Write(handshake, 0, handshake.Length);
                wsStream.Flush();

                dbTcp = new TcpClient();
                dbTcp.NoDelay = true;
                dbTcp.Connect(targetHost, targetPort);
                NetworkStream dbStream = dbTcp.GetStream();

                object writeLock = new object();
                bool closed = false;

                Thread dbToWs = new Thread(() =>
                {
                    byte[] buf = new byte[32768];
                    try
                    {
                        while (!closed)
                        {
                            int n = dbStream.Read(buf, 0, buf.Length);
                            if (n <= 0) break;
                            lock (writeLock) { WriteWsFrame(wsStream, 0x02, buf, n); }
                        }
                    }
                    catch {}
                    finally
                    {
                        closed = true;
                        try { lock (writeLock) { WriteWsFrame(wsStream, 0x08, new byte[0], 0); } } catch {}
                        try { wsTcp.Close(); } catch {}
                    }
                });
                dbToWs.IsBackground = true;
                dbToWs.Start();

                while (!closed)
                {
                    int opcode;
                    byte[] payload = ReadWsFrame(wsStream, out opcode);
                    if (payload == null || opcode == 0x08) break;
                    if (opcode == 0x09)
                    {
                        lock (writeLock) { WriteWsFrame(wsStream, 0x0A, payload, payload.Length); }
                        continue;
                    }
                    if (opcode == 0x01 || opcode == 0x02 || opcode == 0x00)
                    {
                        if (payload.Length > 0)
                        {
                            dbStream.Write(payload, 0, payload.Length);
                            dbStream.Flush();
                        }
                    }
                }
                closed = true;
            }
            catch {}
            finally
            {
                try { if (dbTcp != null) dbTcp.Close(); } catch {}
                try { wsTcp.Close(); } catch {}
            }
        }

        static string ReadHttpHeaders(NetworkStream stream)
        {
            List<byte> buf = new List<byte>(1024);
            while (buf.Count < 16384)
            {
                int b = stream.ReadByte();
                if (b < 0) return null;
                buf.Add((byte)b);
                int c = buf.Count;
                if (c >= 4 && buf[c - 4] == 13 && buf[c - 3] == 10 && buf[c - 2] == 13 && buf[c - 1] == 10)
                {
                    return Encoding.ASCII.GetString(buf.ToArray());
                }
            }
            return null;
        }

        static bool ReadExact(Stream s, byte[] buf, int count)
        {
            int offset = 0;
            while (offset < count)
            {
                int n = s.Read(buf, offset, count - offset);
                if (n <= 0) return false;
                offset += n;
            }
            return true;
        }

        static byte[] ReadWsFrame(Stream s, out int opcode)
        {
            opcode = 0x08;
            byte[] hdr = new byte[2];
            if (!ReadExact(s, hdr, 2)) return null;
            opcode = hdr[0] & 0x0F;
            bool masked = (hdr[1] & 0x80) != 0;
            long len = hdr[1] & 0x7F;
            if (len == 126)
            {
                byte[] ext = new byte[2];
                if (!ReadExact(s, ext, 2)) return null;
                len = (ext[0] << 8) | ext[1];
            }
            else if (len == 127)
            {
                byte[] ext = new byte[8];
                if (!ReadExact(s, ext, 8)) return null;
                len = 0;
                for (int i = 0; i < 8; i++) len = (len << 8) | ext[i];
            }
            if (len < 0 || len > 16 * 1024 * 1024) return null;

            byte[] maskKey = new byte[4];
            if (masked && !ReadExact(s, maskKey, 4)) return null;

            byte[] payload = new byte[(int)len];
            if (len > 0 && !ReadExact(s, payload, (int)len)) return null;
            if (masked)
            {
                for (int i = 0; i < payload.Length; i++) payload[i] ^= maskKey[i % 4];
            }
            return payload;
        }

        static void WriteWsFrame(Stream s, int opcode, byte[] data, int count)
        {
            using (MemoryStream ms = new MemoryStream())
            {
                ms.WriteByte((byte)(0x80 | (opcode & 0x0F)));
                if (count < 126)
                {
                    ms.WriteByte((byte)count);
                }
                else if (count <= 65535)
                {
                    ms.WriteByte(126);
                    ms.WriteByte((byte)((count >> 8) & 0xFF));
                    ms.WriteByte((byte)(count & 0xFF));
                }
                else
                {
                    ms.WriteByte(127);
                    ulong ulen = (ulong)count;
                    for (int i = 7; i >= 0; i--) ms.WriteByte((byte)((ulen >> (i * 8)) & 0xFF));
                }
                if (count > 0) ms.Write(data, 0, count);
                byte[] frame = ms.ToArray();
                s.Write(frame, 0, frame.Length);
                s.Flush();
            }
        }

        static int RunClient(int localPort, string wssUrl, string token)
        {
            TcpListener listener = new TcpListener(IPAddress.Loopback, localPort);
            listener.Start();
            Console.WriteLine("PROXY_READY 127.0.0.1:" + localPort);
            Console.Out.Flush();

            while (true)
            {
                try
                {
                    TcpClient localTcp = listener.AcceptTcpClient();
                    localTcp.NoDelay = true;
                    Task.Run(() => HandleProxyClient(localTcp, wssUrl, token));
                }
                catch
                {
                    break;
                }
            }
            return 0;
        }

        static async Task HandleProxyClient(TcpClient localTcp, string wssUrl, string token)
        {
            ClientWebSocket ws = null;
            try
            {
                Exception lastEx = null;
                for (int attempt = 0; attempt < 4; attempt++)
                {
                    ClientWebSocket candidate = new ClientWebSocket();
                    candidate.Options.SetRequestHeader("Authorization", "Bearer " + token);
                    try
                    {
                        await candidate.ConnectAsync(new Uri(wssUrl), CancellationToken.None);
                        ws = candidate;
                        break;
                    }
                    catch (Exception ex)
                    {
                        lastEx = ex;
                        try { candidate.Dispose(); } catch {}
                    }
                    if (attempt < 3) await Task.Delay(500);
                }
                if (ws == null) throw (lastEx ?? new Exception("Failed to connect WebSocket tunnel."));
                NetworkStream tcpStream = localTcp.GetStream();

                Task t1 = Task.Run(async () =>
                {
                    byte[] buf = new byte[32768];
                    try
                    {
                        while (ws.State == WebSocketState.Open)
                        {
                            int n = await tcpStream.ReadAsync(buf, 0, buf.Length);
                            if (n <= 0) break;
                            await ws.SendAsync(new ArraySegment<byte>(buf, 0, n), WebSocketMessageType.Binary, true, CancellationToken.None);
                        }
                    }
                    catch {}
                    try { await ws.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "EOF", CancellationToken.None); } catch {}
                });

                Task t2 = Task.Run(async () =>
                {
                    byte[] buf = new byte[32768];
                    try
                    {
                        while (ws.State == WebSocketState.Open)
                        {
                            WebSocketReceiveResult res = await ws.ReceiveAsync(new ArraySegment<byte>(buf), CancellationToken.None);
                            if (res.MessageType == WebSocketMessageType.Close) break;
                            if (res.Count > 0)
                            {
                                await tcpStream.WriteAsync(buf, 0, res.Count);
                                await tcpStream.FlushAsync();
                            }
                        }
                    }
                    catch {}
                    try { localTcp.Close(); } catch {}
                });

                await Task.WhenAny(t1, t2);
            }
            catch {}
            finally
            {
                try { if (ws != null) ws.Dispose(); } catch {}
                try { localTcp.Close(); } catch {}
            }
        }
    }
}
'@

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $needsBuild = -not (Test-Path $exePath)
    if (-not $needsBuild -and (Test-Path $csPath)) {
        $existingSrc = [System.IO.File]::ReadAllText($csPath, $utf8NoBom)
        if ($existingSrc -ne $csSource) { $needsBuild = $true }
    } elseif (-not (Test-Path $csPath)) {
        $needsBuild = $true
    }

    if ($needsBuild) {
        [System.IO.File]::WriteAllText($csPath, $csSource, $utf8NoBom)
        $csc = Get-JavisCscPath
        $out = & $csc /nologo /optimize+ /target:exe /out:$exePath $csPath 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exePath)) {
            throw "Failed to compile BBJavisTunnel.exe: $out"
        }
    }
    return $exePath
}

function Ensure-CloudflaredBinary {
    param([Parameter(Mandatory = $true)][string]$BinDir)
    if (-not (Test-Path $BinDir)) {
        $null = New-Item -ItemType Directory -Path $BinDir -Force
    }
    $cfPath = Join-Path $BinDir "cloudflared.exe"
    if (Test-Path $cfPath) {
        return $cfPath
    }

    $dlUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    $apiUrl = "https://api.github.com/repos/cloudflare/cloudflared/releases/latest"

    $expectedSha = $null
    try {
        $wcApi = New-Object System.Net.WebClient
        $wcApi.Headers.Add("User-Agent", "BB_Javis/2.0")
        $relJson = $wcApi.DownloadString($apiUrl) | ConvertFrom-Json
        $wcApi.Dispose()
        $asset = $relJson.assets | Where-Object { $_.name -eq "cloudflared-windows-amd64.exe" } | Select-Object -First 1
        if ($asset -and $asset.digest -and $asset.digest -match "^sha256:([0-9a-fA-F]{64})$") {
            $expectedSha = $Matches[1].ToLower()
        }
    } catch {}

    $tmpDl = Join-Path $BinDir ("cloudflared_" + [Guid]::NewGuid().ToString("N").Substring(0, 6) + ".tmp")
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "BB_Javis/2.0")
    try {
        $wc.DownloadFile($dlUrl, $tmpDl)
    } finally {
        $wc.Dispose()
    }

    if ($expectedSha) {
        $actualSha = (Get-FileHash -Path $tmpDl -Algorithm SHA256).Hash.ToLower()
        if ($actualSha -ne $expectedSha) {
            Remove-Item $tmpDl -Force -ErrorAction SilentlyContinue
            throw "cloudflared.exe SHA-256 verification failed! Expected $expectedSha got $actualSha"
        }
    }

    Move-Item -Path $tmpDl -Destination $cfPath -Force
    return $cfPath
}
# __END_JAVIS_LIB__

if ($InstallService.IsPresent) {
    $installScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot "install_service.ps1" } else { "" }
    if ($installScript -and (Test-Path $installScript)) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript -GatewayUrl $GatewayUrl -DeviceName $DeviceName
        return
    }
    throw "install_service.ps1 not found locally."
}

if ($UninstallService.IsPresent) {
    $uninstallScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot "uninstall_service.ps1" } else { "" }
    if ($uninstallScript -and (Test-Path $uninstallScript)) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstallScript
        return
    }
    throw "uninstall_service.ps1 not found locally."
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$isFixedService = ($Mode -eq "fix" -or $AsService.IsPresent)
$serviceConfigDir = Join-Path $env:ProgramData "BB_Javis"
$serviceConfigFile = Join-Path $serviceConfigDir "service_config.json"
$deviceKeyFile = Join-Path $serviceConfigDir "device_key.dpapi"
$dbProfilesFile = Join-Path $serviceConfigDir "db_profiles.dpapi"
$auditDir = Join-Path $serviceConfigDir "audit"
$binDir = Join-Path $serviceConfigDir "bin"
$pairingBannerFile = Join-Path $serviceConfigDir "pairing.txt"

function Resolve-JavisGatewayUrl {
    param([string]$ArgUrl)
    if (-not [string]::IsNullOrWhiteSpace($ArgUrl)) { return $ArgUrl.Trim().TrimEnd('/') + "/" }
    if (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_GATEWAY_URL)) { return $env:BB_JAVIS_GATEWAY_URL.Trim().TrimEnd('/') + "/" }
    if (Test-Path $serviceConfigFile) {
        try {
            $cfg = Get-Content $serviceConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg -and -not [string]::IsNullOrWhiteSpace($cfg.gatewayUrl)) {
                return $cfg.gatewayUrl.ToString().Trim().TrimEnd('/') + "/"
            }
        } catch {}
    }
    return "https://bb-javis-gateway.apisit-yimboa.workers.dev/"
}

function Save-JavisDbProfile {
    param([string]$Name, [string]$ConnStr)
    if (-not (Test-Path $serviceConfigDir)) { $null = New-Item -ItemType Directory -Path $serviceConfigDir -Force }
    $map = @{}
    if (Test-Path $dbProfilesFile) {
        try {
            $encRaw = [System.IO.File]::ReadAllText($dbProfilesFile, $utf8NoBom)
            $plainJson = Unprotect-JavisLocalSecret -ProtectedBase64 $encRaw -Scope "LocalMachine"
            $obj = $plainJson | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = $p.Value }
        } catch {}
    }
    $map[$Name] = $ConnStr
    $newJson = $map | ConvertTo-Json -Compress
    $encOut = Protect-JavisLocalSecret -PlainText $newJson -Scope "LocalMachine"
    [System.IO.File]::WriteAllText($dbProfilesFile, $encOut, $utf8NoBom)
}

function Get-JavisDbConnectionString {
    param([string]$ProfileName, [string]$OverrideConn)
    if (-not [string]::IsNullOrWhiteSpace($OverrideConn)) { return $OverrideConn }
    if ([string]::IsNullOrWhiteSpace($ProfileName)) { $ProfileName = "Default" }
    if (Test-Path $dbProfilesFile) {
        $encRaw = [System.IO.File]::ReadAllText($dbProfilesFile, $utf8NoBom)
        $plainJson = Unprotect-JavisLocalSecret -ProtectedBase64 $encRaw -Scope "LocalMachine"
        $obj = $plainJson | ConvertFrom-Json
        if ($obj -and $obj.PSObject.Properties[$ProfileName]) {
            return $obj.PSObject.Properties[$ProfileName].Value.ToString()
        }
    }
    throw "DB Profile '$ProfileName' not found on customer server. Run with -ConfigureDbProfile first."
}

if ($ConfigureDbProfile.IsPresent) {
    if ([string]::IsNullOrWhiteSpace($DbProfileName)) { $DbProfileName = Read-Host "Enter DB Profile Name (e.g. MainDB)" }
    if ([string]::IsNullOrWhiteSpace($DbConnectionString)) {
        $sec = Read-Host "Enter SQL ConnectionString for '$DbProfileName'" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $DbConnectionString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    Save-JavisDbProfile -Name $DbProfileName -ConnStr $DbConnectionString
    Write-Host "[OK] Saved DPAPI-encrypted DB profile '$DbProfileName' to $dbProfilesFile" -ForegroundColor Green
    return
}

$BaseUrl = Resolve-JavisGatewayUrl -ArgUrl $GatewayUrl
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    if ([Environment]::UserInteractive) {
        $entered = Read-Host "Enter BB_JAVIS Cloudflare Gateway URL (e.g. https://bb-javis-gateway.example.workers.dev)"
        if (-not [string]::IsNullOrWhiteSpace($entered)) {
            $BaseUrl = $entered.Trim().TrimEnd('/') + "/"
        }
    }
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        throw "GatewayUrl is required. Pass -GatewayUrl or set BB_JAVIS_GATEWAY_URL."
    }
}

function Invoke-GatewayHttp {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Method = "GET",
        [string]$Body = $null,
        [int]$TimeoutSec = 15,
        [string]$Key = $script:DeviceToken,
        [hashtable]$ExtraHeaders = @{}
    )
    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = $Method
    $request.Timeout = $TimeoutSec * 1000
    $request.ReadWriteTimeout = $TimeoutSec * 1000
    $request.KeepAlive = $false

    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $request.Headers["X-Javis-Key"] = $Key
    }
    foreach ($hk in $ExtraHeaders.Keys) {
        $request.Headers[$hk] = $ExtraHeaders[$hk]
    }

    if (-not [string]::IsNullOrEmpty($Body)) {
        $request.ContentType = "application/json; charset=utf-8"
        $bytes = $utf8NoBom.GetBytes($Body)
        $request.ContentLength = $bytes.Length
        $reqStream = $request.GetRequestStream()
        try {
            $reqStream.Write($bytes, 0, $bytes.Length)
        } finally {
            $reqStream.Close()
        }
    }

    try {
        $response = $request.GetResponse()
        $respStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($respStream, $utf8NoBom)
        $result = $reader.ReadToEnd()
        $reader.Close()
        $respStream.Close()
        $response.Close()
        return $result
    } catch [System.Net.WebException] {
        if ($_.Response) {
            try {
                $respStream = $_.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($respStream, $utf8NoBom)
                $errResult = $reader.ReadToEnd()
                $reader.Close()
                $respStream.Close()
                $_.Response.Close()
                return $errResult
            } catch {}
        }
        throw $_
    } finally {
        try { $request.Abort() } catch {}
    }
}

# Resolve or create Device Identity + RSA-2048 keypair
$script:DeviceId = ""
$script:DeviceToken = ""
$script:TenantId = ""
$script:PairedAdmins = @{}
$script:DeviceCustomName = if (-not [string]::IsNullOrWhiteSpace($DeviceName)) { $DeviceName.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_HOST)) { $env:BB_JAVIS_HOST.Trim() } else { $env:COMPUTERNAME }
$script:DevicePrivXml = ""
$script:DevicePubXml = ""

if ($isFixedService) {
    if (-not (Test-Path $serviceConfigDir)) { $null = New-Item -ItemType Directory -Path $serviceConfigDir -Force }
    if (Test-Path $serviceConfigFile) {
        try {
            $saved = Get-Content $serviceConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($saved) {
                if ($saved.device_id) { $script:DeviceId = $saved.device_id.ToString() }
                if ($saved.custom_name -and [string]::IsNullOrWhiteSpace($DeviceName)) { $script:DeviceCustomName = $saved.custom_name.ToString() }
                if ($saved.tenant) { $script:TenantId = $saved.tenant.ToString() }
                if ($saved.device_token_dpapi) {
                    $script:DeviceToken = Unprotect-JavisLocalSecret -ProtectedBase64 $saved.device_token_dpapi -Scope "LocalMachine"
                }
                if ($saved.paired_admins) {
                    foreach ($p in $saved.paired_admins.PSObject.Properties) {
                        $script:PairedAdmins[$p.Name] = $p.Value.ToString()
                    }
                }
            }
        } catch {}
    }
    if (Test-Path $deviceKeyFile) {
        try {
            $encPair = [System.IO.File]::ReadAllText($deviceKeyFile, $utf8NoBom)
            $pairJson = Unprotect-JavisLocalSecret -ProtectedBase64 $encPair -Scope "LocalMachine" | ConvertFrom-Json
            $script:DevicePrivXml = $pairJson.PrivateXml
            $script:DevicePubXml = $pairJson.PublicXml
        } catch {}
    }
}

function New-Javis4DigitPin {
    $rb = New-JavisRandomBytes -Length 2
    $val = ([uint16]$rb[0] -shl 8) -bor [uint16]$rb[1]
    return (1000 + ($val % 9000)).ToString()
}

if ([string]::IsNullOrWhiteSpace($script:DeviceId)) {
    $script:DeviceId = New-Javis4DigitPin
}
if ([string]::IsNullOrWhiteSpace($script:DevicePrivXml)) {
    $kp = New-JavisRsaKeyPair
    $script:DevicePrivXml = $kp.PrivateXml
    $script:DevicePubXml = $kp.PublicXml
    if ($isFixedService) {
        $encPair = Protect-JavisLocalSecret -PlainText ($kp | ConvertTo-Json -Compress) -Scope "LocalMachine"
        [System.IO.File]::WriteAllText($deviceKeyFile, $encPair, $utf8NoBom)
    }
}

function Save-ServicePairingState {
    if (-not $isFixedService) { return }
    $encTok = if ($script:DeviceToken) { Protect-JavisLocalSecret -PlainText $script:DeviceToken -Scope "LocalMachine" } else { "" }
    $cfgObj = @{
        device_id          = $script:DeviceId
        hostname           = $env:COMPUTERNAME
        custom_name        = $script:DeviceCustomName
        mode               = "fix"
        gatewayUrl         = $BaseUrl
        tenant             = $script:TenantId
        device_token_dpapi = $encTok
        paired_admins      = $script:PairedAdmins
        updated_at         = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($serviceConfigFile, $cfgObj, $utf8NoBom)
}

$script:LastActivityUtc = [DateTime]::UtcNow

function Invoke-DevicePairing {
    while ($true) {
        $code = ""
        $pairSecret = ""
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            Invoke-IdleTimeoutShutdownIfExpired
            if ($attempt -gt 0 -or $script:DeviceId -notmatch "^\d{4}$") {
                $script:DeviceId = New-Javis4DigitPin
            }
            $code = $script:DeviceId
            $reqBody = @{
                device_id      = $script:DeviceId
                pairing_code   = $code
                hostname       = $env:COMPUTERNAME
                custom_name    = $script:DeviceCustomName
                device_pub_key = $script:DevicePubXml
            } | ConvertTo-Json -Compress

            $respRaw = Invoke-GatewayHttp -Uri ($BaseUrl + "pairing/request") -Method "POST" -Body $reqBody -TimeoutSec 15 -Key ""
            $respObj = $respRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($respObj -and $respObj.error -eq "Conflict") {
                $script:DeviceId = New-Javis4DigitPin
                continue
            }
            if ($respObj -and $respObj.pairing_secret) {
                $pairSecret = $respObj.pairing_secret
                break
            }
            throw "Failed to create pairing request: $respRaw"
        }
        if (-not $pairSecret) {
            throw "Unable to reserve a unique 4-digit pairing PIN after 10 attempts."
        }

        if ($isFixedService) {
            [System.IO.File]::WriteAllText($pairingBannerFile, "PAIRING_PIN=$code`r`nDEVICE_ID=$($script:DeviceId)`r`nCREATED_UTC=$([DateTime]::UtcNow.ToString('o'))", $utf8NoBom)
        }

        Write-Host "======================================================================" -ForegroundColor DarkCyan
        Write-Host "             BB_JAVIS ZERO-TRUST DEVICE PAIRING REQUIRED              " -ForegroundColor Yellow
        Write-Host "======================================================================" -ForegroundColor DarkCyan
        Write-Host "  -> Remote PIN   : " -NoNewline -ForegroundColor Gray
        Write-Host "[ $code ]" -ForegroundColor Green
        Write-Host "  -> Machine Name : $($script:DeviceCustomName) ($env:COMPUTERNAME)" -ForegroundColor White
        Write-Host "  -> Run on Dev   : send_remote_command.bat -Pair $code" -ForegroundColor Yellow
        if (-not $isFixedService -and $IdleTimeoutMinutes -gt 0) {
            Write-Host "  -> Auto-Close   : Idle timeout $IdleTimeoutMinutes min (temp mode)" -ForegroundColor Gray
        }
        Write-Host "======================================================================" -ForegroundColor DarkCyan

        $expiredPin = $false
        while ($true) {
            Start-Sleep -Seconds 2
            Invoke-IdleTimeoutShutdownIfExpired
            try {
                $statusRaw = Invoke-GatewayHttp -Uri ($BaseUrl + "pairing/status/$code") -Method "GET" -TimeoutSec 10 -Key "" -ExtraHeaders @{ "X-Pairing-Secret" = $pairSecret }
                $statusObj = $statusRaw | ConvertFrom-Json
                if ($statusObj -and $statusObj.status -eq "claimed" -and $statusObj.device_token) {
                    if ($statusObj.device_id) { $script:DeviceId = $statusObj.device_id.ToString() }
                    $script:DeviceToken = $statusObj.device_token.ToString()
                    $script:TenantId = $statusObj.tenant.ToString()
                    $script:PairedAdmins[$statusObj.admin_id.ToString()] = $statusObj.admin_pub_key.ToString()
                    Save-ServicePairingState
                    if (Test-Path $pairingBannerFile) { Remove-Item $pairingBannerFile -Force -ErrorAction SilentlyContinue }
                    $script:LastActivityUtc = [DateTime]::UtcNow
                    Write-Host "[PAIRED] Paired with admin '$($statusObj.admin_id)' -> Remote PIN: [ $($script:DeviceId) ] (Tenant: $($script:TenantId))." -ForegroundColor Green
                    return
                }
                if ($statusObj -and $statusObj.error -eq "Gone") {
                    Write-Host "[PAIRING] Pairing PIN expired. Generating a new 4-digit PIN..." -ForegroundColor Yellow
                    $script:DeviceId = New-Javis4DigitPin
                    $expiredPin = $true
                    break
                }
            } catch {}
        }
        if (-not $expiredPin) { break }
    }
}

function Get-LocalIPv4 {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
               Select-Object -ExpandProperty IPAddress -First 1)
        if ($ip) { return $ip }
    } catch {}
    return "127.0.0.1"
}

$script:DeviceLocalIp = Get-LocalIPv4
$script:LastHeartbeatUtc = [DateTime]::MinValue
$script:ActiveTunnels = @{}
$script:isExiting = $false
$script:restartRequested = $false

function Update-DeviceHeartbeat {
    param([string]$Status = "online")
    try {
        $devUrl = $BaseUrl + "devices/$($script:DeviceId).json"
        $devData = @{
            device_id      = $script:DeviceId
            hostname       = $env:COMPUTERNAME
            custom_name    = $script:DeviceCustomName
            local_ip       = $script:DeviceLocalIp
            device_pub_key = $script:DevicePubXml
            service_mode   = $isFixedService
            status         = $Status
            last_heartbeat = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            tenant         = $script:TenantId
        } | ConvertTo-Json -Compress
        $null = Invoke-GatewayHttp -Uri $devUrl -Method "PUT" -Body $devData -TimeoutSec 5
        $script:LastHeartbeatUtc = [DateTime]::UtcNow
    } catch {}
}

function Close-JavisTunnelById {
    param([string]$TunnelId)
    if (-not $script:ActiveTunnels.ContainsKey($TunnelId)) { return }
    $t = $script:ActiveTunnels[$TunnelId]
    try { if ($t.cf_proc -and -not $t.cf_proc.HasExited) { Stop-Process -Id $t.cf_proc.Id -Force -ErrorAction SilentlyContinue } } catch {}
    try { if ($t.ws_proc -and -not $t.ws_proc.HasExited) { Stop-Process -Id $t.ws_proc.Id -Force -ErrorAction SilentlyContinue } } catch {}
    if (-not [string]::IsNullOrWhiteSpace($t.temp_sql_user) -and -not [string]::IsNullOrWhiteSpace($t.db_conn)) {
        try {
            $sqlConn = New-Object System.Data.SqlClient.SqlConnection($t.db_conn)
            $sqlConn.Open()
            $cmd = $sqlConn.CreateCommand()
            $uEsc = $t.temp_sql_user.Replace("]", "]]")
            $cmd.CommandText = "IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$($t.temp_sql_user)') DROP USER [$uEsc]; IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$($t.temp_sql_user)') DROP LOGIN [$uEsc];"
            $null = $cmd.ExecuteNonQuery()
            $sqlConn.Close()
        } catch {}
    }
    $script:ActiveTunnels.Remove($TunnelId)
    if (-not $script:isExiting) { $script:LastActivityUtc = [DateTime]::UtcNow }
}

function Close-ExpiredTunnels {
    $now = [DateTime]::UtcNow
    foreach ($tid in @($script:ActiveTunnels.Keys)) {
        if ($now -ge $script:ActiveTunnels[$tid].expires_utc) {
            Close-JavisTunnelById -TunnelId $tid
        }
    }
}

$cleanExitAction = {
    if ($script:isExiting) { return }
    $script:isExiting = $true
    foreach ($tid in @($script:ActiveTunnels.Keys)) {
        Close-JavisTunnelById -TunnelId $tid
    }
    if (-not [string]::IsNullOrWhiteSpace($script:DeviceToken)) {
        if ($isFixedService) {
            try { Update-DeviceHeartbeat -Status "offline" } catch {}
        } else {
            try { $null = Invoke-GatewayHttp -Uri ($BaseUrl + "jobs/$($script:DeviceId).json") -Method "DELETE" -TimeoutSec 5 } catch {}
            try { $null = Invoke-GatewayHttp -Uri ($BaseUrl + "devices/$($script:DeviceId).json") -Method "DELETE" -TimeoutSec 5 } catch {}
        }
    }
}

function Invoke-IdleTimeoutShutdownIfExpired {
    # Active on-demand tunnels defer the idle timer until they close or expire
    if ($script:ActiveTunnels -and $script:ActiveTunnels.Count -gt 0) {
        $script:LastActivityUtc = [DateTime]::UtcNow
        return
    }
    if (Test-JavisIdleTimeoutExpired -IsFixedService $isFixedService -IdleTimeoutMinutes $IdleTimeoutMinutes -LastActivityUtc $script:LastActivityUtc -ActiveTunnelCount 0) {
        Write-Host "[IDLE-EXIT] No command or activity for $IdleTimeoutMinutes min in temp mode. Closing PowerShell..." -ForegroundColor Yellow
        & $cleanExitAction
        [Environment]::Exit(0)
    }
}

try {
    [Console]::TreatControlCAsInput = $false
    [Console]::add_CancelKeyPress([ConsoleCancelEventHandler]{ param($s, $e) & $cleanExitAction })
} catch {}

if ([string]::IsNullOrWhiteSpace($script:DeviceToken) -or $script:PairedAdmins.Count -eq 0) {
    Invoke-DevicePairing
}

function Send-EncryptedJobResult {
    param(
        [string]$JobId,
        [string]$AdminPubXml,
        [string]$Status,
        [int]$ExitCode,
        [hashtable]$PlainResult
    )
    $plainJson = $PlainResult | ConvertTo-Json -Depth 5 -Compress
    $resEnv = (Protect-JavisPayload -PlainJson $plainJson -RecipientPubXml $AdminPubXml -SenderPrivXml $script:DevicePrivXml -JobId $JobId) | ConvertFrom-Json
    $patch = @{
        status          = $Status
        exit_code       = $ExitCode
        completed_at    = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        result_envelope = $resEnv
    } | ConvertTo-Json -Depth 6 -Compress
    $null = Invoke-GatewayHttp -Uri ($BaseUrl + "jobs/$($script:DeviceId)/$JobId.json") -Method "PATCH" -Body $patch -TimeoutSec 15
}

function Execute-SqlQueryMode {
    param([string]$ConnStr, [string]$Sql, [bool]$RawData, [int]$MaxRows)
    if (-not (Test-JavisReadOnlySql -Sql $Sql)) {
        throw "Blocked: Mode 'Query' only permits Read-Only SELECT/WITH statements. Use Mode 'SqlExec' for writes."
    }
    if ($MaxRows -le 0 -or $MaxRows -gt 5000) { $MaxRows = 500 }

    $conn = New-Object System.Data.SqlClient.SqlConnection($ConnStr)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandTimeout = 30
        $cmd.CommandText = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SET LOCK_TIMEOUT 5000; SET ROWCOUNT $MaxRows;`r`n" + $Sql
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        $ds = New-Object System.Data.DataSet
        $null = $adapter.Fill($ds)
        $rows = @()
        if ($ds.Tables.Count -gt 0 -and $ds.Tables[0].Rows.Count -gt 0) {
            $cols = @($ds.Tables[0].Columns | ForEach-Object { $_.ColumnName })
            $tmp = [System.Collections.Generic.List[object]]::new()
            foreach ($dr in $ds.Tables[0].Rows) {
                $obj = [ordered]@{}
                foreach ($c in $cols) {
                    $v = $dr[$c]
                    $obj[$c] = if ($v -is [DBNull]) { $null } else { $v }
                }
                $tmp.Add([PSCustomObject]$obj)
            }
            $rows = Protect-JavisPiiTable -Rows ($tmp.ToArray()) -RawData:$RawData
        }
        return @{
            count = $rows.Count
            json  = ($rows | ConvertTo-Json -Depth 4 -Compress)
        }
    } finally {
        if ($conn.State -eq "Open") { $conn.Close() }
        $conn.Dispose()
    }
}

function Execute-SqlWriteMode {
    param([string]$ConnStr, [string]$Sql, [bool]$ConfirmWrite)
    if (-not $ConfirmWrite) {
        throw "Blocked: Mode 'SqlExec' requires explicit confirm_write=true."
    }
    $conn = New-Object System.Data.SqlClient.SqlConnection($ConnStr)
    $tx = $null
    try {
        $conn.Open()
        $tx = $conn.BeginTransaction()
        $cmd = $conn.CreateCommand()
        $cmd.Transaction = $tx
        $cmd.CommandTimeout = 60
        $cmd.CommandText = $Sql
        $affected = $cmd.ExecuteNonQuery()
        $tx.Commit()
        return $affected
    } catch {
        if ($tx) { try { $tx.Rollback() } catch {} }
        throw $_
    } finally {
        if ($conn.State -eq "Open") { $conn.Close() }
        $conn.Dispose()
    }
}

function Start-JavisOnDemandTunnel {
    param($Payload)
    $targetPort = if ($Payload.target_port) { [int]$Payload.target_port } else { 1433 }
    $ttlMin = if ($Payload.ttl_min) { [Math]::Min(120, [Math]::Max(1, [int]$Payload.ttl_min)) } else { 30 }
    $ttlSec = $ttlMin * 60

    $tBinDir = if ($isFixedService) { $binDir } else { Join-Path $env:TEMP "bb_javis_bin" }
    $tunnelExe = Ensure-JavisTunnelExe -BinDir $tBinDir
    $cfExe = Ensure-CloudflaredBinary -BinDir $tBinDir

    $probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $wsPort = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port
    $probe.Stop()

    $tokBytes = New-JavisRandomBytes -Length 32
    $tunnelToken = (($tokBytes | ForEach-Object { $_.ToString("x2") }) -join "")
    $tunnelId = "tun-" + [Guid]::NewGuid().ToString("N").Substring(0, 8)

    $wsProc = Start-Process -FilePath $tunnelExe -ArgumentList "server $wsPort 127.0.0.1 $targetPort $tunnelToken $ttlSec" -WindowStyle Hidden -PassThru

    $cfErrLog = Join-Path $tBinDir "$tunnelId.cf.log"
    $cfProc = Start-Process -FilePath $cfExe -ArgumentList "tunnel --no-autoupdate --url http://127.0.0.1:$wsPort" -RedirectStandardError $cfErrLog -WindowStyle Hidden -PassThru

    $tunnelUrl = ""
    $tunnelRegistered = $false
    $urlFoundAt = [DateTime]::MaxValue
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 300
        if (Test-Path $cfErrLog) {
            $logTxt = Get-Content $cfErrLog -Raw -ErrorAction SilentlyContinue
            if (-not $tunnelUrl -and $logTxt -match "(https://[a-z0-9-]+\.trycloudflare\.com)") {
                $tunnelUrl = $Matches[1]
                $urlFoundAt = [DateTime]::UtcNow
            }
            if ($tunnelUrl -and $logTxt -match "Registered tunnel connection") {
                $tunnelRegistered = $true
                break
            }
            if ($tunnelUrl -and ([DateTime]::UtcNow - $urlFoundAt).TotalSeconds -ge 4) {
                break
            }
        }
    }
    if ($tunnelRegistered) { Start-Sleep -Milliseconds 800 }
    Remove-Item $cfErrLog -Force -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($tunnelUrl)) {
        try { Stop-Process -Id $cfProc.Id -Force -ErrorAction SilentlyContinue } catch {}
        try { Stop-Process -Id $wsProc.Id -Force -ErrorAction SilentlyContinue } catch {}
        throw "cloudflared quick tunnel did not emit a trycloudflare.com URL within 25s."
    }

    $tempUser = ""
    $tempPass = ""
    $dbConn = ""
    if ($Payload.ephemeral_ro_sql) {
        try {
            $dbConn = Get-JavisDbConnectionString -ProfileName $Payload.db_profile -OverrideConn $Payload.connection_string
            $tempUser = "javis_ro_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
            $pBytes = New-JavisRandomBytes -Length 18
            $tempPass = [Convert]::ToBase64String($pBytes) + "!a1"
            $pEsc = $tempPass.Replace("'", "''")
            $uEsc = $tempUser.Replace("]", "]]")
            $sqlConn = New-Object System.Data.SqlClient.SqlConnection($dbConn)
            try {
                $sqlConn.Open()
                $cmd = $sqlConn.CreateCommand()
                $cmd.CommandText = "CREATE LOGIN [$uEsc] WITH PASSWORD = N'$pEsc', CHECK_POLICY = OFF; CREATE USER [$uEsc] FOR LOGIN [$uEsc]; ALTER ROLE [db_datareader] ADD MEMBER [$uEsc];"
                $null = $cmd.ExecuteNonQuery()
            } finally {
                if ($sqlConn.State -eq "Open") { $sqlConn.Close() }
                $sqlConn.Dispose()
            }
        } catch {
            try { Stop-Process -Id $cfProc.Id -Force -ErrorAction SilentlyContinue } catch {}
            try { Stop-Process -Id $wsProc.Id -Force -ErrorAction SilentlyContinue } catch {}
            throw $_
        }
    }

    $expiresUtc = [DateTime]::UtcNow.AddSeconds($ttlSec)
    $script:ActiveTunnels[$tunnelId] = @{
        tunnel_id     = $tunnelId
        ws_proc       = $wsProc
        cf_proc       = $cfProc
        temp_sql_user = $tempUser
        db_conn       = $dbConn
        expires_utc   = $expiresUtc
    }

    return @{
        tunnel_id     = $tunnelId
        tunnel_url    = $tunnelUrl
        tunnel_token  = $tunnelToken
        expires_at    = $expiresUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        temp_sql_user = $tempUser
        temp_sql_pass = $tempPass
    }
}

function Execute-RemoteJob {
    param([string]$JobId, $JobDetails)

    $adminId = if ($JobDetails.admin_id) { $JobDetails.admin_id.ToString() } else { "" }
    if ([string]::IsNullOrWhiteSpace($adminId) -or -not $script:PairedAdmins.ContainsKey($adminId)) {
        Write-Host "[SECURITY] Rejected job $JobId from unpaired admin '$adminId'." -ForegroundColor Red
        return
    }
    $adminPubXml = $script:PairedAdmins[$adminId]

    if (-not $JobDetails.envelope) {
        Write-Host "[SECURITY] Rejected unsigned plaintext job $JobId." -ForegroundColor Red
        return
    }

    try {
        $plainJson = Unprotect-JavisPayload -Envelope $JobDetails.envelope -RecipientPrivXml $script:DevicePrivXml -ExpectedSenderPubXml $adminPubXml -ExpectedJobId $JobId -MaxSkewSec 300
        $payload = $plainJson | ConvertFrom-Json
    } catch {
        Write-Host "[SECURITY] Job $JobId signature/decryption failed: $_" -ForegroundColor Red
        return
    }

    $script:LastActivityUtc = [DateTime]::UtcNow

    $mode = if ($payload.mode) { $payload.mode.ToString() } else { "PowerShell" }
    $dbProfile = if ($payload.db_profile) { $payload.db_profile.ToString() } else { "" }
    $cmdTextForAudit = if ($payload.sql) { $payload.sql.ToString() } elseif ($payload.command) { $payload.command.ToString() } else { $mode }

    $exitCode = 0
    $rowsAffected = 0
    $resData = @{ stdout = ""; stderr = "" }

    try {
        if ($mode -eq "Query") {
            $connStr = Get-JavisDbConnectionString -ProfileName $dbProfile -OverrideConn $payload.connection_string
            $maxRows = if ($payload.max_rows) { [int]$payload.max_rows } else { 500 }
            $qRes = Execute-SqlQueryMode -ConnStr $connStr -Sql $payload.sql -RawData:([bool]$payload.raw_data) -MaxRows $maxRows
            $rowsAffected = $qRes.count
            $resData.stdout = $qRes.json
        }
        elseif ($mode -eq "SqlExec") {
            $connStr = Get-JavisDbConnectionString -ProfileName $dbProfile -OverrideConn $payload.connection_string
            $rowsAffected = Execute-SqlWriteMode -ConnStr $connStr -Sql $payload.sql -ConfirmWrite:([bool]$payload.confirm_write)
            $resData.stdout = (@{ status = "success"; rows_affected = $rowsAffected } | ConvertTo-Json -Compress)
        }
        elseif ($mode -eq "Tunnel") {
            $tInfo = Start-JavisOnDemandTunnel -Payload $payload
            $resData = $tInfo
            $resData.stdout = "Tunnel $($tInfo.tunnel_id) active until $($tInfo.expires_at)"
            $resData.stderr = ""
        }
        elseif ($mode -eq "CloseTunnel") {
            Close-JavisTunnelById -TunnelId $payload.tunnel_id
            $resData.stdout = "Tunnel $($payload.tunnel_id) closed."
        }
        elseif ($mode -eq "SetAlias") {
            $script:DeviceCustomName = $payload.command.ToString().Trim()
            Save-ServicePairingState
            Update-DeviceHeartbeat -Status "online"
            $resData.stdout = "Alias updated to '$($script:DeviceCustomName)'."
        }
        elseif ($mode -eq "Restart") {
            $script:restartRequested = $true
            $resData.stdout = "Agent restart scheduled."
        }
        elseif ($mode -eq "Download") {
            $rp = $payload.remote_path.ToString()
            if (-not (Test-Path $rp)) { throw "Remote path not found: $rp" }
            $bytes = [System.IO.File]::ReadAllBytes($rp)
            $resData.file_name = [System.IO.Path]::GetFileName($rp)
            $resData.file_data = [Convert]::ToBase64String($bytes)
            $resData.stdout = "Downloaded $($bytes.Length) bytes."
        }
        elseif ($mode -eq "Upload") {
            $rp = $payload.remote_path.ToString()
            $dir = Split-Path -Parent $rp
            if ($dir -and -not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
            $bytes = [Convert]::FromBase64String($payload.file_data.ToString())
            [System.IO.File]::WriteAllBytes($rp, $bytes)
            $resData.stdout = "Uploaded $($bytes.Length) bytes to $rp."
        }
        else {
            # PowerShell Mode (Runspace execution)
            $ps = [System.Management.Automation.PowerShell]::Create()
            try {
                [void]$ps.AddScript($payload.command.ToString())
                $out = $ps.Invoke()
                $outStr = ($out | Out-String).TrimEnd()
                $errStr = (($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "`r`n").TrimEnd()
                $resData.stdout = $outStr
                $resData.stderr = $errStr
                if ($ps.Streams.Error.Count -gt 0) { $exitCode = 1 }
            } finally {
                $ps.Dispose()
            }
        }
    } catch {
        $exitCode = 1
        $resData.stderr = $_.Exception.Message
    }

    $localAuditRoot = if ($isFixedService) { $auditDir } else { Join-Path $env:TEMP "bb_javis_audit" }
    try {
        $null = Add-JavisAuditEntry -AuditDir $localAuditRoot -JobId $JobId -AdminId $adminId -Mode $mode -DbProfile $dbProfile -CommandText $cmdTextForAudit -ExitCode $exitCode -RowsAffected $rowsAffected
    } catch {}

    try {
        $metaBody = @{
            job_id         = $JobId
            admin_id       = $adminId
            device_id      = $script:DeviceId
            mode           = $mode
            command_sha256 = (Get-JavisSha256Hex -Text $cmdTextForAudit)
            status         = $(if ($exitCode -eq 0) { "completed" } else { "failed" })
        } | ConvertTo-Json -Compress
        $null = Invoke-GatewayHttp -Uri ($BaseUrl + "audit") -Method "POST" -Body $metaBody -TimeoutSec 5
    } catch {}

    $finalStatus = if ($exitCode -eq 0) { "completed" } else { "failed" }
    Send-EncryptedJobResult -JobId $JobId -AdminPubXml $adminPubXml -Status $finalStatus -ExitCode $exitCode -PlainResult $resData
    $script:LastActivityUtc = [DateTime]::UtcNow
}

Update-DeviceHeartbeat -Status "online"

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "         BB_JAVIS ZERO-TRUST REMOTE AGENT (E2E + TUNNEL READY)        " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  -> Remote PIN : [ $($script:DeviceId) ]" -ForegroundColor Green
Write-Host "  -> Host Alias : $($script:DeviceCustomName) ($env:COMPUTERNAME)" -ForegroundColor Cyan
Write-Host "  -> Tenant     : $($script:TenantId)" -ForegroundColor White
Write-Host "  -> Gateway    : $BaseUrl" -ForegroundColor Gray
if (-not $isFixedService -and $IdleTimeoutMinutes -gt 0) {
    Write-Host "  -> Auto-Close : Idle timeout $IdleTimeoutMinutes min (temp mode)" -ForegroundColor Gray
}
Write-Host "======================================================================" -ForegroundColor DarkCyan

$lastProcessedJob = ""
try {
    while (-not $script:isExiting) {
        Close-ExpiredTunnels
        Invoke-IdleTimeoutShutdownIfExpired
        if ($script:restartRequested) {
            $script:restartRequested = $false
            [GC]::Collect()
        }

        try {
            $sseTimeoutMs = 35000
            if (-not $isFixedService -and $IdleTimeoutMinutes -gt 0 -and $script:ActiveTunnels.Count -eq 0) {
                $remMs = [int][Math]::Ceiling((($script:LastActivityUtc.AddMinutes($IdleTimeoutMinutes)) - [DateTime]::UtcNow).TotalMilliseconds)
                if ($remMs -lt 35000) {
                    $sseTimeoutMs = [Math]::Max(1000, $remMs)
                }
            }
            $streamUrl = $BaseUrl + "jobs/$($script:DeviceId).json"
            $request = [System.Net.HttpWebRequest]::Create($streamUrl)
            $request.Accept = "text/event-stream"
            $request.Headers["X-Javis-Key"] = $script:DeviceToken
            $request.Timeout = $sseTimeoutMs
            $request.ReadWriteTimeout = $sseTimeoutMs

            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream, $utf8NoBom)
            $dataBuffer = [System.Text.StringBuilder]::new()

            while (-not $reader.EndOfStream -and -not $script:isExiting) {
                Close-ExpiredTunnels
                Invoke-IdleTimeoutShutdownIfExpired
                if (([DateTime]::UtcNow - $script:LastHeartbeatUtc).TotalSeconds -ge 28) {
                    Update-DeviceHeartbeat -Status "online"
                }

                $line = $reader.ReadLine()
                Invoke-IdleTimeoutShutdownIfExpired
                if ($null -eq $line) { break }

                if ($line.StartsWith("data: ")) {
                    $null = $dataBuffer.AppendLine($line.Substring(6))
                } elseif ($line -eq "" -and $dataBuffer.Length -gt 0) {
                    $rawJson = $dataBuffer.ToString().Trim()
                    [void]$dataBuffer.Clear()
                    if ($rawJson -and $rawJson -ne "null") {
                        $eventObj = ConvertFrom-Json -InputObject $rawJson -ErrorAction SilentlyContinue
                        if ($eventObj) {
                            $payload = if ($eventObj.data) { $eventObj.data } else { $eventObj }
                            $targetJobId = $null
                            $targetJobDetails = $null
                            if ($payload -is [System.Management.Automation.PSCustomObject]) {
                                if ($payload.status -eq "pending" -and $payload.envelope) {
                                    $path = if ($eventObj.path) { $eventObj.path.TrimStart('/') } else { "" }
                                    $targetJobId = if ($path) { $path } else { "job-" + [Guid]::NewGuid().ToString("N").Substring(0, 8) }
                                    $targetJobDetails = $payload
                                } else {
                                    foreach ($prop in $payload.PSObject.Properties) {
                                        if ($prop.Value -and $prop.Value.status -eq "pending" -and $prop.Value.envelope) {
                                            $targetJobId = $prop.Name
                                            $targetJobDetails = $prop.Value
                                            break
                                        }
                                    }
                                }
                            }
                            if ($targetJobId -and $targetJobId -ne $lastProcessedJob) {
                                try { $reader.Close(); $stream.Close(); $response.Close(); $request.Abort() } catch {}
                                Execute-RemoteJob -JobId $targetJobId -JobDetails $targetJobDetails
                                $lastProcessedJob = $targetJobId
                                Update-DeviceHeartbeat -Status "online"
                                break
                            }
                        }
                    }
                }
            }
            try { $reader.Close(); $stream.Close(); $response.Close(); $request.Abort() } catch {}
        } catch {
            Close-ExpiredTunnels
            Invoke-IdleTimeoutShutdownIfExpired
            if (([DateTime]::UtcNow - $script:LastHeartbeatUtc).TotalSeconds -ge 28) {
                Update-DeviceHeartbeat -Status "online"
            }
            try {
                $jsonRaw = Invoke-GatewayHttp -Uri ($BaseUrl + "jobs/$($script:DeviceId).json") -Method "GET" -TimeoutSec 5
                if ($jsonRaw -and $jsonRaw.Trim() -ne "null" -and $jsonRaw.Trim().StartsWith("{")) {
                    $jobs = ConvertFrom-Json -InputObject $jsonRaw.Trim() -ErrorAction SilentlyContinue
                    if ($jobs -is [System.Management.Automation.PSCustomObject]) {
                        foreach ($prop in $jobs.PSObject.Properties) {
                            if ($prop.Value -and $prop.Value.status -eq "pending" -and $prop.Value.envelope -and $prop.Name -ne $lastProcessedJob) {
                                Execute-RemoteJob -JobId $prop.Name -JobDetails $prop.Value
                                $lastProcessedJob = $prop.Name
                                Update-DeviceHeartbeat -Status "online"
                                break
                            }
                        }
                    }
                }
            } catch {}
            Start-Sleep -Seconds $PollIntervalSec
        }
    }
} finally {
    & $cleanExitAction
}
