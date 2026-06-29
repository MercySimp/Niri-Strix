#!/usr/bin/env bash
# Install the local companion service on the Arch machine.
# Run once after cloning the repo.
set -e

COMPANION_DIR="$HOME/.local/share/deck-shell/companion"
SERVICE_DIR="$HOME/.config/systemd/user"

echo "[1/4] Copying companion files..."
mkdir -p "$COMPANION_DIR"
cp main.py requirements.txt "$COMPANION_DIR/"

echo "[2/4] Creating Python venv and installing dependencies..."
python -m venv "$COMPANION_DIR/.venv"
"$COMPANION_DIR/.venv/bin/pip" install -r "$COMPANION_DIR/requirements.txt"

echo "[3/4] Installing systemd user service..."
mkdir -p "$SERVICE_DIR"
cp deck-companion.service "$SERVICE_DIR/"
systemctl --user daemon-reload

echo "[4/4] Enabling and starting service..."
systemctl --user enable --now deck-companion.service

echo
echo "Done. Companion running at http://localhost:8001"
echo "Test with: curl http://localhost:8001/installed"
