import QtQuick 2.9
import QtQuick.Window 2.2

import StreamingPreferences 1.0
import SystemProperties 1.0
import ComputerManager 1.0

Item {
    id: sheet
    property var theme
    property bool open: false
    signal closeRequested()
    signal toastRequested(string message)

    property string section: "video"
    property var resolutionOptions: []
    property var fpsOptions: []
    // Not bound to enableMicrophone. Turning the switch on asks macOS
    // first, and the preference stays off until that result arrives.
    property bool micWanted: false

    anchors.fill: parent
    visible: open || hideTimer.running
    opacity: open ? 1 : 0
    enabled: open
    z: 30
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    onOpenChanged: {
        if (open)
            StreamingPreferences.refreshMicrophoneStatus()
        else
            hideTimer.start()
    }
    Timer { id: hideTimer; interval: 180 }

    function resKey(w, h) { return w + "x" + h }

    function rebuildChoices() {
        // Labels only. This must not write StreamingPreferences width or
        // height — the native mode on a 4K panel is the 4K preset, and
        // applying it here snaps a chosen size back to 4K.
        var resolutions = [
            { text: "720p", value: resKey(1280, 720), w: 1280, h: 720 },
            { text: "1080p", value: resKey(1920, 1080), w: 1920, h: 1080 },
            { text: "1440p", value: resKey(2560, 1440), w: 2560, h: 1440 },
            { text: "4K", value: resKey(3840, 2160), w: 3840, h: 2160 }
        ]
        var native = SystemProperties.getNativeResolution(0)
        if (native && native.width > 0 && native.height > 0) {
            var known = false
            for (var i = 0; i < resolutions.length; i++) {
                if (resolutions[i].w === native.width && resolutions[i].h === native.height)
                    known = true
            }
            if (!known)
                resolutions.unshift({ text: qsTr("This display"), value: resKey(native.width, native.height), w: native.width, h: native.height })
        }
        resolutionOptions = resolutions

        var rates = [
            { text: qsTr("30 FPS"), value: 30 },
            { text: qsTr("60 FPS"), value: 60 }
        ]
        var hz = SystemProperties.getRefreshRate(0)
        if (hz > 0 && hz !== 30 && hz !== 60)
            rates.push({ text: qsTr("%1 FPS").arg(hz), value: hz })
        fpsOptions = rates
    }

    function optionSelected(options, value) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].value == value)
                return true
        }
        return false
    }

    function applyResolution(key) {
        var parts = ("" + key).split("x")
        if (parts.length !== 2)
            return
        var w = parseInt(parts[0], 10)
        var h = parseInt(parts[1], 10)
        if (!(w > 0) || !(h > 0))
            return
        if (StreamingPreferences.width === w && StreamingPreferences.height === h)
            return
        StreamingPreferences.width = w
        StreamingPreferences.height = h
        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(w, h, StreamingPreferences.fps, StreamingPreferences.enableYUV444)
        StreamingPreferences.save()
    }

    function applyFps(fps) {
        StreamingPreferences.fps = fps
        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                    StreamingPreferences.width, StreamingPreferences.height, fps, StreamingPreferences.enableYUV444)
    }

    function applyYuv(next) {
        if (StreamingPreferences.enableYUV444 === next)
            return
        StreamingPreferences.enableYUV444 = next
        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                    StreamingPreferences.width, StreamingPreferences.height, StreamingPreferences.fps, next)
    }

    function setMdns(next) {
        if (StreamingPreferences.enableMdns === next)
            return
        StreamingPreferences.enableMdns = next
        if (Window.window && Window.window.pollingActive) {
            ComputerManager.stopPollingAsync()
            ComputerManager.startPolling()
        }
    }

    function codecChoices() {
        var options = [
            { text: qsTr("Automatic"), value: StreamingPreferences.VCC_AUTO },
            { text: "H.264", value: StreamingPreferences.VCC_FORCE_H264 },
            { text: "HEVC", value: StreamingPreferences.VCC_FORCE_HEVC },
            { text: "AV1", value: StreamingPreferences.VCC_FORCE_AV1 }
        ]
        if (SystemProperties.hasPyroWaveVulkan || SystemProperties.hasPyroWaveMetal)
            options.push({ text: "PyroWave", value: StreamingPreferences.VCC_FORCE_PYROWAVE })
        return options
    }

    Component.onCompleted: {
        rebuildChoices()
        micWanted = StreamingPreferences.enableMicrophone
    }

    Connections {
        target: StreamingPreferences
        onMicrophoneAccessFinished: sheet.micWanted = granted
    }

    Rectangle {
        anchors.fill: parent
        color: sheet.theme.scrim
        MouseArea { anchors.fill: parent; onClicked: sheet.closeRequested() }
    }

    Rectangle {
        id: panel
        width: Math.min(880, parent.width - 32)
        height: Math.min(680, parent.height - 32)
        anchors.centerIn: parent
        radius: 22
        color: sheet.theme.sheetSurface
        border.width: 1
        border.color: sheet.theme.stroke
        clip: true

        MouseArea { anchors.fill: parent }

        Row {
            anchors.fill: parent

            Rectangle {
                width: 196
                height: parent.height
                color: sheet.theme.dark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.03)

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 4

                    TwTextV2 {
                        text: qsTr("Settings")
                        theme: sheet.theme
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        bottomPadding: 8
                    }

                    Repeater {
                        model: ListModel {
                            ListElement { sectionId: "video"; label: qsTr("Video"); symbol: "display" }
                            ListElement { sectionId: "audio"; label: qsTr("Audio"); symbol: "speaker.wave.3" }
                            ListElement { sectionId: "input"; label: qsTr("Input"); symbol: "gamecontroller" }
                            ListElement { sectionId: "network"; label: qsTr("Network"); symbol: "network" }
                            ListElement { sectionId: "advanced"; label: qsTr("Advanced"); symbol: "slider.horizontal.3" }
                        }

                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: 10
                            color: sheet.section === model.sectionId ? sheet.theme.selection : (navArea.containsMouse ? sheet.theme.fill : "transparent")
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                spacing: 8
                                SymbolV2 {
                                    symbol: model.symbol
                                    pointSize: 15
                                    theme: sheet.theme
                                    tint: sheet.section === model.sectionId ? sheet.theme.accent : sheet.theme.ink
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                TwTextV2 {
                                    text: model.label
                                    theme: sheet.theme
                                    font.pixelSize: 13
                                    font.weight: sheet.section === model.sectionId ? Font.DemiBold : Font.Normal
                                    color: sheet.section === model.sectionId ? sheet.theme.accent : sheet.theme.ink
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            MouseArea {
                                id: navArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sheet.section = model.sectionId
                            }
                        }
                    }
                }
            }

            Flickable {
                id: scroller
                width: parent.width - 196
                height: parent.height
                contentWidth: width
                contentHeight: page.implicitHeight + 32
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: page
                    width: scroller.width - 40
                    x: 20
                    y: 20
                    spacing: 18

                    TwTextV2 {
                        text: sheet.section === "video" ? qsTr("Video")
                              : sheet.section === "audio" ? qsTr("Audio")
                              : sheet.section === "input" ? qsTr("Input")
                              : sheet.section === "network" ? qsTr("Network")
                              : qsTr("Advanced")
                        theme: sheet.theme
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    Column {
                        width: parent.width
                        spacing: 14
                        visible: sheet.section === "video"

                        TwTextV2 { theme: sheet.theme; text: qsTr("Resolution"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            width: parent.width
                            theme: sheet.theme
                            options: sheet.resolutionOptions
                            current: sheet.resKey(StreamingPreferences.width, StreamingPreferences.height)
                            onPicked: sheet.applyResolution(value)
                        }
                        TwTextV2 {
                            width: parent.width
                            visible: !sheet.optionSelected(sheet.resolutionOptions, sheet.resKey(StreamingPreferences.width, StreamingPreferences.height))
                            theme: sheet.theme
                            color: sheet.theme.tertiary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            text: qsTr("Using a custom %1×%2. Switch to Classic to type another size.").arg(StreamingPreferences.width).arg(StreamingPreferences.height)
                        }

                        TwTextV2 { theme: sheet.theme; text: qsTr("Frame rate"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            width: parent.width
                            theme: sheet.theme
                            options: sheet.fpsOptions
                            current: StreamingPreferences.fps
                            onPicked: sheet.applyFps(value)
                        }
                        TwTextV2 {
                            width: parent.width
                            visible: !sheet.optionSelected(sheet.fpsOptions, StreamingPreferences.fps)
                            theme: sheet.theme
                            color: sheet.theme.tertiary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            text: qsTr("Using a custom %1 FPS. Switch to Classic to type another rate.").arg(StreamingPreferences.fps)
                        }

                        TwTextV2 {
                            theme: sheet.theme
                            text: qsTr("Bitrate · %1 Mb/s").arg((StreamingPreferences.bitrateKbps / 1000).toFixed(1))
                            color: sheet.theme.secondary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        SliderV2 {
                            width: parent.width
                            theme: sheet.theme
                            from: 500
                            to: 500000
                            value: Math.min(StreamingPreferences.bitrateKbps, 500000)
                            onMoved: StreamingPreferences.bitrateKbps = value
                        }

                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("V-Sync")
                            subtitle: qsTr("Turn off for lower latency. You may see tearing.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.enableVsync
                                onToggled: StreamingPreferences.enableVsync = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            enabled: StreamingPreferences.enableVsync
                            title: qsTr("Frame pacing")
                            subtitle: qsTr("Delays early frames to reduce micro-stutter.")
                            SwitchV2 {
                                theme: sheet.theme
                                enabled: StreamingPreferences.enableVsync
                                checked: StreamingPreferences.enableVsync && StreamingPreferences.framePacing
                                onToggled: StreamingPreferences.framePacing = next
                            }
                        }

                        TwTextV2 { theme: sheet.theme; text: qsTr("Display mode"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            width: parent.width
                            theme: sheet.theme
                            current: StreamingPreferences.windowMode
                            options: [
                                { text: qsTr("Fullscreen"), value: StreamingPreferences.WM_FULLSCREEN },
                                { text: qsTr("Borderless"), value: StreamingPreferences.WM_FULLSCREEN_DESKTOP },
                                { text: qsTr("Window"), value: StreamingPreferences.WM_WINDOWED }
                            ]
                            onPicked: StreamingPreferences.windowMode = value
                        }

                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            enabled: SystemProperties.supportsHdr
                            title: qsTr("HDR")
                            subtitle: SystemProperties.supportsHdr ? qsTr("Some games still need an HDR monitor on the host.")
                                                                   : qsTr("This computer cannot display HDR.")
                            SwitchV2 {
                                theme: sheet.theme
                                enabled: SystemProperties.supportsHdr
                                checked: SystemProperties.supportsHdr && StreamingPreferences.enableHdr
                                onToggled: StreamingPreferences.enableHdr = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            divider: false
                            title: qsTr("YUV 4:4:4")
                            subtitle: qsTr("Sharper text and desktop. Not ideal for fast games.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.enableYUV444
                                onToggled: sheet.applyYuv(next)
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 14
                        visible: sheet.section === "audio"

                        TwTextV2 { theme: sheet.theme; text: qsTr("Channels"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            width: parent.width
                            theme: sheet.theme
                            current: StreamingPreferences.audioConfig
                            options: [
                                { text: qsTr("Stereo"), value: StreamingPreferences.AC_STEREO },
                                { text: qsTr("5.1"), value: StreamingPreferences.AC_51_SURROUND },
                                { text: qsTr("7.1"), value: StreamingPreferences.AC_71_SURROUND }
                            ]
                            onPicked: StreamingPreferences.audioConfig = value
                        }
                        TwTextV2 { theme: sheet.theme; text: qsTr("Spatial audio"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            width: parent.width
                            theme: sheet.theme
                            enabled: StreamingPreferences.audioConfig !== StreamingPreferences.AC_STEREO
                            current: StreamingPreferences.spatialAudioConfig
                            options: [
                                { text: qsTr("Enabled"), value: StreamingPreferences.SAC_AUTO },
                                { text: qsTr("Disabled"), value: StreamingPreferences.SAC_DISABLED }
                            ]
                            onPicked: StreamingPreferences.spatialAudioConfig = value
                        }
                        TwTextV2 {
                            width: parent.width
                            theme: sheet.theme
                            color: sheet.theme.tertiary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            text: qsTr("Uses the CoreAudio spatial mixer on headphones, built-in MacBook speakers, and 2-channel USB devices. Stereo skips it.")
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            enabled: StreamingPreferences.audioConfig !== StreamingPreferences.AC_STEREO && StreamingPreferences.spatialAudioConfig !== StreamingPreferences.SAC_DISABLED
                            title: qsTr("Head tracking")
                            subtitle: qsTr("Requires supported Apple or Beats headphones.")
                            SwitchV2 {
                                theme: sheet.theme
                                enabled: StreamingPreferences.audioConfig !== StreamingPreferences.AC_STEREO && StreamingPreferences.spatialAudioConfig !== StreamingPreferences.SAC_DISABLED
                                checked: enabled && StreamingPreferences.spatialHeadTracking
                                onToggled: StreamingPreferences.spatialHeadTracking = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Mute host speakers")
                            subtitle: qsTr("Restart a game already running for this to apply.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: !StreamingPreferences.playAudioOnHost
                                onToggled: StreamingPreferences.playAudioOnHost = !next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            divider: Qt.platform.os == "osx"
                            title: qsTr("Mute when Twilight is in the background")
                            subtitle: qsTr("Silences the stream when another window is active.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.muteOnFocusLoss
                                onToggled: StreamingPreferences.muteOnFocusLoss = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            visible: Qt.platform.os == "osx"
                            divider: false
                            title: qsTr("Stream microphone to the host")
                            subtitle: qsTr("Sends this Mac's microphone on the encrypted control stream. A Vibepollo build with Vibelight passthrough opens Steam Streaming Microphone after the first packet, and Steam has to be running. Stock Sunshine does not.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: sheet.micWanted
                                onToggled: {
                                    sheet.micWanted = next
                                    StreamingPreferences.setMicrophoneEnabled(next)
                                }
                            }
                        }
                        TwTextV2 {
                            width: parent.width
                            visible: Qt.platform.os == "osx" && StreamingPreferences.microphoneStatusText !== ""
                            theme: sheet.theme
                            color: sheet.theme.tertiary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            text: StreamingPreferences.microphoneStatusText
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 4
                        visible: sheet.section === "input"

                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Optimize mouse for remote desktop")
                            subtitle: qsTr("Absolute mouse, no capture. Right for the desktop, wrong for most games.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.absoluteMouseMode
                                onToggled: StreamingPreferences.absoluteMouseMode = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            visible: Qt.platform.os == "osx"
                            title: qsTr("Use CoreHID raw mouse (macOS games)")
                            subtitle: qsTr("Needs Input Monitoring permission. Restart the stream, or grab the mouse again, for it to take effect.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.coreHidMouse
                                onToggled: StreamingPreferences.coreHidMouse = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Touchscreen as a trackpad")
                            subtitle: qsTr("When off, touches map to absolute screen positions.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: !StreamingPreferences.absoluteTouchMode
                                onToggled: StreamingPreferences.absoluteTouchMode = !next
                            }
                        }
                        TwTextV2 { theme: sheet.theme; text: qsTr("Capture system shortcuts"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold; topPadding: 8 }
                        ChoiceV2 {
                            width: parent.width
                            theme: sheet.theme
                            current: StreamingPreferences.captureSysKeysMode
                            options: [
                                { text: qsTr("Off"), value: StreamingPreferences.CSK_OFF },
                                { text: qsTr("Fullscreen"), value: StreamingPreferences.CSK_FULLSCREEN },
                                { text: qsTr("Always"), value: StreamingPreferences.CSK_ALWAYS }
                            ]
                            onPicked: StreamingPreferences.captureSysKeysMode = value
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Swap left and right mouse buttons")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.swapMouseButtons
                                onToggled: StreamingPreferences.swapMouseButtons = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Reverse scroll direction")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.reverseScrollDirection
                                onToggled: StreamingPreferences.reverseScrollDirection = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Swap A/B and X/Y")
                            subtitle: qsTr("Matches Nintendo-style face buttons.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.swapFaceButtons
                                onToggled: StreamingPreferences.swapFaceButtons = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Gamepad mouse")
                            subtitle: qsTr("Hold Start to move the pointer with the right stick.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.gamepadMouse
                                onToggled: StreamingPreferences.gamepadMouse = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Background gamepad")
                            subtitle: qsTr("Keep sending gamepad input when the stream window is not focused.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.backgroundGamepad
                                onToggled: StreamingPreferences.backgroundGamepad = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            divider: false
                            title: qsTr("Multiple controllers")
                            subtitle: qsTr("Each gamepad is its own player. Off means every pad is player 1.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.multiController
                                onToggled: StreamingPreferences.multiController = next
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 4
                        visible: sheet.section === "network"

                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Find computers on the local network")
                            subtitle: qsTr("mDNS discovery. Turn off if you only add hosts by address.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.enableMdns
                                onToggled: sheet.setMdns(next)
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Detect blocked connections")
                            subtitle: qsTr("Checks whether this network filters streaming ports.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.detectNetworkBlocking
                                onToggled: StreamingPreferences.detectNetworkBlocking = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            divider: false
                            title: qsTr("Connection quality warnings")
                            subtitle: qsTr("Tells you when the link is too weak for the current settings.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.connectionWarnings
                                onToggled: StreamingPreferences.connectionWarnings = next
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 14
                        visible: sheet.section === "advanced"

                        TwTextV2 { theme: sheet.theme; text: qsTr("Video codec"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            width: parent.width
                            theme: sheet.theme
                            current: StreamingPreferences.videoCodecConfig
                            options: sheet.codecChoices()
                            onPicked: StreamingPreferences.videoCodecConfig = value
                        }
                        TwTextV2 {
                            theme: sheet.theme
                            visible: SystemProperties.hasPyroWaveMetal && SystemProperties.hasPyroWaveVulkan
                            text: qsTr("PyroWave GPU backend")
                            color: sheet.theme.secondary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        ChoiceV2 {
                            width: parent.width
                            theme: sheet.theme
                            visible: SystemProperties.hasPyroWaveMetal && SystemProperties.hasPyroWaveVulkan
                            current: StreamingPreferences.pyroWaveBackend
                            options: [
                                { text: qsTr("Automatic"), value: StreamingPreferences.PWBC_AUTO },
                                { text: "Metal", value: StreamingPreferences.PWBC_METAL },
                                { text: "Vulkan", value: StreamingPreferences.PWBC_VULKAN }
                            ]
                            onPicked: StreamingPreferences.pyroWaveBackend = value
                        }
                        TwTextV2 {
                            width: parent.width
                            theme: sheet.theme
                            visible: SystemProperties.hasPyroWaveMetal && SystemProperties.hasPyroWaveVulkan
                            color: sheet.theme.tertiary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            text: qsTr("Used only when the codec is PyroWave. Automatic prefers Metal on Apple7 GPUs and otherwise uses Vulkan. H.264, HEVC, and AV1 stay on VideoToolbox.")
                        }
                        TwTextV2 { theme: sheet.theme; text: qsTr("Decoder"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            width: parent.width
                            theme: sheet.theme
                            current: StreamingPreferences.videoDecoderSelection
                            options: [
                                { text: qsTr("Automatic"), value: StreamingPreferences.VDS_AUTO },
                                { text: qsTr("Hardware"), value: StreamingPreferences.VDS_FORCE_HARDWARE },
                                { text: qsTr("Software"), value: StreamingPreferences.VDS_FORCE_SOFTWARE }
                            ]
                            onPicked: StreamingPreferences.videoDecoderSelection = value
                        }

                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Optimize game settings for streaming")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.gameOptimizations
                                onToggled: StreamingPreferences.gameOptimizations = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Quit the app on the host when the stream ends")
                            subtitle: qsTr("Unsaved progress on the host will be lost.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.quitAppAfter
                                onToggled: StreamingPreferences.quitAppAfter = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Keep the display awake")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.keepAwake
                                onToggled: StreamingPreferences.keepAwake = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Discord Rich Presence")
                            subtitle: qsTr("Shows the game name on Discord while you stream.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.richPresence
                                onToggled: StreamingPreferences.richPresence = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Classic performance overlay")
                            subtitle: qsTr("The yellow Classic stats, including FEC on H.264, HEVC, and AV1. Separate from Twilight's chips, and it does not add those FEC lines to PyroWave.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.showPerformanceOverlay
                                onToggled: StreamingPreferences.showPerformanceOverlay = next
                            }
                        }
                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("Twilight performance overlay")
                            subtitle: qsTr("FPS, bitrate, and latency chips while a Twilight stream is open. Turn this off to hide them.")
                            SwitchV2 {
                                theme: sheet.theme
                                checked: StreamingPreferences.showTwilightHud
                                onToggled: StreamingPreferences.showTwilightHud = next
                            }
                        }

                        TwTextV2 { theme: sheet.theme; text: qsTr("Window when Twilight opens"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            width: parent.width
                            visible: SystemProperties.hasDesktopEnvironment
                            theme: sheet.theme
                            current: StreamingPreferences.uiDisplayMode
                            options: [
                                { text: qsTr("Window"), value: StreamingPreferences.UI_WINDOWED },
                                { text: qsTr("Maximized"), value: StreamingPreferences.UI_MAXIMIZED },
                                { text: qsTr("Fullscreen"), value: StreamingPreferences.UI_FULLSCREEN }
                            ]
                            onPicked: StreamingPreferences.uiDisplayMode = value
                        }
                        TwTextV2 {
                            width: parent.width
                            theme: sheet.theme
                            color: sheet.theme.tertiary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            text: qsTr("The window mode applies the next time the app opens. Packet size and fully custom modes stay in Classic.")
                        }

                    }
                }
            }
        }

        Item {
            z: 2
            width: 32
            height: 32
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
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

    Shortcut {
        sequence: "Escape"
        enabled: sheet.open
        onActivated: sheet.closeRequested()
    }
}
