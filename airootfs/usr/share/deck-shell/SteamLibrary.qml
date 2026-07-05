// SteamLibrary.qml — Singleton ListModel for the game library.
// Installed detection uses synchronous XHR HEAD on file:// URLs (Qt 5.15 safe).
// Does NOT require a signed-in account to show installed games.

pragma Singleton
import QtQuick 2.15

ListModel {
    id: root

    // 0 = Installed only, 1 = All Owned
    property int  filterMode: 0        // Default: show installed games immediately
    property bool loading:    false

    // Games from the remote backend (populated after sign-in)
    property var _owned: []

    // Games scanned locally from ACF files (populated at startup via C++ model)
    property var _local: []

    // ---------------------------------------------------------------------------
    // Called by main.qml Connections on SteamLibraryCtrl when the C++ model
    // finishes its local ACF scan (on startup, before any sign-in).
    // 'games' is an array of {appId, name, coverUrl, installed:true}
    // ---------------------------------------------------------------------------
    function setLocalGames(games) {
        _local = games
        // If we have no owned list yet, use local as the seed so
        // InstalledOnly mode has something to display immediately.
        if (_owned.length === 0)
            _rebuild()
    }

    // Called by main.qml after the backend returns the full owned list.
    function loadOwnedGames(games) {
        _owned = games
        _rebuild()
    }

    function refresh() {
        _rebuild()
    }

    function launchGame(appId) {
        Qt.openUrlExternally("steam://run/" + appId)
    }

    function installGame(appId) {
        Qt.openUrlExternally("steam://install/" + appId)
    }

    // ---------------------------------------------------------------------------
    // Check if a game's ACF manifest exists using a synchronous file:// XHR.
    // Qt's file:// handler returns status 0 for success, never 200.
    // Returns true if the file exists on disk.
    // ---------------------------------------------------------------------------
    function _isInstalled(appId) {
        // Try the two most common Steam library paths.
        var paths = [
            "file://" + _homePath() + "/.local/share/Steam/steamapps/appmanifest_" + appId + ".acf",
            "file://" + _homePath() + "/.steam/steam/steamapps/appmanifest_" + appId + ".acf"
        ]
        for (var i = 0; i < paths.length; i++) {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", paths[i], false)   // synchronous
            try { xhr.send() } catch(e) { continue }
            // Qt file:// XHR: status 0 + responseText non-empty = file exists.
            // status 0 + empty = file not found.
            if (xhr.status === 0 && xhr.responseText.length > 0)
                return true
        }
        return false
    }

    // ---------------------------------------------------------------------------
    // Get the home directory path. Qt.resolvedUrl("~/") doesn't expand ~,
    // so we extract it from a known StandardPaths equivalent by reading
    // the HOME env var via the same XHR trick.
    // Simpler: the C++ model sets _homePathCache via setHomePath().
    // ---------------------------------------------------------------------------
    property string _homePathCache: ""
    function setHomePath(p) { _homePathCache = p }
    function _homePath() {
        if (_homePathCache !== "") return _homePathCache
        // Fallback: Qt.resolvedUrl("/") gives us file:///; home is /root or /home/user.
        // We can't know without C++ help, so return the most common Arch path.
        return "/home/" + _guessUser()
    }
    function _guessUser() {
        // Read /proc/self/status to get the UID, then /etc/passwd.
        // Simpler fallback: read $HOME from /proc/self/environ.
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///proc/self/environ", false)
        try {
            xhr.send()
            var env = xhr.responseText
            var idx = env.indexOf("HOME=")
            if (idx >= 0) {
                var rest = env.substring(idx + 5)
                var end  = rest.indexOf("\x00")
                return end > 0 ? rest.substring(rest.lastIndexOf("/") + 1, end) : "user"
            }
        } catch(e) {}
        return "user"
    }

    // ---------------------------------------------------------------------------
    // Rebuild the visible list based on filterMode and available data.
    // ---------------------------------------------------------------------------
    function _rebuild() {
        loading = true
        root.clear()

        // Decide which source list to use.
        // If we have an owned list from the backend, use it (it's complete).
        // If not, fall back to the local ACF scan from C++.
        var source = _owned.length > 0 ? _owned : _local

        for (var i = 0; i < source.length; i++) {
            var g = source[i]

            // For local games, installed is already true.
            // For owned games, check the ACF file.
            var inst = (source === _local)
                ? (g.installed === true)
                : _isInstalled(g.appId)

            if (filterMode === 0 && !inst)
                continue   // InstalledOnly: skip uninstalled

            root.append({
                appId:      g.appId      || "",
                name:       g.name       || "",
                coverUrl:   g.coverUrl   || ("https://cdn.steamstatic.com/steam/apps/" + g.appId + "/library_600x900.jpg"),
                installed:  inst,
                lastPlayed: g.playtimeForever ? String(g.playtimeForever) : (g.lastPlayed || "0")
            })
        }

        loading = false
    }

    onFilterModeChanged: _rebuild()
}
