import QtQuick 2.9
import QtQuick.Controls 2.2

import AutoUpdateChecker 1.0
import SystemProperties 1.0

// GPL-3.0 interactive notice plus the third-party license texts in qrc.
// The same files are copied to Contents/Resources/Licenses on macOS.
Item {
    id: root
    property var theme: null

    readonly property color bodyColor: theme ? theme.ink : palette.windowText
    readonly property color mutedColor: theme ? theme.secondary : palette.windowText
    readonly property color linkColor: theme ? theme.accent : palette.link

    property string licenseText: ""
    property string licenseFile: "GPL-3.0.txt"
    property string noticesText: ""

    width: parent ? parent.width : implicitWidth
    implicitHeight: column.implicitHeight
    height: column.implicitHeight

    SystemPalette {
        id: palette
        colorGroup: SystemPalette.Active
    }

    function loadText(fileName) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "qrc:/licenses/" + fileName, false)
        xhr.send()
        if (!xhr.responseText)
            return qsTr("Could not read %1.").arg(fileName)
        return xhr.responseText
    }

    function showLicense(fileName) {
        root.licenseFile = fileName
        root.licenseText = loadText(fileName)
    }

    Component.onCompleted: {
        noticesText = loadText("NOTICES.txt")
        showLicense("GPL-3.0.txt")
    }

    Column {
        id: column
        width: parent.width
        spacing: 14

        Text {
            width: parent.width
            text: qsTr("About Twilight")
            color: root.bodyColor
            font.pixelSize: 22
            font.bold: true
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            text: qsTr("Version %1").arg(SystemProperties.versionString)
            color: root.mutedColor
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            text: AutoUpdateChecker.macAppStoreBuild
                  ? qsTr("This copy of Twilight updates through the Mac App Store. It does not download a disk image.")
                  : AutoUpdateChecker.checksGitHubReleases
                    ? qsTr("Twilight can look for a newer release on GitHub. Nothing is downloaded until you choose to update.")
                    : qsTr("This build does not check GitHub for Twilight releases.")
            color: root.mutedColor
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        Button {
            text: AutoUpdateChecker.checking ? qsTr("Checking…") : qsTr("Check for Updates")
            enabled: !AutoUpdateChecker.checking
            onClicked: AutoUpdateChecker.checkNow()
        }

        CheckBox {
            visible: AutoUpdateChecker.checksGitHubReleases
            text: qsTr("Check for updates when Twilight opens")
            checked: AutoUpdateChecker.checkOnLaunch
            onToggled: AutoUpdateChecker.checkOnLaunch = checked
        }

        TextEdit {
            width: parent.width
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: root.bodyColor
            font.pixelSize: 13
            text: root.noticesText
        }

        Button {
            text: qsTr("Open corresponding source")
            onClicked: Qt.openUrlExternally("https://github.com/Neguete10/twilight")
        }

        Text {
            width: parent.width
            text: qsTr("License text")
            color: root.bodyColor
            font.pixelSize: 16
            font.bold: true
        }

        Column {
            width: parent.width
            spacing: 4

            Repeater {
                model: [
                    { label: qsTr("GNU GPL 3.0"), file: "GPL-3.0.txt" },
                    { label: qsTr("qmdnsengine (MIT)"), file: "qmdnsengine-MIT.txt" },
                    { label: qsTr("h264bitstream (LGPL 2.1)"), file: "h264bitstream-LGPL-2.1.txt" },
                    { label: qsTr("SDL_GameControllerDB (zlib)"), file: "SDL_GameControllerDB-Zlib.txt" },
                    { label: qsTr("FFmpeg (LGPL 2.1)"), file: "FFmpeg-LGPL-2.1.txt" },
                    { label: qsTr("OpenSSL (Apache 2.0)"), file: "OpenSSL-Apache-2.0.txt" },
                    { label: qsTr("Opus (BSD)"), file: "Opus-BSD.txt" },
                    { label: qsTr("SDL2 (zlib)"), file: "SDL2-Zlib.txt" },
                    { label: qsTr("SDL2_ttf (zlib)"), file: "SDL2_ttf-Zlib.txt" },
                    { label: qsTr("libplacebo (LGPL 2.1)"), file: "libplacebo-LGPL-2.1.txt" }
                ]

                Button {
                    text: modelData.label
                    highlighted: root.licenseFile === modelData.file
                    onClicked: root.showLicense(modelData.file)
                }
            }
        }

        TextEdit {
            width: parent.width
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: root.bodyColor
            font.pixelSize: 11
            font.family: "Menlo"
            text: root.licenseText
        }
    }
}
