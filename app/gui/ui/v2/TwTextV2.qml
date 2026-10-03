import QtQuick 2.9

Text {
    id: label
    property var theme: null

    color: theme ? theme.ink : "#F2F2F7"
    font.family: (theme && theme.fontFamily) ? theme.fontFamily : ""
    font.pixelSize: 14
    font.weight: Font.Normal
    elide: Text.ElideNone
    wrapMode: Text.NoWrap
}
