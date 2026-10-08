import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Window 2.2
import QtQuick.Controls.Material 2.2

import ComputerManager 1.0
import AutoUpdateChecker 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0

ApplicationWindow {
    property bool pollingActive: false

    // Interactive launches use the Twilight shell. Command-line pair, stream,
    // and quit windows pass their own initialView and stay on the stack.
    readonly property bool twilightShell: initialView === ""
    property bool v2Active: twilightShell
    property bool streamActive: false
    property string pendingUpdateVersion: ""
    property string pendingUpdateUrl: ""


    // Update prompt (PR25). DialogCardV2 in ShellV2 binds to these.
    // Download / Not now leave the app in place; Download only opens a browser URL.
    property bool updatePromptOpen: false
    property bool updateInfoOpen: false
    property bool updatePromptDeferred: false
    property string updateInfoTitle: ""
    property string updateInfoMessage: ""
    property bool updatePromptClosing: false
    property bool updateInfoClosing: false

    function updatePromptMessage() {
        var version = AutoUpdateChecker.availableVersion
        var notes = AutoUpdateChecker.releaseNotes
        var hasDisk = AutoUpdateChecker.downloadUrl !== ""
        var body = hasDisk
                ? qsTr("Twilight %1 is available. This copy is %2.\n\nDownload opens the disk image in your browser. Twilight does not download or replace this app on its own. When the file finishes downloading, open the disk image and drag Twilight to Applications.")
                    .arg(version).arg(SystemProperties.versionString)
                : qsTr("Twilight %1 is available. This copy is %2.\n\nView release opens the release page in your browser. Twilight does not download or replace this app on its own.")
                    .arg(version).arg(SystemProperties.versionString)
        if (notes !== "")
            body += "\n\n" + qsTr("What's new:") + "\n" + notes
        return body
    }

    function updateConfirmText() {
        return AutoUpdateChecker.downloadUrl !== "" ? qsTr("Download") : qsTr("View release")
    }

    function openUpdatePrompt() {
        if (AutoUpdateChecker.availableVersion === "")
            return
        if (streamActive) {
            updatePromptDeferred = true
            return
        }

        updatePromptDeferred = false
        updateInfoOpen = false
        updatePromptOpen = true
    }

    function acceptPendingUpdate() {
        if (updatePromptClosing)
            return

        updatePromptClosing = true
        var url = AutoUpdateChecker.downloadUrl !== "" ? AutoUpdateChecker.downloadUrl : AutoUpdateChecker.releasePageUrl
        updatePromptOpen = false
        // The browser downloads the disk image. This process does not.
        if (url !== "")
            Qt.openUrlExternally(url)
        updatePromptClosing = false
    }

    function dismissPendingUpdate() {
        if (updatePromptClosing)
            return

        updatePromptClosing = true
        updatePromptOpen = false
        updatePromptDeferred = false
        updatePromptClosing = false
    }

    function openUpdateInfo(title, message) {
        if (streamActive)
            return

        updateInfoTitle = title
        updateInfoMessage = message
        updateInfoOpen = true
    }

    function dismissUpdateInfo() {
        if (updateInfoClosing)
            return

        updateInfoClosing = true
        updateInfoOpen = false
        updateInfoClosing = false
    }


    id: window
    width: 1280
    height: 600

    // This function runs prior to creation of the initial StackView item
    function doEarlyInit() {
        // Override the background color to Material 2 colors for Qt 6.5+
        // in order to improve contrast between GFE's placeholder box art
        // and the background of the app grid.
        if (SystemProperties.usesMaterial3Theme) {
            Material.background = "#303030"
        }

        SdlGamepadKeyNavigation.enable()
    }

    onClosing: {
        if (v2Active) {
            StreamingPreferences.save()
        }
    }

    Component.onCompleted: {
        if (twilightShell) {
            title = "Twilight"
            if (width < 1100) {
                width = 1180
            }
            if (height < 720) {
                height = 800
            }
        }

        // Show the window according to the user's preferences
        if (SystemProperties.hasDesktopEnvironment) {
            if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_MAXIMIZED) {
                window.showMaximized()
            }
            else if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_FULLSCREEN) {
                window.showFullScreen()
            }
            else {
                window.show()
            }
        } else {
            window.showFullScreen()
        }

        // Display any modal dialogs for configuration warnings
        if (SystemProperties.isWow64) {
            wow64Dialog.open()
        }
        else if (!SystemProperties.hasHardwareAcceleration) {
            if (SystemProperties.isRunningXWayland) {
                xWaylandDialog.open()
            }
            else {
                noHwDecoderDialog.open()
            }
        }

        if (SystemProperties.unmappedGamepads) {
            unmappedGamepadDialog.unmappedGamepads = SystemProperties.unmappedGamepads
            unmappedGamepadDialog.open()
        }

        AutoUpdateChecker.updateAvailable.connect(function(version, releaseUrl, downloadUrl, notes, manual) {
            pendingUpdateVersion = version
            pendingUpdateUrl = downloadUrl !== "" ? downloadUrl : releaseUrl
            openUpdatePrompt()
        })
        AutoUpdateChecker.upToDate.connect(function(version, manual) {
            if (manual)
                openUpdateInfo(qsTr("You're up to date"),
                               qsTr("You're running Twilight %1. The latest release is %2.")
                               .arg(SystemProperties.versionString).arg(version))
        })
        AutoUpdateChecker.checkFailed.connect(function(message, manual) {
            if (manual)
                openUpdateInfo(qsTr("Could not check for updates"), message)
        })
        AutoUpdateChecker.start()
    }

    onStreamActiveChanged: {
        if (!streamActive && updatePromptDeferred)
            openUpdatePrompt()
    }
  
    // This configures the maximum width of the singleton attached QML ToolTip. If left unconstrained,
    // it will never insert a line break and just extend on forever.
    ToolTip.toolTip.contentWidth: ToolTip.toolTip.implicitContentWidth < 400 ? ToolTip.toolTip.implicitContentWidth : 400

    function goBack() {
        stackView.pop()
    }

    // StreamSegue, QuitSegue, and the command-line windows still assign
    // toolBar.visible. The Classic toolbar is gone, so this is not a header.
    // It is created before the stack so a segue pushed during startup can see it.
    Item {
        id: toolBar
        visible: false
        width: 0
        height: 0
    }

    StackView {
        id: stackView
        anchors.fill: parent
        focus: !v2Active
        visible: !v2Active
        enabled: !v2Active

        Component.onCompleted: {
            // Perform our early initialization before constructing
            // the initial view and pushing it to the StackView
            doEarlyInit()
            if (!twilightShell) {
                push(initialView)
            }
        }

        onCurrentItemChanged: {
            // Ensure focus travels to the next view when going back
            if (currentItem) {
                currentItem.forceActiveFocus()
            }
        }

        Keys.onEscapePressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onBackPressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }
    }


    Loader {
        id: v2Shell
        anchors.fill: parent
        active: v2Active
        visible: v2Active
        focus: v2Active
        source: "qrc:/gui/ui/v2/ShellV2.qml"
    }

    // This timer keeps us polling for 5 minutes of inactivity
    // to allow the user to work with Moonlight on a second display
    // while dealing with configuration issues. This will ensure
    // machines come online even if the input focus isn't on Moonlight.
    Timer {
        id: inactivityTimer
        interval: 5 * 60000
        onTriggered: {
            if (!active && pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
    }

    onVisibleChanged: {
        // When we become invisible while streaming is going on,
        // stop polling immediately.
        if (!visible) {
            inactivityTimer.stop()

            if (pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
        else if (active) {
            // When we become visible and active again, start polling
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    onActiveChanged: {
        if (active) {
            // Stop the inactivity timer
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }
        else {
            // Start the inactivity timer to stop polling
            // if focus does not return within a few minutes.
            inactivityTimer.restart()
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    ErrorMessageDialog {
        id: noHwDecoderDialog
        text: qsTr("No functioning hardware accelerated video decoder was detected by Moonlight. " +
                   "Your streaming performance may be severely degraded in this configuration.")
        helpText: qsTr("Click the Help button for more information on solving this problem.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    ErrorMessageDialog {
        id: xWaylandDialog
        text: qsTr("Hardware acceleration doesn't work on XWayland. Continuing on XWayland may result in poor streaming performance. " +
                   "Try running with QT_QPA_PLATFORM=wayland or switch to X11.")
        helpText: qsTr("Click the Help button for more information.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    NavigableMessageDialog {
        id: wow64Dialog
        standardButtons: Dialog.Ok | Dialog.Cancel
        text: qsTr("This version of Moonlight isn't optimized for your PC. Please download the '%1' version of Moonlight for the best streaming performance.").arg(SystemProperties.friendlyNativeArchName)
        onAccepted: {
            Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-qt/releases");
        }
    }

    ErrorMessageDialog {
        id: unmappedGamepadDialog
        property string unmappedGamepads : ""
        text: qsTr("Moonlight detected gamepads without a mapping:") + "\n" + unmappedGamepads
        helpTextSeparator: "\n\n"
        helpText: qsTr("Click the Help button for information on how to map your gamepads.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Gamepad-Mapping"
    }

    // This dialog appears when quitting via keyboard or gamepad button
    NavigableMessageDialog {
        id: quitConfirmationDialog
        standardButtons: Dialog.Yes | Dialog.No
        text: qsTr("Are you sure you want to quit?")
        // For keyboard/gamepad navigation
        onAccepted: Qt.quit()
    }

    // HACK: This belongs in StreamSegue but keeping a dialog around after the parent
    // dies can trigger bugs in Qt 5.12 that cause the app to crash. For now, we will
    // host this dialog in a QML component that is never destroyed.
    //
    // To repro: Start a stream, cut the network connection to trigger the "Connection
    // terminated" dialog, wait until the app grid times out back to the PC grid, then
    // try to dismiss the dialog.
    ErrorMessageDialog {
        id: streamSegueErrorDialog

        property bool quitAfter: false

        onClosed: {
            if (quitAfter) {
                Qt.quit()
            }

            // StreamSegue assumes its dialog will be re-created each time we
            // start streaming, so fake it by wiping out the text each time.
            text = ""
        }
    }
}
