# ⚡ BB_JAVIS / CMD_Remote: Zero-Trust Remote Server & DB Management

High-performance remote server control, SQL database querying/tunneling, and file transfer without VPN — powered by **Cloudflare Edge Gateway**, **SSE Real-Time Push (<10ms)**, and **End-to-End Encryption (RSA-2048 OAEP + AES-256-CBC + HMAC-SHA256)**.

---

## 🤖 Quick Guide for AI Agents (สำหรับสั่งให้ AI เรียนรู้การใช้งาน)

If an operator asks you (an AI coding assistant) to learn or operate **CMD_Remote / BB_JAVIS** from this repository, follow these exact rules and commands:

### 1. First-Time Check (Controller Dev Machine)
Run `-List` to check paired online devices:
```cmd
send_remote_command.bat -List
```
- **If this Dev machine has never been registered:** Running `send_remote_command.bat` prompts once for a **Team License Key (`JAVIS-XXXX-XXXX-XXXX`)** issued by the Team Owner (via `license_manager.bat`), or pass `-LicenseKey "JAVIS-XXXX-XXXX-XXXX"`. After activation, credentials are encrypted via Windows DPAPI under `%LOCALAPPDATA%\BB_Javis\` and never prompted again.
- **If no target device appears in `-List` yet:** Ask the target operator for their **4-digit Remote PIN** (`1000-9999`), then pair once:
  ```cmd
  send_remote_command.bat -Pair "4821"
  ```

### 2. AI Auto-Decision Matrix (Which `-Mode` to use)
Always choose the execution mode automatically based on the task (never ask the user unnecessarily, **except** before SQL writes):

| Task Type | Required Mode | Key Behavior & Safety Gate |
|---|---|---|
| **Read SQL (`SELECT`, `WITH`), 1–3 statements** | **`-Mode Query`** (or `-Mode Auto`) | Sub-second JSON output, supports Windows Auth (`Integrated Security=True`) on target server, blocks writes (`DELETE`/`UPDATE`/`DROP`/`EXEC`), and masks PII columns automatically (pass `-RawData` only when raw values are needed). |
| **Batch Read SQL (`>= 4` statements), large `.sql`, or direct SSMS/TCP access** | **`-Mode Tunnel`** (or `-Mode Auto`) | Opens encrypted local port `127.0.0.1:11433` → target `1433` via On-Demand Cloudflare Tunnel (with automatic fallback to `Query`). |
| **Write / Schema SQL (`INSERT`, `UPDATE`, `DELETE`, `ALTER`, `DROP`)** | **`-Mode SqlExec`** *(Human Gate Required)* | Runs inside an automatic transaction rollback wrapper and requires `-ConfirmWrite`. **AI RULE: Never pass `-ConfirmWrite` automatically; show the target machine, `DbProfile`, and exact SQL to the user for explicit approval first.** |
| **OS commands, Windows Services, file inspection** | **`-Mode PowerShell`** (or `-Mode Auto`) | E2E encrypted PowerShell runspace execution + RSA-SHA256 signature verification. |
| **File transfer** | **`-Mode Upload` / `-Mode Download`** | Encrypted base64 payload transfer between Dev and Target. |

### 3. Essential AI Command Reference
```cmd
:: Fleet status
send_remote_command.bat -List

:: Pair a new target machine using its 4-digit PIN
send_remote_command.bat -Pair "4821"

:: Run PowerShell by 4-digit PIN or Machine Name (-TargetHost)
send_remote_command.bat -Pin "4821" -Mode PowerShell -Command "hostname; Get-Service *SQL*"
send_remote_command.bat -TargetHost "TDP-IMMIGRATION" -Mode PowerShell -Command "Get-Process | Select -First 10"

:: Auto-Mode (1-3 SELECT -> Query | >=4 SELECT -> Tunnel+Fallback | Write -> SqlExec Gate | Non-SQL -> PowerShell)
send_remote_command.bat -TargetHost "TDP-IMMIGRATION" -Mode Auto -DbProfile "Default" -SqlQuery "SELECT TOP 10 name FROM sys.databases"

:: Read-Only SQL Query with DPAPI DB Profile (no DB password sent over network)
send_remote_command.bat -TargetHost "TDP-IMMIGRATION" -Mode Query -DbProfile "Default" -SqlQuery "SELECT TOP 5 * FROM Users"
send_remote_command.bat -TargetHost "TDP-IMMIGRATION" -Mode Query -DbProfile "Default" -SqlQuery "SELECT TOP 5 * FROM Users" -RawData

:: Explicit DB Write (ONLY after user confirms exact SQL)
send_remote_command.bat -TargetHost "TDP-IMMIGRATION" -Mode SqlExec -DbProfile "Default" -SqlQuery "UPDATE Config SET Value = '1' WHERE Id = 5" -ConfirmWrite

