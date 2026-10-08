import QtQuick 2.9
import QtQuick.Window 2.2
import StreamHudStats 1.0
import StreamingPreferences 1.0

Window {
    id: hud
    // Not Qt.Tool: on macOS that is an NSPanel, which hides when the SDL
    // stream becomes the active app. The stream loop raises this window
    // over fullscreen after the SDL window exists.
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint
    color: "transparent"
    title: ""
    // Chips follow the Twilight overlay plus the runtime shortcut. The quick
    // menu uses this same window when the chips are hidden, so End Stream
    // stays reachable while the mouse is captured.
    visible: StreamHudStats.streaming && StreamingPreferences.uiVersion === "v2" && ((StreamingPreferences.showTwilightHud && StreamHudStats.hudShown) || StreamHudStats.quickMenuOpen)

    width: column.implicitWidth
    height: column.implicitHeight

    function place() {
        // On macOS the stream loop owns the frame. Setting x/y here uses the
        // desktop, which leaves the chips behind when the stream becomes PiP.
        if (Qt.platform.os === "osx") {
            StreamHudStats.followStream()
            return
        }
        var avail = Screen.desktopAvailableWidth
        if (avail <= 0)
            avail = width
        x = Math.round((avail - width) / 2)
        y = 28
    }

    onVisibleChanged: {
        if (visible) {
            place()
            StreamHudStats.orderFront()
        }
    }
    onWidthChanged: if (visible) place()

    Component.onCompleted: StreamHudStats.attachWindow(hud)

    Column {
        id: column
        spacing: 6

        HudChipsV2 {
            id: chips
            visible: StreamingPreferences.showTwilightHud && StreamHudStats.hudShown
        }

        Rectangle {
            id: quickMenu
            visible: StreamHudStats.quickMenuOpen
            width: 240
            height: visible ? menuColumn.implicitHeight + 20 : 0
            radius: 16
            color: chips.glass
            border.width: 1
            border.color: chips.edge

            Column {
                id: menuColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 8

                Text {
                    width: parent.width
                    text: qsTr("Stream")
                    color: chips.mute
                    font.pixelSize: 12
                    font.family: chips.uiFont
                }
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 10
                    color: chips.danger
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("End Stream")
                        color: "#FFFFFF"
                        font.pixelSize: 14
                        font.family: chips.uiFont
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: StreamHudStats.endStreamFromMenu()
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 10
                    color: "transparent"
                    border.width: 1
                    border.color: chips.edge
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Close")
                        color: chips.ink
                        font.pixelSize: 14
                        font.family: chips.uiFont
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: StreamHudStats.closeQuickMenu()
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Esc or Select+Start closes this. A ends the stream.")
                    color: chips.mute
                    font.pixelSize: 11
                    font.family: chips.uiFont
                }
            }
        }

        Text {
            visible: chips.visible && StreamHudStats.hasSample && StreamHudStats.codecText !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: StreamHudStats.codecText
            color: chips.mute
            font.pixelSize: 11
            font.family: chips.uiFont
        }
    }
}
