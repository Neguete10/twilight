import QtQuick 2.9
import QtQuick.Window 2.2
import StreamHudStats 1.0
import StreamingPreferences 1.0

Window {
    id: hud
    flags: Qt.FramelessWindowHint | Qt.Tool | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint
    color: "transparent"
    title: ""
    visible: StreamHudStats.streaming && StreamingPreferences.uiVersion === "v2"

    width: column.implicitWidth
    height: column.implicitHeight

    function place() {
        var avail = Screen.desktopAvailableWidth
        if (avail <= 0)
            avail = width
        x = Math.round((avail - width) / 2)
        y = 28
    }

    onVisibleChanged: if (visible) place()
    onWidthChanged: if (visible) place()

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
