import QtQuick 2.9

Flow {
    id: root
    property var theme
    property var options: []
    property var current: undefined
    property bool enabled: true
    signal picked(variant value)

    spacing: 8
    opacity: enabled ? 1 : 0.45

    Repeater {
        model: root.options ? root.options.length : 0

        Rectangle {
            property var spec: root.options[index]
            property bool selected: spec && spec.value === root.current

            width: label.implicitWidth + 28
            height: 34
            radius: 10
            color: selected ? root.theme.accent : root.theme.fill
            border.width: 1
            border.color: selected ? root.theme.accent : root.theme.stroke

            TwTextV2 {
                id: label
                anchors.centerIn: parent
                theme: root.theme
                text: spec ? spec.text : ""
                font.pixelSize: 13
                font.weight: selected ? Font.DemiBold : Font.Normal
                color: selected ? root.theme.accentInk : root.theme.ink
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.enabled
                cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (spec) root.picked(spec.value)
            }
        }
    }
}
