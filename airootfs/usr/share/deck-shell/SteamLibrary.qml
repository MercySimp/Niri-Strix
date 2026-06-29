// SteamLibrary.qml
// Singleton model that owns all library state.
// Installed detection reads ~/.local/share/Steam/steamapps/appmanifest_{appId}.acf
// directly from disk using Qt's FileInfo — no companion service, no network call.

pragma Singleton
import QtQuick 2.15
import Qt.labs.platform 1.1

ListModel {
    id: root

    // 0 = Installed only, 1 = All Owned
    property int  filterMode: 0
    property bool loading:    false

    // Full owned list returned by the remote server
    property var _owned: []

    // Path to Steam's steamapps directory on the local Arch machine
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
    // Check if a game is installed by looking for its appmanifest ACF file.
    // FileInfo.exists() does a plain stat() call — instant, no network, no service.
    // ---------------------------------------------------------------------------
    function _isInstalled(appId) {
        return FileInfo.exists(steamAppsPath + "appmanifest_" + appId + ".acf")
    }

    // ---------------------------------------------------------------------------
    // Rebuild the visible list based on filterMode
    // ---------------------------------------------------------------------------
    function _rebuild() {
        loading = true
        root.clear()

        if (filterMode === 0) {
            // Installed only — walk the server's owned list and filter locally.
            // If owned list is empty (not signed in), show nothing here;
            // user sees the empty-state prompt to sign in.
            for (var i = 0; i < _owned.length; i++) {
                var g = _owned[i]
                if (_isInstalled(g.appId)) {
                    root.append({
                        appId:      g.appId,
                        name:       g.name,
                        coverUrl:   g.coverUrl,
                        installed:  true,
                        lastPlayed: g.playtimeForever ? String(g.playtimeForever) : "0"
                    })
                }
            }
        } else {
            // All Owned — annotate each game with local installed state
            for (var j = 0; j < _owned.length; j++) {
                var og = _owned[j]
                root.append({
                    appId:      og.appId,
                    name:       og.name,
                    coverUrl:   og.coverUrl,
                    installed:  _isInstalled(og.appId),
                    lastPlayed: og.playtimeForever ? String(og.playtimeForever) : "0"
                })
            }
        }

        loading = false
    }

    onFilterModeChanged: _rebuild()
}
