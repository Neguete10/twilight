import QtQuick 2.9

Item {
    id: root
    property var theme
    property bool checked: false
    property bool enabled: true
    property bool keyed: false
    signal toggled(bool next)

    function activate() {
        if (root.enabled)
            root.toggled(!root.checked)
    }

    width: 44
    height: 26
    opacity: enabled ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.theme.accent : root.theme.fillStrong
        border.width: root.keyed ? 2 : 1
        border.color: root.keyed ? root.theme.ink : (root.checked ? root.theme.accent : root.theme.stroke)

        Rectangle {
            width: 20
            height: 20
            radius: 10
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 3
            color: "#FFFFFF"
            Behavior on x {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled(!root.checked)
    }
}
