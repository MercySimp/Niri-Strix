import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtGamepad 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 1920
    height: 1080
    color: "#14161a"
    title: "Deck Shell"

    Gamepad {
        id: pad
        deviceId: GamepadManager.connectedGamepads.length > 0 ? GamepadManager.connectedGamepads[0] : -1
        onButtonAChanged: if (buttonA) focusItem.activate()
        onButtonBChanged: if (buttonB) stack.pop()
        onButtonXChanged: if (buttonX) stack.currentItem.openDetails()
        onButtonYChanged: if (buttonY) stack.currentItem.openSettings()
        onLeftStickYChanged: navigator.handleAxis(leftStickY)
        onLeftStickXChanged: navigator.handleAxis(leftStickX)
        onButtonDownChanged: if (buttonDown) navigator.moveDown()
        onButtonUpChanged: if (buttonUp) navigator.moveUp()
        onButtonLeftChanged: if (buttonLeft) navigator.moveLeft()
        onButtonRightChanged: if (buttonRight) navigator.moveRight()
    }

    // Simple focus manager for controller navigation
    QtObject {
        id: navigator
        function handleAxis(v) {
            if (v > 0.5) moveDown();
            else if (v < -0.5) moveUp();
        }
        function moveDown() { FocusScope.moveFocus(Qt.DownFocus); }
        function moveUp()   { FocusScope.moveFocus(Qt.UpFocus); }
        function moveLeft() { FocusScope.moveFocus(Qt.LeftFocus); }
        function moveRight(){ FocusScope.moveFocus(Qt.RightFocus); }
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

            Rectangle {
                anchors.fill: parent
                color: "#14161a"
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 40
                spacing: 40

                Text {
                    text: "Deck Mode"
                    color: "white"
                    font.pixelSize: 48
                }

                RowLayout {
                    spacing: 24

                    Repeater {
                        model: [
                            { label: "Library" },
                            { label: "Store" },
                            { label: "Downloads" },
                            { label: "Settings" },
                            { label: "Power" }
                        ]
                        delegate: Button {
                            text: modelData.label
                            Layout.preferredWidth: 260
                            Layout.preferredHeight: 140
                            font.pixelSize: 24
                            focus: index === 0
                            Keys.onReturnPressed: clicked()
                            onClicked: {
                                if (text === "Library") stack.push(libraryPage)
                                else if (text === "Settings") stack.push(settingsPage)
                                else if (text === "Power") stack.push(powerPage)
                            }
                        }
                    }
                }
            }

            function activate() {
                if (FocusScope.focusItem && FocusScope.focusItem.clicked)
                    FocusScope.focusItem.clicked()
            }

            function openDetails() {}
            function openSettings() {}
        }
    }

    Component {
        id: libraryPage
        FocusScope {
            anchors.fill: parent

            Rectangle { anchors.fill: parent; color: "#14161a" }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 40
                spacing: 24

                Text {
                    text: "Library"
                    color: "white"
                    font.pixelSize: 40
                }

                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cellWidth: 220
                    cellHeight: 280
                    model: 20
                    delegate: Rectangle {
                        width: 200
                        height: 260
                        color: focus ? "#2a7bd9" : "#1f2329"
                        radius: 12
                        border.color: "#3b4048"
                        focus: index === 0

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 16
                            text: "Game " + (index + 1)
                            color: "white"
                            font.pixelSize: 20
                        }
                    }
                }
            }

            function activate() {}
            function openDetails() {}
            function openSettings() {}
        }
    }

    Component {
        id: settingsPage
        FocusScope {
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 40
                spacing: 16
                Text { text: "Settings"; color: "white"; font.pixelSize: 40 }
                Text { text: "(Display, audio, controller mappings, network)"; color: "#aaaaaa"; font.pixelSize: 24 }
            }
            function activate() {}
            function openDetails() {}
            function openSettings() {}
        }
    }

    Component {
        id: powerPage
        FocusScope {
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "#14161a" }
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 24
                Text { text: "Power"; color: "white"; font.pixelSize: 40 }
                RowLayout {
                    spacing: 24
                    Button { text: "Shutdown" }
                    Button { text: "Restart" }
                    Button { text: "Exit Deck Mode"; onClicked: Qt.quit() }
                }
            }
            function activate() {}
            function openDetails() {}
            function openSettings() {}
        }
    }
}
