"""Deck Shell backend — FastAPI

Endpoints
---------
GET  /auth/steam          → redirect to Steam OpenID
GET  /auth/steam/callback → handle OpenID return, store session
GET  /auth/steam/done     → success page with user data in query params for QML shell
GET  /auth/status         → {linked, persona, avatar, steamId}
POST /auth/logout         → clear session
GET  /library/owned       → {games: [{appId, name, coverUrl, lastPlayed}]}
POST /system/power        → {action: shutdown|reboot|suspend}
"""

import os
import re
import subprocess
from pathlib import Path
from typing import Optional
from urllib.parse import quote

import httpx
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse, RedirectResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.sessions import SessionMiddleware

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SECRET_KEY    = os.environ.get("DECK_SECRET", "change_me_in_production")
STEAM_API_KEY = os.environ.get("STEAM_API_KEY", "")
BACKEND_URL   = os.environ.get("BACKEND_URL", "https://api.accesshomeserver.uk")

OPENID_ENDPOINT = "https://steamcommunity.com/openid/login"
RETURN_TO       = f"{BACKEND_URL}/auth/steam/callback"
REALM           = BACKEND_URL

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Deck Shell API", version="0.3.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(
    SessionMiddleware,
    secret_key=SECRET_KEY,
    session_cookie="deck_session",
    max_age=60 * 60 * 24 * 30,   # 30 days
    https_only=True,
    same_site="lax",
)

# ---------------------------------------------------------------------------
# Steam OpenID helpers
# ---------------------------------------------------------------------------
def build_openid_params(return_to: str, realm: str) -> dict:
    return {
        "openid.ns":         "http://specs.openid.net/auth/2.0",
        "openid.mode":       "checkid_setup",
        "openid.return_to":  return_to,
        "openid.realm":      realm,
        "openid.identity":   "http://specs.openid.net/auth/2.0/identifier_select",
        "openid.claimed_id": "http://specs.openid.net/auth/2.0/identifier_select",
    }


def extract_steam_id(claimed_id: str) -> Optional[str]:
    m = re.search(r"steamcommunity\.com/openid/id/(\d+)", claimed_id or "")
    return m.group(1) if m else None


async def verify_openid(params: dict) -> bool:
    check_params = {**params, "openid.mode": "check_authentication"}
    async with httpx.AsyncClient() as client:
        r = await client.post(OPENID_ENDPOINT, data=check_params, timeout=10)
    return "is_valid:true" in r.text


async def fetch_player_summary(steam_id: str) -> dict:
    if STEAM_API_KEY:
        url = (
            f"https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/"
            f"?key={STEAM_API_KEY}&steamids={steam_id}"
        )
        async with httpx.AsyncClient() as client:
            r = await client.get(url, timeout=10)
        players = r.json().get("response", {}).get("players", [])
        if players:
            p = players[0]
            return {"persona": p.get("personaname", ""), "avatar": p.get("avatarfull", "")}
    # Fallback: public community XML
    url = f"https://steamcommunity.com/profiles/{steam_id}/?xml=1"
    async with httpx.AsyncClient() as client:
        r = await client.get(url, timeout=10)
    persona = re.search(r"<steamID><!\[CDATA\[(.+?)\]\]>", r.text)
    avatar  = re.search(r"<avatarFull><!\[CDATA\[(.+?)\]\]>", r.text)
    return {
        "persona": persona.group(1) if persona else steam_id,
        "avatar":  avatar.group(1)  if avatar  else "",
    }


async def fetch_owned_games_api(steam_id: str) -> list[dict]:
    url = (
        f"https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
        f"?key={STEAM_API_KEY}&steamid={steam_id}"
        f"&include_appinfo=true&include_played_free_games=true"
    )
    async with httpx.AsyncClient() as client:
        r = await client.get(url, timeout=15)
    return r.json().get("response", {}).get("games", [])


# ---------------------------------------------------------------------------
# Routes — Auth
# ---------------------------------------------------------------------------
@app.get("/auth/steam")
async def auth_steam_begin():
    params = build_openid_params(RETURN_TO, REALM)
    qs = "&".join(f"{k}={v}" for k, v in params.items())
    return RedirectResponse(f"{OPENID_ENDPOINT}?{qs}")


