import QtQuick 2.9

// System palette, 8pt grid, SF Pro on macOS via the system UI font.
// Glass is a translucent fill plus a hairline. Qt GraphicalEffects is not
// a dependency of this client, so this does not use a backdrop blur.
// Item, not QtObject: Qt 5.9 will not instantiate SystemPalette as a
// property value inside a QtObject, and that took the whole shell down.
Item {
    id: theme
    width: 0
    height: 0

    SystemPalette {
        id: pal
        colorGroup: SystemPalette.Active
    }

    readonly property real luminance: pal.window.r * 0.2126 + pal.window.g * 0.7152 + pal.window.b * 0.0722
    readonly property bool dark: luminance < 0.45

    readonly property string fontFamily: {
        var os = Qt.platform.os
        if (os === "osx" || os === "macos")
            return ".AppleSystemUIFont"
        if (os === "windows")
            return "Segoe UI"
        return ""
    }

    readonly property int space: 8
    readonly property int radius: 16
    readonly property int sidebarWidth: 280

    readonly property color ink: pal.windowText
    readonly property color bg: dark ? Qt.tint(pal.window, "#22101828") : Qt.tint(pal.window, "#14FFFFFF")
    readonly property color wash: dark ? Qt.rgba(0.35, 0.48, 0.95, 0.22) : Qt.rgba(0.20, 0.42, 0.95, 0.14)
    readonly property color accent: dark ? "#9EBEFF" : "#0B57D0"
    readonly property color accentInk: dark ? "#07111F" : "#FFFFFF"
    readonly property color online: dark ? "#32D74B" : "#1B7F34"
    readonly property color offline: Qt.rgba(ink.r, ink.g, ink.b, 0.35)
    readonly property color warn: dark ? "#FFB340" : "#C45500"
    readonly property color danger: dark ? "#FF6961" : "#D70015"

    readonly property color secondary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.68 : 0.62)
    readonly property color tertiary: Qt.rgba(ink.r, ink.g, ink.b, 0.42)
    readonly property color fill: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.08 : 0.05)
    readonly property color fillStrong: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.14 : 0.08)
    readonly property color stroke: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.16 : 0.12)
    readonly property color sheen: Qt.rgba(1, 1, 1, dark ? 0.16 : 0.7)
    readonly property color glass: dark ? Qt.rgba(0.09, 0.10, 0.13, 0.72) : Qt.rgba(1, 1, 1, 0.74)
    readonly property color elevated: dark ? Qt.rgba(0.12, 0.13, 0.16, 0.96) : Qt.rgba(0.99, 0.99, 1, 0.97)
    // Settings sheet only. Fully opaque so the host behind the panel cannot show through.
    readonly property color sheetSurface: dark ? "#1F2129" : "#FCFCFF"
    readonly property color sidebar: dark ? Qt.rgba(0.07, 0.08, 0.10, 0.66) : Qt.rgba(1, 1, 1, 0.62)
    readonly property color scrim: Qt.rgba(0, 0, 0, dark ? 0.46 : 0.28)
    readonly property color selection: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.22 : 0.14)
    readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
}
