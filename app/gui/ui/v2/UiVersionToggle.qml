import QtQuick 2.9

Item {
    id: root
    property bool darkChrome: true
    property string currentVersion: "v2"
    signal requestVersion(string version)

    implicitWidth: 208
    implicitHeight: 32

    readonly property color track: darkChrome ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color ink: darkChrome ? "#F5F5F7" : "#1C1C1E"
    readonly property color mute: darkChrome ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.52)
    readonly property color pill: darkChrome ? Qt.rgba(1, 1, 1, 0.18) : "#FFFFFF"
    readonly property color edge: darkChrome ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.track
        border.width: 1
        border.color: root.edge

        Rectangle {
            id: pill
            y: 3
            width: (parent.width - 6) / 2
            height: parent.height - 6
            radius: height / 2
            color: root.pill
            border.width: root.darkChrome ? 0 : 1
            border.color: root.edge
            x: root.currentVersion === "v2" ? 3 : parent.width - width - 3
            Behavior on x {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: 3

        Item {
            width: parent.width / 2
            height: parent.height
            TwTextV2 {
                anchors.centerIn: parent
                text: qsTr("Twilight")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: root.currentVersion === "v2" ? root.ink : root.mute
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requestVersion("v2")
            }
        }

        Item {
            width: parent.width / 2
            height: parent.height
            TwTextV2 {
                anchors.centerIn: parent
                text: qsTr("Classic")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: root.currentVersion === "v1" ? root.ink : root.mute
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requestVersion("v1")
            }
        }
    }
}
