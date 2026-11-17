param (
    [string]$ApiKey = "",
    [string]$GatewayUrl = "",
    [Alias("Pin")][string]$DeviceId = "",
    [string]$Pair = "",
    [string]$Mode = "",
    [string]$DbProfile = "Default",
    [string]$ConnectionString = "",
    [Alias("Command", "Script")][string]$SqlQuery = "",
    [string]$SqlFile = "",
    [string]$OutputDir = "",
    [string]$LocalPath = "",
    [string]$RemotePath = "",
    [string]$TargetHost = "",
    [int]$TimeoutSec = 300,
    [int]$MaxRows = 500,
    [switch]$RawData,
    [switch]$ConfirmWrite,
    [int]$LocalPort = 11433,
    [int]$TargetPort = 1433,
    [int]$DurationMin = 30,
    [switch]$EphemeralReadOnlySql,
    [string]$RevokeRole = "",
    [string]$RevokeId = "",
    [switch]$List,
    [switch]$PurgeOffline
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
            ClientWebSocket ws = new ClientWebSocket();
            ws.Options.SetRequestHeader("Authorization", "Bearer " + token);
            try
            {
                await ws.ConnectAsync(new Uri(wssUrl), CancellationToken.None);
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
                try { ws.Dispose(); } catch {}
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

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$configDir = Join-Path $env:LOCALAPPDATA "BB_Javis"
$configFile = Join-Path $configDir "config.json"
$adminPrivFile = Join-Path $configDir "admin_key.dpapi"
$adminPubFile = Join-Path $configDir "admin_pub.xml"
$pairedStoreFile = Join-Path $configDir "paired_devices.dpapi"
$binDir = Join-Path $configDir "bin"

$localCfg = $null
if (Test-Path $configFile) {
    try { $localCfg = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

$script:JavisApiKey = if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey.Trim() }
    elseif (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_API_KEY)) { $env:BB_JAVIS_API_KEY.Trim() }
    elseif ($localCfg -and $localCfg.apiKey) { $localCfg.apiKey.ToString().Trim() }
    else { "" }

$BaseUrl = if (-not [string]::IsNullOrWhiteSpace($GatewayUrl)) { $GatewayUrl.Trim().TrimEnd('/') + "/" }
    elseif (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_GATEWAY_URL)) { $env:BB_JAVIS_GATEWAY_URL.Trim().TrimEnd('/') + "/" }
    elseif ($localCfg -and $localCfg.gatewayUrl) { $localCfg.gatewayUrl.ToString().Trim().TrimEnd('/') + "/" }
    else { "https://bb-javis-gateway.apisit-yimboa.workers.dev/" }

if ([string]::IsNullOrWhiteSpace($script:JavisApiKey) -or [string]::IsNullOrWhiteSpace($BaseUrl)) {
    throw "Missing Admin API Key or GatewayUrl. Run gen_key.bat -SaveToThisMachine first, or pass -ApiKey and -GatewayUrl."
}

$script:AdminId = if ($localCfg -and $localCfg.adminId) { $localCfg.adminId.ToString() } else { "" }
if ([string]::IsNullOrWhiteSpace($script:AdminId)) {
    $parts = $script:JavisApiKey.Split('_')
    if ($parts.Length -ge 4 -and $parts[0] -eq "bbj") { $script:AdminId = $parts[3] }
}

if (-not (Test-Path $adminPrivFile) -or -not (Test-Path $adminPubFile)) {
    throw "Admin RSA keypair missing in $configDir. Run gen_key.bat -SaveToThisMachine."
}
$script:AdminPrivXml = Unprotect-JavisLocalSecret -ProtectedBase64 ([System.IO.File]::ReadAllText($adminPrivFile, $utf8NoBom)) -Scope "CurrentUser"
$script:AdminPubXml = [System.IO.File]::ReadAllText($adminPubFile, $utf8NoBom)

function Invoke-GatewayHttp {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Method = "GET",
        [string]$Body = $null,
        [int]$TimeoutSec = 15
    )
    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = $Method
    $request.Timeout = $TimeoutSec * 1000
    $request.ReadWriteTimeout = $TimeoutSec * 1000
    $request.KeepAlive = $false
    $request.Headers["X-Javis-Key"] = $script:JavisApiKey

    if (-not [string]::IsNullOrEmpty($Body)) {
        $request.ContentType = "application/json; charset=utf-8"
        $bytes = $utf8NoBom.GetBytes($Body)
        $request.ContentLength = $bytes.Length
        $reqStream = $request.GetRequestStream()
        try { $reqStream.Write($bytes, 0, $bytes.Length) }
        finally { $reqStream.Close() }
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

function Load-PairedDevicesMap {
    $map = @{}
    if (Test-Path $pairedStoreFile) {
        try {
            $raw = Unprotect-JavisLocalSecret -ProtectedBase64 ([System.IO.File]::ReadAllText($pairedStoreFile, $utf8NoBom)) -Scope "CurrentUser"
            $obj = $raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = $p.Value }
        } catch {}
    }
    return $map
}

function Save-PairedDevicesMap {
    param([hashtable]$Map)
    if (-not (Test-Path $configDir)) { $null = New-Item -ItemType Directory -Path $configDir -Force }
    $enc = Protect-JavisLocalSecret -PlainText ($Map | ConvertTo-Json -Depth 6 -Compress) -Scope "CurrentUser"
    [System.IO.File]::WriteAllText($pairedStoreFile, $enc, $utf8NoBom)
}

if (-not [string]::IsNullOrWhiteSpace($Pair)) {
    $claimBody = @{
        pairing_code  = $Pair.Trim().ToUpper()
        admin_pub_key = $script:AdminPubXml
    } | ConvertTo-Json -Compress
    $raw = Invoke-GatewayHttp -Uri ($BaseUrl + "pairing/claim") -Method "POST" -Body $claimBody -TimeoutSec 15
    $res = $raw | ConvertFrom-Json
    if (-not $res -or -not $res.device_id -or -not $res.device_pub_key) {
        throw "Pairing claim failed: $raw"
    }
    $map = Load-PairedDevicesMap
    $map[$res.device_id] = @{
        device_id      = $res.device_id
        hostname       = $res.hostname
        custom_name    = $res.custom_name
        device_pub_key = $res.device_pub_key
        paired_at      = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    Save-PairedDevicesMap -Map $map
    Write-Host "[PAIRED] Claimed device '$($res.custom_name)' ($($res.device_id)) successfully." -ForegroundColor Green
    return
}

if ($Mode -eq "Revoke") {
    if ([string]::IsNullOrWhiteSpace($RevokeRole) -or [string]::IsNullOrWhiteSpace($RevokeId)) {
        throw "Specify -RevokeRole <adm|dev> and -RevokeId <id>."
    }
    $revBody = @{ role = $RevokeRole; subject_id = $RevokeId } | ConvertTo-Json -Compress
    $raw = Invoke-GatewayHttp -Uri ($BaseUrl + "admin/revoke") -Method "POST" -Body $revBody -TimeoutSec 10
    Write-Host $raw -ForegroundColor Yellow
    return
}

function Get-RegisteredDevices {
    $devList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $raw = Invoke-GatewayHttp -Uri ($BaseUrl + "devices.json") -Method "GET" -TimeoutSec 12
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Trim() -eq "null") { return $devList }
    $data = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $data) { return $devList }
    $nowUtc = [DateTime]::UtcNow
    foreach ($prop in $data.PSObject.Properties) {
        $d = $prop.Value
        if (-not $d) { continue }
        $id = if ($d.device_id) { $d.device_id.ToString() } else { $prop.Name }
        $hostName = if ($d.hostname) { $d.hostname.ToString() } else { "Unknown" }
        $custom = if ($d.custom_name) { $d.custom_name.ToString() } else { $hostName }
        $ageSec = 999999
        if ($d.last_heartbeat) {
            try { $ageSec = [int]($nowUtc - [DateTime]::Parse($d.last_heartbeat).ToUniversalTime()).TotalSeconds } catch {}
        }
        $isOnline = ($d.status -eq "online" -and $ageSec -le 180)
        $devList.Add([PSCustomObject]@{
            DeviceId     = $id
            Status       = $(if ($isOnline) { "ONLINE" } else { "OFFLINE" })
            IsOnline     = $isOnline
            Hostname     = $hostName
            CustomName   = $custom
            DisplayName  = $(if ($custom -ne $hostName) { "$custom ($hostName)" } else { $hostName })
            LocalIP      = $(if ($d.local_ip) { $d.local_ip.ToString() } else { "-" })
            DevicePubKey = $(if ($d.device_pub_key) { $d.device_pub_key.ToString() } else { "" })
            AgeSec       = $ageSec
        })
    }
    return $devList
}

