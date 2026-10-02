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

    signal closeRequested()
    signal wakeRequested()
    signal pairRequested()
    signal testRequested()
    signal renameRequested()
    signal deleteRequested()
    signal showHiddenToggled(bool next)

    anchors.fill: parent
    visible: open || hideTimer.running
    opacity: open ? 1 : 0
    enabled: open
    z: 20
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    onOpenChanged: if (!open) hideTimer.start()
    Timer { id: hideTimer; interval: 180 }

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
                    width: 32
                    height: 32
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
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
                theme: sheet.theme
                symbol: "bolt.fill"
                title: qsTr("Wake")
                visible: !sheet.online && sheet.wakeable
                onTriggered: sheet.wakeRequested()
            }
            HostActionV2 {
                theme: sheet.theme
                symbol: "checkmark"
                title: qsTr("Pair")
                visible: !sheet.paired && sheet.online
                onTriggered: sheet.pairRequested()
            }
            HostActionV2 {
                theme: sheet.theme
                symbol: "wifi"
                title: qsTr("Test network")
                onTriggered: sheet.testRequested()
            }
            HostActionV2 {
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
                    theme: sheet.theme
                    checked: sheet.showHidden
                    onToggled: sheet.showHiddenToggled(next)
                }
            }

            HostActionV2 {
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
        enabled: sheet.open
        onActivated: sheet.closeRequested()
    }
}
