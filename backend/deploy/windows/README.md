# Windows Deployment Guide
## api.accesshomeserver.uk → Deck Shell Backend

### Architecture

```
Internet
   │
   │ HTTPS :443
   ▼
Router (accesshomeserver.uk)
   │  Port forward 80 + 443 → this machine
   ▼
Windows Home Server
 ┌─────────────────┐
 │  Caddy :443       │  ← auto TLS (Let's Encrypt)
 │  reverse_proxy    │
 │  localhost:8000   │
 └────────┬────────┘
          │
 ┌────────┴────────┐
 │  FastAPI :8000    │  ← STEAM_API_KEY stored here
 │  (uvicorn via     │     users never see it
 │   NSSM service)   │
 └─────────────────┘
```

### Prerequisites

| Tool | Where to get |
|---|---|
| Python 3.11+ | https://python.org/downloads |
| NSSM | https://nssm.cc/download — extract `nssm.exe` to `C:\nssm\` |
| Caddy | Installed automatically by `install-caddy.bat` |

### Step-by-step

#### 1. DNS
In your domain registrar (or Cloudflare if you proxy through them),
add an **A record**:
```
Type: A
Name: api
Value: <your home public IP>
TTL: 300
```
This makes `api.accesshomeserver.uk` point to your home server.

#### 2. Router port forwarding
Forward **TCP 80** and **TCP 443** to this Windows machine's local IP.
Caddy needs port 80 for the ACME HTTP challenge when issuing the TLS cert.

#### 3. Install the backend service
```bat
REM Run as Administrator
cd backend\deploy\windows
install-service.bat
```
When prompted, edit `backend\.env` and fill in:
- `DECK_SECRET` — any long random string
- `STEAM_API_KEY` — from https://steamcommunity.com/dev/apikey
  (use `http://api.accesshomeserver.uk` as the domain when registering the key)

#### 4. Install Caddy
```bat
REM Run as Administrator
install-caddy.bat
```
Caddy will automatically obtain a TLS certificate for `api.accesshomeserver.uk`
on its first request.

#### 5. Windows Firewall
Allow inbound TCP on ports 80 and 443:
```powershell
netsh advfirewall firewall add rule name="Caddy HTTP" protocol=TCP dir=in localport=80 action=allow
netsh advfirewall firewall add rule name="Caddy HTTPS" protocol=TCP dir=in localport=443 action=allow
```

#### 6. Update QML shell
The `main.qml` `backendUrl` is already set to `https://api.accesshomeserver.uk`.
No client-side changes needed.

### Service management

```bat
REM Check status
nssm status DeckShellBackend

REM Restart after .env changes
nssm restart DeckShellBackend

REM View logs
type C:\DeckShell\logs\deck-backend.log
```

### Updating the backend

```bat
cd backend
git pull
call .venv\Scripts\activate.bat
pip install -r requirements.txt
nssm restart DeckShellBackend
```
