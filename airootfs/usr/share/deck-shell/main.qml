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

    // Parse a single query param from a URL string
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

    // Called after login completes.
    // SteamLibraryCtrl is the same C++ object as SteamLibrary but registered
    // under a second context property name — this avoids a Qt6 bug where
    // QAbstractListModel objects used as view models get wrapped in a proxy
    // that shadows Q_INVOKABLE methods.
    function handleLoginDone(urlStr) {
        var persona = getParam(urlStr, "persona")
        var avatar  = getParam(urlStr, "avatar")
        var sid     = getParam(urlStr, "steamid")

        if (persona !== "") {
            steamLinked  = true
            steamPersona = persona
            steamAvatar  = avatar
            steamId      = sid
            SteamLibraryCtrl.fetchOwnedGamesForId(sid)
        } else {
            pollAuthStatus()
        }
    }

    // XHR fallback for startup session restore
    function pollAuthStatus() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", backendUrl + "/auth/status", true)
        xhr.withCredentials = true
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    if (data.linked) {
                        steamLinked  = data.linked
                        steamPersona = data.persona  || ""
                        steamAvatar  = data.avatar   || ""
                        steamId      = data.steamId  || ""
                        SteamLibraryCtrl.fetchOwnedGamesForId(steamId)
                    }
                } catch(e) { console.warn("pollAuthStatus parse error:", e) }
            } else {
                console.warn("pollAuthStatus HTTP", xhr.status)
            }
        }
        xhr.send()
    }

    function doLogout() {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", backendUrl + "/auth/logout", true)
        xhr.withCredentials = true
        xhr.send()
        steamLinked  = false
        steamPersona = ""
        steamAvatar  = ""
        steamId      = ""
        SteamLibraryCtrl.refresh()
    }

    // Poll on startup in case the user was already logged in from a previous session
    Component.onCompleted: pollAuthStatus()

    // ── Controller signals ────────────────────────────────────────────────────────────────────────
    Connections {
        target: Gamepad
        ignoreUnknownSignals: true
        function onButtonA()    { stack.currentItem.activate() }
        function onButtonB()    { stack.pop() }
        function onButtonX()    { stack.currentItem.openDetails() }
        function onButtonY()    { stack.currentItem.openSettings() }
        function onDpadUp()     { navigator.moveUp() }
        function onDpadDown()   { navigator.moveDown() }
        function onDpadLeft()   { navigator.moveLeft() }
        function onDpadRight()  { navigator.moveRight() }
        function onAxisLeftY(v) { navigator.handleAxis(v) }
        function onLB() { SteamLibrary.filterMode = 0 }
        function onRB() { SteamLibrary.filterMode = 1 }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onReturnPressed: stack.currentItem.activate()
        Keys.onEscapePressed: stack.pop()
        Keys.onUpPressed:     navigator.moveUp()
        Keys.onDownPressed:   navigator.moveDown()
        Keys.onLeftPressed:   { navigator.moveLeft(); SteamLibrary.filterMode = 0 }
        Keys.onRightPressed:  { navigator.moveRight(); SteamLibrary.filterMode = 1 }
        Keys.onPressed: function(ev) {
            if (ev.key === Qt.Key_Q) { SteamLibrary.filterMode = 0; ev.accepted = true }
            else if (ev.key === Qt.Key_E) { SteamLibrary.filterMode = 1; ev.accepted = true }
        }
    }

    QtObject {
        id: navigator
        function handleAxis(v) {
            if      (v >  0.5) moveDown()
            else if (v < -0.5) moveUp()
        }
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

    // ════════════════════════════════════════════════════════════════════════
    // HOME
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: homePage
        FocusScope {
            anchors.fill: parent
            focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 60
                spacing: 48

                RowLayout {
                    spacing: 20
                    Text { text: "\u2665  Deck Mode"; color: "#e8e8e8"; font.pixelSize: 52; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Row {
                        spacing: 12
                        visible: root.steamLinked
                        Image { source: root.steamAvatar; width: 40; height: 40; fillMode: Image.PreserveAspectCrop }
                        Text { text: root.steamPersona; color: "#8a9bb5"; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
                    }
                }

                RowLayout {
                    spacing: 28
                    Layout.fillWidth: true
                    Repeater {
                        model: [
                            { label: "Library",   icon: "\uD83C\uDFAE" },
                            { label: "Store",      icon: "\uD83D\uDED2" },
                            { label: "Downloads",  icon: "\u2B07" },
                            { label: "Settings",   icon: "\u2699" },
                            { label: "Power",       icon: "\u23FB" }
                        ]
                        delegate: Rectangle {
                            Layout.preferredWidth: 240
                            Layout.preferredHeight: 150
                            color: activeFocus ? "#2a7bd9" : "#1f2531"
                            radius: 14
                            border.color: activeFocus ? "#5ba3ff" : "#2e3540"
                            border.width: activeFocus ? 3 : 1
                            focus: index === 0
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Column {
                                anchors.centerIn: parent
                                spacing: 10
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; font.pixelSize: 36 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: "white"; font.pixelSize: 22; font.bold: activeFocus }
                            }
                            Keys.onReturnPressed: doNav()
                            MouseArea { anchors.fill: parent; onClicked: parent.doNav() }
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
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 16
                    Text { text: "Recently Played"; color: "#8a9bb5"; font.pixelSize: 24; font.bold: true }
                    ListView {
                        id: recentList
                        Layout.fillWidth: true
                        height: 200
                        orientation: ListView.Horizontal
                        spacing: 20
                        clip: true
                        model: SteamLibrary
                        delegate: Rectangle {
                            visible: lastPlayed !== "" && lastPlayed !== "0"
                            width: visible ? 160 : 0
                            height: 190
                            color: "#1a2030"
                            radius: 10
                            clip: true
                            Image { anchors.fill: parent; source: coverUrl; fillMode: Image.PreserveAspectCrop }
                            Rectangle {
                                anchors.bottom: parent.bottom; width: parent.width; height: 44; color: "#cc14161a"; radius: 10
                                Text { anchors.centerIn: parent; text: name; color: "white"; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter }
                            }
                            MouseArea { anchors.fill: parent; onClicked: SteamLibraryCtrl.launchGame(appId) }
                        }
                    }
                    Text {
                        visible: recentList.count === 0 || SteamLibrary.loading
                        text: SteamLibrary.loading ? "Loading library\u2026" : "No recent games \u2014 head to Library to play something!"
                        color: "#555e6e"; font.pixelSize: 22; anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
            function activate()     { var item = root.activeFocusItem; if (item && item.doNav) item.doNav() }
            function openDetails()  {}
            function openSettings() { stack.push(settingsPage) }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // LIBRARY
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: libraryPage
        FocusScope {
            anchors.fill: parent
            focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 48
                spacing: 20

                RowLayout {
                    spacing: 20
                    Text { text: "\u25C4"; color: "#5ba3ff"; font.pixelSize: 28; MouseArea { anchors.fill: parent; onClicked: stack.pop() } }
                    Text { text: "Library"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text { text: SteamLibrary.count + " games"; color: "#8a9bb5"; font.pixelSize: 22; Layout.alignment: Qt.AlignVCenter }
                    Rectangle { width: 120; height: 44; color: "#1f2531"; radius: 10; border.color: "#2e3540"
                        Text { anchors.centerIn: parent; text: "\u21BA  Refresh"; color: "#8a9bb5"; font.pixelSize: 18 }
                        MouseArea { anchors.fill: parent; onClicked: {
                            if (root.steamId !== "")
                                SteamLibraryCtrl.fetchOwnedGamesForId(root.steamId)
                            else
                                SteamLibraryCtrl.refresh()
                        }}
                    }
                }

                RowLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Repeater {
                        model: ["Installed", "All Owned"]
                        delegate: Rectangle {
                            property bool active: (index === SteamLibrary.filterMode)
                            Layout.preferredWidth: 200
                            height: 48
                            color: active ? "#2a7bd9" : "#1f2531"
                            radius: 10
                            border.color: active ? "#5ba3ff" : "#2e3540"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                anchors.centerIn: parent; spacing: 8
                                Text { text: index === 0 ? "LB" : "RB"; color: active ? "white" : "#555e6e"; font.pixelSize: 14; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: modelData; color: active ? "white" : "#8a9bb5"; font.pixelSize: 20; font.bold: active; anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { anchors.fill: parent; onClicked: SteamLibrary.filterMode = index }
                        }
                    }
                    Text {
                        visible: SteamLibrary.filterMode === 1 && !root.steamLinked
                        text: "\u26A0  Sign in with Steam in Settings to see your full library"
                        color: "#da7101"; font.pixelSize: 18
                        Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: 20
                    }
                }

                Text { visible: SteamLibrary.loading; text: "Fetching Steam library\u2026"; color: "#8a9bb5"; font.pixelSize: 24; Layout.alignment: Qt.AlignHCenter }

                GridView {
                    id: gameGrid
                    visible: !SteamLibrary.loading && SteamLibrary.count > 0
                    Layout.fillWidth: true; Layout.fillHeight: true
                    cellWidth: 200; cellHeight: 300
                    focus: true; clip: true
                    model: SteamLibrary
                    delegate: Rectangle {
                        width: 184; height: 284
                        color: GridView.isCurrentItem ? "#1e2e45" : "#1a1e28"
                        radius: 12
                        border.color: GridView.isCurrentItem ? "#5ba3ff" : "#2e3540"
                        border.width: GridView.isCurrentItem ? 3 : 1
                        clip: true
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Image {
                            id: coverImg
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            height: parent.height * 0.78
                            source: coverUrl; fillMode: Image.PreserveAspectCrop; smooth: true; asynchronous: true
                            Rectangle { anchors.fill: parent; color: "#252c38"; visible: coverImg.status !== Image.Ready; Text { anchors.centerIn: parent; text: "\uD83C\uDFAE"; font.pixelSize: 52 } }
                        }
                        Text {
                            anchors.top: coverImg.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 8
                            text: name; color: installed ? "white" : "#b0b8c8"
                            font.pixelSize: 15; font.bold: GridView.isCurrentItem
                            elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                        }
                        Rectangle {
                            visible: !installed
                            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 16; height: 24; radius: 8; color: "#1f2531"; border.color: "#2e3540"
                            Text { anchors.centerIn: parent; text: "Not installed"; color: "#8a9bb5"; font.pixelSize: 13 }
                        }
                        Keys.onReturnPressed: installed ? SteamLibraryCtrl.launchGame(appId) : SteamLibraryCtrl.installGame(appId)
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { gameGrid.currentIndex = index; gameGrid.forceActiveFocus() }
                            onDoubleClicked: installed ? SteamLibraryCtrl.launchGame(appId) : SteamLibraryCtrl.installGame(appId)
                        }
                    }
                }

                Column {
                    visible: !SteamLibrary.loading && SteamLibrary.count === 0
                    Layout.alignment: Qt.AlignHCenter; spacing: 16
                    Text { text: "\uD83C\uDFAE"; font.pixelSize: 64; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "No games found"; color: "#e8e8e8"; font.pixelSize: 30; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        text: root.steamLinked
                            ? (root.steamId !== "" ? "Make sure STEAM_API_KEY is set on this machine." : "Install a game from the Store.")
                            : "Sign in with Steam in Settings to see your full library."
                        color: "#555e6e"; font.pixelSize: 20; anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
            function activate() { if (gameGrid.currentItem) { if (gameGrid.currentItem.installed) SteamLibraryCtrl.launchGame(gameGrid.currentItem.appId); else SteamLibraryCtrl.installGame(gameGrid.currentItem.appId) } }
            function openDetails()  {}
            function openSettings() {}
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // STEAM ACCOUNT
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: steamAccountPage
        FocusScope {
            anchors.fill: parent
            focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }

            WebEngineView {
                id: loginWebView
                anchors.fill: parent
                visible: false
                url: "about:blank"

                onUrlChanged: {
                    var u = url.toString()
                    if (u.includes("/auth/steam/done") || u.includes("/auth/steam/callback")) {
                        visible = false
                        url = "about:blank"
                        root.handleLoginDone(u)
                    }
                }

                onLoadingChanged: function(info) {
                    if (info.status === WebEngineView.LoadFailedStatus) {
                        console.warn("Steam login page failed:", info.errorString)
                        loginErrText.visible = true
                        visible = false
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 60
                spacing: 32
                visible: !loginWebView.visible

                RowLayout {
                    Text { text: "\u25C4"; color: "#5ba3ff"; font.pixelSize: 28; MouseArea { anchors.fill: parent; onClicked: stack.pop() } }
                    Text { text: "Steam Account"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
                }

                Rectangle {
                    id: loginErrText
                    visible: false
                    Layout.fillWidth: true; height: 56
                    color: "#2a1a1a"; radius: 10; border.color: "#c0392b"
                    Text { anchors.centerIn: parent; text: "\u26A0  Could not reach the login server. Check your network connection."; color: "#e74c3c"; font.pixelSize: 18 }
                }

                ColumnLayout {
                    visible: root.steamLinked
                    spacing: 20
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
                        width: 220; height: 58; radius: 12; color: activeFocus ? "#c0392b" : "#1f2531"
                        border.color: activeFocus ? "#e74c3c" : "#2e3540"; border.width: activeFocus ? 3 : 1
                        focus: root.steamLinked
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent; text: "Sign Out"; color: "white"; font.pixelSize: 22; font.bold: true }
                        Keys.onReturnPressed: root.doLogout()
                        MouseArea { anchors.fill: parent; onClicked: root.doLogout() }
                    }
                }

                ColumnLayout {
                    visible: !root.steamLinked
                    spacing: 24
                    Text {
                        text: "Connect your Steam account to see your full game library."
                        color: "#8a9bb5"; font.pixelSize: 22
                        wrapMode: Text.WordWrap; Layout.maximumWidth: 860
                    }
                    Rectangle {
                        width: 320; height: 72; radius: 14
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: activeFocus ? "#1a8fc2" : "#1b8fc1" }
                            GradientStop { position: 1.0; color: activeFocus ? "#1063a0" : "#155e8e" }
                        }
                        border.color: activeFocus ? "#5ba3ff" : "#1779a8"; border.width: activeFocus ? 3 : 1
                        focus: !root.steamLinked
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
                            loginWebView.visible = true
                            loginWebView.forceActiveFocus()
                        }
                    }
                    Text {
                        text: "Your Steam credentials are entered directly on Steam's website. We never see your password."
                        color: "#555e6e"; font.pixelSize: 16
                        wrapMode: Text.WordWrap; Layout.maximumWidth: 780
                    }
                }
            }
            function activate()     { var item = root.activeFocusItem; if (item && item.openSteamLogin) item.openSteamLogin() }
            function openDetails()  {}
            function openSettings() {}
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // STORE
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: storePage
        FocusScope {
            anchors.fill: parent; focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 28
                Text { text: "\uD83D\uDED2  Steam Store"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                Text { text: "Opens Steam's built-in store browser."; color: "#8a9bb5"; font.pixelSize: 22; Layout.alignment: Qt.AlignHCenter }
                Rectangle { width: 260; height: 64; radius: 14; color: "#2a7bd9"; Layout.alignment: Qt.AlignHCenter
                    Text { anchors.centerIn: parent; text: "Open Steam Store"; color: "white"; font.pixelSize: 24; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: Qt.openUrlExternally("steam://store") }
                    Keys.onReturnPressed: Qt.openUrlExternally("steam://store"); focus: true
                }
                Rectangle { width: 140; height: 48; radius: 10; color: "#1f2531"; Layout.alignment: Qt.AlignHCenter
                    Text { anchors.centerIn: parent; text: "\u25C4 Back"; color: "#5ba3ff"; font.pixelSize: 20 }
                    MouseArea { anchors.fill: parent; onClicked: stack.pop() }
                }
            }
            function activate() {} function openDetails() {} function openSettings() {}
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SETTINGS
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: settingsPage
        FocusScope {
            anchors.fill: parent; focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 60; spacing: 28
                RowLayout {
                    Text { text: "\u25C4"; color: "#5ba3ff"; font.pixelSize: 28; MouseArea { anchors.fill: parent; onClicked: stack.pop() } }
                    Text { text: "Settings"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 80
                    color: activeFocus ? "#1f2e42" : "#191d26"; radius: 10
                    border.color: activeFocus ? "#5ba3ff" : "#2e3540"
                    focus: true
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
                                font.pixelSize: 16; elide: Text.ElideRight; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter
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
                        Layout.fillWidth: true; height: 72
                        color: activeFocus ? "#1f2e42" : "#191d26"; radius: 10
                        border.color: activeFocus ? "#5ba3ff" : "#2e3540"; focus: false
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 28; text: modelData; color: "white"; font.pixelSize: 24 }
                        Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: 28; text: "\u276F"; color: "#5ba3ff"; font.pixelSize: 22 }
                    }
                }
            }
            function activate()     { stack.push(steamAccountPage) }
            function openDetails()  {}
            function openSettings() {}
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // POWER
    // ════════════════════════════════════════════════════════════════════════
    Component {
        id: powerPage
        FocusScope {
            anchors.fill: parent; focus: true
            Rectangle { anchors.fill: parent; color: "#0d0f13"; opacity: 0.97 }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 32
                Text { Layout.alignment: Qt.AlignHCenter; text: "\u23FB  Power"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
                RowLayout {
                    spacing: 28
                    Repeater {
                        model: [
                            { label: "Shutdown",      cmd: "systemctl poweroff" },
                            { label: "Restart",        cmd: "systemctl reboot"   },
                            { label: "Sleep",          cmd: "systemctl suspend"  },
                            { label: "Exit Deck Mode", cmd: ""                   }
                        ]
                        delegate: Rectangle {
                            width: 220; height: 120
                            color: activeFocus ? "#c0392b" : "#1f2531"; radius: 14
                            border.color: activeFocus ? "#e74c3c" : "#2e3540"; border.width: activeFocus ? 3 : 1
                            focus: index === 0
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { anchors.centerIn: parent; text: modelData.label; color: "white"; font.pixelSize: 22; font.bold: activeFocus }
                            Keys.onReturnPressed: doAction()
                            MouseArea { anchors.fill: parent; onClicked: parent.doAction() }
                            function doAction() { if (modelData.cmd !== "") Qt.openUrlExternally("exec://" + modelData.cmd); else Qt.quit() }
                        }
                    }
                }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Press \u241B / B to cancel"; color: "#555e6e"; font.pixelSize: 20 }
            }
            function activate() {} function openDetails() {} function openSettings() {}
        }
    }
}