if ($PurgeOffline.IsPresent) {
    $devs = Get-RegisteredDevices
    $cnt = 0
    foreach ($d in $devs) {
        if (-not $d.IsOnline) {
            $null = Invoke-GatewayHttp -Uri ($BaseUrl + "devices/$($d.DeviceId).json") -Method "DELETE" -TimeoutSec 5
            $cnt++
        }
    }
    Write-Host "[PURGED] Removed $cnt offline device(s)." -ForegroundColor Green
    return
}

if ($List.IsPresent -or $Mode -eq "List") {
    $devs = Get-RegisteredDevices
    $devs | Format-Table DeviceId, Status, DisplayName, LocalIP, AgeSec -AutoSize
    return
}

$pairedMap = Load-PairedDevicesMap
if ([string]::IsNullOrWhiteSpace($DeviceId) -and -not [string]::IsNullOrWhiteSpace($TargetHost)) {
    $devs = Get-RegisteredDevices
    $t = $TargetHost.Trim().ToLower()
    $m = $devs | Where-Object { ($_.Hostname.ToLower() -eq $t -or $_.CustomName.ToLower() -eq $t) -and $_.IsOnline } | Select-Object -First 1
    if (-not $m) {
        $m = $devs | Where-Object { ($_.Hostname.ToLower() -like "*$t*" -or $_.CustomName.ToLower() -like "*$t*") -and $_.IsOnline } | Select-Object -First 1
    }
    if (-not $m) { throw "TargetHost '$TargetHost' not found online." }
    $DeviceId = $m.DeviceId
    if ($m.DevicePubKey -and -not $pairedMap.ContainsKey($DeviceId)) {
        $pairedMap[$DeviceId] = @{ device_id = $DeviceId; device_pub_key = $m.DevicePubKey }
        Save-PairedDevicesMap -Map $pairedMap
    }
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    $devs = Get-RegisteredDevices
    $devs | Format-Table DeviceId, Status, DisplayName, LocalIP, AgeSec -AutoSize
    $DeviceId = (Read-Host "Enter target DeviceId").Trim()
}

