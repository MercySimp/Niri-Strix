#!/usr/bin/env bash
# steam-install-confirm.sh
# Watches for Steam's install confirmation dialog and auto-clicks "Install".
# Runs as a background service alongside deck-shell (see steam-install-confirm.service).
# Requires: xdotool

set -euo pipefail

# How often to poll for the dialog (milliseconds)
POLL_MS=200

log() { echo "[steam-install-confirm] $*" >&2; }

log "Starting. Polling every ${POLL_MS}ms for Steam install dialog..."

while true; do
    sleep "$(echo "scale=3; $POLL_MS/1000" | bc)"

    # Find a window owned by the steam process whose title is exactly "Install"
    # xdotool search returns exit code 1 if nothing found, so we swallow that.
    WID=$(xdotool search --sync --limit 1 --name '^Install$' 2>/dev/null || true)
    [[ -z "$WID" ]] && continue

    # Double-check the window belongs to a steam process
    PID=$(xdotool getwindowpid "$WID" 2>/dev/null || true)
    if [[ -z "$PID" ]]; then continue; fi
    PROC=$(cat /proc/"$PID"/comm 2>/dev/null || true)
    if [[ "$PROC" != *steam* ]]; then continue; fi

    log "Detected Steam install dialog (wid=$WID pid=$PID). Auto-confirming..."

    # Bring window to focus so xdotool key events land correctly
    xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 0.1

    # Tab to the Install button (it's the default focused button) and press Return.
    # Using key Return directly hits the focused "Install" button.
    xdotool key --window "$WID" Return 2>/dev/null || true

    log "Sent Return to install dialog (wid=$WID). Download should start."

    # Brief pause to avoid re-triggering on the same window before it closes
    sleep 1
done
