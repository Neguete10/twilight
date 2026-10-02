import QtQuick 2.9

Item {
    id: dialog
    property var theme
    property bool open: false
    property string title: ""
    property string message: ""
    property string hero: ""
    property string confirmText: qsTr("OK")
    property string cancelText: qsTr("Cancel")
    property bool showConfirm: true
    property bool showCancel: true
    property bool danger: false
    property bool field: false
    property string fieldText: ""
    property string fieldPlaceholder: ""
    signal confirmed()
    signal canceled()

    anchors.fill: parent
    visible: open
    z: open ? 40 : 0

    function close() {
        canceled()
    }

    onOpenChanged: {
        if (open && field) {
            fieldInput.text = fieldText
            fieldInput.forceActiveFocus()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: dialog.theme ? dialog.theme.scrim : "#66000000"
        MouseArea {
            anchors.fill: parent
            onClicked: dialog.canceled()
        }
    }

    Rectangle {
        id: card
        width: Math.min(460, parent.width - 48)
        anchors.centerIn: parent
        radius: 20
        color: dialog.theme ? dialog.theme.elevated : "#1C1C1E"
        border.width: 1
        border.color: dialog.theme ? dialog.theme.stroke : "#333"

        Column {
            id: column
            width: parent.width - 48
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 24
            spacing: 12

            TwTextV2 {
                width: parent.width
                theme: dialog.theme
                text: dialog.title
                font.pixelSize: 20
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            TwTextV2 {
                width: parent.width
                visible: dialog.hero !== ""
                theme: dialog.theme
                text: dialog.hero
                font.pixelSize: 36
                font.weight: Font.Bold
                font.letterSpacing: 4
                horizontalAlignment: Text.AlignHCenter
                color: dialog.theme ? dialog.theme.accent : "#9EBEFF"
            }

            TwTextV2 {
                width: parent.width
                theme: dialog.theme
                text: dialog.message
                color: dialog.theme ? dialog.theme.secondary : "#AAA"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }

            Rectangle {
                visible: dialog.field
                width: parent.width
                height: visible ? 40 : 0
                radius: 10
                color: dialog.theme ? dialog.theme.field : "#222"
                border.width: 1
                border.color: fieldInput.activeFocus ? dialog.theme.accent : dialog.theme.stroke

                TextInput {
                    id: fieldInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: dialog.theme ? dialog.theme.ink : "white"
                    font.family: dialog.theme ? dialog.theme.fontFamily : ""
                    font.pixelSize: 14
                    selectByMouse: true
                    onTextChanged: dialog.fieldText = text
                    Keys.onReturnPressed: if (dialog.showConfirm) dialog.confirmed()
                    Keys.onEnterPressed: if (dialog.showConfirm) dialog.confirmed()
                }

                TwTextV2 {
                    anchors.fill: fieldInput
                    enabled: false
                    visible: fieldInput.text === ""
                    theme: dialog.theme
                    text: dialog.fieldPlaceholder
                    color: dialog.theme ? dialog.theme.tertiary : "#888"
                    font.pixelSize: 14
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Item { width: 1; height: 4 }

            Row {
                anchors.right: parent.right
                spacing: 8

                Rectangle {
                    visible: dialog.showCancel
                    width: cancelLabel.implicitWidth + 28
                    height: 36
                    radius: 10
                    color: cancelArea.containsMouse ? dialog.theme.fillStrong : "transparent"
                    border.width: 1
                    border.color: dialog.theme.stroke
                    TwTextV2 {
                        id: cancelLabel
                        anchors.centerIn: parent
                        theme: dialog.theme
                        text: dialog.cancelText
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dialog.canceled()
                    }
                }

                Rectangle {
                    visible: dialog.showConfirm
                    width: confirmLabel.implicitWidth + 28
                    height: 36
                    radius: 10
                    color: dialog.danger ? dialog.theme.danger : dialog.theme.accent
                    TwTextV2 {
                        id: confirmLabel
                        anchors.centerIn: parent
                        theme: dialog.theme
                        text: dialog.confirmText
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: dialog.danger ? "#FFFFFF" : dialog.theme.accentInk
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dialog.confirmed()
                    }
                }
            }

            Item { width: 1; height: 8 }
        }

        height: column.height + 24
    }

    Shortcut {
        sequence: "Escape"
        enabled: dialog.open
        onActivated: dialog.canceled()
    }
}