if (-not $pairedMap.ContainsKey($DeviceId) -or -not $pairedMap[$DeviceId].device_pub_key) {
    $devs = Get-RegisteredDevices
    $found = $devs | Where-Object { $_.DeviceId -eq $DeviceId } | Select-Object -First 1
    if ($found -and $found.DevicePubKey) {
        $pairedMap[$DeviceId] = @{ device_id = $DeviceId; device_pub_key = $found.DevicePubKey }
        Save-PairedDevicesMap -Map $pairedMap
    } else {
        throw "No paired public key for '$DeviceId'. Run -Pair <PairingCode> first."
    }
}
$targetPubXml = $pairedMap[$DeviceId].device_pub_key.ToString()

if ([string]::IsNullOrWhiteSpace($Mode)) {
    $Mode = if (-not [string]::IsNullOrWhiteSpace($SqlQuery) -or -not [string]::IsNullOrWhiteSpace($SqlFile)) { "PowerShell" } else { Read-Host "Enter Mode (PowerShell, Query, SqlExec, Tunnel, Download, Upload)" }
}

function Send-SignedJobAndWait {
    param([hashtable]$InnerPayload, [int]$WaitSec = $TimeoutSec)
    $jobId = "job-" + [Guid]::NewGuid().ToString("N").Substring(0, 12)
    $innerJson = $InnerPayload | ConvertTo-Json -Depth 6 -Compress
    $envObj = (Protect-JavisPayload -PlainJson $innerJson -RecipientPubXml $targetPubXml -SenderPrivXml $script:AdminPrivXml -JobId $jobId) | ConvertFrom-Json

    $jobDoc = @{
        id          = $jobId
        device_id   = $DeviceId
        admin_id    = $script:AdminId
        status      = "pending"
        created_at  = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        timeout_sec = $WaitSec
        abort       = $false
        envelope    = $envObj
    } | ConvertTo-Json -Depth 7 -Compress

    $jobUrl = $BaseUrl + "jobs/$DeviceId/$jobId.json"
    $null = Invoke-GatewayHttp -Uri $jobUrl -Method "PUT" -Body $jobDoc -TimeoutSec 15

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $resultObj = $null
    while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
        try {
            $raw = Invoke-GatewayHttp -Uri $jobUrl -Method "GET" -TimeoutSec 10
            if ($raw -and $raw.Trim() -ne "null") {
                $doc = $raw | ConvertFrom-Json
                if ($doc -and ($doc.status -eq "completed" -or $doc.status -eq "failed" -or $doc.status -eq "cancelled")) {
                    $resultObj = $doc
                    break
                }
            }
        } catch {}
        Start-Sleep -Milliseconds 350
    }

    try { $null = Invoke-GatewayHttp -Uri $jobUrl -Method "DELETE" -TimeoutSec 5 } catch {}
    if (-not $resultObj) { throw "Timed out waiting for job $jobId." }
    if (-not $resultObj.result_envelope) { throw "Agent returned unencrypted/missing result envelope." }

    $resPlain = Unprotect-JavisPayload -Envelope $resultObj.result_envelope -RecipientPrivXml $script:AdminPrivXml -ExpectedSenderPubXml $targetPubXml -ExpectedJobId $jobId -MaxSkewSec 300
    return @{
        status    = $resultObj.status
        exit_code = $resultObj.exit_code
        data      = ($resPlain | ConvertFrom-Json)
    }
}