:: On-Demand Tunnel (connect SSMS / app to 127.0.0.1,11433)
send_remote_command.bat -TargetHost "TDP-IMMIGRATION" -Mode Tunnel -LocalPort 11433 -TargetPort 1433 -DurationMin 30

:: File Transfer
send_remote_command.bat -Pin "4821" -Mode Upload -LocalPath "C:\local\app.zip" -RemotePath "C:\temp\app.zip"
send_remote_command.bat -Pin "4821" -Mode Download -RemotePath "C:\logs\app.log" -OutputDir "C:\downloads"

:: Revoke compromised device or admin
send_remote_command.bat -Mode Revoke -RevokeRole "adm" -RevokeId "oldadmin"
```

---

## 💻 How to Run on Target Machines (Dual-Mode Agent)

### 1️⃣ Mode 1: Temporary / On-Demand Session (`da.gd/bbj`)
> Ideal for ad-hoc troubleshooting. Generates a random 4-digit PIN in memory, purges cloud session on exit, and **auto-closes PowerShell after 5 hours of inactivity** (`-IdleTimeoutMinutes 300`, paused while an active Tunnel is open).

Open **PowerShell (Run as Administrator)** on the target machine:
```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj | iex
```
*(Or double-click `start_remote_agent.bat`)*

### 2️⃣ Mode 2: Persistent Windows Service 24/7 (`da.gd/bbj-fix`)
> Ideal for production servers or POS machines. Registers native Windows Service `BB_JAVIS_Remote` under `SYSTEM`.

Open **PowerShell (Run as Administrator)** on the target machine:
```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj-fix | iex
```
*(Or run `install_service.bat` as Administrator)*
- Waits up to 30 seconds for `C:\ProgramData\BB_Javis\pairing.txt` and prints the **4-digit Remote PIN** right in the installer window (waits up to 120s for Dev `-Pair <PIN>` confirmation; you may close anytime and the service remains active).
- Logs any startup exceptions to `C:\ProgramData\BB_Javis\service_error.log`.
- Configure saved DPAPI DB Profiles on the target server via:
  ```powershell
  powershell -File start_remote_agent.ps1 -ConfigureDbProfile -DbProfileName "Default" -DbConnectionString "Server=.\SQLEXPRESS;Database=MyDb;Integrated Security=True;"
  ```

### 🗑️ Uninstall Service (`da.gd/bbj-unfix`)
```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072; irm da.gd/bbj-unfix | iex
```
*(Or run `uninstall_service.bat`)*

---

## 🔑 Team Onboarding & Owner License Management

The system separates **Owner** (`bbj_own_*`) and **Teammate** (`bbj_adm_*`) privileges:
- **Team Owner (`license_manager.bat`):**
  - First run upgrades this Owner PC once using `JAVIS_MASTER_SECRET` to `bbj_own_*` (preserving existing paired devices).
  - Issue keys (`JAVIS-XXXX-XXXX-XXXX`), limit machine count (`-MaxDevices 1` bound via Windows `MachineGuid`), set optional expiration (`-ExpireDays 30`), list active machines, and revoke access instantly:
    ```cmd
    license_manager.bat -Issue -TeamUser "somchai" -MaxDevices 1 -ExpireDays 30
    license_manager.bat -List
    license_manager.bat -Revoke -LicenseKey "JAVIS-XXXX-XXXX-XXXX"
    ```
- **Teammates (`send_remote_command.bat`):**
  - **Do not need `JAVIS_MASTER_SECRET`.**
  - On first launch on a Dev machine, enter the `JAVIS-XXXX-XXXX-XXXX` License Key when prompted (or run `send_remote_command.bat -LicenseKey "JAVIS-..."`). All subsequent runs work immediately with full command/DB/tunnel capabilities across tenant devices, while blocking unauthorized license minting (`403 Forbidden`).

---

## 🔒 Zero-Trust Security Architecture

1. **Zero-Secret Distribution:** No database URLs, Firebase secrets, or master keys exist in this repository; all traffic routes through the Cloudflare Edge Gateway (`https://bb-javis-gateway.apisit-yimboa.workers.dev`) with full TLS verification.
2. **E2E Cryptography:** Command payloads and outputs are RSA-2048 OAEP + AES-256-CBC + HMAC-SHA256 encrypted and RSA-SHA256 signed with replay protection (`MaxSkewSec = 300`, `job_id` binding).
3. **DPAPI Secret Storage:** Target DB connection strings (`LocalMachine`) and Dev RSA/API keys (`CurrentUser`) are encrypted with Windows DPAPI.
4. **Dual Hash-Chained Audit Log:** Tamper-evident `audit_YYYY-MM.jsonl` stored locally on target machines plus metadata at the Worker `/audit` endpoint.
