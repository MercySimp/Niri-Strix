import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
// QtGamepad was dropped from Qt 6. Controller input is handled by the
// SDL2 GamepadHandler C++ backend injected as context property "Gamepad".
// Keyboard arrows/Enter/Escape provide the same actions for testing.

ApplicationWindow {
    id: root
    visible: true
    width: 1920
    height: 1080
    color: "#14161a"
    title: "Deck Shell"
    flags: Qt.Window

    // ── SDL2 controller signals (wired via GamepadHandler C++ backend) ──────
    Connections {
        target: Gamepad   // injected by main.cpp via engine.rootContext()
        ignoreUnknownSignals: true
        function onButtonA()     { stack.currentItem.activate() }
        function onButtonB()     { stack.pop() }
        function onButtonX()     { stack.currentItem.openDetails() }
        function onButtonY()     { stack.currentItem.openSettings() }
        function onDpadUp()      { navigator.moveUp() }
        function onDpadDown()    { navigator.moveDown() }
        function onDpadLeft()    { navigator.moveLeft() }
        function onDpadRight()   { navigator.moveRight() }
        function onAxisLeftY(v)  { navigator.handleAxis(v) }
    }

    // ── Keyboard fallback (arrow keys + Enter + Escape) ───────────────────
    Item {
        anchors.fill: parent
        focus: true
        Keys.onReturnPressed:  stack.currentItem.activate()
        Keys.onEscapePressed:  stack.pop()
        Keys.onUpPressed:      navigator.moveUp()
        Keys.onDownPressed:    navigator.moveDown()
        Keys.onLeftPressed:    navigator.moveLeft()
        Keys.onRightPressed:   navigator.moveRight()
    }

    // ── Focus navigator ───────────────────────────────────────────────────
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

    // ── Main page stack ───────────────────────────────────────────────────
    StackView {
        id: stack
        anchors.fill: parent
        initialItem: homePage
    }

    // ── Home ──────────────────────────────────────────────────────────────
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

                Text {
                    text: "\u2665  Deck Mode"
                    color: "#e8e8e8"
                    font.pixelSize: 52
                    font.bold: true
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
                            { label: "Power",      icon: "\u23FB" }
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
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    font.pixelSize: 36
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    color: "white"
                                    font.pixelSize: 22
                                    font.bold: activeFocus
                                }
                            }

                            Keys.onReturnPressed: clicked()
                            MouseArea { anchors.fill: parent; onClicked: parent.clicked() }

                            function clicked() {
                                if (modelData.label === "Library")   stack.push(libraryPage)
                                else if (modelData.label === "Settings") stack.push(settingsPage)
                                else if (modelData.label === "Power")    stack.push(powerPage)
                            }
                        }
                    }
                }

                // Recent / featured area placeholder
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#1a1e26"
                    radius: 12
                    Text {
                        anchors.centerIn: parent
                        text: "Recent Games"
                        color: "#555e6e"
                        font.pixelSize: 28
                    }
                }
            }

            function activate() {
                var item = root.activeFocusItem
                if (item && item.clicked) item.clicked()
            }
            function openDetails()  {}
            function openSettings() {}
        }
    }

    // ── Library ───────────────────────────────────────────────────────────
    Component {
        id: libraryPage
        FocusScope {
            anchors.fill: parent
            focus: true

            Rectangle { anchors.fill: parent; color: "#14161a" }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 60
                spacing: 28

                RowLayout {
                    Text {
                        text: "\u25C4"
                        color: "#5ba3ff"
                        font.pixelSize: 28
                        MouseArea { anchors.fill: parent; onClicked: stack.pop() }
                    }
                    Text {
                        text: "Library"
                        color: "#e8e8e8"
                        font.pixelSize: 44
                        font.bold: true
                    }
                }

                GridView {
                    id: gameGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cellWidth: 230
                    cellHeight: 290
                    focus: true
                    clip: true
                    model: 20

                    delegate: Rectangle {
                        width: 210
                        height: 270
                        color: GridView.isCurrentItem ? "#2a7bd9" : "#1f2531"
                        radius: 14
                        border.color: GridView.isCurrentItem ? "#5ba3ff" : "#2e3540"
                        border.width: GridView.isCurrentItem ? 3 : 1

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Rectangle {
                                width: parent.width
                                height: parent.height * 0.72
                                color: "#252c38"
                                radius: 10
                                Text {
                                    anchors.centerIn: parent
                                    text: "\uD83C\uDFAE"
                                    font.pixelSize: 48
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Game " + (index + 1)
                                color: "white"
                                font.pixelSize: 18
                                font.bold: GridView.isCurrentItem
                            }
                        }
                    }

                    Keys.onReturnPressed: currentItem.forceActiveFocus()
                }
            }

            function activate()     {}
            function openDetails()  {}
            function openSettings() {}
        }
    }

    // ── Settings ──────────────────────────────────────────────────────────
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

                RowLayout {
                    Text { text: "\u25C4"; color: "#5ba3ff"; font.pixelSize: 28
                        MouseArea { anchors.fill: parent; onClicked: stack.pop() } }
                    Text { text: "Settings"; color: "#e8e8e8"; font.pixelSize: 44; font.bold: true }
                }

                Repeater {
                    model: ["Display", "Audio", "Controller", "Network", "System"]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 72
                        color: activeFocus ? "#1f2e42" : "#191d26"
                        radius: 10
                        border.color: activeFocus ? "#5ba3ff" : "#2e3540"
                        focus: index === 0
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 28
                            text: modelData
                            color: "white"
                            font.pixelSize: 24
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 28
                            text: "\u276F"
                            color: "#5ba3ff"
                            font.pixelSize: 22
                        }
                    }
                }
            }

            function activate()     {}
            function openDetails()  {}
            function openSettings() {}
        }
    }

    // ── Power ─────────────────────────────────────────────────────────────
    Component {
        id: powerPage
        FocusScope {
            anchors.fill: parent
            focus: true

            Rectangle { anchors.fill: parent; color: "#0d0f13"; opacity: 0.97 }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 32

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "\u23FB  Power"
                    color: "#e8e8e8"
                    font.pixelSize: 44
                    font.bold: true
                }

                RowLayout {
                    spacing: 28

                    Repeater {
                        model: [
                            { label: "Shutdown",     cmd: "systemctl poweroff" },
                            { label: "Restart",       cmd: "systemctl reboot" },
                            { label: "Sleep",         cmd: "systemctl suspend" },
                            { label: "Exit Deck Mode", cmd: "" }
                        ]
                        delegate: Rectangle {
                            width: 220
                            height: 120
                            color: activeFocus ? "#c0392b" : "#1f2531"
                            radius: 14
                            border.color: activeFocus ? "#e74c3c" : "#2e3540"
                            border.width: activeFocus ? 3 : 1
                            focus: index === 0
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: "white"
                                font.pixelSize: 22
                                font.bold: activeFocus
                            }

                            Keys.onReturnPressed: doAction()
                            MouseArea { anchors.fill: parent; onClicked: parent.doAction() }

                            function doAction() {
                                if (modelData.cmd !== "") Qt.openUrlExternally("exec://" + modelData.cmd)
                                else Qt.quit()
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Press \u241B / B to cancel"
                    color: "#555e6e"
                    font.pixelSize: 20
                }
            }

            function activate()     {}
            function openDetails()  {}
            function openSettings() {}
        }
    }
}
