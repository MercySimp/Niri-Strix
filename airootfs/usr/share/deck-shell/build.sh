#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Repo root is 3 levels up from airootfs/usr/share/deck-shell
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SERVICE_SRC="$REPO_ROOT/airootfs/usr/lib/systemd/user/steam-install-confirm.service"

echo "[build] Configuring..."
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release

echo "[build] Compiling..."
cmake --build build --parallel

echo "[build] Installing binary..."
sudo cmake --install build

echo "[build] Installing watcher script..."
sudo install -Dm755 "$SCRIPT_DIR/steam-install-confirm.sh" /usr/share/deck-shell/steam-install-confirm.sh

echo "[build] Installing systemd user service..."
if [[ ! -f "$SERVICE_SRC" ]]; then
    echo "[build] ERROR: service file not found at $SERVICE_SRC"
    exit 1
fi
sudo install -Dm644 "$SERVICE_SRC" /usr/lib/systemd/user/steam-install-confirm.service

echo "[build] Enabling systemd user service..."
systemctl --user daemon-reload
systemctl --user enable --now steam-install-confirm.service

echo "[build] Done."
