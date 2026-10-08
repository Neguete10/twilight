import QtQuick 2.9

Rectangle {
    id: action
    property var theme
    property string symbol: "info.circle"
    property string title: ""
    property bool danger: false
    property bool keyed: false
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? 44 : 0
    radius: 12
    color: keyed ? (theme ? theme.selection : "transparent")
                 : (area.containsMouse ? (theme ? theme.fill : "transparent") : "transparent")
    border.width: keyed ? 1 : 0
    border.color: theme ? theme.accent : "transparent"

    Row {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 10

        SymbolV2 {
            symbol: action.symbol
            pointSize: 16
            theme: action.theme
            tint: action.danger && action.theme ? action.theme.danger : (action.theme ? action.theme.ink : "white")
            anchors.verticalCenter: parent.verticalCenter
        }

        TwTextV2 {
            text: action.title
            theme: action.theme
            color: action.danger && action.theme ? action.theme.danger : (action.theme ? action.theme.ink : "white")
            font.pixelSize: 14
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: action.triggered()
    }
}
