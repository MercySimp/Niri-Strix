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

echo "[build] Installing systemd user service..."
# Must be copied before daemon-reload so systemctl can find the unit
sudo install -Dm644 \
    "$(dirname "$0")/../lib/systemd/user/steam-install-confirm.service" \
    /usr/lib/systemd/user/steam-install-confirm.service

echo "[build] Enabling systemd user service..."
systemctl --user daemon-reload
systemctl --user enable --now steam-install-confirm.service

echo "[build] Done."
