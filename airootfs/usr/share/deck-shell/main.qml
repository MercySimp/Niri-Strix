import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: root
    visible: true
    width: 1920
    height: 1080
    color: "#14161a"
    title: "Deck Shell"
    flags: Qt.Window

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
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onReturnPressed: stack.currentItem.activate()
        Keys.onEscapePressed: stack.pop()
        Keys.onUpPressed:     navigator.moveUp()
        Keys.onDownPressed:   navigator.moveDown()
        Keys.onLeftPressed:   navigator.moveLeft()
        Keys.onRightPressed:  navigator.moveRight()
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
                Text { text: "\u2665  Deck Mode"; color: "#e8e8e8"; font.pixelSize: 52; font.bold: true }
                RowLayout {
                    spacing: 28
                    Layout.fillWidth: true
                    Repeater {
                        model: [
                            { label: "Library",    icon: "\uD83C\uDFAE" },
                            { label: "Store",       icon: "\uD83D\uDED2" },
                            { label: "Downloads",   icon: "\u2B07" },
                            { label: "Settings",    icon: "\u2699" },
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
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 44
                                color: "#cc14161a"
                                radius: 10
                                Text { anchors.centerIn: parent; text: name; color: "white"; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter }
                            }
                            MouseArea { anchors.fill: parent; onClicked: SteamLibrary.launchGame(appId) }
                        }
                    }
                    Text {
                        visible: recentList.count === 0 || SteamLibrary.loading
                        text: SteamLibrary.loading ? "Loading library\u2026" : "No recent games — head to Library to play something!"
                        color: "#555e6e"
                        font.pixelSize: 22
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
            function activate()     { var item = root.activeFocusItem; if (item && item.doNav) item.doNav() }
            function openDetails()  {}
            function openSettings() { stack.push(settingsPage) }
        }
    }

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
                    Rectangle { width: 120; height: 44; color: "#1f2531"; radius: 10; border.color: "#2e3540"; Text { anchors.centerIn: parent; text: "\u21BA  Refresh"; color: "#8a9bb5"; font.pixelSize: 18 }; MouseArea { anchors.fill: parent; onClicked: SteamLibrary.refresh() } }
                }

                RowLayout {
                    spacing: 16
                    Layout.fillWidth: true
                    Text { text: "LB: Installed"; color: "#8a9bb5"; font.pixelSize: 18 }
                    Text { text: "RB: All Owned"; color: "#8a9bb5"; font.pixelSize: 18 }
                }

                Item {
                    anchors.fill: parent
                    Keys.onPressed: function(ev) {
                        if (ev.key === Qt.Key_Q) {
                            SteamLibrary.filterMode = 0; // InstalledOnly
                            ev.accepted = true;
                        } else if (ev.key === Qt.Key_E) {
                            SteamLibrary.filterMode = 1; // AllOwned
                            ev.accepted = true;
                        }
                    }
                }

                Text {
                    visible: SteamLibrary.loading
                    text: "Fetching Steam library\u2026"
                    color: "#8a9bb5"
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignHCenter
                }

                GridView {
                    id: gameGrid
                    visible: !SteamLibrary.loading && SteamLibrary.count > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cellWidth: 200
                    cellHeight: 300
                    focus: true
                    clip: true
                    model: SteamLibrary
                    delegate: Rectangle {
                        width: 184
                        height: 284
                        color: GridView.isCurrentItem ? "#1e2e45" : "#1a1e28"
                        radius: 12
                        border.color: GridView.isCurrentItem ? "#5ba3ff" : "#2e3540"
                        border.width: GridView.isCurrentItem ? 3 : 1
                        clip: true
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Image {
                            id: coverImg
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: parent.height * 0.78
                            source: coverUrl
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            asynchronous: true
                            Rectangle { anchors.fill: parent; color: "#252c38"; visible: coverImg.status !== Image.Ready; Text { anchors.centerIn: parent; text: "\uD83C\uDFAE"; font.pixelSize: 52 } }
                        }
                        Text {
                            anchors.top: coverImg.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 8
                            text: name
                            color: installed ? "white" : "#b0b8c8"
                            font.pixelSize: 15
                            font.bold: GridView.isCurrentItem
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Rectangle {
                            visible: !installed
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 16
                            height: 24
                            radius: 8
                            color: "#1f2531"
                            border.color: "#2e3540"
                            Text { anchors.centerIn: parent; text: "Not installed"; color: "#8a9bb5"; font.pixelSize: 13 }
                        }
                        Keys.onReturnPressed: installed ? SteamLibrary.launchGame(appId) : SteamLibrary.installGame(appId)
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { gameGrid.currentIndex = index; gameGrid.forceActiveFocus() }
                            onDoubleClicked: installed ? SteamLibrary.launchGame(appId) : SteamLibrary.installGame(appId)
                        }
                    }
                }
            }
            function activate() {
                if (gameGrid.currentItem) {
                    if (gameGrid.currentItem.installed)
                        SteamLibrary.launchGame(gameGrid.currentItem.appId)
                    else
                        SteamLibrary.installGame(gameGrid.currentItem.appId)
                }
            }
            function openDetails()  {}
            function openSettings() {}
        }
    }

    Component {
        id: storePage
        FocusScope {
            anchors.fill: parent
            focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 28
                Text { text: "\uD83D\uDED2  Steam Store"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                Text { text: "Opens Steam's built-in store browser."; color: "#8a9bb5"; font.pixelSize: 22; Layout.alignment: Qt.AlignHCenter }
                Rectangle { width: 260; height: 64; radius: 14; color: "#2a7bd9"; Layout.alignment: Qt.AlignHCenter; Text { anchors.centerIn: parent; text: "Open Steam Store"; color: "white"; font.pixelSize: 24; font.bold: true }; MouseArea { anchors.fill: parent; onClicked: Qt.openUrlExternally("steam://store") }; Keys.onReturnPressed: Qt.openUrlExternally("steam://store"); focus: true }
                Rectangle { width: 140; height: 48; radius: 10; color: "#1f2531"; Layout.alignment: Qt.AlignHCenter; Text { anchors.centerIn: parent; text: "\u25C4 Back"; color: "#5ba3ff"; font.pixelSize: 20 }; MouseArea { anchors.fill: parent; onClicked: stack.pop() } }
            }
            function activate()     {}
            function openDetails()  {}
            function openSettings() {}
        }
    }

    Component {
        id: settingsPage
        FocusScope {
            anchors.fill: parent
            focus: true
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 60
                spacing: 28
                RowLayout { Text { text: "\u25C4"; color: "#5ba3ff"; font.pixelSize: 28; MouseArea { anchors.fill: parent; onClicked: stack.pop() } }; Text { text: "Settings"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true } }
                Repeater {
                    model: ["Display", "Audio", "Controller", "Network", "System"]
                    delegate: Rectangle { Layout.fillWidth: true; height: 72; color: activeFocus ? "#1f2e42" : "#191d26"; radius: 10; border.color: activeFocus ? "#5ba3ff" : "#2e3540"; focus: index === 0; Behavior on color { ColorAnimation { duration: 120 } }; Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 28; text: modelData; color: "white"; font.pixelSize: 24 }; Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: 28; text: "\u276F"; color: "#5ba3ff"; font.pixelSize: 22 } }
                }
            }
            function activate()     {}
            function openDetails()  {}
            function openSettings() {}
        }
    }

    Component {
        id: powerPage
        FocusScope {
            anchors.fill: parent
            focus: true
            Rectangle { anchors.fill: parent; color: "#0d0f13"; opacity: 0.97 }
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 32
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
            function activate()     {}
            function openDetails()  {}
            function openSettings() {}
        }
    }
}
