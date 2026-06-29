// SteamLibrary.qml
// Singleton model that owns all library state.
// Installed detection is done CLIENT-SIDE by checking local ACF files
// via Qt's FileInfo — Steam never has to be running.

pragma Singleton
import QtQuick 2.15

ListModel {
    id: root

    // 0 = Installed only, 1 = All Owned
    property int  filterMode: 0
    property bool loading:    false

    // Full owned list from server (no installed field)
    property var  _owned: []

    // Default Steam steamapps path on Arch
    readonly property string steamAppsPath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation)
        + "/.local/share/Steam/steamapps/"

    // ---------------------------------------------------------------------------
    // Public API
    // ---------------------------------------------------------------------------

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
    // Private: rebuild the visible list based on filterMode
    // ---------------------------------------------------------------------------
    function _isInstalled(appId) {
        // Check for appmanifest_{appId}.acf on local disk.
        // Qt.resolvedUrl turns the file:// path into something FileInfo can use.
        var path = steamAppsPath + "appmanifest_" + appId + ".acf"
        // Use XMLHttpRequest HEAD trick — FileInfo is not available in plain QML
        // without a C++ plugin, so we use a synchronous XHR to file://
        var xhr = new XMLHttpRequest()
        xhr.open("HEAD", "file://" + path, false)   // false = synchronous
        try { xhr.send() } catch(e) { return false }
        return xhr.status === 200
    }

    function _rebuild() {
        loading = true
        root.clear()

        if (filterMode === 0) {
            // Installed only — scan ACF files directly, no server needed
            _scanInstalledLocal()
        } else {
            // All owned — use server list, annotate with local installed state
            for (var i = 0; i < _owned.length; i++) {
                var g = _owned[i]
                root.append({
                    appId:      g.appId,
                    name:       g.name,
                    coverUrl:   g.coverUrl,
                    installed:  _isInstalled(g.appId),
                    lastPlayed: g.playtimeForever ? String(g.playtimeForever) : "0"
                })
            }
        }

        loading = false
    }

    function _scanInstalledLocal() {
        // Ask the local companion service for installed IDs.
        // The companion is a tiny localhost:8001 server that runs on the Arch
        // machine and reads ~/.local/share/Steam/steamapps/appmanifest_*.acf
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "http://localhost:8001/installed", true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                for (var i = 0; i < data.games.length; i++) {
                    var g = data.games[i]
                    root.append({
                        appId:      g.appId,
                        name:       g.name,
                        coverUrl:   g.coverUrl,
                        installed:  true,
                        lastPlayed: g.lastPlayed || "0"
                    })
                }
            }
            loading = false
        }
        xhr.send()
    }

    onFilterModeChanged: _rebuild()
}
