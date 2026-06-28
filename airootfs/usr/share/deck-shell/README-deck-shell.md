# QML Deck Shell

This is a minimal Qt Quick/QML shell that mimics the core structure of Steam Big Picture / Steam Deck UI:

- Full-screen, controller-first interface
- Home screen with large tiles for **Library**, **Store**, **Downloads**, **Settings**, and **Power**
- Game grid with cover art and details view
- Basic controller navigation using Qt Gamepad

The actual implementation lives under `airootfs/usr/share/deck-shell` and is built into a `deck-shell` executable
that runs under Gamescope.
