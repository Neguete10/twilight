import QtQuick 2.9

Item {
    id: root
    property var theme
    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 500
    signal moved(real value)

    implicitHeight: 28
    height: 28

    function valueFromX(x) {
        var span = Math.max(1, width)
        var t = Math.max(0, Math.min(1, x / span))
        var raw = from + t * (to - from)
        var snapped = Math.round(raw / stepSize) * stepSize
        if (snapped < from)
            snapped = from
        if (snapped > to)
            snapped = to
        return snapped
    }

    readonly property real fraction: (to === from) ? 0 : Math.max(0, Math.min(1, (value - from) / (to - from)))

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: root.theme.fillStrong

        Rectangle {
            width: Math.max(4, parent.width * root.fraction)
            height: parent.height
            radius: 2
            color: root.theme.accent
        }
    }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(root.width - width, root.fraction * root.width - width / 2))
        color: "#FFFFFF"
        border.width: 1
        border.color: root.theme.stroke
    }

    MouseArea {
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        cursorShape: Qt.PointingHandCursor
        onPressed: root.moved(root.valueFromX(mouse.x))
        onPositionChanged: if (pressed) root.moved(root.valueFromX(mouse.x))
    }
}
