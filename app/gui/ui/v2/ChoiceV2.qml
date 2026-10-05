import QtQuick 2.9

Flow {
    id: root
    property var theme
    property var options: []
    property var current: undefined
    property bool enabled: true
    signal picked(variant value)

    // keyIndex < 0 means the selected chip is the couch cursor.
    property bool keyed: false
    property int keyIndex: -1

    function clearKey() {
        keyIndex = -1
    }

    function selectedRow() {
        for (var i = 0; i < rows.count; i++) {
            if (rows.get(i).choice == root.current)
                return i
        }
        return 0
    }

    function moveKey(dir) {
        if (!root.enabled || rows.count === 0)
            return
        var next = keyIndex < 0 ? selectedRow() : keyIndex + dir
        if (next < 0)
            next = 0
        if (next >= rows.count)
            next = rows.count - 1
        keyIndex = next
    }

    function optionValue(i) {
        // Read at the moment of the pick. A binding on options[index] inside
        // the delegate aliases every chip to the last preset.
        if (root.options && i >= 0 && i < root.options.length && root.options[i])
            return root.options[i].value
        if (i >= 0 && i < rows.count)
            return rows.get(i).choice
        return undefined
    }

    function pickKey() {
        if (!root.enabled || rows.count === 0)
            return
        if (keyIndex < 0)
            keyIndex = selectedRow()
        root.picked(optionValue(keyIndex))
    }

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
                // ListModel roles keep the type of the first value. Mixed
                // numbers and the "custom" sentinel would collapse, so every
                // choice is stored as text and compared with ==.
                choice: row.value === undefined || row.value === null ? "" : ("" + row.value)
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
            border.width: (root.keyed && (index === root.keyIndex || (root.keyIndex < 0 && selected))) ? 2 : 1
            border.color: (root.keyed && (index === root.keyIndex || (root.keyIndex < 0 && selected)))
                           ? root.theme.ink
                           : (selected ? root.theme.accent : root.theme.stroke)

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
                onClicked: root.picked(root.optionValue(index))
            }
        }
    }
}
