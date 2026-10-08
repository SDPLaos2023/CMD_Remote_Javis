# ⚡ BB_JAVIS Remote: Real-Time Zero-Dependency Remote Server & DB Management

High-performance remote server execution, file transfer, and SQL database management via Cloud Command Board. Operates seamlessly without VPN, powered by **AI Autonomous Resilience (Intelligent Watchdog, Auto-Retry & In-Place Auto-Restart)** to detect and recover from stalled commands automatically.

---

## 🚀 Key Features

* **AI Autonomous Resilience & Intelligent Watchdog:**
  * **Pending Hang Guard (>20s):** Detects dispatched jobs that have not been picked up by any agent within 20 seconds.
  * **Running Stalled Guard (>30s):** Detects running jobs that stall silently without heartbeats or output for more than 30 seconds.
  * **Autonomous Auto-Retry:** Automatically aborts the stalled job (Emergency Abort) and resends it (Retry 1/1) without requiring operator intervention.
  * **Heartbeat-Aware Safety:** For long-running operations (such as large database backups), active heartbeats every 1.5 seconds ensure the process continues safely without premature timeouts.
* **In-Place Agent Auto-Restart (Self-Healing):**
  * If a command stalls repeatedly after retry, an escalation signal `__JAVIS_SYSTEM_RESTART__` is dispatched.
  * The agent executes an In-Place Reset (clearing Runspaces, Sockets, and running GC) within the same console window.
  * **Preserves Same PIN:** Retains the existing 4-digit Secret Key (PIN) so ongoing automation can continue immediately.
* **Enterprise Security Gateway (Cloudflare Edge WAF):** Obfuscates backend database infrastructure with anti-scanning protections.
* **Multi-Tenant Data Isolation:** Isolates organization/fleet namespaces using HMAC-SHA256 Cryptographic API Keys.
* **Local Machine Profile Persistence:** Persists local API keys (`config.json`) so users only need to enter keys once.
* **Real-Time SSE Push Engine (<10ms):** Delivers sub-10ms command dispatch and status notifications via Server-Sent Events.
* **Zero-Dependency 100%:** Powered entirely by Native .NET HTTP; runs out-of-the-box on modern Windows Server systems without external dependencies.
* **Zero-Touch One-Link Setup:** Instantly runnable on remote servers via single-line commands with automated TLS 1.2 negotiation.
* **Self-Destruct Clean Exit & Zero-Footprint:** Pressing `Ctrl+C` or closing the console purges the cloud session node immediately (Zero Data Residue).
* **Universal Database & File Engine:**
  * Real-time streaming PowerShell / CMD execution.
  * Direct SQL Server queries returning JSON results.
  * Automated SQL database backups with compression.
  * Secure bidirectional file and directory transfers.
  * GUI automation via UI Automation (`win-arm`) and real-time desktop screen streaming.

---

## 💻 How to Run on Target Machines (Dual-Mode Target Agent)

The system supports two operating modes:

### 1️⃣ Mode 1: On-Demand / Temporary Session (`da.gd/bbj`)
> Ideal for ad-hoc debugging or temporary tasks. Randomizes a 4-digit PIN in memory; closing the console deletes the session completely.

Open **PowerShell (Run as Administrator)** and execute:
```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj | iex
```

---

### 2️⃣ Mode 2: Persistent Background Windows Service (`da.gd/bbj-fix`)
> Ideal for production servers or retail POS stations running 24/7. Automatically starts on boot and remembers a permanent fixed PIN.

Open **PowerShell (Run as Administrator)** and execute:
```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj-fix | iex
```
*(Or run `install_service.bat`)*

* **Custom Host Name / Alias:** Prompts for a friendly machine name (e.g. `POS-Branch1`, `UAT-DB-01`) or inherits `$env:COMPUTERNAME` by pressing Enter. Can also be pre-set via `$env:BB_JAVIS_HOST = "MyServer"`.
* Registers as a native Windows Service: `BB_JAVIS_Remote`.
* Runs 24/7 in the background under the `SYSTEM` account with a persistent PIN.
* Once installation completes, you can safely **close the PowerShell window**.

#### To Uninstall Service:
```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj-unfix | iex
```
*(Or run `uninstall_service.bat`)*

---

## 🎮 Controller Usage (Send Commands & Fleet Management)

### Interactive Fleet Management:
Run the controller without arguments to display registered machines:
```cmd
send_remote_command.bat
```
* **Status Table:** Shows online/offline status, IP addresses, hostnames, and aliases.
* **Navigation:**
  * Enter `[1-N]` to select a machine.
  * Enter machine name or IP to auto-match.
  * Enter 4-digit PIN directly.
  * Press `[N]` to rename a machine (Set Alias).
  * Press `[D]` to delete an offline device.
  * Press `[R]` to refresh fleet status.
  * Press `[Q]` to quit.

### Automated Command Line Execution:
```cmd
:: Run PowerShell command on specific PIN
send_remote_command.bat -SecretKey "7881" -Mode "PowerShell" -Command "Get-Service | Select-Object -First 5"

:: Target by Machine Alias or Name
send_remote_command.bat -TargetHost "POS-Branch1" -Mode "PowerShell" -Command "hostname"

:: Execute SQL Query
send_remote_command.bat -SecretKey "7881" -Mode "Sql" -ConnectionString "Server=localhost;Database=master;Integrated Security=True;" -SqlQuery "SELECT @@VERSION AS Version"

:: Purge all offline machines from cloud
send_remote_command.bat -PurgeOffline
```

---

## 🔒 Security Architecture

1. **HMAC-SHA256 API Key Verification:** Every request is authenticated against an enterprise tenant profile.
2. **Dynamic 4-Digit Ephemeral / Persistent PIN:** Target machines must match the operator's secret key before accepting any command.
3. **Emergency Job Cancellation:** Operator `Ctrl+C` sends an immediate abort signal to kill running processes on the remote machine.
4. **Zero Cloud Storage of Sensitive Output:** Job payloads self-destruct upon completion.
