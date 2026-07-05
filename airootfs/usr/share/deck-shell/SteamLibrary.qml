pragma Singleton
import QtQuick 2.15

ListModel {
    id: root

    property int  filterMode: 0
    property bool loading:    false
    property var  _owned: []
    property var  _local: []

    property string _homePathCache: ""
    function setHomePath(p) {
        console.log("[SteamLibrary] setHomePath called with:", p)
        _homePathCache = p
    }

    function _homePath() {
        if (_homePathCache !== "") {
            console.log("[SteamLibrary] _homePath using cache:", _homePathCache)
            return _homePathCache
        }
        var guessed = "/home/" + _guessUser()
        console.log("[SteamLibrary] _homePath guessed (no cache):", guessed)
        return guessed
    }

    function _guessUser() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///proc/self/environ", false)
        try {
            xhr.send()
            var env = xhr.responseText
            var idx = env.indexOf("HOME=")
            if (idx >= 0) {
                var rest = env.substring(idx + 5)
                var end  = rest.indexOf("\x00")
                var home = end > 0 ? rest.substring(0, end) : rest
                console.log("[SteamLibrary] _guessUser parsed HOME from environ:", home)
                return home.substring(home.lastIndexOf("/") + 1)
            }
        } catch(e) {
            console.log("[SteamLibrary] _guessUser XHR error:", e)
        }
        console.log("[SteamLibrary] _guessUser falling back to 'user'")
        return "user"
    }

    function _isInstalled(appId) {
        var base = _homePath()
        var paths = [
            "file://" + base + "/.local/share/Steam/steamapps/appmanifest_" + appId + ".acf",
            "file://" + base + "/.steam/steam/steamapps/appmanifest_" + appId + ".acf"
        ]
        for (var i = 0; i < paths.length; i++) {
            console.log("[SteamLibrary] _isInstalled checking:", paths[i])
            var xhr = new XMLHttpRequest()
            xhr.open("GET", paths[i], false)
            try { xhr.send() } catch(e) {
                console.log("[SteamLibrary] _isInstalled XHR exception for", paths[i], ":", e)
                continue
            }
            console.log("[SteamLibrary] _isInstalled", paths[i],
                        "-> status:", xhr.status,
                        "responseText length:", xhr.responseText.length)
            if (xhr.status === 0 && xhr.responseText.length > 0) {
                console.log("[SteamLibrary] _isInstalled FOUND:", appId)
                return true
            }
        }
        console.log("[SteamLibrary] _isInstalled NOT FOUND:", appId)
        return false
    }

    function setLocalGames(games) {
        console.log("[SteamLibrary] setLocalGames called, count:", games.length)
        for (var i = 0; i < games.length; i++)
            console.log("[SteamLibrary]   local game[", i, "]:", games[i].appId, games[i].name, "installed:", games[i].installed)
        _local = games
        if (_owned.length === 0) {
            console.log("[SteamLibrary] no owned list, rebuilding from local")
            _rebuild()
        }
    }

    function loadOwnedGames(games) {
        console.log("[SteamLibrary] loadOwnedGames called, count:", games.length)
        _owned = games
        _rebuild()
    }

    function refresh() {
        console.log("[SteamLibrary] refresh() called")
        _rebuild()
    }

    function launchGame(appId) {
        Qt.openUrlExternally("steam://run/" + appId)
    }

    // POST to backend /library/install so steamcmd handles it silently
    // without triggering the Steam client confirmation popup.
    function installGame(appId, name) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "https://api.accesshomeserver.uk/library/install", true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                console.log("[SteamLibrary] installGame response:", xhr.status, xhr.responseText)
            }
        }
        xhr.send(JSON.stringify({ appId: appId }))
        console.log("[SteamLibrary] installGame triggered for appId:", appId)
    }

    function _rebuild() {
        var source = _owned.length > 0 ? _owned : _local
        console.log("[SteamLibrary] _rebuild() filterMode:", filterMode,
                    "_owned.length:", _owned.length,
                    "_local.length:", _local.length,
                    "source.length:", source.length)

        loading = true
        root.clear()

        var appended = 0
        for (var i = 0; i < source.length; i++) {
            var g = source[i]
            var inst = (source === _local)
                ? (g.installed === true)
                : _isInstalled(g.appId)

            console.log("[SteamLibrary] game[", i, "]", g.appId, g.name,
                        "inst:", inst, "filterMode:", filterMode)

            if (filterMode === 0 && !inst) {
                console.log("[SteamLibrary]   SKIPPED (not installed, InstalledOnly mode)")
                continue
            }

            var entry = {
                appId:      g.appId      || "",
                name:       g.name       || "",
                coverUrl:   g.coverUrl   || ("https://cdn.steamstatic.com/steam/apps/" + g.appId + "/library_600x900.jpg"),
                installed:  inst,
                lastPlayed: g.playtimeForever ? String(g.playtimeForever) : (g.lastPlayed || "0")
            }
            console.log("[SteamLibrary]   APPENDING:", JSON.stringify(entry))
            root.append(entry)
            appended++
        }

        loading = false
        console.log("[SteamLibrary] _rebuild() done. appended:", appended, "model.count:", root.count)
    }

    onFilterModeChanged: {
        console.log("[SteamLibrary] filterMode changed to:", filterMode)
        _rebuild()
    }
}
