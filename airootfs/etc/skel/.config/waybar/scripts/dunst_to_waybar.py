#!/usr/bin/env python3

import json
import subprocess

MAX_NOTIFICATIONS = 10  # Lines in the tooltip

def run_dunstctl_cmd(cmd):
    try:
        result = subprocess.run(
            ["dunstctl"] + cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            text=True
        )
        return result.stdout.strip()
    except Exception:
        return ""

def get_dunst_history():
    try:
        result = run_dunstctl_cmd(["history"])
        return json.loads(result)
    except Exception:
        return {"data": [[]]}

def get_notification_count():
    return run_dunstctl_cmd(["count", "history"])

def is_dunst_paused():
    return run_dunstctl_cmd(["is-paused"]) == "true"

def get_icon(paused):
    return "" if paused else ""  # Font Awesome icons (pause / bell)

def extract_bodies(history_json, limit=MAX_NOTIFICATIONS):
    try:
        notifications = history_json["data"][0]
        bodies = []
        for notification in reversed(notifications):
            body = notification.get("message", {}).get("data", "")
            if body:
                bodies.append(body.strip())
            if len(bodies) >= limit:
                break
        return bodies
    except Exception:
        return []

def main():
    paused = is_dunst_paused()
    icon = get_icon(paused)
    count = get_notification_count()
    history = get_dunst_history()
    bodies = extract_bodies(history)

    tooltip = "\n".join(bodies) if bodies else "No notifications"
    output = {
        "text": f"{icon} {count}",
        "tooltip": tooltip
    }

    print(json.dumps(output))

if __name__ == "__main__":
    main()
