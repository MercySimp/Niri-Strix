"""Deck Shell Local Companion — runs on the Arch machine at localhost:8001

This tiny service reads the local Steam installation and exposes:
  GET /installed  → {games: [{appId, name, coverUrl, lastPlayed}]}

It never talks to the internet. The QML shell calls it directly for the
'Installed' library tab, so no API key or internet connection is needed
for locally installed games.

Run once at session start via the deck-companion.service systemd unit.
"""

import os
import re
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

STEAM_DIR = Path(os.environ.get("STEAM_DIR", Path.home() / ".local/share/Steam"))

app = FastAPI(title="Deck Shell Companion", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


def parse_acf_value(text: str, key: str) -> str:
    m = re.search(rf'"{ re.escape(key) }"\s+"([^"]+)"', text)
    return m.group(1) if m else ""


def get_last_played() -> dict:
    timestamps: dict[str, str] = {}
    userdata = STEAM_DIR / "userdata"
    if not userdata.exists():
        return timestamps
    for uid_dir in userdata.iterdir():
        config = uid_dir / "config" / "localconfig.vdf"
        if not config.exists():
            continue
        text = config.read_text(errors="replace")
        for m in re.finditer(r'"(\d{5,})"[\s\S]*?"LastPlayed"\s+"(\d+)"', text):
            timestamps[m.group(1)] = m.group(2)
    return timestamps


@app.get("/installed")
def installed_games():
    steam_apps = STEAM_DIR / "steamapps"
    last_played = get_last_played()
    games = []

    if not steam_apps.exists():
        return JSONResponse({"games": [], "error": "steamapps not found"})

    for mf in steam_apps.glob("appmanifest_*.acf"):
        try:
            text   = mf.read_text(errors="replace")
            app_id = parse_acf_value(text, "appid")
            name   = parse_acf_value(text, "name")
            if not app_id:
                continue
            games.append({
                "appId":      app_id,
                "name":       name or f"App {app_id}",
                "coverUrl":   f"https://cdn.akamai.steamstatic.com/steam/apps/{app_id}/library_600x900.jpg",
                "lastPlayed": last_played.get(app_id, "0"),
            })
        except Exception:
            continue

    return JSONResponse({"games": games})
