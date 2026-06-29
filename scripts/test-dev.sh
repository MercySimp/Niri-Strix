#!/usr/bin/env bash
# test-dev.sh
# Run the Deck Shell QML app inside your existing Niri/Wayland session for testing.
# No gamescope, no TTY switching, no autologin needed.
#
# Usage:
#   chmod +x scripts/test-dev.sh
#   ./scripts/test-dev.sh

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_DIR/airootfs/usr/share/deck-shell"

echo "[1/3] Checking dependencies..."
for pkg in qt6-base qt6-declarative qt6-webengine; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        echo "  Missing: $pkg - installing..."
        sudo pacman -S --needed --noconfirm "$pkg"
    else
        echo "  OK: $pkg"
    fi
done

# Find qml6 binary
QML_BIN=""
for p in /usr/lib/qt6/bin/qml /usr/bin/qml6 /usr/bin/qml; do
    if [ -x "$p" ]; then
        QML_BIN="$p"
        break
    fi
done

if [ -z "$QML_BIN" ]; then
    QML_BIN=$(command -v qml6 2>/dev/null || command -v qml 2>/dev/null || true)
fi

if [ -z "$QML_BIN" ]; then
    echo "ERROR: qml6 binary not found. Install qt6-declarative."
    exit 1
fi

echo "  Using QML binary: $QML_BIN"

echo "[2/3] Copying shell files to /usr/share/deck-shell..."
sudo mkdir -p /usr/share/deck-shell
sudo cp -r "$SHELL_DIR/"* /usr/share/deck-shell/
echo "  Done."

echo "[3/3] Launching Deck Shell (windowed 1280x800 for dev testing)..."
echo "  Press Ctrl+C or use the Power menu to exit."
echo ""

exec "$QML_BIN" -geometry 1280x800 /usr/share/deck-shell/main.qml
