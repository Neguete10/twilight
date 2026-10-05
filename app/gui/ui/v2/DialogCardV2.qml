import QtQuick 2.9

import SystemProperties 1.0

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
    property bool field2: false
    property string field2Text: ""
    property string field2Placeholder: ""
    property bool digitsOnly: false
    property int fieldMinimum: 0
    property int fieldMaximum: 99999
    property int field2Minimum: 0
    property int field2Maximum: 99999
    property string helpUrl: ""
    property string helpText: ""
    // Which control the couch cursor is on: field, field2, help, cancel, confirm.
    property string focusSlot: "confirm"
    signal confirmed()
    signal canceled()
    property int layer: 40

    anchors.fill: parent
    visible: open
    z: open ? layer : 0

    readonly property bool helpVisible: helpUrl !== "" && SystemProperties.hasBrowser

    function close() {
        canceled()
    }

    function focusOrder() {
        var order = []
        if (field)
            order.push("field")
        if (field && field2)
            order.push("field2")
        if (helpVisible)
            order.push("help")
        if (showCancel)
            order.push("cancel")
        if (showConfirm)
            order.push("confirm")
        return order
    }

    function moveFocus(delta) {
        var order = focusOrder()
        if (order.length === 0)
            return
        var index = 0
        for (var i = 0; i < order.length; i++) {
            if (order[i] === focusSlot)
                index = i
        }
        index = index + delta
        if (index < 0)
            index = order.length - 1
        else if (index >= order.length)
            index = 0
        focusSlot = order[index]
        applyFocusSlot()
    }

    function applyFocusSlot() {
        if (focusSlot === "field")
            fieldInput.forceActiveFocus()
        else if (focusSlot === "field2")
            field2Input.forceActiveFocus()
        else
            keySink.forceActiveFocus()
    }

    function activateSlot() {
        if (focusSlot === "help") {
            Qt.openUrlExternally(helpUrl)
            dialog.canceled()
        }
        else if (focusSlot === "cancel")
            dialog.canceled()
        else if (focusSlot === "confirm" && showConfirm)
            dialog.confirmed()
        else if (focusSlot === "field" && field2)
            moveFocus(1)
        else if (showConfirm)
            dialog.confirmed()
    }

    function armOnOpen() {
        if (field) {
            fieldInput.text = fieldText
            focusSlot = "field"
        }
        if (field2)
            field2Input.text = field2Text
        if (!field) {
            if (showConfirm)
                focusSlot = "confirm"
            else if (showCancel)
                focusSlot = "cancel"
            else if (helpVisible)
                focusSlot = "help"
        }
        applyFocusSlot()
    }

    onOpenChanged: {
        if (open)
            armOnOpen()
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
        width: Math.min(480, parent.width - 48)
        anchors.centerIn: parent
        radius: 20
        color: dialog.theme ? dialog.theme.elevated : "#1C1C1E"
        border.width: 1
        border.color: dialog.theme ? dialog.theme.stroke : "#333"

        MouseArea { anchors.fill: parent }

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
                textFormat: Text.PlainText
                color: dialog.theme ? dialog.theme.secondary : "#AAA"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }

            TwTextV2 {
                width: parent.width
                visible: dialog.helpText !== "" && dialog.helpVisible
                theme: dialog.theme
                text: dialog.helpText
                color: dialog.theme ? dialog.theme.secondary : "#AAA"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Row {
                visible: dialog.field
                width: parent.width
                spacing: 8

                Rectangle {
                    width: dialog.field2 ? (parent.width - 8) / 2 : parent.width
                    height: visible ? 40 : 0
                    radius: 10
                    color: dialog.theme ? dialog.theme.field : "#222"
                    border.width: fieldInput.activeFocus ? 2 : 1
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
                        inputMethodHints: dialog.digitsOnly ? Qt.ImhDigitsOnly : Qt.ImhNone
                        validator: dialog.digitsOnly ? fieldValidator : null
                        onTextChanged: dialog.fieldText = text
                        onActiveFocusChanged: if (activeFocus) dialog.focusSlot = "field"
                        Keys.onReturnPressed: dialog.activateSlot()
                        Keys.onEnterPressed: dialog.activateSlot()
                        Keys.onEscapePressed: dialog.canceled()
                        Keys.onDownPressed: dialog.moveFocus(1)
                        Keys.onTabPressed: dialog.moveFocus(1)
                        Keys.onBacktabPressed: dialog.moveFocus(-1)
                        Keys.onUpPressed: dialog.moveFocus(-1)
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

                Rectangle {
                    visible: dialog.field2
                    width: (parent.width - 8) / 2
                    height: visible ? 40 : 0
                    radius: 10
                    color: dialog.theme ? dialog.theme.field : "#222"
                    border.width: field2Input.activeFocus ? 2 : 1
                    border.color: field2Input.activeFocus ? dialog.theme.accent : dialog.theme.stroke

                    TextInput {
                        id: field2Input
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: dialog.theme ? dialog.theme.ink : "white"
                        font.family: dialog.theme ? dialog.theme.fontFamily : ""
                        font.pixelSize: 14
                        selectByMouse: true
                        inputMethodHints: dialog.digitsOnly ? Qt.ImhDigitsOnly : Qt.ImhNone
                        validator: dialog.digitsOnly ? field2Validator : null
                        onTextChanged: dialog.field2Text = text
                        onActiveFocusChanged: if (activeFocus) dialog.focusSlot = "field2"
                        Keys.onReturnPressed: dialog.activateSlot()
                        Keys.onEnterPressed: dialog.activateSlot()
                        Keys.onEscapePressed: dialog.canceled()
                        Keys.onDownPressed: dialog.moveFocus(1)
                        Keys.onTabPressed: dialog.moveFocus(1)
                        Keys.onBacktabPressed: dialog.moveFocus(-1)
                        Keys.onUpPressed: dialog.moveFocus(-1)
                    }

                    TwTextV2 {
                        anchors.fill: field2Input
                        enabled: false
                        visible: field2Input.text === ""
                        theme: dialog.theme
                        text: dialog.field2Placeholder
                        color: dialog.theme ? dialog.theme.tertiary : "#888"
                        font.pixelSize: 14
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Item { width: 1; height: 4 }

            Row {
                anchors.right: parent.right
                spacing: 8

                Rectangle {
                    visible: dialog.helpVisible
                    width: helpLabel.implicitWidth + 28
                    height: 36
                    radius: 10
                    color: helpArea.containsMouse ? dialog.theme.fillStrong : "transparent"
                    border.width: dialog.focusSlot === "help" ? 2 : 1
                    border.color: dialog.focusSlot === "help" ? dialog.theme.accent : dialog.theme.stroke
                    TwTextV2 {
                        id: helpLabel
                        anchors.centerIn: parent
                        theme: dialog.theme
                        text: qsTr("Help")
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: dialog.theme.accent
                    }
                    MouseArea {
                        id: helpArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dialog.focusSlot = "help"
                            dialog.activateSlot()
                        }
                    }
                }

                Rectangle {
                    visible: dialog.showCancel
                    width: cancelLabel.implicitWidth + 28
                    height: 36
                    radius: 10
                    color: cancelArea.containsMouse ? dialog.theme.fillStrong : "transparent"
                    border.width: dialog.focusSlot === "cancel" ? 2 : 1
                    border.color: dialog.focusSlot === "cancel" ? dialog.theme.accent : dialog.theme.stroke
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
                    border.width: dialog.focusSlot === "confirm" ? 2 : 0
                    border.color: dialog.theme.ink
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

    IntValidator {
        id: fieldValidator
        bottom: dialog.fieldMinimum
        top: dialog.fieldMaximum
    }
    IntValidator {
        id: field2Validator
        bottom: dialog.field2Minimum
        top: dialog.field2Maximum
    }

    Item {
        id: keySink
        focus: dialog.open && dialog.focusSlot !== "field" && dialog.focusSlot !== "field2"
        Keys.onPressed: {
            if (!dialog.open)
                return
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                dialog.canceled()
                event.accepted = true
            }
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab
                     || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                dialog.moveFocus(-1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                dialog.moveFocus(1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                dialog.activateSlot()
                event.accepted = true
            }
            else if (event.key === Qt.Key_Hangup || event.key === Qt.Key_Menu) {
                event.accepted = true
            }
        }
    }
}
