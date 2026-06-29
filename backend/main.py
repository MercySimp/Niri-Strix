"""
Deck Shell – Steam auth + library backend

Endpoints:
  GET  /auth/steam           → redirect user to Steam OpenID login
  GET  /auth/steam/callback  → Steam returns here; verify & issue session
  GET  /auth/steam/done      → landing page the webview watches for
  GET  /library/owned        → return owned-games JSON for the linked user
  GET  /auth/status          → return current link status for a session
  POST /auth/logout          → clear session

Environment variables (see .env.example):
  STEAM_API_KEY   – your Steam Web API key
  BACKEND_HOST    – public HTTPS hostname, e.g. auth.deckos.example.com
  SECRET_KEY      – random 32+ char string for session signing
"""

import os
import re
import secrets
import hashlib
import urllib.parse
from datetime import datetime, timedelta
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from pydantic import BaseModel

app = FastAPI(title="DeckShell Steam Auth Service")

# ── Config ────────────────────────────────────────────────────────────────────
STEAM_OPENID_URL  = "https://steamcommunity.com/openid/login"
STEAM_OWNED_URL   = "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
STEAM_CDN         = "https://cdn.steamstatic.com/steam/apps"

STEAM_API_KEY     = os.environ["STEAM_API_KEY"]
BACKEND_HOST      = os.getenv("BACKEND_HOST", "http://localhost:8000")
SECRET_KEY        = os.environ["SECRET_KEY"]

# In-memory session store: session_token -> {steam_id, persona, avatar, expires}
_sessions: dict[str, dict] = {}

# ── Helpers ───────────────────────────────────────────────────────────────────

def _new_token() -> str:
    return secrets.token_hex(32)

def _openid_params(return_to: str, realm: str) -> dict:
    return {
        "openid.ns":         "http://specs.openid.net/auth/2.0",
        "openid.mode":       "checkid_setup",
        "openid.return_to":  return_to,
        "openid.realm":      realm,
        "openid.identity":   "http://specs.openid.net/auth/2.0/identifier_select",
        "openid.claimed_id": "http://specs.openid.net/auth/2.0/identifier_select",
    }

async def _verify_openid(params: dict) -> Optional[str]:
    """Verify the OpenID assertion and return SteamID64 string, or None on failure."""
    check_params = dict(params)
    check_params["openid.mode"] = "check_authentication"
    async with httpx.AsyncClient() as client:
        resp = await client.post(STEAM_OPENID_URL, data=check_params)
    if "is_valid:true" not in resp.text:
        return None
    claimed = params.get("openid.claimed_id", "")
    m = re.search(r"https://steamcommunity\.com/openid/id/(\d+)", claimed)
    return m.group(1) if m else None

async def _fetch_persona(steam_id: str) -> tuple[str, str]:
    """Return (persona_name, avatar_url) for a SteamID64."""
    url = (
        f"https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/"
        f"?key={STEAM_API_KEY}&steamids={steam_id}"
    )
    async with httpx.AsyncClient() as client:
        resp = await client.get(url)
    players = resp.json().get("response", {}).get("players", [])
    if not players:
        return (steam_id, "")
    p = players[0]
    return (p.get("personaname", steam_id), p.get("avatarfull", ""))

async def _fetch_owned(steam_id: str) -> list[dict]:
    """Return list of owned-game dicts from IPlayerService/GetOwnedGames."""
    params = {
        "key":                    STEAM_API_KEY,
        "steamid":                steam_id,
        "include_appinfo":        "1",
        "include_played_free_games": "1",
    }
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.get(STEAM_OWNED_URL, params=params)
    games = resp.json().get("response", {}).get("games", [])
    result = []
    for g in games:
        app_id = str(g.get("appid", ""))
        if not app_id:
            continue
        result.append({
            "appId":    app_id,
            "name":     g.get("name", ""),
            "coverUrl": f"{STEAM_CDN}/{app_id}/library_600x900.jpg",
            "logoUrl":  f"{STEAM_CDN}/{app_id}/header.jpg",
        })
    return result

def _get_session(request: Request) -> Optional[dict]:
    token = request.cookies.get("deck_session")
    if not token:
        return None
    session = _sessions.get(token)
    if not session:
        return None
    if datetime.utcnow() > session["expires"]:
        _sessions.pop(token, None)
        return None
    return session

# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/auth/steam")
async def steam_login():
    """Entry point: redirect user to Steam OpenID."""
    return_to = f"{BACKEND_HOST}/auth/steam/callback"
    realm     = BACKEND_HOST
    params = _openid_params(return_to, realm)
    url = STEAM_OPENID_URL + "?" + urllib.parse.urlencode(params)
    return RedirectResponse(url)

@app.get("/auth/steam/callback")
async def steam_callback(request: Request):
    """Steam redirects here after user approves. Verify and issue session."""
    params = dict(request.query_params)
    steam_id = await _verify_openid(params)
    if not steam_id:
        raise HTTPException(status_code=400, detail="OpenID verification failed")

    persona, avatar = await _fetch_persona(steam_id)
    token   = _new_token()
    expires = datetime.utcnow() + timedelta(days=30)
    _sessions[token] = {
        "steam_id": steam_id,
        "persona":  persona,
        "avatar":   avatar,
        "expires":  expires,
    }

    # Redirect to /auth/steam/done – the webview in the Deck shell watches for this URL
    response = RedirectResponse(f"{BACKEND_HOST}/auth/steam/done?persona={urllib.parse.quote(persona)}")
    response.set_cookie(
        key="deck_session",
        value=token,
        httponly=True,
        secure=True,
        samesite="lax",
        max_age=30 * 24 * 3600,
    )
    return response

@app.get("/auth/steam/done", response_class=HTMLResponse)
async def steam_done(persona: str = ""):
    """Landing page the Deck shell webview watches for to know login is complete."""
    return HTMLResponse(f"""
    <html><head><title>Signed in</title></head>
    <body style="background:#14161a;color:#e8e8e8;font-family:sans-serif;text-align:center;padding-top:20vh">
        <h1>&#x2665; Signed in as {persona}</h1>
        <p>You can close this window and return to the Deck Shell.</p>
    </body></html>
    """)

@app.get("/auth/status")
async def auth_status(request: Request):
    session = _get_session(request)
    if not session:
        return JSONResponse({"linked": False})
    return JSONResponse({
        "linked":   True,
        "steamId":  session["steam_id"],
        "persona":  session["persona"],
        "avatar":   session["avatar"],
    })

@app.post("/auth/logout")
async def logout(request: Request, response: Response):
    token = request.cookies.get("deck_session")
    if token:
        _sessions.pop(token, None)
    response.delete_cookie("deck_session")
    return JSONResponse({"ok": True})

@app.get("/library/owned")
async def library_owned(request: Request):
    """Return JSON list of games owned by the signed-in user."""
    session = _get_session(request)
    if not session:
        raise HTTPException(status_code=401, detail="Not authenticated")
    games = await _fetch_owned(session["steam_id"])
    return JSONResponse({"games": games})
