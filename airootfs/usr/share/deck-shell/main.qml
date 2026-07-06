import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtWebEngine 1.10

ApplicationWindow {
    id: root
    visible: true
    width: 1920
    height: 1080
    color: "#14161a"
    title: "Deck Shell"
    flags: Qt.Window

    readonly property string backendUrl: "https://api.accesshomeserver.uk"

    // Paths are injected from C++ via QStandardPaths (main.cpp) as context
    // properties: webDataPath and webCachePath.  This avoids hardcoding any
    // username AND avoids the unreliable QtCore 6.0 StandardPaths QML singleton.
    // The C++ side also calls QDir().mkpath() on both before the engine loads,
    // so the directories always exist before Chromium's renderer subprocess starts.

    property bool   steamLinked:   false
    property string steamPersona:  ""
    property string steamAvatar:   ""
    property string steamId:       ""
    property string lastFetchedId: ""

    // ── Shared persistent profile ───────────────────────────────────────────────
    // storageName is set last in Component.onCompleted — this is the trigger
    // that switches the profile from off-the-record to disk-based mode.
    // Setting persistentStoragePath and cachePath first prevents the
    // FILE_ERROR_ACCESS_DENIED / "Storage name is empty" cascade.
    WebEngineProfile {
        id: deckProfile
        offTheRecord: false
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        httpCacheType: WebEngineProfile.DiskHttpCache

        Component.onCompleted: {
            persistentStoragePath = webDataPath
            cachePath             = webCachePath
            storageName           = "DeckShell"

            console.log("deckProfile storageName:", storageName)
            console.log("deckProfile persistentStoragePath:", persistentStoragePath)
            console.log("deckProfile cachePath:", cachePath)
            console.log("deckProfile note: exact cookie jar inspection is not available from pure QML; auth persistence is inferred from /auth/status")
        }
    }

    // ── Hidden status-check view ────────────────────────────────────────────────
    WebEngineView {
        id: statusView
        profile: deckProfile
        visible: false
        width: 1; height: 1

        property bool _pending: false

        function check() {
            if (_pending) return
            _pending = true
            console.log("statusView requesting:", root.backendUrl + "/auth/status")
            console.log("statusView checking persisted session using profile path:", webDataPath)
            url = root.backendUrl + "/auth/status"
        }

        onLoadingChanged: function(info) {
            console.log("statusView load status:", info.status, "url:", url.toString())

            if (url.toString() === "about:blank")
                return

            if (info.status !== WebEngineView.LoadSucceededStatus) {
                console.warn("statusView load failed or not successful:", info.status, "url:", url.toString())
                _pending = false
                url = "about:blank"
                return
            }

            runJavaScript("document.body.innerText", function(text) {
                _pending = false
                url = "about:blank"

                var trimmed = (text || "").trim()

                console.log("statusView raw /auth/status reply:", trimmed)

                try {
                    var data = JSON.parse(trimmed)

                    console.log("statusView parsed /auth/status linked:", data.linked)
                    console.log("statusView parsed /auth/status steamId:", data.steamId || "")
                    console.log("statusView parsed /auth/status persona:", data.persona || "")

                    if (data.linked) {
                        console.log("statusView result: server accepted a previously stored session cookie")
                        root.steamLinked  = data.linked
                        root.steamPersona = data.persona || ""
                        root.steamAvatar  = data.avatar || ""
                        root.steamId      = data.steamId || ""
                        root.fetchIfNeeded(root.steamId)
                    } else {
                        console.warn("statusView result: server did not see a valid previous session cookie")
                    }
                } catch (e) {
                    console.warn("statusView parse error:", e)
                    console.warn("statusView raw response head:", trimmed.substring(0, 500))
                }
            })
        }
    }

    function fetchIfNeeded(sid) {
        if (sid === "" || sid === lastFetchedId) return
        lastFetchedId = sid
        SteamLibraryCtrl.filterMode = 1
        SteamLibraryCtrl.fetchOwnedGamesForId(sid)
    }

    function getParam(url, key) {
        var idx = url.indexOf("?")
        if (idx < 0) return ""
        var pairs = url.substring(idx + 1).split("&")
        for (var i = 0; i < pairs.length; i++) {
            var kv = pairs[i].split("=")
            if (decodeURIComponent(kv[0]) === key)
                return kv.length > 1 ? decodeURIComponent(kv[1].replace(/\+/g, " ")) : ""
        }
        return ""
    }

    function handleLoginDone(urlStr) {
        var persona = getParam(urlStr, "persona")
        var avatar  = getParam(urlStr, "avatar")
        var sid     = getParam(urlStr, "steamid")
        if (persona !== "") {
            steamLinked  = true
            steamPersona = persona
            steamAvatar  = avatar
            steamId      = sid
            fetchIfNeeded(sid)
        } else {
            statusView.check()
        }
    }

    function doLogout() {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", backendUrl + "/auth/logout", true)
        xhr.withCredentials = true
        xhr.send()
        steamLinked   = false
        steamPersona  = ""
        steamAvatar   = ""
        steamId       = ""
        lastFetchedId = ""
        SteamLibraryCtrl.filterMode = 0
        SteamLibraryCtrl.refresh()
    }

    function formatSize(bytes) {
        if (!bytes || bytes === 0) return ""
        if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + " MB"
        return (bytes / 1073741824).toFixed(2) + " GB"
    }

    function formatUnixDate(tsStr) {
        var ts = parseInt(tsStr, 10)
        if (!ts || ts === 0) return ""
        var d = new Date(ts * 1000)
        if (isNaN(d.getTime())) return ""
        return d.toLocaleDateString(Qt.locale(), "MMM d, yyyy")
    }

    function formatPlaytime(mins) {
        if (!mins || mins === 0) return ""
        if (mins < 60) return mins + " mins"
        var h = Math.floor(mins / 60)
        var m = mins % 60
        return m > 0 ? (h + " hrs " + m + " mins") : (h + " hrs")
    }

    function fetchNews(appId, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET",
            "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=" + appId + "&count=5&maxlength=0",
            true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return
            var items = []
            if (xhr.status === 200) {
                try {
                    var json = JSON.parse(xhr.responseText)
                    var newsitems = json.appnews && json.appnews.newsitems ? json.appnews.newsitems : []
                    for (var i = 0; i < newsitems.length && i < 5; i++) {
                        var n = newsitems[i]
                        var d = new Date(n.date * 1000)
                        items.push({
                            title: n.title || "Untitled",
                            date:  isNaN(d.getTime()) ? "" : d.toLocaleDateString(Qt.locale(), "MMM d, yyyy"),
                            url:   n.url  || ""
                        })
                    }
                } catch(e) { console.warn("fetchNews parse error:", e) }
            }
            callback(items)
        }
        xhr.send()
    }

    Component.onCompleted: {
        statusView.check()
        SteamLibraryCtrl.refresh()
    }

    // ── Install toast ────────────────────────────────────────────────────────────
    Rectangle {
        id: installToast
        z: 100
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height
        width: 520; height: 64; radius: 16
        color: "#1a3a1a"; border.color: "#4caf50"; border.width: 2
        opacity: 0

        property string gameName: ""

        Text {
            anchors.centerIn: parent
            text: "\u2B07  Installing \u2018" + installToast.gameName + "\u2019\u2026"
            color: "#4caf50"; font.pixelSize: 20; font.bold: true
        }

        function show(name) {
            gameName = name
            showAnim.restart()
        }

        SequentialAnimation {
            id: showAnim
            NumberAnimation { target: installToast; property: "y";       to: root.height - 100; duration: 280; easing.type: Easing.OutCubic }
            NumberAnimation { target: installToast; property: "opacity"; to: 1;                 duration: 120 }
            PauseAnimation  { duration: 3000 }
            NumberAnimation { target: installToast; property: "opacity"; to: 0;                 duration: 200 }
            NumberAnimation { target: installToast; property: "y";       to: root.height;       duration: 1 }
        }
    }

    Connections {
        target: SteamLibraryCtrl
        ignoreUnknownSignals: true
        function onInstallRequested(appId, name) {
            installToast.show(name || ("App " + appId))
        }
    }

    Connections {
        target: Gamepad
        ignoreUnknownSignals: true
        function onButtonA()  { stack.currentItem.activate() }
        function onButtonB()  { stack.pop() }
        function onButtonX()  { stack.currentItem.openDetails() }
        function onButtonY()  { stack.currentItem.openSettings() }
        function onLb()       { SteamLibraryCtrl.filterMode = 0 }
        function onRb()       { SteamLibraryCtrl.filterMode = 1 }
    }

    Item {
        anchors.fill: parent; focus: true
        Keys.onReturnPressed: stack.currentItem.activate()
        Keys.onEscapePressed: stack.pop()
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: homePage
    }

    // ── In-app article viewer popup ──────────────────────────────────────────────
    Rectangle {
        id: articlePopup
        z: 200
        anchors.fill: parent
        color: "#CC000000"
        visible: false

        property string articleUrl: ""

        function openUrl(url) {
            articleUrl = url
            articleWebView.url = url
            visible = true
            closePopupBtn.forceActiveFocus()
        }

        function close() {
            visible = false
            articleWebView.url = "about:blank"
            articleUrl = ""
        }

        MouseArea {
            anchors.fill: parent
            onClicked: articlePopup.close()
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.88
            height: parent.height * 0.88
            color: "#14161a"
            radius: 16
            border.color: "#2a3a55"
            border.width: 2
            clip: true

            MouseArea { anchors.fill: parent }

            Rectangle {
                id: popupTitleBar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 52
                color: "#181e2a"
                radius: 16

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 16
                    color: parent.color
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    text: articlePopup.articleUrl
                    color: "#8a9bb5"
                    font.pixelSize: 14
                    elide: Text.ElideRight
                    width: parent.width - 80
                }

                Rectangle {
                    id: closePopupBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 12
                    width: 36; height: 36; radius: 8
                    color: activeFocus ? "#c0392b" : "#2a1010"
                    border.color: activeFocus ? "#e74c3c" : "#552020"
                    activeFocusOnTab: true
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: "\u2715"
                        color: "#e74c3c"
                        font.pixelSize: 18; font.bold: true
                    }
                    Keys.onReturnPressed: articlePopup.close()
                    MouseArea { anchors.fill: parent; onClicked: articlePopup.close() }
                }
            }

            WebEngineView {
                id: articleWebView
                profile: deckProfile
                anchors.top: popupTitleBar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                url: "about:blank"
            }
        }

        Keys.onEscapePressed: articlePopup.close()
    }

    // ══ HOME ═══════════════════════════════════════════════════════════════════════
    Component {
        id: homePage
        FocusScope {
            width: parent ? parent.width : root.width; height: parent ? parent.height : root.height; focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 60; spacing: 48
                RowLayout {
                    spacing: 20
                    Text { text: "\u2665  Deck Mode"; color: "#e8e8e8"; font.pixelSize: 52; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Row {
                        spacing: 12; visible: root.steamLinked
                        Image { source: root.steamAvatar; width: 40; height: 40; fillMode: Image.PreserveAspectCrop }
                        Text { text: root.steamPersona; color: "#8a9bb5"; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                RowLayout {
                    spacing: 28; Layout.fillWidth: true
                    Repeater {
                        id: homeNavRepeater
                        model: [
                            { label: "Library",  icon: "\uD83C\uDFAE" },
                            { label: "Store",     icon: "\uD83D\uDED2" },
                            { label: "Downloads", icon: "\u2B07" },
                            { label: "Settings",  icon: "\u2699" },
                            { label: "Power",     icon: "\u23FB" }
                        ]
                        delegate: Rectangle {
                            id: navTile
                            Layout.preferredWidth: 240; Layout.preferredHeight: 150
                            color: activeFocus ? "#2a7bd9" : "#1f2531"; radius: 14
                            border.color: activeFocus ? "#5ba3ff" : "#2e3540"; border.width: activeFocus ? 3 : 1
                            focus: index === 0; activeFocusOnTab: true
                            KeyNavigation.right: homeNavRepeater.itemAt(index + 1)
                            KeyNavigation.left:  homeNavRepeater.itemAt(index - 1)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Column {
                                anchors.centerIn: parent; spacing: 10
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; font.pixelSize: 36 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: "white"; font.pixelSize: 22; font.bold: activeFocus }
                            }
                            Keys.onReturnPressed: doNav()
                            MouseArea { anchors.fill: parent; onClicked: { navTile.forceActiveFocus(); navTile.doNav() } }
                            function doNav() {
                                if      (modelData.label === "Library")  stack.push(libraryPage)
                                else if (modelData.label === "Store")    stack.push(storePage)
                                else if (modelData.label === "Settings") stack.push(settingsPage)
                                else if (modelData.label === "Power")    stack.push(powerPage)
                            }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 16
                    Text { text: "Recently Played"; color: "#8a9bb5"; font.pixelSize: 24; font.bold: true }
                    ListView {
                        Layout.fillWidth: true; height: 200; orientation: ListView.Horizontal; spacing: 20; clip: true
                        model: SteamLibraryCtrl
                        delegate: Rectangle {
                            property var _lp: lastPlayed
                            visible: (_lp || "") !== "" && _lp !== "0"
                            width: visible ? 160 : 0; height: 190
                            color: "#1a2030"; radius: 10; clip: true
                            Image { anchors.fill: parent; source: coverUrl || ""; fillMode: Image.PreserveAspectCrop }
                            MouseArea { anchors.fill: parent; onClicked: SteamLibraryCtrl.launchGame(appId) }
                        }
                    }
                }
            }
            function activate()     { var item = root.activeFocusItem; if (item && item.doNav) item.doNav() }
            function openDetails()  {}
            function openSettings() { stack.push(settingsPage) }
        }
    }

    // ══ LIBRARY ════════════════════════════════════════════════════════════════════
    Component {
        id: libraryPage
        FocusScope {
            id: libScope
            width: parent ? parent.width : root.width; height: parent ? parent.height : root.height; focus: true

            Component.onCompleted: root.fetchIfNeeded(root.steamId)

            Rectangle { anchors.fill: parent; color: "#14161a" }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 48; spacing: 20

                RowLayout {
                    spacing: 20; Layout.fillWidth: true
                    Rectangle {
                        width: 48; height: 48; radius: 10
                        color: activeFocus ? "#2a7bd9" : "transparent"
                        border.color: activeFocus ? "#5ba3ff" : "transparent"; activeFocusOnTab: true
                        Text { anchors.centerIn: parent; text: "\u25C4"; color: "#5ba3ff"; font.pixelSize: 28 }
                        Keys.onReturnPressed: stack.pop()
                        MouseArea { anchors.fill: parent; onClicked: stack.pop() }
                    }
                    Text { text: "Library"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: SteamLibraryCtrl.count + " games"
                        color: "#8a9bb5"; font.pixelSize: 22; Layout.alignment: Qt.AlignVCenter
                    }
                    Rectangle {
                        id: refreshBtn
                        width: 120; height: 44
                        color: activeFocus ? "#2a7bd9" : "#1f2531"; radius: 10
                        border.color: activeFocus ? "#5ba3ff" : "#2e3540"; activeFocusOnTab: true
                        Text { anchors.centerIn: parent; text: "\u21BA  Refresh"; color: "#8a9bb5"; font.pixelSize: 18 }
                        Keys.onReturnPressed: refreshBtn.doRefresh()
                        MouseArea { anchors.fill: parent; onClicked: parent.doRefresh() }
                        function doRefresh() {
                            root.lastFetchedId = ""
                            if (root.steamId !== "") root.fetchIfNeeded(root.steamId)
                            else SteamLibraryCtrl.refresh()
                        }
                    }
                }

                RowLayout {
                    spacing: 8; Layout.fillWidth: true
                    Repeater {
                        id: filterTabRepeater
                        model: ["Installed", "All Owned"]
                        delegate: Rectangle {
                            id: filterTab
                            property bool active: (index === SteamLibraryCtrl.filterMode)
                            Layout.preferredWidth: 200; height: 48
                            color: active ? "#2a7bd9" : (activeFocus ? "#263550" : "#1f2531"); radius: 10
                            border.color: (active || activeFocus) ? "#5ba3ff" : "#2e3540"
                            activeFocusOnTab: index === 0; focus: index === 0
                            KeyNavigation.right: filterTabRepeater.itemAt(index + 1)
                            KeyNavigation.left:  filterTabRepeater.itemAt(index - 1)
                            KeyNavigation.down:  gameGrid
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                anchors.centerIn: parent; spacing: 8
                                Text { text: index === 0 ? "LB" : "RB"; color: active ? "white" : "#555e6e"; font.pixelSize: 14; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: modelData; color: active ? "white" : "#8a9bb5"; font.pixelSize: 20; font.bold: active; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Keys.onReturnPressed: SteamLibraryCtrl.filterMode = index
                            MouseArea { anchors.fill: parent; onClicked: { filterTab.forceActiveFocus(); SteamLibraryCtrl.filterMode = index } }
                        }
                    }
                    Text {
                        visible: SteamLibraryCtrl.filterMode === 1 && !root.steamLinked
                        text: "\u26A0  Sign in with Steam in Settings to see your full library"
                        color: "#da7101"; font.pixelSize: 18; Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                }

                Text {
                    visible: SteamLibraryCtrl.loading
                    text: "Fetching Steam library\u2026"
                    color: "#8a9bb5"; font.pixelSize: 24; Layout.alignment: Qt.AlignHCenter
                }

                GridView {
                    id: gameGrid
                    visible: !SteamLibraryCtrl.loading && SteamLibraryCtrl.count > 0
                    Layout.fillWidth: true; Layout.fillHeight: true
                    cellWidth: 200; cellHeight: 300
                    focus: true; activeFocusOnTab: true; clip: true
                    model: SteamLibraryCtrl
                    keyNavigationEnabled: true

                    Keys.onUpPressed:    moveCurrentIndexUp()
                    Keys.onDownPressed:  moveCurrentIndexDown()
                    Keys.onLeftPressed:  moveCurrentIndexLeft()
                    Keys.onRightPressed: moveCurrentIndexRight()

                    delegate: Rectangle {
                        id: gameTile
                        width: 184; height: 284

                        property bool isInstalled: (installed === true)

                        color: GridView.isCurrentItem ? "#1e2e45" : "#1a1e28"; radius: 12
                        border.color: GridView.isCurrentItem ? "#5ba3ff" : "#2e3540"
                        border.width: GridView.isCurrentItem ? 3 : 1
                        clip: true
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Image {
                            id: coverImg
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            height: parent.height * 0.78
                            source: coverUrl || ""
                            fillMode: Image.PreserveAspectCrop; smooth: true; asynchronous: true
                            Rectangle {
                                anchors.fill: parent; color: "#252c38"
                                visible: coverImg.status !== Image.Ready
                                Text { anchors.centerIn: parent; text: "\uD83C\uDFAE"; font.pixelSize: 52 }
                            }
                        }

                        Text {
                            anchors.top: coverImg.bottom; anchors.left: parent.left
                            anchors.right: parent.right; anchors.margins: 8
                            text: name || ""
                            color: gameTile.isInstalled ? "white" : "#b0b8c8"
                            font.pixelSize: 14; font.bold: GridView.isCurrentItem
                            elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            visible: !gameTile.isInstalled
                            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 16; height: 26; radius: 8
                            color: "#0d2a4a"; border.color: "#2a7bd9"
                            Text { anchors.centerIn: parent; text: "\u2B07 Not Installed"; color: "#5ba3ff"; font.pixelSize: 13 }
                        }

                        function openGameDetail() {
                            stack.push(gameDetailPage, {
                                gameAppId:          appId              || "",
                                gameName:           name               || "",
                                gameCover:          coverUrl           || "",
                                gameInstalled:      gameTile.isInstalled,
                                gameSizeOnDisk:     sizeOnDisk         || 0,
                                gameLastPlayed:     lastPlayed         || "",
                                gamePlaytime:       playtimeForever    || 0
                            })
                        }

                        Keys.onReturnPressed: openGameDetail()
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                gameGrid.currentIndex = index
                                gameGrid.forceActiveFocus()
                                gameTile.openGameDetail()
                            }
                        }
                    }
                }

                Column {
                    visible: !SteamLibraryCtrl.loading && SteamLibraryCtrl.count === 0
                    Layout.alignment: Qt.AlignHCenter; spacing: 16
                    Text { text: "\uD83C\uDFAE"; font.pixelSize: 64; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "No games found"; color: "#e8e8e8"; font.pixelSize: 30; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        text: root.steamLinked ? "Make sure the backend has STEAM_API_KEY set."
                                               : "No installed games found, or sign in with Steam in Settings."
                        color: "#555e6e"; font.pixelSize: 20; anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            function activate() {
                if (gameGrid.activeFocus && gameGrid.currentItem)
                    gameGrid.currentItem.openGameDetail()
            }
            function openDetails()  {}
            function openSettings() {}
        }
    }

    // ══ GAME DETAIL PAGE ═══════════════════════════════════════════════════════════
    Component {
        id: gameDetailPage
        FocusScope {
            id: detailScope
            width: parent ? parent.width : root.width
            height: parent ? parent.height : root.height
            focus: true

            property string gameAppId:      ""
            property string gameName:       ""
            property string gameCover:      ""
            property bool   gameInstalled:  false
            property real   gameSizeOnDisk: 0
            property string gameLastPlayed: ""
            property int    gamePlaytime:   0

            property var    newsItems:   []
            property bool   newsLoading: true

            readonly property string heroUrl:
                "https://cdn.akamai.steamstatic.com/steam/apps/" + gameAppId + "/library_hero.jpg"
            readonly property string headerUrl:
                "https://cdn.akamai.steamstatic.com/steam/apps/" + gameAppId + "/header.jpg"

            Component.onCompleted: {
                newsLoading = true
                root.fetchNews(gameAppId, function(items) {
                    newsItems   = items
                    newsLoading = false
                })
            }

            Rectangle { anchors.fill: parent; color: "#14161a" }

            Item {
                id: heroBanner
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 400

                Image {
                    id: heroImg
                    anchors.fill: parent
                    source: detailScope.heroUrl
                    fillMode: Image.PreserveAspectCrop
                    smooth: true; asynchronous: true
                    onStatusChanged: {
                        if (status === Image.Error)
                            source = detailScope.headerUrl
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.55; color: "transparent" }
                        GradientStop { position: 1.0; color: "#14161a" }
                    }
                }
                Rectangle {
                    anchors.fill: parent; color: "#1a2030"
                    visible: heroImg.status !== Image.Ready
                    Text { anchors.centerIn: parent; text: "\uD83C\uDFAE"; font.pixelSize: 96 }
                }

                Rectangle {
                    id: backBtn
                    anchors.top: parent.top; anchors.left: parent.left
                    anchors.margins: 24
                    width: 52; height: 52; radius: 12
                    color: activeFocus ? "#2a7bd9" : "#55000000"
                    border.color: activeFocus ? "#5ba3ff" : "#66ffffff"; border.width: 2
                    focus: true; activeFocusOnTab: true
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "\u25C4"; color: "white"; font.pixelSize: 26 }
                    Keys.onReturnPressed: stack.pop()
                    MouseArea { anchors.fill: parent; onClicked: stack.pop() }
                }

                Row {
                    anchors.top: parent.top; anchors.right: parent.right
                    anchors.margins: 24; spacing: 12
                    Repeater {
                        model: ["\uD83C\uDFAE", "\u2699"]
                        delegate: Rectangle {
                            width: 52; height: 52; radius: 12
                            color: activeFocus ? "#2a7bd9" : "#55000000"
                            border.color: activeFocus ? "#5ba3ff" : "#66ffffff"; border.width: 2
                            activeFocusOnTab: true
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 24; color: "white" }
                        }
                    }
                }
            }

            Rectangle {
                id: actionStrip
                anchors.top: heroBanner.bottom
                anchors.left: parent.left; anchors.right: parent.right
                height: 100
                color: "#181e2a"
                border.color: "#2a3a55"; border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 48; anchors.rightMargin: 48
                    spacing: 32

                    Rectangle {
                        id: primaryBtn
                        width: 260; height: 64; radius: 14
                        activeFocusOnTab: true
                        KeyNavigation.right: uninstallStripBtn.visible ? uninstallStripBtn : null

                        property bool isInstalled: detailScope.gameInstalled
                        color: {
                            if (activeFocus) return isInstalled ? "#22b834" : "#1a6ec2"
                            return isInstalled ? "#1db530" : "#1a5fa8"
                        }
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            anchors.centerIn: parent; spacing: 14
                            Text {
                                text: primaryBtn.isInstalled ? "\u25B6" : "\u2B07"
                                color: "white"; font.pixelSize: 28
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: primaryBtn.isInstalled ? "Play" : "Install"
                                color: "white"; font.pixelSize: 28; font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        function doAction() {
                            if (detailScope.gameInstalled) {
                                SteamLibraryCtrl.launchGame(detailScope.gameAppId)
                            } else {
                                installToast.show(detailScope.gameName)
                                SteamLibraryCtrl.installGame(detailScope.gameAppId)
                            }
                            stack.pop()
                        }
                        Keys.onReturnPressed: doAction()
                        MouseArea { anchors.fill: parent; onClicked: parent.doAction() }
                    }

                    Rectangle {
                        id: uninstallStripBtn
                        visible: detailScope.gameInstalled
                        width: 160; height: 64; radius: 14
                        activeFocusOnTab: true
                        color: activeFocus ? "#4a1010" : "#2a1010"
                        border.color: activeFocus ? "#e74c3c" : "#552020"; border.width: activeFocus ? 2 : 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            anchors.centerIn: parent; spacing: 8
                            Text { text: "\uD83D\uDDD1"; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Uninstall"; color: "#e74c3c"; font.pixelSize: 22; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Keys.onReturnPressed: { SteamLibraryCtrl.uninstallGame(detailScope.gameAppId); stack.pop() }
                        MouseArea { anchors.fill: parent; onClicked: { SteamLibraryCtrl.uninstallGame(detailScope.gameAppId); stack.pop() } }
                    }

                    Rectangle { width: 1; height: 64; color: "#2a3a55"; opacity: 0.6 }

                    Column {
                        spacing: 4
                        visible: {
                            var lp = detailScope.gameLastPlayed
                            return lp !== "" && lp !== "0" && parseInt(lp, 10) > 0
                        }
                        Text { text: "LAST PLAYED"; color: "#8a9bb5"; font.pixelSize: 14; font.bold: true; font.letterSpacing: 1.2 }
                        Text { text: root.formatUnixDate(detailScope.gameLastPlayed); color: "#e8e8e8"; font.pixelSize: 20 }
                    }

                    Column {
                        spacing: 4
                        visible: detailScope.gamePlaytime > 0
                        Text { text: "PLAY TIME"; color: "#8a9bb5"; font.pixelSize: 14; font.bold: true; font.letterSpacing: 1.2 }
                        Text { text: root.formatPlaytime(detailScope.gamePlaytime); color: "#e8e8e8"; font.pixelSize: 20 }
                    }

                    Column {
                        spacing: 4
                        visible: detailScope.gameInstalled && detailScope.gameSizeOnDisk > 0
                        Text { text: "SIZE"; color: "#8a9bb5"; font.pixelSize: 14; font.bold: true; font.letterSpacing: 1.2 }
                        Text { text: root.formatSize(detailScope.gameSizeOnDisk); color: "#e8e8e8"; font.pixelSize: 20 }
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Flickable {
                id: bodyFlick
                anchors.top: actionStrip.bottom
                anchors.left: parent.left; anchors.right: parent.right
                anchors.bottom: parent.bottom
                contentHeight: bodyColumn.implicitHeight + 60
                clip: true
                flickableDirection: Flickable.VerticalFlick
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: bodyColumn
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 60; anchors.rightMargin: 60
                    y: 36
                    spacing: 40

                    Column {
                        width: parent.width; spacing: 12
                        Text { text: "Friends"; color: "#e8e8e8"; font.pixelSize: 28; font.bold: true }
                        Text { text: "PLAYED PREVIOUSLY"; color: "#8a9bb5"; font.pixelSize: 14; font.letterSpacing: 1.4; font.bold: true }
                        Item {
                            width: parent.width; height: 80
                            Row {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 12
                                Rectangle {
                                    width: 56; height: 56; radius: 28
                                    color: "#1f2531"; border.color: "#2e3540"
                                    Text { anchors.centerIn: parent; text: "\uD83D\uDC64"; font.pixelSize: 28 }
                                }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "No friends activity available"; color: "#555e6e"; font.pixelSize: 18 }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: "#2a3a55"; opacity: 0.5 }

                    Column {
                        width: parent.width; spacing: 12
                        Text { text: "Recent News"; color: "#e8e8e8"; font.pixelSize: 28; font.bold: true }
                        Text { visible: detailScope.newsLoading; text: "Loading news\u2026"; color: "#8a9bb5"; font.pixelSize: 18 }
                        Text { visible: !detailScope.newsLoading && detailScope.newsItems.length === 0; text: "No recent news found for this game."; color: "#555e6e"; font.pixelSize: 18 }
                        Column {
                            width: parent.width; spacing: 10
                            visible: !detailScope.newsLoading && detailScope.newsItems.length > 0
                            Repeater {
                                id: newsRepeater
                                model: detailScope.newsItems
                                delegate: Rectangle {
                                    id: newsCard
                                    width: parent ? parent.width : 0
                                    height: newsRow.implicitHeight + 28
                                    radius: 12
                                    property bool hasUrl:  (modelData.url || "") !== ""
                                    property bool hovered: false
                                    property bool focused: activeFocus
                                    color: (hovered || focused) && hasUrl ? "#222840" : "#1a1e28"
                                    border.color: focused && hasUrl ? "#5ba3ff" : (hovered && hasUrl ? "#3a5a8a" : "#2e3540")
                                    border.width: focused && hasUrl ? 2 : 1
                                    Behavior on color        { ColorAnimation { duration: 100 } }
                                    Behavior on border.color { ColorAnimation { duration: 100 } }
                                    activeFocusOnTab: hasUrl
                                    Keys.onReturnPressed: if (hasUrl) articlePopup.openUrl(modelData.url)
                                    function openArticle() { if (hasUrl) articlePopup.openUrl(modelData.url) }
                                    Row {
                                        id: newsRow
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: 20; spacing: 16
                                        Rectangle {
                                            width: 6; height: 44; radius: 3
                                            color: newsCard.focused && newsCard.hasUrl ? "#5ba3ff" : "#2a7bd9"
                                            anchors.verticalCenter: parent.verticalCenter
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        Column {
                                            width: parent.width - 42 - (newsCard.hasUrl ? 36 : 0)
                                            spacing: 4; anchors.verticalCenter: parent.verticalCenter
                                            Text {
                                                width: parent.width
                                                text: modelData.title || ""
                                                color: newsCard.hovered && newsCard.hasUrl ? "#7ab8ff" : "#e8e8e8"
                                                font.pixelSize: 20; font.bold: true; elide: Text.ElideRight
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                            }
                                            Text { text: modelData.date || ""; color: "#8a9bb5"; font.pixelSize: 15 }
                                        }
                                        Text {
                                            visible: newsCard.hasUrl
                                            text: "\u276F"
                                            color: newsCard.focused ? "#5ba3ff" : (newsCard.hovered ? "#7ab8ff" : "#3a4a66")
                                            font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: newsCard.hasUrl
                                        cursorShape: newsCard.hasUrl ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onEntered: newsCard.hovered = true
                                        onExited:  newsCard.hovered = false
                                        onClicked: newsCard.openArticle()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            function activate()     { primaryBtn.doAction() }
            function openDetails()  {}
            function openSettings() {}
        }
    }

    // ══ STEAM ACCOUNT ══════════════════════════════════════════════════════════════
    Component {
        id: steamAccountPage
        FocusScope {
            width: parent ? parent.width : root.width; height: parent ? parent.height : root.height; focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            WebEngineView {
                id: loginWebView
                profile: deckProfile
                anchors.fill: parent; visible: false; url: "about:blank"
                onUrlChanged: {
                    var u = url.toString()
                    if (u.includes("/auth/steam/done") || u.includes("/auth/steam/callback")) {
                        visible = false; url = "about:blank"
                        root.handleLoginDone(u)
                    }
                }
                onLoadingChanged: function(info) {
                    if (info.status === WebEngineView.LoadFailedStatus) {
                        loginErrText.visible = true; visible = false
                    }
                }
            }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 60; spacing: 32; visible: !loginWebView.visible
                RowLayout {
                    Rectangle {
                        width: 48; height: 48; radius: 10; color: activeFocus ? "#2a7bd9" : "transparent"
                        border.color: activeFocus ? "#5ba3ff" : "transparent"; activeFocusOnTab: true
                        Text { anchors.centerIn: parent; text: "\u25C4"; color: "#5ba3ff"; font.pixelSize: 28 }
                        Keys.onReturnPressed: stack.pop()
                        MouseArea { anchors.fill: parent; onClicked: stack.pop() }
                    }
                    Text { text: "Steam Account"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
                }
                Rectangle {
                    id: loginErrText; visible: false
                    Layout.fillWidth: true; height: 56; color: "#2a1a1a"; radius: 10; border.color: "#c0392b"
                    Text { anchors.centerIn: parent; text: "\u26A0  Could not reach the login server."; color: "#e74c3c"; font.pixelSize: 18 }
                }
                ColumnLayout {
                    visible: root.steamLinked; spacing: 20
                    Row {
                        spacing: 20
                        Image { source: root.steamAvatar; width: 80; height: 80; fillMode: Image.PreserveAspectCrop }
                        Column {
                            spacing: 6; anchors.verticalCenter: parent.verticalCenter
                            Text { text: root.steamPersona; color: "#e8e8e8"; font.pixelSize: 32; font.bold: true }
                            Text { text: "Steam ID: " + root.steamId; color: "#8a9bb5"; font.pixelSize: 18 }
                        }
                    }
                    Rectangle {
                        width: 220; height: 58; radius: 12
                        color: activeFocus ? "#c0392b" : "#1f2531"
                        border.color: activeFocus ? "#e74c3c" : "#2e3540"; border.width: activeFocus ? 3 : 1
                        focus: root.steamLinked; activeFocusOnTab: true
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent; text: "Sign Out"; color: "white"; font.pixelSize: 22; font.bold: true }
                        Keys.onReturnPressed: root.doLogout()
                        MouseArea { anchors.fill: parent; onClicked: root.doLogout() }
                    }
                }
                ColumnLayout {
                    visible: !root.steamLinked; spacing: 24
                    Text { text: "Connect your Steam account to see your full game library."; color: "#8a9bb5"; font.pixelSize: 22; wrapMode: Text.WordWrap; Layout.maximumWidth: 860 }
                    Rectangle {
                        id: signInBtn
                        width: 320; height: 72; radius: 14
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: activeFocus ? "#1a8fc2" : "#1b8fc1" }
                            GradientStop { position: 1.0; color: activeFocus ? "#1063a0" : "#155e8e" }
                        }
                        border.color: activeFocus ? "#5ba3ff" : "#1779a8"; border.width: activeFocus ? 3 : 1
                        focus: !root.steamLinked; activeFocusOnTab: true
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        Row {
                            anchors.centerIn: parent; spacing: 14
                            Text { text: "\uD83C\uDFAE"; font.pixelSize: 30; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Sign in with Steam"; color: "white"; font.pixelSize: 24; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Keys.onReturnPressed: openSteamLogin()
                        MouseArea { anchors.fill: parent; onClicked: parent.openSteamLogin() }
                        function openSteamLogin() {
                            loginErrText.visible = false
                            loginWebView.url = root.backendUrl + "/auth/steam"
                            loginWebView.visible = true; loginWebView.forceActiveFocus()
                        }
                    }
                    Text { text: "Your credentials are entered directly on Steam's website."; color: "#555e6e"; font.pixelSize: 16; wrapMode: Text.WordWrap; Layout.maximumWidth: 780 }
                }
            }
            function activate() { var item = root.activeFocusItem; if (item && item.openSteamLogin) item.openSteamLogin() }
            function openDetails() {} function openSettings() {}
        }
    }

    // ══ STORE ══════════════════════════════════════════════════════════════════════
    Component {
        id: storePage
        FocusScope {
            width: parent ? parent.width : root.width; height: parent ? parent.height : root.height; focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 28
                Text { text: "\uD83D\uDED2  Steam Store"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                Rectangle {
                    width: 260; height: 64; radius: 14; color: activeFocus ? "#1a6ec2" : "#2a7bd9"
                    Layout.alignment: Qt.AlignHCenter; focus: true; activeFocusOnTab: true
                    Text { anchors.centerIn: parent; text: "Open Steam Store"; color: "white"; font.pixelSize: 24; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: Qt.openUrlExternally("steam://store") }
                    Keys.onReturnPressed: Qt.openUrlExternally("steam://store")
                }
                Rectangle {
                    width: 140; height: 48; radius: 10; color: activeFocus ? "#2a7bd9" : "#1f2531"
                    Layout.alignment: Qt.AlignHCenter; activeFocusOnTab: true
                    Text { anchors.centerIn: parent; text: "\u25C4 Back"; color: "#5ba3ff"; font.pixelSize: 20 }
                    MouseArea { anchors.fill: parent; onClicked: stack.pop() }
                    Keys.onReturnPressed: stack.pop()
                }
            }
            function activate() {} function openDetails() {} function openSettings() {}
        }
    }

    // ══ SETTINGS ═══════════════════════════════════════════════════════════════════
    Component {
        id: settingsPage
        FocusScope {
            width: parent ? parent.width : root.width; height: parent ? parent.height : root.height; focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 60; spacing: 28
                RowLayout {
                    Rectangle {
                        width: 48; height: 48; radius: 10; color: activeFocus ? "#2a7bd9" : "transparent"
                        border.color: activeFocus ? "#5ba3ff" : "transparent"; activeFocusOnTab: true
                        Text { anchors.centerIn: parent; text: "\u25C4"; color: "#5ba3ff"; font.pixelSize: 28 }
                        Keys.onReturnPressed: stack.pop()
                        MouseArea { anchors.fill: parent; onClicked: stack.pop() }
                    }
                    Text { text: "Settings"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 80; color: activeFocus ? "#1f2e42" : "#191d26"; radius: 10
                    border.color: activeFocus ? "#5ba3ff" : "#2e3540"; focus: true; activeFocusOnTab: true
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 28; anchors.rightMargin: 28
                        Text { text: "Steam Account"; color: "white"; font.pixelSize: 24 }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 160; height: 36; radius: 8
                            color: root.steamLinked ? "#1a4a1a" : "#2a1a1a"
                            border.color: root.steamLinked ? "#4caf50" : "#c0392b"
                            Text {
                                anchors.centerIn: parent
                                text: root.steamLinked ? ("\u2714 " + root.steamPersona) : "Not linked"
                                color: root.steamLinked ? "#4caf50" : "#c0392b"
                                font.pixelSize: 16; elide: Text.ElideRight
                                width: parent.width - 16; horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        Text { text: "\u276F"; color: "#5ba3ff"; font.pixelSize: 22 }
                    }
                    Keys.onReturnPressed: stack.push(steamAccountPage)
                    MouseArea { anchors.fill: parent; onClicked: stack.push(steamAccountPage) }
                }
                Repeater {
                    model: ["Display", "Audio", "Controller", "Network", "System"]
                    delegate: Rectangle {
                        Layout.fillWidth: true; height: 72; color: activeFocus ? "#1f2e42" : "#191d26"; radius: 10
                        border.color: activeFocus ? "#5ba3ff" : "#2e3540"; activeFocusOnTab: true
                        Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 28; text: modelData; color: "white"; font.pixelSize: 24 }
                        Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: 28; text: "\u276F"; color: "#5ba3ff"; font.pixelSize: 22 }
                    }
                }
            }
            function activate() { stack.push(steamAccountPage) } function openDetails() {} function openSettings() {}
        }
    }

    // ══ POWER ══════════════════════════════════════════════════════════════════════
    Component {
        id: powerPage
        FocusScope {
            width: parent ? parent.width : root.width; height: parent ? parent.height : root.height; focus: true
            Rectangle { anchors.fill: parent; color: "#0d0f13" }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 32
                Text { Layout.alignment: Qt.AlignHCenter; text: "\u23FB  Power"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
                RowLayout {
                    spacing: 28
                    Repeater {
                        id: powerRepeater
                        model: [
                            { label: "Shutdown",      cmd: "systemctl poweroff" },
                            { label: "Restart",        cmd: "systemctl reboot"   },
                            { label: "Sleep",          cmd: "systemctl suspend"  },
                            { label: "Exit Deck Mode", cmd: ""                   }
                        ]
                        delegate: Rectangle {
                            id: powerBtn
                            width: 220; height: 120; color: activeFocus ? "#c0392b" : "#1f2531"; radius: 14
                            border.color: activeFocus ? "#e74c3c" : "#2e3540"; border.width: activeFocus ? 3 : 1
                            focus: index === 0; activeFocusOnTab: true
                            KeyNavigation.right: powerRepeater.itemAt(index + 1)
                            KeyNavigation.left:  powerRepeater.itemAt(index - 1)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { anchors.centerIn: parent; text: modelData.label; color: "white"; font.pixelSize: 22; font.bold: activeFocus }
                            Keys.onReturnPressed: doAction()
                            MouseArea { anchors.fill: parent; onClicked: { powerBtn.forceActiveFocus(); powerBtn.doAction() } }
                            function doAction() { if (modelData.cmd !== "") Qt.openUrlExternally("exec://" + modelData.cmd); else Qt.quit() }
                        }
                    }
                }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Press B to cancel"; color: "#555e6e"; font.pixelSize: 20 }
            }
            function activate() { var item = root.activeFocusItem; if (item && item.doAction) item.doAction() }
            function openDetails() {} function openSettings() {}
        }
    }
}
