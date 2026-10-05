import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2
import QtQuick.Controls.Material 2.2

import ComputerManager 1.0
import AutoUpdateChecker 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0

ApplicationWindow {
    property bool pollingActive: false

    // Twilight (V2) is the starting shell. Classic stays available.
    // streamActive blocks a shell swap during a stream.
    property bool v2Active: false
    property bool streamActive: false

    // Update prompt. Download and Not now both leave the app in place.
    // Download only opens a browser URL after the user chooses it.
    property bool updatePromptOpen: false
    property bool updateInfoOpen: false
    property bool updatePromptDeferred: false
    property string updateInfoTitle: ""
    property string updateInfoMessage: ""
    property bool updatePromptClosing: false
    property bool updateInfoClosing: false
    property string classicTitle: ""
    readonly property bool allowShellSwitch: initialView === "qrc:/gui/PcView.qml"

    function activateShell(version) {
        if (streamActive || !allowShellSwitch) {
            return
        }

        var next = version === "v2" ? "v2" : "v1"
        if (((next === "v2") === v2Active) && StreamingPreferences.uiVersion === next) {
            return
        }

        if (StreamingPreferences.uiVersion !== next) {
            StreamingPreferences.uiVersion = next
            StreamingPreferences.save()
        }

        v2Active = next === "v2"
        title = v2Active ? "Twilight" : classicTitle

        if (!v2Active && stackView.depth > 1) {
            stackView.pop(null)
        }

        if (v2Active) {
            if (width < 1100) {
                width = 1180
            }
            if (height < 720) {
                height = 800
            }
        }
        else {
            stackView.forceActiveFocus()
        }
    }

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
        if (!v2Active)
            classicUpdateDialog.open()
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
        if (classicUpdateDialog.visible)
            classicUpdateDialog.close()
        updatePromptClosing = false
    }

    function dismissPendingUpdate() {
        if (updatePromptClosing)
            return

        updatePromptClosing = true
        updatePromptOpen = false
        updatePromptDeferred = false
        if (classicUpdateDialog.visible)
            classicUpdateDialog.close()
        updatePromptClosing = false
    }

    function openUpdateInfo(title, message) {
        if (streamActive)
            return

        updateInfoTitle = title
        updateInfoMessage = message
        updateInfoOpen = true
        if (!v2Active)
            classicUpdateInfoDialog.open()
    }

    function dismissUpdateInfo() {
        if (updateInfoClosing)
            return

        updateInfoClosing = true
        updateInfoOpen = false
        if (classicUpdateInfoDialog.visible)
            classicUpdateInfoDialog.close()
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
        classicTitle = title
        if (allowShellSwitch && StreamingPreferences.uiVersion === "v2") {
            activateShell("v2")
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

    onV2ActiveChanged: {
        // The prompt stays up across a shell change. Closing the Classic
        // dialog here is not a dismissal.
        if (updatePromptOpen) {
            updatePromptClosing = true
            if (v2Active) {
                if (classicUpdateDialog.visible)
                    classicUpdateDialog.close()
            } else {
                classicUpdateDialog.open()
            }
            updatePromptClosing = false
        }
        if (updateInfoOpen) {
            updateInfoClosing = true
            if (v2Active) {
                if (classicUpdateInfoDialog.visible)
                    classicUpdateInfoDialog.close()
            } else {
                classicUpdateInfoDialog.open()
            }
            updateInfoClosing = false
        }
    }
  
    // This configures the maximum width of the singleton attached QML ToolTip. If left unconstrained,
    // it will never insert a line break and just extend on forever.
    ToolTip.toolTip.contentWidth: ToolTip.toolTip.implicitContentWidth < 400 ? ToolTip.toolTip.implicitContentWidth : 400

    function goBack() {
        stackView.pop()
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
            push(initialView)
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

        Keys.onMenuPressed: {
            settingsButton.clicked()
        }

        // This is a keypress we've reserved for letting the
        // SdlGamepadKeyNavigation object tell us to show settings
        // when Menu is consumed by a focused control.
        Keys.onHangupPressed: {
            settingsButton.clicked()
        }
    }

    // Loaded only after the user picks Twilight. Inactive while Classic is showing,
    // so a V2 QML error cannot take down the default shell.
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

    // Workaround for lack of instanceof in Qt 5.9.
    //
    // Based on https://stackoverflow.com/questions/13923794/how-to-do-a-is-a-typeof-or-instanceof-in-qml
    function qmltypeof(obj, className) { // QtObject, string -> bool
        // className plus "(" is the class instance without modification
        // className plus "_QML" is the class instance with user-defined properties
        var str = obj.toString();
        return str.startsWith(className + "(") || str.startsWith(className + "_QML");
    }

    function navigateTo(url, objectType)
    {
        var existingItem = stackView.find(function(item, index) {
            return qmltypeof(item, objectType)
        })

        if (existingItem !== null) {
            // Pop to the existing item
            stackView.pop(existingItem)
        }
        else {
            // Create a new item
            stackView.push(url)
        }
    }

    header: ToolBar {
        id: toolBar
        visible: !v2Active
        height: v2Active ? 0 : 60
        anchors.topMargin: 5
        anchors.bottomMargin: 5

        Label {
            id: titleLabel
            visible: toolBar.width > 700
            anchors.fill: parent
            text: stackView.currentItem.objectName
            font.pointSize: 20
            elide: Label.ElideRight
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
        }

        RowLayout {
            spacing: 10
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.fill: parent

            NavigableToolButton {
                // Only make the button visible if the user has navigated somewhere.
                visible: stackView.depth > 1

                iconSource: "qrc:/res/arrow_left.svg"

                onClicked: goBack()

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            // This label will appear when the window gets too small and
            // we need to ensure the toolbar controls don't collide
            Label {
                id: titleRowLabel
                font.pointSize: titleLabel.font.pointSize
                elide: Label.ElideRight
                horizontalAlignment: Qt.AlignHCenter
                verticalAlignment: Qt.AlignVCenter
                Layout.fillWidth: true

                // We need this label to always be visible so it can occupy
                // the remaining space in the RowLayout. To "hide" it, we
                // just set the text to empty string.
                text: !titleLabel.visible ? stackView.currentItem.objectName : ""
            }

            Label {
                id: versionLabel
                visible: qmltypeof(stackView.currentItem, "SettingsView")
                text: qsTr("Version %1").arg(SystemProperties.versionString)
                font.pointSize: 12
                horizontalAlignment: Qt.AlignRight
                verticalAlignment: Qt.AlignVCenter
            }

            NavigableToolButton {
                id: discordButton
                visible: SystemProperties.hasBrowser &&
                         qmltypeof(stackView.currentItem, "SettingsView")

                iconSource: "qrc:/res/discord.svg"

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Join our community on Discord")

                // TODO need to make sure browser is brought to foreground.
                onClicked: Qt.openUrlExternally("https://moonlight-stream.org/discord");

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                id: addPcButton
                visible: qmltypeof(stackView.currentItem, "PcView")

                iconSource:  "qrc:/res/ic_add_to_queue_white_48px.svg"

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Add PC manually") + (newPcShortcut.nativeText ? (" ("+newPcShortcut.nativeText+")") : "")

                Shortcut {
                    id: newPcShortcut
                    sequence: StandardKey.New
                    enabled: !v2Active
                    onActivated: addPcButton.clicked()
                }

                onClicked: {
                    addPcDialog.open()
                }

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                id: updateButton

                iconSource: "qrc:/res/update.svg"
                visible: AutoUpdateChecker.availableVersion !== ""

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Update available for Twilight: Version %1").arg(AutoUpdateChecker.availableVersion)

                // Reopens the choice. It does not download by itself.
                onClicked: openUpdatePrompt()

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            ToolButton {
                id: aboutButton
                text: qsTr("About")
                font.pixelSize: 14
                Layout.preferredHeight: parent.height
                visible: !qmltypeof(stackView.currentItem, "AboutView")
                onClicked: navigateTo("qrc:/gui/AboutView.qml", "AboutView")

                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                Keys.onRightPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocus)
                Keys.onLeftPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("About Twilight, warranty, and licenses")
            }

            NavigableToolButton {
                id: helpButton
                visible: SystemProperties.hasBrowser

                iconSource: "qrc:/res/question_mark.svg"

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Help") + (helpShortcut.nativeText ? (" ("+helpShortcut.nativeText+")") : "")

                Shortcut {
                    id: helpShortcut
                    sequence: StandardKey.HelpContents
                    enabled: !v2Active
                    onActivated: helpButton.clicked()
                }

                // TODO need to make sure browser is brought to foreground.
                onClicked: Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide");

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                // TODO: Implement gamepad mapping then unhide this button
                visible: false

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Gamepad Mapper")

                iconSource: "qrc:/res/ic_videogame_asset_white_48px.svg"

                onClicked: navigateTo("qrc:/gui/GamepadMapper.qml", "GamepadMapper")

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            Loader {
                id: versionToggleLoader
                active: allowShellSwitch && !v2Active
                visible: active
                source: "qrc:/gui/ui/v2/UiVersionToggle.qml"
                Layout.alignment: Qt.AlignVCenter
                // Qt 6: Loader.implicitWidth/Height are read-only; size via Layout.
                Layout.preferredWidth: item ? item.implicitWidth : 0
                Layout.preferredHeight: item ? item.implicitHeight : 0

                onLoaded: {
                    item.darkChrome = true
                    item.currentVersion = "v1"
                    item.requestVersion.connect(activateShell)
                }
            }

            NavigableToolButton {
                id: settingsButton

                iconSource:  "qrc:/res/settings.svg"

                onClicked: navigateTo("qrc:/gui/SettingsView.qml", "SettingsView")

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }

                Shortcut {
                    id: settingsShortcut
                    sequence: StandardKey.Preferences
                    enabled: !v2Active
                    onActivated: settingsButton.clicked()
                }

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Settings") + (settingsShortcut.nativeText ? (" ("+settingsShortcut.nativeText+")") : "")
            }
        }
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

    NavigableDialog {
        id: classicUpdateDialog
        title: qsTr("Update available")
        modal: true
        z: 100
        standardButtons: Dialog.NoButton

        onRejected: window.dismissPendingUpdate()
        onOpened: notNowButton.forceActiveFocus()

        ColumnLayout {
            Label {
                text: {
                    var version = AutoUpdateChecker.availableVersion
                    var notes = AutoUpdateChecker.releaseNotes
                    var download = AutoUpdateChecker.downloadUrl
                    return window.updatePromptMessage()
                }
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                Layout.preferredWidth: 420
                Layout.maximumWidth: 420
            }
        }

        footer: DialogButtonBox {
            Button {
                id: notNowButton
                text: qsTr("Not now")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            }
            Button {
                text: {
                    var download = AutoUpdateChecker.downloadUrl
                    return window.updateConfirmText()
                }
                DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                onClicked: window.acceptPendingUpdate()
            }
        }
    }

    NavigableMessageDialog {
        id: classicUpdateInfoDialog
        standardButtons: Dialog.Ok
        text: window.updateInfoTitle === "" ? window.updateInfoMessage
                                            : (window.updateInfoTitle + "\n\n" + window.updateInfoMessage)
        onAccepted: window.dismissUpdateInfo()
        onRejected: window.dismissUpdateInfo()
    }

    NavigableDialog {
        id: addPcDialog
        property string label: qsTr("Enter the IP address of your host PC:")

        standardButtons: Dialog.Ok | Dialog.Cancel

        onOpened: {
            // Force keyboard focus on the textbox so keyboard navigation works
            editText.forceActiveFocus()
        }

        onClosed: {
            editText.clear()
        }

        onAccepted: {
            if (editText.text) {
                ComputerManager.addNewHostManually(editText.text.trim())
            }
        }

        ColumnLayout {
            Label {
                text: addPcDialog.label
                font.bold: true
            }

            TextField {
                id: editText
                Layout.fillWidth: true
                focus: true

                Keys.onReturnPressed: {
                    addPcDialog.accept()
                }

                Keys.onEnterPressed: {
                    addPcDialog.accept()
                }
            }
        }
    }
}
