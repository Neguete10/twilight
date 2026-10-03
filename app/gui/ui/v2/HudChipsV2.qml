import QtQuick 2.9
import StreamHudStats 1.0

Item {
    id: chips
    property bool preview: false
    property bool confirming: false

    readonly property bool dark: {
        var lum = palette.window.r * 0.2126 + palette.window.g * 0.7152 + palette.window.b * 0.0722
        return lum < 0.45
    }
    readonly property color ink: dark ? "#F5F5F7" : "#1C1C1E"
    readonly property color mute: dark ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color glass: dark ? Qt.rgba(0.08, 0.09, 0.12, 0.62) : Qt.rgba(1, 1, 1, 0.72)
    readonly property color edge: dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color danger: dark ? "#FF6961" : "#D70015"
    readonly property string uiFont: {
        var os = Qt.platform.os
        if (os === "osx" || os === "macos")
            return ".AppleSystemUIFont"
        if (os === "windows")
            return "Segoe UI"
        return ""
    }

    function chipText(live, sample) {
        if (preview)
            return sample
        if (!StreamHudStats.hasSample || live === "")
            return "—"
        return live
    }

    implicitWidth: bar.implicitWidth
    implicitHeight: bar.implicitHeight
    width: implicitWidth
    height: implicitHeight

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

    Rectangle {
        id: bar
        radius: 22
        color: chips.glass
        border.width: 1
        border.color: chips.edge
        implicitWidth: row.implicitWidth + 16
        implicitHeight: 44

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            height: 1
            color: Qt.rgba(1, 1, 1, chips.dark ? 0.2 : 0.85)
        }

        Row {
            id: row
            x: 8
            y: 6
            spacing: 8

            Repeater {
                model: 3

                Rectangle {
                    property string metricName: index === 0 ? "FPS" : (index === 1 ? "RATE" : "RTT")
                    property string metricValue: index === 0 ? chips.chipText(StreamHudStats.fpsText, "60")
                                              : (index === 1 ? chips.chipText(StreamHudStats.bitrateText, "18.4 Mb/s")
                                                             : chips.chipText(StreamHudStats.latencyText, "4 ms"))

                    radius: 14
                    height: 32
                    width: metric.implicitWidth + 20
                    color: chips.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55)

                    Row {
                        id: metric
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: metricName
                            color: chips.mute
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.family: chips.uiFont
                            font.letterSpacing: 0.6
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: metricValue
                            color: chips.ink
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.family: chips.uiFont
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            Rectangle {
                visible: !chips.preview
                radius: 14
                height: 32
                width: endLabel.implicitWidth + 22
                color: chips.confirming ? chips.danger : (chips.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55))
                Text {
                    id: endLabel
                    anchors.centerIn: parent
                    text: chips.confirming ? qsTr("End stream") : qsTr("End")
                    color: chips.confirming ? "#FFFFFF" : chips.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    font.family: chips.uiFont
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!chips.confirming) {
                            chips.confirming = true
                            confirmTimer.restart()
                        }
                        else {
                            StreamHudStats.requestDisconnect()
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: confirmTimer
        interval: 2200
        onTriggered: chips.confirming = false
    }
}
