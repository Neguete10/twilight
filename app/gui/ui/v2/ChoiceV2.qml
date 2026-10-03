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

    // Copy each option into its own row. Reading options[index] from a
    // delegate after the array is replaced makes every chip see the last
    // entry, and the last resolution preset is 4K.
    ListModel { id: rows }

    function reloadRows() {
        rows.clear()
        if (!root.options)
            return
        for (var i = 0; i < root.options.length; i++) {
            var row = root.options[i]
            if (!row)
                continue
            rows.append({
                label: row.text ? row.text : "",
                choice: row.value
            })
        }
    }

    onOptionsChanged: reloadRows()
    Component.onCompleted: reloadRows()

    Repeater {
        model: rows

        Rectangle {
            property bool selected: model.choice == root.current

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
                text: model.label
                font.pixelSize: 13
                font.weight: selected ? Font.DemiBold : Font.Normal
                color: selected ? root.theme.accentInk : root.theme.ink
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.enabled
                cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.picked(model.choice)
            }
        }
    }
}