$sqlText = $SqlQuery
if ([string]::IsNullOrWhiteSpace($sqlText) -and -not [string]::IsNullOrWhiteSpace($SqlFile) -and (Test-Path $SqlFile)) {
    $sqlText = Get-Content $SqlFile -Raw -Encoding UTF8
}

if ($Mode -eq "SqlExec" -and -not $ConfirmWrite.IsPresent) {
    Write-Host "`n[CONFIRM WRITE] Target: $DeviceId | DbProfile: $DbProfile" -ForegroundColor Yellow
    Write-Host "SQL:`n$sqlText" -ForegroundColor White
    $ans = Read-Host "Type YES to confirm write execution"
    if ($ans -ne "YES") {
        Write-Host "Aborted." -ForegroundColor Red
        return
    }
    $ConfirmWrite = $true
}

if ($Mode -eq "Tunnel") {
    $payload = @{
        mode             = "Tunnel"
        target_port      = $TargetPort
        ttl_min          = $DurationMin
        ephemeral_ro_sql = $EphemeralReadOnlySql.IsPresent
        db_profile       = $DbProfile
        connection_string = $ConnectionString
    }
    Write-Host "[TUNNEL] Requesting zero-config on-demand tunnel to $DeviceId (port $TargetPort, ${DurationMin}m)..." -ForegroundColor Cyan
    $res = Send-SignedJobAndWait -InnerPayload $payload -WaitSec 45
    if ($res.exit_code -ne 0) {
        throw "Tunnel setup failed: $($res.data.stderr)"
    }
    $tUrl = $res.data.tunnel_url.ToString()
    $wssUrl = $tUrl.Replace("https://", "wss://")
    $tTok = $res.data.tunnel_token.ToString()
    $tId = $res.data.tunnel_id.ToString()

    $tunnelExe = Ensure-JavisTunnelExe -BinDir $binDir
    $proxyProc = Start-Process -FilePath $tunnelExe -ArgumentList "client $LocalPort $wssUrl $tTok" -WindowStyle Hidden -PassThru

    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "  BB_JAVIS ON-DEMAND VPN-LIKE TUNNEL ACTIVE                           " -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor DarkCyan
    Write-Host "  -> Local Endpoint : 127.0.0.1,$LocalPort  (Connect SSMS / Code here)" -ForegroundColor Yellow
    Write-Host "  -> Expires UTC    : $($res.data.expires_at)" -ForegroundColor Gray
    if ($res.data.temp_sql_user) {
        Write-Host "  -> Temp SQL User  : $($res.data.temp_sql_user) (db_datareader)" -ForegroundColor Cyan
        Write-Host "  -> Temp SQL Pass  : $($res.data.temp_sql_pass)" -ForegroundColor Cyan
    }
    Write-Host "  Press Ctrl+C to close tunnel cleanly." -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor DarkCyan

    try {
        $endTime = [DateTime]::UtcNow.AddMinutes($DurationMin)
        while ([DateTime]::UtcNow -lt $endTime -and -not $proxyProc.HasExited) {
            Start-Sleep -Seconds 1
        }
    } finally {
        if ($proxyProc -and -not $proxyProc.HasExited) { Stop-Process -Id $proxyProc.Id -Force -ErrorAction SilentlyContinue }
        try {
            $null = Send-SignedJobAndWait -InnerPayload @{ mode = "CloseTunnel"; tunnel_id = $tId } -WaitSec 15
        } catch {}
        Write-Host "`n[TUNNEL CLOSED] Local proxy and remote tunnel terminated cleanly." -ForegroundColor Yellow
    }
    return
}

