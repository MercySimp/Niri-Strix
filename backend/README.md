# Deck Shell – Steam Auth Backend

A small FastAPI service that:
1. Implements the Steam OpenID 2.0 login flow.
2. Verifies the OpenID assertion and extracts the user's SteamID64.
3. Fetches owned games via `IPlayerService/GetOwnedGames` using **your** API key (users never manage keys).
4. Issues a secure HTTP-only session cookie so the Deck Shell QML client can call `/library/owned`.

## Setup

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# Edit .env and fill in STEAM_API_KEY, BACKEND_HOST, SECRET_KEY
export $(grep -v '^#' .env | xargs)

uvicorn main:app --host 0.0.0.0 --port 8000
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/auth/steam` | Redirect user to Steam OpenID login |
| GET | `/auth/steam/callback` | Steam returns here; verify + issue session |
| GET | `/auth/steam/done` | Landing page the Deck shell webview watches for |
| GET | `/auth/status` | Return `{linked, steamId, persona, avatar}` |
| POST | `/auth/logout` | Clear session |
| GET | `/library/owned` | Return owned-games JSON for the signed-in user |

## Deploying

The backend must be reachable over **HTTPS** at the hostname you put in `BACKEND_HOST`.
Steam's OpenID will not redirect to a plain HTTP URL in production.

A minimal deployment: any VPS with nginx + certbot in front of uvicorn, or a free-tier render.com/fly.io service.

The systemd unit at `deck-shell-backend.service` can be used if self-hosting on the same machine.