@app.get("/auth/steam/callback")
async def auth_steam_callback(request: Request):
    params     = dict(request.query_params)
    claimed_id = params.get("openid.claimed_id", "")
    steam_id   = extract_steam_id(claimed_id)
    if not steam_id:
        raise HTTPException(400, "Missing or invalid claimed_id")
    valid = await verify_openid(params)
    if not valid:
        raise HTTPException(403, "OpenID verification failed")

    summary = await fetch_player_summary(steam_id)
    persona = summary["persona"]
    avatar  = summary["avatar"]

    # Store in session for /auth/status and /library/owned
    request.session["steam_id"] = steam_id
    request.session["persona"]  = persona
    request.session["avatar"]   = avatar
    request.session["linked"]   = True

    # Redirect to /done with user data embedded as query params.
    # The QML shell reads these directly from the URL so it never needs
    # to make a separate cookie-authenticated request.
    done_url = (
        f"{BACKEND_URL}/auth/steam/done"
        f"?persona={quote(persona)}"
        f"&avatar={quote(avatar)}"
        f"&steamid={steam_id}"
    )
    return RedirectResponse(done_url)


@app.get("/auth/steam/done", response_class=HTMLResponse)
async def auth_steam_done(request: Request):
    # persona may come from query params (fresh login) or session (page reload)
    persona = request.query_params.get("persona") or request.session.get("persona", "")
    avatar  = request.query_params.get("avatar")  or request.session.get("avatar", "")
    steamid = request.query_params.get("steamid") or request.session.get("steam_id", "")

    # The shell's onUrlChanged fires as soon as this URL is hit, so the
    # page content is mostly cosmetic — but we keep it friendly in case
    # someone lands here in a real browser.
    return HTMLResponse(
        f"<html><body style='background:#14161a;color:white;font-family:sans-serif;"
        f"display:flex;align-items:center;justify-content:center;height:100vh;margin:0'>"
        f"<h2>\u2714 Signed in as {persona}. Returning to Deck Shell\u2026</h2>"
        f"</body></html>"
    )


@app.get("/auth/status")
async def auth_status(request: Request):
    return JSONResponse({
        "linked":  request.session.get("linked",   False),
        "steamId": request.session.get("steam_id", ""),
        "persona": request.session.get("persona",  ""),
        "avatar":  request.session.get("avatar",   ""),
    })


@app.post("/auth/logout")
async def auth_logout(request: Request):
    request.session.clear()
    return JSONResponse({"ok": True})


# ---------------------------------------------------------------------------
# Routes — Library
# ---------------------------------------------------------------------------
@app.get("/library/owned")
async def library_owned(request: Request):
    steam_id = request.session.get("steam_id", "")
    games: list[dict] = []

    if STEAM_API_KEY and steam_id:
        try:
            owned = await fetch_owned_games_api(steam_id)
            for g in owned:
                app_id = str(g["appid"])
                games.append({
                    "appId":           app_id,
                    "name":            g.get("name", f"App {app_id}"),
                    "coverUrl":        f"https://cdn.akamai.steamstatic.com/steam/apps/{app_id}/library_600x900.jpg",
                    "playtimeForever": g.get("playtime_forever", 0),
                })
            return JSONResponse({"games": games, "source": "api"})
        except Exception:
            pass

    return JSONResponse({"games": [], "source": "none"})


# ---------------------------------------------------------------------------
# Routes — System power
# ---------------------------------------------------------------------------
@app.post("/system/power")
async def system_power(request: Request):
    body   = await request.json()
    action = body.get("action", "")
    cmds   = {
        "shutdown": ["systemctl", "poweroff"],
        "reboot":   ["systemctl", "reboot"],
        "suspend":  ["systemctl", "suspend"],
    }
    if action not in cmds:
        raise HTTPException(400, f"Unknown action: {action}")
    subprocess.Popen(cmds[action])
    return JSONResponse({"ok": True})
