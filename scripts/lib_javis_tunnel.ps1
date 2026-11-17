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
