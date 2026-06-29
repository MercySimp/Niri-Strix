# Deck Shell Backend

FastAPI service that handles Steam OpenID authentication and library queries
for the Deck Shell QML frontend.

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `DECK_SECRET` | `change_me_in_production` | Session signing key — **change this** |
| `STEAM_API_KEY` | *(empty)* | [Steam Web API key](https://steamcommunity.com/dev/apikey). Required for full owned-game list. Without it only locally installed games are returned. |
| `BACKEND_URL` | `http://localhost:8000` | Public base URL of this server (used in OpenID `return_to`) |
| `STEAM_DIR` | `~/.local/share/Steam` | Path to your Steam installation |

## Running

```bash
DECK_SECRET=mysecret STEAM_API_KEY=YOUR_KEY uvicorn main:app --host 0.0.0.0 --port 8000
```

## Auth flow

1. QML opens `WebEngineView` → `GET /auth/steam`
2. Backend redirects to `https://steamcommunity.com/openid/login` with proper OpenID params.
3. User logs in on Steam's website.
4. Steam redirects to `GET /auth/steam/callback` with the signed assertion.
5. Backend verifies the assertion, fetches persona/avatar, stores session cookie.
6. Backend redirects to `GET /auth/steam/done`.
7. QML's `onUrlChanged` sees `/auth/steam/done` → closes the WebEngineView.
8. QML polls `GET /auth/status` → updates persona/avatar in the UI.

## Endpoints

| Method | Path | Auth required | Description |
|---|---|---|---|
| GET | `/auth/steam` | No | Begin OpenID flow |
| GET | `/auth/steam/callback` | No | OpenID return handler |
| GET | `/auth/steam/done` | No | Success page (closes overlay) |
| GET | `/auth/status` | No | Current session state |
| POST | `/auth/logout` | No | Clear session |
| GET | `/library/owned` | Session (optional) | All owned games (API) or installed games (fallback) |
| GET | `/library/installed` | No | Locally installed games only |
| POST | `/system/power` | No | `{action: shutdown\|reboot\|suspend}` |
