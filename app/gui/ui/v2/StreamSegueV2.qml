import QtQuick 2.9
import QtQuick.Window 2.2

import SdlGamepadKeyNavigation 1.0
import StreamHudStats 1.0
import StreamingPreferences 1.0

// Twilight stream launch. Mirrors StreamSegue.qml signal handling without
// touching the stack the command-line windows still use.
Item {
    id: segue
    // Creator may pass Window.window from Shell (Item scope). Timer is a
    // QtObject, so reading Window.window there returns undefined and Session
    // falls back to display 0 (#28). Keep a snapshot, not a live binding.
    property var hostWindow
    property var host
    property var session
    property string appName
    property bool isResume: false
    property string stageText: isResume ? qsTr("Resuming %1").arg(appName) : qsTr("Starting %1").arg(appName)
    property string errorText: ""

    anchors.fill: parent

    function stageStarting(stage) {
        stageText = qsTr("Starting %1").arg(stage)
    }

    function stageFailed(stage, errorCode, failingPorts) {
        errorText = qsTr("Starting %1 failed: Error %2").arg(stage).arg(errorCode)
        if (failingPorts) {
            errorText += "\n\n" + qsTr("Check your firewall and port forwarding rules for port(s): %1").arg(failingPorts)
        }
    }

    function showShellWindow() {
        if (!Window.window)
            return
        Window.window.visible = true
        // Hiding the Qt window leaves the native fullscreen space. Game Mode
        // only stays available if that space is restored when the shell returns.
        if (StreamingPreferences.uiDisplayMode === StreamingPreferences.UI_FULLSCREEN)
            Window.window.showFullScreen()
    }

    function connectionStarted() {
        card.visible = false
        if (Window.window)
            Window.window.streamActive = true
        StreamHudStats.noteSessionStarted()
        if (Window.window)
            Window.window.visible = false
    }

    function displayLaunchError(text) {
        errorText = text
    }

    function displayLaunchWarning(text) {
        if (host && host.toast)
            host.toast(text)
    }

    function quitStarting() {
        stageText = qsTr("Quitting %1").arg(appName)
        card.visible = true
        showShellWindow()
    }

    function sessionFinished(portTestResult) {
        if (portTestResult !== 0 && portTestResult !== -1 && errorText !== "") {
            errorText += "\n\n" + qsTr("This PC's Internet connection is blocking Twilight. Streaming over the Internet may not work while connected to this network.")
        }

        SdlGamepadKeyNavigation.enable()
        StreamHudStats.noteSessionEnded()
        if (Window.window)
            Window.window.streamActive = false
        showShellWindow()

        card.visible = false
        if (errorText !== "" && host && host.showError)
            host.showError(errorText)
    }

    function sessionReadyForDeletion() {
        session = null
        gc()
        segue.destroy()
    }

    Component.onCompleted: {
        if (!session)
            return
        // Snapshot before the timer. A live binding to Window.window can go
        // undefined if the attached context shifts during the delay.
        if (!hostWindow)
            hostWindow = Window.window
        session.stageStarting.connect(stageStarting)
        session.stageFailed.connect(stageFailed)
        session.connectionStarted.connect(connectionStarted)
        session.displayLaunchError.connect(displayLaunchError)
        session.displayLaunchWarning.connect(displayLaunchWarning)
        session.quitStarting.connect(quitStarting)
        session.sessionFinished.connect(sessionFinished)
        session.readyForDeletion.connect(sessionReadyForDeletion)
        startTimer.start()
    }

    Timer {
        id: startTimer
        interval: 120
        onTriggered: {
            hint.text = qsTr("Tip: press %1 to disconnect.").arg(SdlGamepadKeyNavigation.getConnectedGamepads() > 0
                ? qsTr("Start+Select+L1+R1")
                : qsTr("Ctrl+Alt+Shift+Q"))
            SdlGamepadKeyNavigation.disable()
            gc()
            if (!hostWindow)
                hostWindow = Window.window
            if (!hostWindow)
                console.warn("StreamSegueV2: hostWindow is null; stream may open on the primary display")
            session.exec(hostWindow)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: host && host.theme ? host.theme.bg : "#12141A"
    }

    Rectangle {
        id: card
        width: Math.min(440, parent.width - 64)
        height: cardColumn.height + 48
        anchors.centerIn: parent
        radius: 22
        color: host && host.theme ? host.theme.glass : Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        border.color: host && host.theme ? host.theme.stroke : "#333"

        Column {
            id: cardColumn
            width: parent.width - 48
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 24
            spacing: 8

            SymbolV2 {
                symbol: "moon.stars"
                pointSize: 28
                theme: host ? host.theme : null
                tint: host && host.theme ? host.theme.accent : "#9EBEFF"
            }

            TwTextV2 {
                width: parent.width
                theme: host ? host.theme : null
                text: stageText
                font.pixelSize: 22
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            TwTextV2 {
                id: hint
                width: parent.width
                theme: host ? host.theme : null
                text: qsTr("Connecting to the host…")
                color: host && host.theme ? host.theme.secondary : "#AAA"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Item {
                width: parent.width
                height: 4
                Rectangle {
                    id: bar
                    width: parent.width * 0.35
                    height: 3
                    radius: 2
                    color: host && host.theme ? host.theme.accent : "#9EBEFF"
                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        running: card.visible
                        NumberAnimation { from: 0; to: cardColumn.width * 0.65; duration: 900; easing.type: Easing.InOutCubic }
                        NumberAnimation { from: cardColumn.width * 0.65; to: 0; duration: 900; easing.type: Easing.InOutCubic }
                    }
                }
            }
        }
    }
}
