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

    property bool   steamLinked:  false
    property string steamPersona: ""
    property string steamAvatar:  ""
    property string steamId:      ""
    property string lastFetchedId: ""

    function fetchIfNeeded(sid) {
        console.log("[main] fetchIfNeeded sid:", sid, "lastFetchedId:", lastFetchedId)
        if (sid === "" || sid === lastFetchedId) {
            console.log("[main] fetchIfNeeded: skipping (already fetched or no sid)")
            return
        }
        lastFetchedId = sid
        SteamLibrary.filterMode = 1
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
        console.log("[main] handleLoginDone persona:", persona, "sid:", sid)
        if (persona !== "") {
            steamLinked  = true
            steamPersona = persona
            steamAvatar  = avatar
            steamId      = sid
            fetchIfNeeded(sid)
        } else {
            pollAuthStatus()
        }
    }

    function pollAuthStatus() {
        console.log("[main] pollAuthStatus called")
        var xhr = new XMLHttpRequest()
        xhr.open("GET", backendUrl + "/auth/status", true)
        xhr.withCredentials = true
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return
            console.log("[main] pollAuthStatus response status:", xhr.status, "body:", xhr.responseText.substring(0, 200))
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    console.log("[main] pollAuthStatus parsed: linked=", data.linked, "steamId=", data.steamId)
                    if (data.linked) {
                        steamLinked  = data.linked
                        steamPersona = data.persona  || ""
                        steamAvatar  = data.avatar   || ""
                        steamId      = data.steamId  || ""
                        fetchIfNeeded(steamId)
                    }
                } catch(e) { console.warn("[main] pollAuthStatus parse error:", e) }
            }
        }
        xhr.send()
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
        SteamLibrary.filterMode = 0
        SteamLibrary.refresh()
    }

    // ─── C++ → QML bridge ────────────────────────────────────────────────────
    Connections {
        target: SteamLibraryCtrl
        ignoreUnknownSignals: true

        function onCountChanged() {
            console.log("[main] SteamLibraryCtrl.onCountChanged fired.",
                        "count:", SteamLibraryCtrl.count,
                        "loading:", SteamLibraryCtrl.loading)
            if (SteamLibraryCtrl.loading) {
                console.log("[main] still loading, skipping bridge")
                return
            }

            // Pass home path to QML singleton for ACF file checks
            var hp = SteamLibraryCtrl.homePath
            console.log("[main] SteamLibraryCtrl.homePath:", hp)
            SteamLibrary.setHomePath(hp || "")

            var games = []
            var n = SteamLibraryCtrl.count
            console.log("[main] reading", n, "games from C++ model")
            for (var i = 0; i < n; i++) {
                var idx = SteamLibraryCtrl.index(i, 0)
                var game = {
                    appId:      SteamLibraryCtrl.data(idx, 0x101),  // AppIdRole
                    name:       SteamLibraryCtrl.data(idx, 0x102),  // NameRole
                    coverUrl:   SteamLibraryCtrl.data(idx, 0x103),  // CoverUrlRole
                    installed:  SteamLibraryCtrl.data(idx, 0x105),  // InstalledRole
                    lastPlayed: SteamLibraryCtrl.data(idx, 0x107)   // LastPlayedRole
                }
                console.log("[main]   game[", i, "]:", game.appId, game.name, "installed:", game.installed)
                games.push(game)
            }

            if (root.steamLinked && root.steamId !== "") {
                console.log("[main] bridge -> loadOwnedGames (", games.length, "games)")
                SteamLibrary.loadOwnedGames(games)
            } else {
                console.log("[main] bridge -> setLocalGames (", games.length, "games)")
                SteamLibrary.setLocalGames(games)
            }
        }

        function onLoadingChanged() {
            console.log("[main] SteamLibraryCtrl.onLoadingChanged: loading=", SteamLibraryCtrl.loading)
            SteamLibrary.loading = SteamLibraryCtrl.loading
        }
    }

    Component.onCompleted: {
        console.log("[main] Component.onCompleted")
        pollAuthStatus()
        SteamLibraryCtrl.refresh()
    }

    Connections {
        target: Gamepad
        ignoreUnknownSignals: true
        function onButtonA()    { stack.currentItem.activate() }
        function onButtonB()    { stack.pop() }
        function onLb()         { SteamLibrary.filterMode = 0 }
        function onRb()         { SteamLibrary.filterMode = 1 }
    }

    Item {
        anchors.fill: parent; focus: true
        Keys.onReturnPressed: stack.currentItem.activate()
        Keys.onEscapePressed: stack.pop()
    }

    QtObject {
        id: navigator
        function moveUp()    { root.activeFocusItem.nextItemInFocusChain(false).forceActiveFocus() }
        function moveDown()  { root.activeFocusItem.nextItemInFocusChain(true).forceActiveFocus() }
        function moveLeft()  { root.activeFocusItem.nextItemInFocusChain(false).forceActiveFocus() }
        function moveRight() { root.activeFocusItem.nextItemInFocusChain(true).forceActiveFocus() }
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: homePage
    }

    // ══ HOME ═════════════════════════════════════════════════════════════════════
    Component {
        id: homePage
        FocusScope {
            width:  parent ? parent.width  : root.width
            height: parent ? parent.height : root.height
            focus: true
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
                        Layout.fillWidth: true; height: 200
                        orientation: ListView.Horizontal; spacing: 20; clip: true
                        model: SteamLibrary
                        delegate: Rectangle {
                            visible: (lastPlayed || "") !== "" && lastPlayed !== "0"
                            width: visible ? 160 : 0; height: 190
                            color: "#1a2030"; radius: 10; clip: true
                            Image { anchors.fill: parent; source: coverUrl || ""; fillMode: Image.PreserveAspectCrop }
                            MouseArea { anchors.fill: parent; onClicked: SteamLibrary.launchGame(appId) }
                        }
                    }
                }
            }
            function activate()     { var item = root.activeFocusItem; if (item && item.doNav) item.doNav() }
            function openDetails()  {}
            function openSettings() { stack.push(settingsPage) }
        }
    }

    // ══ LIBRARY ══════════════════════════════════════════════════════════════════
    Component {
        id: libraryPage
        FocusScope {
            width:  parent ? parent.width  : root.width
            height: parent ? parent.height : root.height
            focus: true

            Component.onCompleted: {
                console.log("[main] libraryPage.onCompleted. SteamLibrary.count:",
                            SteamLibrary.count, "loading:", SteamLibrary.loading)
                root.fetchIfNeeded(root.steamId)
            }

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
                        text: SteamLibrary.count + " games"
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
                            console.log("[main] Refresh button pressed")
                            root.lastFetchedId = ""
                            if (root.steamId !== "") root.fetchIfNeeded(root.steamId)
                            else { SteamLibraryCtrl.refresh(); SteamLibrary.refresh() }
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
                            property bool active: (index === SteamLibrary.filterMode)
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
                            Keys.onReturnPressed: {
                                console.log("[main] filter tab pressed, index:", index)
                                SteamLibrary.filterMode = index
                            }
                            MouseArea { anchors.fill: parent; onClicked: { filterTab.forceActiveFocus(); SteamLibrary.filterMode = index } }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // Loading indicator
                Text {
                    visible: SteamLibrary.loading
                    text: "Fetching Steam library\u2026"
                    color: "#8a9bb5"; font.pixelSize: 24; Layout.alignment: Qt.AlignHCenter
                }

                // ── The grid ──────────────────────────────────────────────────
                GridView {
                    id: gameGrid
                    // Log why the grid is visible or not
                    property bool shouldBeVisible: !SteamLibrary.loading && SteamLibrary.count > 0
                    visible: shouldBeVisible
                    onShouldBeVisibleChanged:
                        console.log("[main] gameGrid visible:", shouldBeVisible,
                                    "loading:", SteamLibrary.loading,
                                    "count:", SteamLibrary.count)

                    Layout.fillWidth: true; Layout.fillHeight: true
                    cellWidth: 200; cellHeight: 300
                    focus: true; activeFocusOnTab: true; clip: true
                    model: SteamLibrary
                    keyNavigationEnabled: true

                    Keys.onUpPressed:   moveCurrentIndexUp()
                    Keys.onDownPressed: moveCurrentIndexDown()
                    Keys.onLeftPressed:  moveCurrentIndexLeft()
                    Keys.onRightPressed: moveCurrentIndexRight()

                    delegate: Rectangle {
                        id: gameTile
                        width: 184; height: 284

                        // Use 'var' — typed 'bool' throws when model resets
                        // and the role resolves to undefined mid-teardown.
                        property var _installed: installed
                        function inst() { return _installed === true }

                        Component.onCompleted:
                            console.log("[main] delegate created: appId=", appId,
                                        "name=", name,
                                        "raw installed role value:", installed,
                                        "inst():", inst())

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
                            color: gameTile.inst() ? "white" : "#b0b8c8"
                            font.pixelSize: 15; font.bold: GridView.isCurrentItem
                            elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            visible: !gameTile.inst()
                            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 16; height: 24; radius: 8
                            color: "#1f2531"; border.color: "#2e3540"
                            Text { anchors.centerIn: parent; text: "Not installed"; color: "#8a9bb5"; font.pixelSize: 13 }
                        }

                        Keys.onReturnPressed:
                            inst() ? SteamLibrary.launchGame(appId) : SteamLibrary.installGame(appId)
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { gameGrid.currentIndex = index; gameGrid.forceActiveFocus() }
                            onDoubleClicked: inst() ? SteamLibrary.launchGame(appId) : SteamLibrary.installGame(appId)
                        }
                    }
                }

                // Empty state
                Column {
                    visible: !SteamLibrary.loading && SteamLibrary.count === 0
                    Layout.alignment: Qt.AlignHCenter; spacing: 16
                    Text { text: "\uD83C\uDFAE"; font.pixelSize: 64; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "No games found"; color: "#e8e8e8"; font.pixelSize: 30; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        text: root.steamLinked
                            ? "Make sure the backend has STEAM_API_KEY set."
                            : "No installed games found, or sign in with Steam in Settings."
                        color: "#555e6e"; font.pixelSize: 20; anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            function activate() {
                if (gameGrid.activeFocus && gameGrid.currentItem)
                    gameGrid.currentItem.inst()
                        ? SteamLibrary.launchGame(gameGrid.currentItem.appId)
                        : SteamLibrary.installGame(gameGrid.currentItem.appId)
            }
            function openDetails()  {}
            function openSettings() {}
        }
    }

    // ══ STEAM ACCOUNT ══════════════════════════════════════════════════════════
    Component {
        id: steamAccountPage
        FocusScope {
            width:  parent ? parent.width  : root.width
            height: parent ? parent.height : root.height
            focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            WebEngineView {
                id: loginWebView
                anchors.fill: parent; visible: false; url: "about:blank"
                onUrlChanged: {
                    var u = url.toString()
                    if (u.includes("/auth/steam/done") || u.includes("/auth/steam/callback")) {
                        visible = false; url = "about:blank"
                        root.handleLoginDone(u)
                    }
                }
            }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 60; spacing: 32; visible: !loginWebView.visible
                RowLayout {
                    Rectangle {
                        width: 48; height: 48; radius: 10
                        color: activeFocus ? "#2a7bd9" : "transparent"
                        border.color: activeFocus ? "#5ba3ff" : "transparent"; activeFocusOnTab: true
                        Text { anchors.centerIn: parent; text: "\u25C4"; color: "#5ba3ff"; font.pixelSize: 28 }
                        Keys.onReturnPressed: stack.pop()
                        MouseArea { anchors.fill: parent; onClicked: stack.pop() }
                    }
                    Text { text: "Steam Account"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
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
                        Row {
                            anchors.centerIn: parent; spacing: 14
                            Text { text: "\uD83C\uDFAE"; font.pixelSize: 30; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Sign in with Steam"; color: "white"; font.pixelSize: 24; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Keys.onReturnPressed: openSteamLogin()
                        MouseArea { anchors.fill: parent; onClicked: parent.openSteamLogin() }
                        function openSteamLogin() {
                            loginWebView.url = root.backendUrl + "/auth/steam"
                            loginWebView.visible = true; loginWebView.forceActiveFocus()
                        }
                    }
                }
            }
            function activate() { var item = root.activeFocusItem; if (item && item.openSteamLogin) item.openSteamLogin() }
            function openDetails() {} function openSettings() {}
        }
    }

    // ══ STORE ═══════════════════════════════════════════════════════════════════
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

    // ══ SETTINGS ════════════════════════════════════════════════════════════════
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
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 28; anchors.rightMargin: 28
                        Text { text: "Steam Account"; color: "white"; font.pixelSize: 24 }
                        Item { Layout.fillWidth: true }
                        Text { text: root.steamLinked ? ("\u2714 " + root.steamPersona) : "Not linked"; color: root.steamLinked ? "#4caf50" : "#c0392b"; font.pixelSize: 16 }
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

    // ══ POWER ═══════════════════════════════════════════════════════════════════
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
