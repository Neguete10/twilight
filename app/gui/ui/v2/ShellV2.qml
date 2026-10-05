import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Window 2.2

import ComputerModel 1.0
import AppModel 1.0
import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import StreamHudStats 1.0
import AutoUpdateChecker 1.0

Item {
    id: shell
    anchors.fill: parent
    focus: true

    ThemeV2 { id: themeColors }
    property alias theme: themeColors

    property int hostRevision: 0
    property int selectedIndex: -1
    property int appRevision: 0
    property int desktopIndex: -1
    property bool showHidden: false
    property bool directLaunchConsumed: true
    property var appModel: null
    property var hudWindow: null
    property var hudComponent: null
    property string query: ""

    property bool settingsOpen: false
    property bool hostSheetOpen: false
    property bool addOpen: false
    property bool pairOpen: false
    property bool renameOpen: false
    property bool deleteOpen: false
    property bool quitOpen: false
    property bool errorOpen: false
    property bool testOpen: false
    property bool leaveOpen: false
    property bool quitting: false
    property string pairPin: ""
    property string quitAppName: ""
    property string pendingAppName: ""
    property int pendingAppIndex: -1
    property string errorMessage: ""
    property string testMessage: ""
    property string toastText: ""

    readonly property bool updateDialogOpen: Window.window !== null && (Window.window.updatePromptOpen || Window.window.updateInfoOpen)
    readonly property bool modalOpen: settingsOpen || hostSheetOpen || addOpen || pairOpen || renameOpen || deleteOpen || quitOpen || errorOpen || testOpen || leaveOpen || updateDialogOpen || quitting

    readonly property string selectedName: {
        var rev = hostRevision
        return selectedIndex < 0 ? "" : computerModel.computerNameAt(selectedIndex)
    }
    readonly property bool selectedOnline: {
        var rev = hostRevision
        return selectedIndex >= 0 && computerModel.computerOnlineAt(selectedIndex)
    }
    readonly property bool selectedPaired: {
        var rev = hostRevision
        return selectedIndex >= 0 && computerModel.computerPairedAt(selectedIndex)
    }
    readonly property bool selectedWakeable: {
        var rev = hostRevision
        return selectedIndex >= 0 && computerModel.computerWakeableAt(selectedIndex)
    }
    readonly property bool selectedBusy: {
        var rev = hostRevision
        return selectedIndex >= 0 && computerModel.computerBusyAt(selectedIndex)
    }
    readonly property bool selectedUnknown: {
        var rev = hostRevision
        return selectedIndex >= 0 && computerModel.computerStatusUnknownAt(selectedIndex)
    }
    readonly property bool selectedSupported: {
        var rev = hostRevision
        return selectedIndex < 0 || computerModel.computerSupportedAt(selectedIndex)
    }
    readonly property string selectedDetails: {
        var rev = hostRevision
        return selectedIndex < 0 ? "" : computerModel.computerDetailsAt(selectedIndex)
    }
    readonly property bool desktopShown: {
        var rev = appRevision
        if (desktopIndex < 0 || !appModel)
            return false
        if (query === "")
            return true
        return appModel.appNameAt(desktopIndex).toLowerCase().indexOf(query.toLowerCase()) !== -1
    }

    function toast(text) {
        toastText = text
        toastTimer.restart()
    }

    function showError(text) {
        errorMessage = text
        errorOpen = true
    }

    function destroyApps() {
        var old = appModel
        appModel = null
        desktopIndex = -1
        if (old)
            old.destroy()
    }

    function persistPreferences() {
        StreamingPreferences.save()
    }

    function refreshDesktop() {
        desktopIndex = -1
        if (!appModel)
            return
        var count = appModel.appCount()
        for (var i = 0; i < count; i++) {
            if (appModel.appNameAt(i).toLowerCase() === "desktop") {
                desktopIndex = i
                return
            }
        }
    }

    function onAppsChanged() {
        appRevision = appRevision + 1
        refreshDesktop()
    }

    function rebuildApps() {
        destroyApps()
        if (selectedIndex < 0 || !computerModel.computerPairedAt(selectedIndex))
            return
        appModel = Qt.createQmlObject("import AppModel 1.0; AppModel {}", shell, "twilightAppModel")
        if (!appModel)
            return
        appModel.initialize(ComputerManager, selectedIndex, showHidden)
        appModel.rowsInserted.connect(onAppsChanged)
        appModel.rowsRemoved.connect(onAppsChanged)
        appModel.dataChanged.connect(onAppsChanged)
        appModel.modelReset.connect(onAppsChanged)
        onAppsChanged()
    }

    function selectHost(index, fromUser) {
        if (index < 0) {
            selectedIndex = -1
            destroyApps()
            return
        }
        var changed = index !== selectedIndex || !appModel
        selectedIndex = index
        if (changed)
            rebuildApps()
        if (fromUser) {
            var uuid = computerModel.computerUuidAt(index)
            if (uuid !== "")
                StreamingPreferences.lastSelectedHostUuid = uuid
            directLaunchConsumed = false
            considerDirectLaunch()
        }
    }

    function indexForSavedHost() {
        var saved = StreamingPreferences.lastSelectedHostUuid
        if (saved === "")
            return -1
        var count = computerModel.computerCount()
        for (var i = 0; i < count; i++) {
            if (computerModel.computerUuidAt(i) === saved)
                return i
        }
        return -1
    }

    function noteComputersChanged() {
        hostRevision = hostRevision + 1
        var count = computerModel.computerCount()
        if (count <= 0) {
            selectHost(-1, false)
            return
        }
        if (selectedIndex < 0 || selectedIndex >= count || !appModel) {
            var next = selectedIndex
            if (next < 0 || next >= count) {
                var saved = indexForSavedHost()
                next = saved >= 0 ? saved : 0
            }
            selectHost(next, false)
        }
    }

    function considerDirectLaunch() {
        if (directLaunchConsumed || !appModel)
            return
        if (!computerModel.computerOnlineAt(selectedIndex) || !computerModel.computerPairedAt(selectedIndex))
            return
        var idx = appModel.getDirectLaunchAppIndex()
        if (idx < 0)
            return
        directLaunchConsumed = true
        startApp(idx, false)
    }

    function setShowHidden(next) {
        if (showHidden === next)
            return
        showHidden = next
        directLaunchConsumed = true
        rebuildApps()
    }

    function beginPair() {
        if (selectedIndex < 0)
            return
        pairPin = computerModel.generatePinString()
        computerModel.pairComputer(selectedIndex, pairPin)
        pairOpen = true
    }

    function startApp(appIndex, quitExisting) {
        if (!appModel || quitting)
            return
        if (!computerModel.computerSupportedAt(selectedIndex)) {
            showError(qsTr("This build of Twilight does not support the GeForce Experience version on %1.").arg(selectedName))
            return
        }
        if (!computerModel.computerOnlineAt(selectedIndex)) {
            toast(qsTr("This host is offline."))
            return
        }
        if (!computerModel.computerPairedAt(selectedIndex)) {
            beginPair()
            return
        }
        var name = appModel.appNameAt(appIndex)
        var appId = appModel.appIdAt(appIndex)
        var runningId = appModel.getRunningAppId()
        if (runningId !== 0 && runningId !== appId) {
            if (!quitExisting)
                return
            pendingAppIndex = appIndex
            pendingAppName = name
            quitAppName = appModel.getRunningAppName()
            quitOpen = true
            return
        }
        launchSession(appIndex, name, runningId === appId)
    }

    function launchSession(appIndex, name, isResume) {
        var component = Qt.createComponent("qrc:/gui/ui/v2/StreamSegueV2.qml")
        if (component.status === Component.Error) {
            showError(component.errorString())
            return
        }
        var session = appModel.createSessionForApp(appIndex)
        component.createObject(shell, {
            "host": shell,
            "session": session,
            "appName": name,
            "isResume": isResume
        })
    }

    function afterQuit(error) {
        ComputerManager.quitAppCompleted.disconnect(afterQuit)
        quitting = false
        if (error !== undefined && error !== null && ("" + error) !== "") {
            showError("" + error)
            return
        }
        launchSession(pendingAppIndex, pendingAppName, false)
    }

    function addComplete(success, detectedPortBlocking) {
        if (success)
            return
        var text = qsTr("Unable to connect to the specified PC.")
        if (detectedPortBlocking)
            text += "\n\n" + qsTr("This PC's Internet connection is blocking Twilight. Streaming over the Internet may not work while connected to this network.")
        showError(text)
    }

    function pairComplete(error) {
        pairOpen = false
        if (error !== undefined && error !== null && ("" + error) !== "")
            showError("" + error)
    }

    function wakeComplete(index, message, sent) {
        if (message === undefined || message === null || message === "")
            return
        if (hostSheetOpen && index === selectedIndex) {
            hostSheet.wakeNotice = message
            hostSheet.wakeNoticeSent = sent
            return
        }
        toast(message)
    }

    function testComplete(result, blockedPorts) {
        if (result === -1) {
            testMessage = qsTr("The network test could not be performed because none of Twilight's connection testing servers were reachable from this PC.")
        }
        else if (result === 0) {
            testMessage = qsTr("This network does not appear to be blocking Twilight. If you still have trouble connecting, check your PC's firewall settings.")
        }
        else {
            testMessage = qsTr("Your PC's current network connection seems to be blocking Twilight.") + "\n\n" + qsTr("The following network ports were blocked:") + "\n" + blockedPorts
        }
        testOpen = true
    }

    function dropUnavailablePyroWave() {
        if (SystemProperties.hasPyroWaveVulkan || SystemProperties.hasPyroWaveMetal)
            return
        if (StreamingPreferences.videoCodecConfig === StreamingPreferences.VCC_FORCE_PYROWAVE)
            StreamingPreferences.videoCodecConfig = StreamingPreferences.VCC_AUTO
    }

    function ensureHud() {
        if (hudWindow)
            return
        if (!hudComponent) {
            hudComponent = Qt.createComponent("qrc:/gui/ui/v2/StreamHudV2.qml", Component.PreferSynchronous)
        }
        if (hudComponent.status === Component.Loading) {
            hudComponent.statusChanged.connect(function() { shell.ensureHud() })
            return
        }
        if (hudComponent.status !== Component.Ready) {
            console.warn("Twilight HUD did not load: " + hudComponent.errorString())
            return
        }
        // Parent stays null so hiding the main window does not hide the HUD.
        // hudComponent is a shell property so the component is not collected.
        hudWindow = hudComponent.createObject(null)
        if (!hudWindow)
            console.warn("Twilight HUD window was not created: " + hudComponent.errorString())
    }

    function requestShell(version) {
        if (Window.window && Window.window.streamActive)
            return
        persistPreferences()
        if (Window.window && Window.window.activateShell)
            Window.window.activateShell(version)
    }

    ComputerModel {
        id: computerModel
        Component.onCompleted: initialize(ComputerManager)
    }

    Connections {
        target: computerModel
        onModelReset: shell.noteComputersChanged()
        onRowsInserted: shell.noteComputersChanged()
        onRowsRemoved: shell.noteComputersChanged()
        onDataChanged: shell.hostRevision = shell.hostRevision + 1
    }

    Component.onCompleted: {
        dropUnavailablePyroWave()
        ensureHud()
        ComputerManager.computerAddCompleted.connect(addComplete)
        computerModel.pairingCompleted.connect(pairComplete)
        computerModel.connectionTestCompleted.connect(testComplete)
        computerModel.wakeCompleted.connect(wakeComplete)
        noteComputersChanged()
        forceActiveFocus()
    }

    // Component.onDestruction is Qt 5.10. Preferences are written when the
    // settings sheet closes, when the shell switches, and when the window closes.

    Shortcut {
        sequence: StandardKey.Preferences
        enabled: !shell.modalOpen
        onActivated: shell.settingsOpen = true
    }
    Shortcut {
        sequence: "Escape"
        enabled: !shell.modalOpen
        onActivated: shell.leaveOpen = true
    }
    Shortcut {
        sequence: StandardKey.New
        enabled: !shell.modalOpen
        onActivated: shell.addOpen = true
    }

    Rectangle {
        anchors.fill: parent
        color: theme.bg
    }
    Rectangle {
        width: parent.width * 0.55
        height: parent.height * 0.7
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -width * 0.2
        anchors.topMargin: -height * 0.25
        radius: width
        color: theme.wash
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Item {
            width: parent.width
            height: 56
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                SymbolV2 {
                    symbol: "moon.stars"
                    pointSize: 22
                    theme: shell.theme
                    tint: theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    TwTextV2 {
                        theme: shell.theme
                        text: "Twilight"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                TwTextV2 {
                    visible: AutoUpdateChecker.availableVersion !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    theme: shell.theme
                    text: qsTr("Update")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: theme.accent
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Window.window && Window.window.openUpdatePrompt)
                                Window.window.openUpdatePrompt()
                        }
                    }
                }
                TwTextV2 {
                    anchors.verticalCenter: parent.verticalCenter
                    theme: shell.theme
                    text: qsTr("About")
                    font.pixelSize: 13
                    color: aboutArea.containsMouse ? theme.accent : theme.secondary
                    MouseArea {
                        id: aboutArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            settingsSheet.section = "about"
                            shell.settingsOpen = true
                        }
                    }
                }
                UiVersionToggle {
                    anchors.verticalCenter: parent.verticalCenter
                    darkChrome: theme.dark
                    currentVersion: "v2"
                    onRequestVersion: shell.requestShell(version)
                }
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: gearArea.containsMouse ? theme.fillStrong : theme.fill
                    border.width: 1
                    border.color: theme.stroke
                    anchors.verticalCenter: parent.verticalCenter
                    SymbolV2 {
                        anchors.centerIn: parent
                        symbol: "gearshape"
                        pointSize: 16
                        theme: shell.theme
                        tint: theme.ink
                    }
                    MouseArea {
                        id: gearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shell.settingsOpen = true
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: theme.stroke
            }
        }

        Item {
            width: parent.width
            height: parent.height - 56

            Rectangle {
                id: sidebar
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 16
                width: theme.sidebarWidth
                radius: 20
                color: theme.sidebar
                border.width: 1
                border.color: theme.stroke

                TwTextV2 {
                    id: hostsLabel
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 16
                    theme: shell.theme
                    text: qsTr("Hosts")
                    color: theme.secondary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                ListView {
                    id: hostList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: hostsLabel.bottom
                    anchors.bottom: addButton.top
                    anchors.margins: 8
                    anchors.topMargin: 8
                    clip: true
                    spacing: 4
                    model: computerModel
                    currentIndex: shell.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        width: hostList.width
                        height: 56
                        radius: 12
                        color: shell.selectedIndex === index ? theme.selection : (hostArea.containsMouse ? theme.fill : "transparent")

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: model.statusUnknown ? theme.warn : (model.online ? theme.online : theme.offline)
                        }
                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 30
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            TwTextV2 {
                                width: parent.width
                                theme: shell.theme
                                text: model.name
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            TwTextV2 {
                                width: parent.width
                                theme: shell.theme
                                color: theme.secondary
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                text: model.statusUnknown ? qsTr("Looking…")
                                      : (model.online && model.paired && model.busy) ? qsTr("Streaming")
                                      : (model.online && model.paired) ? qsTr("Ready")
                                      : (model.online && !model.paired) ? qsTr("Not paired")
                                      : model.wakeable ? qsTr("Asleep")
                                      : qsTr("Offline")
                            }
                        }
                        MouseArea {
                            id: hostArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shell.selectHost(index, true)
                        }
                    }
                }

                TwTextV2 {
                    anchors.centerIn: hostList
                    visible: {
                        var rev = shell.hostRevision
                        return rev >= 0 && computerModel.computerCount() === 0
                    }
                    theme: shell.theme
                    color: theme.secondary
                    text: qsTr("No hosts yet")
                    font.pixelSize: 13
                }

                Rectangle {
                    id: addButton
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    height: 40
                    radius: 12
                    color: addArea.containsMouse ? theme.accent : theme.fill
                    border.width: 1
                    border.color: addArea.containsMouse ? theme.accent : theme.stroke
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        SymbolV2 {
                            symbol: "plus"
                            pointSize: 14
                            theme: shell.theme
                            tint: addArea.containsMouse ? theme.accentInk : theme.ink
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        TwTextV2 {
                            theme: shell.theme
                            text: qsTr("Add host")
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: addArea.containsMouse ? theme.accentInk : theme.ink
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: addArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shell.addOpen = true
                    }
                }
            }

            Item {
                id: library
                anchors.left: sidebar.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 8
                anchors.rightMargin: 20
                anchors.topMargin: 16
                anchors.bottomMargin: 16

                Item {
                    id: emptyState
                    anchors.fill: parent
                    visible: shell.selectedIndex < 0
                    Column {
                        anchors.centerIn: parent
                        spacing: 12
                        width: 360
                        SymbolV2 {
                            symbol: "moon.stars"
                            pointSize: 36
                            theme: shell.theme
                            tint: theme.accent
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        TwTextV2 {
                            width: parent.width
                            theme: shell.theme
                            text: qsTr("Add a computer")
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        TwTextV2 {
                            width: parent.width
                            theme: shell.theme
                            color: theme.secondary
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            text: StreamingPreferences.enableMdns
                                  ? qsTr("Twilight is looking on your local network. You can also add a host by address.")
                                  : qsTr("Automatic discovery is off. Add a host by address.")
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    visible: shell.selectedIndex >= 0

                    Column {
                        id: libraryHeader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 16

                    Item {
                        width: parent.width
                        height: 72
                        Column {
                            anchors.left: parent.left
                            anchors.right: hostButton.left
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            TwTextV2 {
                                width: parent.width
                                theme: shell.theme
                                text: shell.selectedName
                                font.pixelSize: 32
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            TwTextV2 {
                                width: parent.width
                                theme: shell.theme
                                color: theme.secondary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                text: {
                                    var state = shell.selectedUnknown ? qsTr("Looking…")
                                            : shell.selectedOnline && shell.selectedPaired ? qsTr("Ready to stream")
                                            : shell.selectedOnline ? qsTr("Online, not paired")
                                            : qsTr("Offline")
                                    return state + "  ·  " + StreamingPreferences.width + "×" + StreamingPreferences.height + "  ·  " + StreamingPreferences.fps + " FPS"
                                }
                            }
                        }
                        Rectangle {
                            id: hostButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: hostLabel.implicitWidth + 36
                            height: 36
                            radius: 12
                            color: hostArea.containsMouse ? theme.fillStrong : theme.fill
                            border.width: 1
                            border.color: theme.stroke
                            TwTextV2 {
                                id: hostLabel
                                anchors.centerIn: parent
                                theme: shell.theme
                                text: qsTr("Host")
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: hostArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: shell.hostSheetOpen = true
                            }
                        }
                    }

                    Rectangle {
                        visible: shell.selectedOnline && !shell.selectedPaired
                        width: parent.width
                        height: visible ? 120 : 0
                        radius: 18
                        color: theme.glass
                        border.width: 1
                        border.color: theme.stroke
                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            width: parent.width - 32
                            TwTextV2 {
                                width: parent.width
                                theme: shell.theme
                                text: qsTr("Pair to see apps")
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                            }
                            Rectangle {
                                width: 120
                                height: 36
                                radius: 10
                                color: theme.accent
                                TwTextV2 {
                                    anchors.centerIn: parent
                                    theme: shell.theme
                                    text: qsTr("Pair")
                                    color: theme.accentInk
                                    font.weight: Font.DemiBold
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: shell.beginPair()
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: searchBox
                        visible: shell.selectedPaired
                        width: Math.min(320, parent.width)
                        height: visible ? 36 : 0
                        radius: 10
                        color: theme.field
                        border.width: 1
                        border.color: searchInput.activeFocus ? theme.accent : theme.stroke
                        SymbolV2 {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            symbol: "magnifyingglass"
                            pointSize: 14
                            theme: shell.theme
                            tint: theme.secondary
                        }
                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            anchors.leftMargin: 32
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: theme.ink
                            font.family: theme.fontFamily
                            font.pixelSize: 14
                            clip: true
                            selectByMouse: true
                            text: shell.query
                            onTextChanged: shell.query = text
                        }
                        TwTextV2 {
                            anchors.fill: searchInput
                            enabled: false
                            visible: searchInput.text === ""
                            theme: shell.theme
                            color: theme.tertiary
                            font.pixelSize: 14
                            verticalAlignment: Text.AlignVCenter
                            text: qsTr("Search apps")
                        }
                    }

                    }

                    Flickable {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: libraryHeader.bottom
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 16
                        visible: shell.selectedPaired
                        contentWidth: width
                        contentHeight: appColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: appColumn
                            width: parent.width
                            spacing: 16

                            Rectangle {
                                visible: shell.desktopShown
                                width: parent.width
                                height: visible ? 148 : 0
                                radius: 18
                                color: theme.glass
                                border.width: 1
                                border.color: theme.stroke
                                clip: true

                                Image {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 220
                                    fillMode: Image.PreserveAspectCrop
                                    horizontalAlignment: Image.AlignHCenter
                                    verticalAlignment: Image.AlignVCenter
                                    asynchronous: true
                                    source: {
                                        var rev = shell.appRevision
                                        if (!shell.desktopShown || !shell.appModel)
                                            return ""
                                        return shell.appModel.appBoxArtAt(shell.desktopIndex)
                                    }
                                }
                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 244
                                    anchors.right: streamButton.left
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    TwTextV2 {
                                        theme: shell.theme
                                        text: qsTr("Desktop")
                                        font.pixelSize: 22
                                        font.weight: Font.DemiBold
                                    }
                                    TwTextV2 {
                                        width: parent.width
                                        theme: shell.theme
                                        color: theme.secondary
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                        text: qsTr("Stream the host display.")
                                    }
                                }
                                Rectangle {
                                    id: streamButton
                                    anchors.right: parent.right
                                    anchors.rightMargin: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: streamLabel.implicitWidth + 36
                                    height: 40
                                    radius: 12
                                    color: theme.accent
                                    TwTextV2 {
                                        id: streamLabel
                                        anchors.centerIn: parent
                                        theme: shell.theme
                                        text: qsTr("Stream")
                                        color: theme.accentInk
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: shell.startApp(shell.desktopIndex, true)
                                    }
                                }
                            }

                            Grid {
                                width: parent.width
                                columns: Math.max(2, Math.floor(width / 196))
                                spacing: 16

                                Repeater {
                                    model: shell.appModel
                                    delegate: Item {
                                        property bool matches: {
                                            if (index === shell.desktopIndex)
                                                return false
                                            if (shell.query === "")
                                                return true
                                            return model.name.toLowerCase().indexOf(shell.query.toLowerCase()) !== -1
                                        }
                                        visible: matches
                                        width: matches ? 180 : 0
                                        height: matches ? 236 : 0

                                        Column {
                                            width: parent.width
                                            spacing: 8
                                            Rectangle {
                                                width: 180
                                                height: 180
                                                radius: 14
                                                color: theme.fill
                                                border.width: model.running ? 2 : 1
                                                border.color: model.running ? theme.accent : theme.stroke
                                                clip: true
                                                Image {
                                                    anchors.fill: parent
                                                    asynchronous: true
                                                    fillMode: Image.PreserveAspectCrop
                                                    source: model.boxart
                                                    opacity: model.hidden ? 0.4 : 1
                                                }
                                                Rectangle {
                                                    visible: model.running
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.margins: 8
                                                    radius: 8
                                                    width: liveLabel.implicitWidth + 12
                                                    height: 20
                                                    color: theme.accent
                                                    TwTextV2 {
                                                        id: liveLabel
                                                        anchors.centerIn: parent
                                                        theme: shell.theme
                                                        text: qsTr("Live")
                                                        color: theme.accentInk
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                                Rectangle {
                                                    z: 2
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: 8
                                                    width: 28
                                                    height: 28
                                                    radius: 14
                                                    color: model.directLaunch ? theme.accent : Qt.rgba(0, 0, 0, 0.35)
                                                    SymbolV2 {
                                                        anchors.centerIn: parent
                                                        symbol: model.directLaunch ? "star.fill" : "star"
                                                        pointSize: 13
                                                        theme: shell.theme
                                                        tint: model.directLaunch ? theme.accentInk : "#FFFFFF"
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: shell.appModel.setAppDirectLaunch(index, !model.directLaunch)
                                                    }
                                                }
                                                MouseArea {
                                                    z: 1
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                    onClicked: {
                                                        if (mouse.button === Qt.RightButton)
                                                            shell.appModel.setAppHidden(index, !model.hidden)
                                                        else
                                                            shell.startApp(index, true)
                                                    }
                                                }
                                            }
                                            TwTextV2 {
                                                width: parent.width
                                                theme: shell.theme
                                                text: model.name
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                opacity: model.hidden ? 0.45 : 1
                                            }
                                        }
                                    }
                                }
                            }

                            TwTextV2 {
                                visible: {
                                    var rev = shell.appRevision
                                    return rev >= 0 && shell.appModel && shell.appModel.appCount() === 0
                                }
                                theme: shell.theme
                                color: theme.secondary
                                font.pixelSize: 14
                                text: shell.selectedOnline ? qsTr("Looking for apps…") : qsTr("No saved apps for this host yet.")
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: shell.quitting
        color: theme.scrim
        z: 15
        TwTextV2 {
            anchors.centerIn: parent
            theme: shell.theme
            text: qsTr("Quitting %1…").arg(shell.quitAppName)
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        visible: shell.toastText !== ""
        z: 50
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        radius: 12
        color: theme.elevated
        border.width: 1
        border.color: theme.stroke
        width: toastLabel.implicitWidth + 28
        height: 36
        TwTextV2 {
            id: toastLabel
            anchors.centerIn: parent
            theme: shell.theme
            text: shell.toastText
            font.pixelSize: 13
        }
    }
    Timer {
        id: toastTimer
        interval: 2800
        onTriggered: shell.toastText = ""
    }

    HostSheetV2 {
        id: hostSheet
        theme: shell.theme
        escapeEnabled: !shell.updateDialogOpen
        open: shell.hostSheetOpen
        hostName: shell.selectedName
        online: shell.selectedOnline
        paired: shell.selectedPaired
        wakeable: shell.selectedWakeable
        busy: shell.selectedBusy
        statusUnknown: shell.selectedUnknown
        supported: shell.selectedSupported
        details: shell.selectedDetails
        showHidden: shell.showHidden
        onCloseRequested: {
            hostSheet.wakeNotice = ""
            shell.hostSheetOpen = false
        }
        onWakeRequested: computerModel.wakeComputer(shell.selectedIndex)
        onPairRequested: shell.beginPair()
        onTestRequested: computerModel.testConnectionForComputer(shell.selectedIndex)
        onRenameRequested: {
            renameDialog.fieldText = shell.selectedName
            shell.renameOpen = true
        }
        onDeleteRequested: shell.deleteOpen = true
        onShowHiddenToggled: shell.setShowHidden(next)
    }

    SettingsSheetV2 {
        id: settingsSheet
        theme: shell.theme
        escapeEnabled: !shell.updateDialogOpen
        open: shell.settingsOpen
        onCloseRequested: {
            StreamingPreferences.save()
            shell.settingsOpen = false
        }
        onToastRequested: shell.toast(message)
    }

    DialogCardV2 {
        id: addDialog
        theme: shell.theme
        open: shell.addOpen
        title: qsTr("Add host")
        message: qsTr("Enter the IP address or hostname of the computer running Sunshine or GeForce Experience.")
        confirmText: qsTr("Add")
        field: true
        fieldPlaceholder: "192.168.1.20"
        onConfirmed: {
            if (fieldText.trim() === "")
                return
            ComputerManager.addNewHostManually(fieldText.trim())
            shell.addOpen = false
        }
        onCanceled: shell.addOpen = false
    }

    DialogCardV2 {
        theme: shell.theme
        open: shell.pairOpen
        title: qsTr("Pair")
        hero: shell.pairPin
        message: qsTr("Enter this PIN on the host. On Sunshine, open the web UI. This closes when pairing finishes.")
        showConfirm: false
        cancelText: qsTr("Close")
        onCanceled: shell.pairOpen = false
    }

    DialogCardV2 {
        id: renameDialog
        theme: shell.theme
        open: shell.renameOpen
        title: qsTr("Rename host")
        message: qsTr("This name is stored by Twilight on this computer.")
        confirmText: qsTr("Save")
        field: true
        onConfirmed: {
            if (fieldText.trim() === "")
                return
            computerModel.renameComputer(shell.selectedIndex, fieldText.trim())
            shell.renameOpen = false
        }
        onCanceled: shell.renameOpen = false
    }

    DialogCardV2 {
        theme: shell.theme
        open: shell.deleteOpen
        title: qsTr("Remove host")
        message: qsTr("Remove %1 from this computer? You can add it again later.").arg(shell.selectedName)
        confirmText: qsTr("Remove")
        danger: true
        onConfirmed: {
            computerModel.deleteComputer(shell.selectedIndex)
            shell.deleteOpen = false
        }
        onCanceled: shell.deleteOpen = false
    }

    DialogCardV2 {
        theme: shell.theme
        open: shell.quitOpen
        title: qsTr("Quit the running app")
        message: qsTr("Quit %1 before starting %2? Unsaved progress on the host will be lost.").arg(shell.quitAppName).arg(shell.pendingAppName)
        confirmText: qsTr("Quit and stream")
        danger: true
        onConfirmed: {
            shell.quitOpen = false
            shell.quitting = true
            ComputerManager.quitAppCompleted.connect(shell.afterQuit)
            shell.appModel.quitRunningApp()
        }
        onCanceled: shell.quitOpen = false
    }

    DialogCardV2 {
        theme: shell.theme
        open: shell.errorOpen
        title: qsTr("Something went wrong")
        message: shell.errorMessage
        showCancel: false
        confirmText: qsTr("OK")
        onConfirmed: shell.errorOpen = false
        onCanceled: shell.errorOpen = false
    }

    DialogCardV2 {
        theme: shell.theme
        open: shell.testOpen
        title: qsTr("Network test")
        message: shell.testMessage
        showCancel: false
        confirmText: qsTr("OK")
        onConfirmed: shell.testOpen = false
        onCanceled: shell.testOpen = false
    }

    DialogCardV2 {
        theme: shell.theme
        layer: 60
        open: Window.window ? Window.window.updatePromptOpen : false
        title: qsTr("Update available")
        message: {
            var version = AutoUpdateChecker.availableVersion
            var notes = AutoUpdateChecker.releaseNotes
            var download = AutoUpdateChecker.downloadUrl
            return Window.window ? Window.window.updatePromptMessage() : ""
        }
        confirmText: {
            var download = AutoUpdateChecker.downloadUrl
            return Window.window ? Window.window.updateConfirmText() : qsTr("Download")
        }
        cancelText: qsTr("Not now")
        onConfirmed: {
            if (Window.window)
                Window.window.acceptPendingUpdate()
        }
        onCanceled: {
            if (Window.window)
                Window.window.dismissPendingUpdate()
        }
    }

    DialogCardV2 {
        theme: shell.theme
        layer: 60
        open: Window.window ? Window.window.updateInfoOpen : false
        title: Window.window ? Window.window.updateInfoTitle : ""
        message: Window.window ? Window.window.updateInfoMessage : ""
        showCancel: false
        confirmText: qsTr("OK")
        onConfirmed: {
            if (Window.window)
                Window.window.dismissUpdateInfo()
        }
        onCanceled: {
            if (Window.window)
                Window.window.dismissUpdateInfo()
        }
    }

    DialogCardV2 {
        theme: shell.theme
        open: shell.leaveOpen
        title: qsTr("Quit Twilight?")
        message: qsTr("This closes Twilight.")
        confirmText: qsTr("Quit")
        danger: true
        onConfirmed: {
            shell.persistPreferences()
            Qt.quit()
        }
        onCanceled: shell.leaveOpen = false
    }
}
