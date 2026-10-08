import QtQuick 2.9

Item {
    id: sheet
    property var theme
    property bool open: false
    property string hostName: ""
    property bool online: false
    property bool paired: false
    property bool wakeable: false
    property bool busy: false
    property bool statusUnknown: false
    property bool supported: true
    property string details: ""
    property bool showHidden: false
    property string wakeNotice: ""
    property bool wakeNoticeSent: false
    property bool escapeEnabled: true
    // False while a dialog is covering the sheet, so this chain does not steal keys.
    property bool keysOn: false
    property int focusPos: 0

    signal closeRequested()
    signal wakeRequested()
    signal pairRequested()
    signal testRequested()
    signal renameRequested()
    signal deleteRequested()
    signal showHiddenToggled(bool next)
    signal quitRequested()

    anchors.fill: parent
    visible: open || hideTimer.running
    opacity: open ? 1 : 0
    enabled: open
    z: 20
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    onBusyChanged: if (open) paintFocus()
    onOpenChanged: {
        if (open) {
            focusPos = 0
            paintFocus()
            keySink.forceActiveFocus()
        }
        else {
            hideTimer.start()
        }
    }
    onKeysOnChanged: if (keysOn) keySink.forceActiveFocus()
    Timer { id: hideTimer; interval: 180 }

    function chain() {
        var ids = []
        if (wakeAction.visible)
            ids.push("wake")
        if (pairAction.visible)
            ids.push("pair")
        if (quitAction.visible)
            ids.push("quit")
        ids.push("test")
        ids.push("rename")
        ids.push("hidden")
        ids.push("remove")
        ids.push("close")
        return ids
    }

    function paintFocus() {
        var ids = chain()
        if (focusPos < 0)
            focusPos = 0
        if (focusPos >= ids.length)
            focusPos = Math.max(0, ids.length - 1)
        var id = ids.length > 0 ? ids[focusPos] : ""
        wakeAction.keyed = id === "wake"
        pairAction.keyed = id === "pair"
        quitAction.keyed = id === "quit"
        testAction.keyed = id === "test"
        renameAction.keyed = id === "rename"
        hiddenSwitch.keyed = id === "hidden"
        removeAction.keyed = id === "remove"
        closeHit.keyed = id === "close"
    }

    function moveFocus(delta) {
        var ids = chain()
        if (ids.length === 0)
            return
        var next = focusPos + delta
        if (next < 0)
            next = 0
        if (next >= ids.length)
            next = ids.length - 1
        focusPos = next
        paintFocus()
    }

    function activateFocus() {
        var ids = chain()
        if (focusPos < 0 || focusPos >= ids.length)
            return
        var id = ids[focusPos]
        if (id === "wake")
            wakeAction.triggered()
        else if (id === "pair")
            pairAction.triggered()
        else if (id === "quit")
            quitAction.triggered()
        else if (id === "test")
            testAction.triggered()
        else if (id === "rename")
            renameAction.triggered()
        else if (id === "hidden")
            hiddenSwitch.activate()
        else if (id === "remove")
            removeAction.triggered()
        else if (id === "close")
            sheet.closeRequested()
    }

    Rectangle {
        anchors.fill: parent
        color: sheet.theme.scrim
        MouseArea { anchors.fill: parent; onClicked: sheet.closeRequested() }
    }

    Rectangle {
        id: panel
        width: Math.min(420, parent.width - 32)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 16
        radius: 20
        color: sheet.theme.elevated
        border.width: 1
        border.color: sheet.theme.stroke

        MouseArea { anchors.fill: parent }

        Item {
            anchors.fill: parent
            anchors.margins: 20

            Column {
                id: hostHeader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 8

            Item {
                width: parent.width
                height: 28
                TwTextV2 {
                    text: qsTr("Host")
                    theme: sheet.theme
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: sheet.theme.secondary
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    id: closeHit
                    property bool keyed: false
                    width: 32
                    height: 32
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: "transparent"
                        border.width: closeHit.keyed ? 2 : 0
                        border.color: sheet.theme.accent
                    }
                    SymbolV2 {
                        anchors.centerIn: parent
                        symbol: "xmark"
                        pointSize: 14
                        theme: sheet.theme
                        tint: sheet.theme.secondary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheet.closeRequested()
                    }
                }
            }

            TwTextV2 {
                width: parent.width
                theme: sheet.theme
                text: sheet.hostName
                font.pixelSize: 26
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            TwTextV2 {
                width: parent.width
                theme: sheet.theme
                color: sheet.theme.secondary
                font.pixelSize: 13
                text: sheet.statusUnknown ? qsTr("Looking for this computer…")
                      : (sheet.online && sheet.paired && sheet.busy) ? qsTr("Online · in a stream")
                      : (sheet.online && sheet.paired) ? qsTr("Online · ready")
                      : (sheet.online && !sheet.paired) ? qsTr("Online · not paired")
                      : sheet.wakeable ? qsTr("Asleep · Wake is available")
                      : qsTr("Offline")
            }

            }

            Flickable {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: hostHeader.bottom
                anchors.bottom: parent.bottom
                anchors.topMargin: 8
                contentWidth: width
                contentHeight: actions.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

            Column {
                id: actions
                width: parent.width
                spacing: 8

            HostActionV2 {
                id: wakeAction
                theme: sheet.theme
                symbol: "bolt.fill"
                title: qsTr("Wake")
                visible: !sheet.online && sheet.wakeable
                onTriggered: {
                    sheet.wakeNotice = ""
                    sheet.wakeRequested()
                }
            }
            TwTextV2 {
                width: parent.width
                visible: sheet.wakeNotice !== ""
                theme: sheet.theme
                color: sheet.wakeNoticeSent ? sheet.theme.secondary : sheet.theme.danger
                font.pixelSize: 13
                wrapMode: Text.Wrap
                text: sheet.wakeNotice
            }
            HostActionV2 {
                id: pairAction
                theme: sheet.theme
                symbol: "checkmark"
                title: qsTr("Pair")
                visible: !sheet.paired && sheet.online
                onTriggered: sheet.pairRequested()
            }
            HostActionV2 {
                id: quitAction
                theme: sheet.theme
                symbol: "stop.fill"
                title: qsTr("Quit running app")
                danger: true
                visible: sheet.online && sheet.paired && sheet.busy
                onTriggered: sheet.quitRequested()
            }
            HostActionV2 {
                id: testAction
                theme: sheet.theme
                symbol: "wifi"
                title: qsTr("Test network")
                onTriggered: sheet.testRequested()
            }
            HostActionV2 {
                id: renameAction
                theme: sheet.theme
                symbol: "pencil"
                title: qsTr("Rename")
                onTriggered: sheet.renameRequested()
            }

            SettingRowV2 {
                width: parent.width
                theme: sheet.theme
                title: qsTr("Show hidden apps")
                subtitle: qsTr("Hidden apps stay out of the library until this is on.")
                SwitchV2 {
                    id: hiddenSwitch
                    theme: sheet.theme
                    checked: sheet.showHidden
                    onToggled: sheet.showHiddenToggled(next)
                }
            }

            HostActionV2 {
                id: removeAction
                theme: sheet.theme
                symbol: "trash"
                title: qsTr("Remove host")
                danger: true
                onTriggered: sheet.deleteRequested()
            }

            TwTextV2 {
                id: detailsText
                width: parent.width
                theme: sheet.theme
                text: sheet.details
                color: sheet.theme.tertiary
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: sheet.open && sheet.escapeEnabled && sheet.keysOn
        onActivated: sheet.closeRequested()
    }

    Item {
        id: keySink
        focus: sheet.open && sheet.keysOn
        Keys.onPressed: {
            if (!sheet.open || !sheet.keysOn)
                return
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                sheet.moveFocus(-1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                sheet.moveFocus(1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                sheet.activateFocus()
                event.accepted = true
            }
            else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                sheet.closeRequested()
                event.accepted = true
            }
            else if (event.key === Qt.Key_Hangup) {
                event.accepted = true
            }
        }
    }
}
