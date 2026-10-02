import QtQuick 2.9

Item {
    id: row
    property var theme
    property string title
    property string subtitle: ""
    property bool enabled: true
    property bool divider: true

    // Implementation items are assigned to `frame`, not the default property,
    // so callers can drop a switch or button into the trailing slot.
    // labelBlock is filled from inside the frame so the row height does not
    // depend on an id that Qt 5.9 cannot see from the outer object.
    property real labelBlock: 0
    default property alias controls: slot.data
    property Item frame: Item {
        parent: row
        anchors.fill: parent

        Column {
            id: textCol
            anchors.left: parent.left
            anchors.right: slot.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            TwTextV2 {
                width: textCol.width
                theme: row.theme
                text: row.title
                font.pixelSize: 14
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }

            TwTextV2 {
                width: textCol.width
                visible: row.subtitle !== ""
                theme: row.theme
                text: row.subtitle
                color: row.theme ? row.theme.secondary : "#888"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Binding {
            target: row
            property: "labelBlock"
            value: textCol.implicitHeight
        }

        Item {
            id: slot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: row.theme ? row.theme.stroke : "transparent"
            visible: row.divider
        }
    }

    implicitHeight: Math.max(56, labelBlock + 20)
    height: implicitHeight
    opacity: enabled ? 1 : 0.45
}