$inner = @{
    mode              = $Mode
    command           = $sqlText
    sql               = $sqlText
    db_profile        = $DbProfile
    connection_string = $ConnectionString
    raw_data          = $RawData.IsPresent
    confirm_write     = $ConfirmWrite.IsPresent
    max_rows          = $MaxRows
    remote_path       = $RemotePath
}

if ($Mode -eq "Upload") {
    if (-not (Test-Path $LocalPath)) { throw "LocalPath not found: $LocalPath" }
    $inner.file_name = [System.IO.Path]::GetFileName($LocalPath)
    $inner.file_data = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($LocalPath))
}

$jobResult = Send-SignedJobAndWait -InnerPayload $inner -WaitSec $TimeoutSec

if ($Mode -eq "Download" -and $jobResult.exit_code -eq 0 -and $jobResult.data.file_data) {
    if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = (Get-Location).Path }
    if (-not (Test-Path $OutputDir)) { $null = New-Item -ItemType Directory -Path $OutputDir -Force }
    $outFile = Join-Path $OutputDir $jobResult.data.file_name
    [System.IO.File]::WriteAllBytes($outFile, [Convert]::FromBase64String($jobResult.data.file_data))
    Write-Host "[SAVED] $outFile" -ForegroundColor Green
}

if ($jobResult.data.stdout) { Write-Output $jobResult.data.stdout }
if ($jobResult.data.stderr) { Write-Host $jobResult.data.stderr -ForegroundColor Red }
if ($jobResult.exit_code -ne 0) { exit $jobResult.exit_code }
