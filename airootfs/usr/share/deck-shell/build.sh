#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "[build] Configuring..."
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release

echo "[build] Compiling..."
cmake --build build --parallel

echo "[build] Installing binary..."
sudo cmake --install build

echo "[build] Installing watcher script..."
sudo install -Dm755 steam-install-confirm.sh /usr/share/deck-shell/steam-install-confirm.sh

echo "[build] Enabling systemd user service..."
systemctl --user daemon-reload
systemctl --user enable --now steam-install-confirm.service

echo "[build] Done."
