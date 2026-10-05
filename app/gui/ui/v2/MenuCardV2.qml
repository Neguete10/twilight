import QtQuick 2.9

// Couch menu. D-pad / arrows move, Return or Space picks, Escape dismisses.
// Entries are copied into a ListModel so a replaced array cannot alias every row.
Item {
    id: menu
    property var theme
    property bool open: false
    property string title: ""
    property var entries: []
    property int current: 0
    signal picked(string entryId)
    signal dismissed()

    anchors.fill: parent
    visible: open
    z: open ? 36 : 0

    ListModel { id: rows }

    function reload() {
        rows.clear()
        var first = 0
        var found = false
        if (!menu.entries)
            return
        for (var i = 0; i < menu.entries.length; i++) {
            var entry = menu.entries[i]
            if (!entry)
                continue
            var enabledEntry = entry.enabled !== false
            var action = entry["action"] ? ("" + entry["action"]) : ""
            rows.append({
                entryId: action,
                label: entry.text ? ("" + entry.text) : "",
                enabledEntry: enabledEntry ? "1" : "0"
            })
            if (enabledEntry && !found) {
                first = rows.count - 1
                found = true
            }
        }
        current = found ? first : 0
    }

    function move(delta) {
        if (rows.count === 0)
            return
        var next = current
        for (var step = 0; step < rows.count; step++) {
            next = next + delta
            if (next < 0)
                next = rows.count - 1
            else if (next >= rows.count)
                next = 0
            if (rows.get(next).enabledEntry === "1") {
                current = next
                return
            }
        }
    }

    function activate() {
        if (rows.count === 0)
            return
        if (current < 0 || current >= rows.count)
            return
        if (rows.get(current).enabledEntry !== "1")
            return
        menu.picked(rows.get(current).entryId)
    }

    onOpenChanged: {
        if (open) {
            reload()
            keySink.forceActiveFocus()
        }
    }
    onEntriesChanged: if (open) reload()

    Rectangle {
        anchors.fill: parent
        color: menu.theme ? menu.theme.scrim : "#66000000"
        MouseArea {
            anchors.fill: parent
            onClicked: menu.dismissed()
        }
    }

    Rectangle {
        id: card
        width: Math.min(360, parent.width - 48)
        anchors.centerIn: parent
        radius: 18
        color: menu.theme ? menu.theme.elevated : "#1C1C1E"
        border.width: 1
        border.color: menu.theme ? menu.theme.stroke : "#333"

        MouseArea { anchors.fill: parent }

        Column {
            id: column
            width: parent.width - 24
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 16
            spacing: 4

            TwTextV2 {
                width: parent.width
                leftPadding: 8
                visible: menu.title !== ""
                theme: menu.theme
                text: menu.title
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: menu.theme ? menu.theme.secondary : "#AAA"
                bottomPadding: 4
            }

            Repeater {
                model: rows
                Rectangle {
                    width: column.width
                    height: 40
                    radius: 10
                    color: menu.current === index
                           ? (menu.theme ? menu.theme.selection : "#333")
                           : (rowArea.containsMouse ? (menu.theme ? menu.theme.fill : "#222") : "transparent")
                    opacity: model.enabledEntry === "1" ? 1 : 0.4
                    TwTextV2 {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        theme: menu.theme
                        text: model.label
                        font.pixelSize: 14
                        font.weight: menu.current === index ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        enabled: model.enabledEntry === "1"
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            menu.current = index
                            menu.activate()
                        }
                    }
                }
            }

            Item { width: 1; height: 8 }
        }

        height: column.height + 16
    }

    Item {
        id: keySink
        focus: menu.open
        Keys.onPressed: {
            if (!menu.open)
                return
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                menu.move(-1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                menu.move(1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                menu.activate()
                event.accepted = true
            }
            else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                menu.dismissed()
                event.accepted = true
            }
            else if (event.key === Qt.Key_Hangup || event.key === Qt.Key_Menu) {
                event.accepted = true
            }
        }
    }
}
