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
    visible: StreamHudStats.streaming && StreamingPreferences.uiVersion === "v2" && StreamingPreferences.showTwilightHud

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

        HudChipsV2 { id: chips }

        Text {
            visible: StreamHudStats.hasSample && StreamHudStats.codecText !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: StreamHudStats.codecText
            color: chips.mute
            font.pixelSize: 11
            font.family: chips.uiFont
        }
    }
}
