import QtQuick 2.9

Text {
    id: label
    property var theme: null

    color: theme ? theme.ink : "#F2F2F7"
    // Assigning "" or the generic alias "Sans Serif" makes Qt 6.11 warn.
    Binding on font.family {
        when: label.theme && label.theme.fontFamily !== ""
        value: label.theme.fontFamily
    }
    font.pixelSize: 14
    font.weight: Font.Normal
    elide: Text.ElideNone
    wrapMode: Text.NoWrap
}
