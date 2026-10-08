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
import SdlGamepadKeyNavigation 1.0

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
    property string errorHelpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"
    property string errorHelpText: ""
    property string testMessage: ""
    property string toastText: ""
    property bool quitOnly: false
    // Captured when Quit is confirmed. Cancel and a click falling through
    // onto Resume must not turn a quit-only into a launch.
    property bool quitLaunchNext: false
    property int savedNextIndex: -1
    property string savedNextName: ""
    property bool appMenuOpen: false
    property int menuAppIndex: -1
    property var appMenuEntries: []
    property string navZone: "hosts"
    property int appCursor: 0
    property int headerPos: 0
    property bool navActive: false
    property var slotByIndex: ({})
    property int slotCount: 0

    readonly property bool updateDialogOpen: Window.window !== null && (Window.window.updatePromptOpen || Window.window.updateInfoOpen)
    readonly property string updateUrl: (Window.window && Window.window.pendingUpdateUrl) ? Window.window.pendingUpdateUrl : ""
    readonly property string updateVersion: (Window.window && Window.window.pendingUpdateVersion) ? Window.window.pendingUpdateVersion : ""

    readonly property bool modalOpen: settingsOpen || hostSheetOpen || addOpen || pairOpen || renameOpen || deleteOpen || quitOpen || errorOpen || testOpen || leaveOpen || updateDialogOpen || quitting || appMenuOpen

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
        errorHelpUrl = "https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"
        errorHelpText = qsTr("Click Help for possible solutions.")
        errorMessage = text
        errorOpen = true
    }

    function destroyApps() {
        var old = appModel
        appModel = null
        desktopIndex = -1
        slotByIndex = ({})
        slotCount = 0
        appCursor = 0
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
        rebuildSlots()
        if (appMenuOpen) {
            if (!appModel || menuAppIndex < 0 || menuAppIndex >= appModel.appCount())
                appMenuOpen = false
            else
                openAppMenu(menuAppIndex)
        }
    }

    function rebuildSlots() {
        var map = {}
        var countSlots = 0
        if (desktopShown && desktopIndex >= 0) {
            map[desktopIndex] = countSlots
            countSlots = countSlots + 1
        }
        if (appModel) {
            var count = appModel.appCount()
            for (var i = 0; i < count; i++) {
                if (i === desktopIndex)
                    continue
                var name = appModel.appNameAt(i)
                if (query !== "" && name.toLowerCase().indexOf(query.toLowerCase()) === -1)
                    continue
                map[i] = countSlots
                countSlots = countSlots + 1
            }
        }
        slotByIndex = map
        slotCount = countSlots
        if (appCursor >= slotCount)
            appCursor = Math.max(0, slotCount - 1)
    }

    function appIndexForCursor() {
        var keys = Object.keys(slotByIndex)
        for (var i = 0; i < keys.length; i++) {
            if (slotByIndex[keys[i]] === appCursor)
                return parseInt(keys[i], 10)
        }
        return -1
    }

    function headerIds() {
        var ids = []
        if (updateUrl !== "" || AutoUpdateChecker.availableVersion !== "")
            ids.push("update")
        ids.push("settings")
        return ids
    }

    function headerArmed(id) {
        if (navZone !== "header" || !navActive)
            return false
        var ids = headerIds()
        return headerPos >= 0 && headerPos < ids.length && ids[headerPos] === id
    }

    function focusNav() {
        if (modalOpen)
            return
        if (navZone === "search")
            searchInput.forceActiveFocus()
        else
            navSink.forceActiveFocus()
    }

    function revealAppCursor() {
        if (!appFlick || slotCount <= 0)
            return
        var y = 0
        var desktopSlots = desktopShown ? 1 : 0
        if (desktopSlots && appCursor > 0)
            y = 148 + 16
        if (!(desktopSlots && appCursor === 0)) {
            var gridIndex = appCursor - desktopSlots
            var cols = appGrid ? Math.max(1, appGrid.columns) : 2
            var row = Math.floor(Math.max(0, gridIndex) / cols)
            y = y + row * (236 + 16)
        }
        if (y < appFlick.contentY)
            appFlick.contentY = y
        else if (y + 200 > appFlick.contentY + appFlick.height)
            appFlick.contentY = Math.max(0, y + 236 - appFlick.height)
    }

    function moveHost(delta) {
        var count = computerModel.computerCount()
        if (count <= 0) {
            navZone = "addHost"
            return
        }
        if (navZone === "addHost") {
            if (delta < 0) {
                navZone = "hosts"
                selectHost(count - 1, false)
                hostList.positionViewAtIndex(count - 1, ListView.Contain)
            }
            return
        }
        if (navZone !== "hosts")
            navZone = "hosts"
        var next = selectedIndex + delta
        if (next < 0) {
            navZone = "header"
            headerPos = 0
            return
        }
        if (next >= count) {
            navZone = "addHost"
            return
        }
        selectHost(next, false)
        hostList.positionViewAtIndex(next, ListView.Contain)
    }

    function enterApps() {
        if (selectedIndex < 0 || !selectedPaired) {
            if (selectedIndex >= 0 && selectedOnline && !selectedPaired)
                beginPair()
            else if (selectedIndex >= 0)
                hostSheetOpen = true
            return
        }
        rebuildSlots()
        navZone = slotCount > 0 ? "apps" : "hosts"
        if (appCursor < 0 || appCursor >= slotCount)
            appCursor = 0
        revealAppCursor()
    }

    function moveApp(dx, dy) {
        if (slotCount <= 0) {
            navZone = "hosts"
            return
        }
        var desktopSlots = desktopShown ? 1 : 0
        var cols = appGrid ? Math.max(1, appGrid.columns) : 2
        if (desktopSlots && appCursor === 0) {
            if (dx < 0) {
                navZone = "hosts"
                return
            }
            if (dy > 0 && slotCount > 1)
                appCursor = 1
            else if (dy < 0) {
                navZone = "search"
                searchInput.forceActiveFocus()
            }
            revealAppCursor()
            return
        }
        var gridIndex = appCursor - desktopSlots
        var col = gridIndex % cols
        if (dx < 0 && col === 0) {
            navZone = "hosts"
            return
        }
        if (dy < 0 && gridIndex < cols) {
            if (desktopSlots)
                appCursor = 0
            else {
                navZone = "search"
                searchInput.forceActiveFocus()
            }
            revealAppCursor()
            return
        }
        var next = gridIndex + dx + dy * cols
        var gridCount = slotCount - desktopSlots
        if (next < 0 || next >= gridCount)
            return
        appCursor = next + desktopSlots
        revealAppCursor()
    }

    function activateHost() {
        if (navZone === "addHost" || computerModel.computerCount() === 0) {
            addOpen = true
            return
        }
        if (selectedIndex < 0)
            return
        if (!selectedOnline) {
            hostSheetOpen = true
            return
        }
        if (!selectedPaired) {
            beginPair()
            return
        }
        if (!selectedSupported) {
            showError(qsTr("This build of Twilight does not support the GeForce Experience version on %1.").arg(selectedName))
            return
        }
        var directIndex = appModel ? appModel.getDirectLaunchAppIndex() : -1
        if (directIndex >= 0) {
            directLaunchConsumed = false
            considerDirectLaunch()
            return
        }
        enterApps()
    }

    function activateApp() {
        var index = appIndexForCursor()
        if (index < 0 || !appModel)
            return
        if (appModel.appRunningAt(index))
            openAppMenu(index)
        else
            startApp(index, true)
    }

    function activateHeader() {
        var ids = headerIds()
        if (headerPos < 0 || headerPos >= ids.length)
            return
        var id = ids[headerPos]
        if (id === "update") {
            // Same as clicking the header Update chip: ask first (PR25).
            if (Window.window && Window.window.openUpdatePrompt)
                Window.window.openUpdatePrompt()
            else if (updateUrl !== "")
                Qt.openUrlExternally(updateUrl)
        }
        else if (id === "settings")
            settingsOpen = true
    }

    function moveHeader(delta) {
        var ids = headerIds()
        if (ids.length === 0)
            return
        var next = headerPos + delta
        if (next < 0)
            next = 0
        if (next >= ids.length)
            next = ids.length - 1
        headerPos = next
    }

    function canHideApp(index) {
        if (!appModel || index < 0)
            return false
        return appModel.appHiddenAt(index) || (!appModel.appRunningAt(index) && !appModel.appDirectLaunchAt(index))
    }

    function trySetHidden(index, hidden) {
        if (!appModel || index < 0)
            return
        if (hidden && !canHideApp(index)) {
            if (appModel.appRunningAt(index))
                toast(qsTr("Quit %1 before hiding it.").arg(appModel.appNameAt(index)))
            else
                toast(qsTr("Turn off direct launch before hiding %1.").arg(appModel.appNameAt(index)))
            return
        }
        appModel.setAppHidden(index, hidden)
        if (hidden)
            toast(qsTr("Hidden. It stays here so you can show it again. Host → Show hidden apps brings it back later."))
    }

    function trySetDirect(index, next) {
        if (!appModel || index < 0)
            return
        if (next && appModel.appHiddenAt(index)) {
            toast(qsTr("Show %1 in the library before turning on direct launch.").arg(appModel.appNameAt(index)))
            return
        }
        appModel.setAppDirectLaunch(index, next)
    }

    function openAppMenu(index) {
        if (!appModel || index < 0)
            return
        menuAppIndex = index
        var running = appModel.appRunningAt(index)
        var hidden = appModel.appHiddenAt(index)
        var direct = appModel.appDirectLaunchAt(index)
        // "action", not "id": QML does not round-trip an "id" field on a plain object.
        var entries = [{ action: "launch", text: running ? qsTr("Resume") : qsTr("Launch"), enabled: true }]
        if (running)
            entries.push({ action: "quit", text: qsTr("Quit"), enabled: true })
        entries.push({ action: "direct", text: direct ? qsTr("Direct launch on") : qsTr("Direct launch"), enabled: !hidden })
        entries.push({ action: "hide", text: hidden ? qsTr("Show in library") : qsTr("Hide"), enabled: canHideApp(index) })
        appMenuEntries = entries
        appMenuOpen = true
    }

    function pickAppMenu(action) {
        var index = menuAppIndex
        if (!appModel || index < 0) {
            appMenuOpen = false
            return
        }
        // Open the quit dialog before closing the menu so modalOpen stays
        // true. Closing first drops focus onto the grid, and the same
        // confirm key resumes the running app instead of quitting it.
        if (action === "quit") {
            requestQuitOnly()
            appMenuOpen = false
            return
        }
        appMenuOpen = false
        if (action === "launch")
            startApp(index, true)
        else if (action === "direct")
            trySetDirect(index, !appModel.appDirectLaunchAt(index))
        else if (action === "hide")
            trySetHidden(index, !appModel.appHiddenAt(index))
    }

    function requestQuitOnly() {
        if (!appModel || quitting)
            return
        if (appModel.getRunningAppId() === 0) {
            toast(qsTr("Nothing is running on this host."))
            return
        }
        quitOnly = true
        pendingAppIndex = -1
        pendingAppName = ""
        quitAppName = appModel.getRunningAppName()
        quitOpen = true
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
            navZone = "addHost"
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
            quitOnly = false
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
            "isResume": isResume,
            // Resolve on this Item, not inside StreamSegueV2's Timer (#28).
            "hostWindow": Window.window
        })
    }

    function confirmQuit() {
        if (!appModel || quitting)
            return
        if (appModel.getRunningAppId() === 0) {
            quitOpen = false
            quitOnly = false
            toast(qsTr("Nothing is running on this host."))
            return
        }
        // Snapshot before the dialog closes. Hiding it delivers the same
        // click to whatever is underneath (often Resume) and Cancel clears
        // quitOnly. Either one used to start another session instead of
        // stopping the host app.
        savedNextIndex = pendingAppIndex
        savedNextName = pendingAppName
        quitLaunchNext = !quitOnly && savedNextIndex >= 0
        quitting = true
        quitOpen = false
        appModel.quitRunningApp()
    }

    function afterQuit(error) {
        if (!quitting)
            return
        var launchNext = quitLaunchNext
        var nextIndex = savedNextIndex
        var nextName = savedNextName
        quitting = false
        quitOnly = false
        quitLaunchNext = false
        pendingAppIndex = -1
        pendingAppName = ""
        savedNextIndex = -1
        savedNextName = ""
        if (error !== undefined && error !== null && ("" + error) !== "") {
            showError("" + error)
            return
        }
        if (launchNext)
            launchSession(nextIndex, nextName, false)
    }

    function addComplete(success, detectedPortBlocking) {
        if (success)
            return
        var text = qsTr("Unable to connect to the specified PC.")
        if (detectedPortBlocking)
            text += "\n\n" + qsTr("This PC's Internet connection is blocking Twilight. Streaming over the Internet may not work while connected to this network.")
        errorHelpUrl = "https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide"
        errorHelpText = detectedPortBlocking ? "" : qsTr("Click Help for possible solutions.")
        errorMessage = text
        errorOpen = true
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

    // Stays for the life of the shell. Connecting shell.afterQuit from the
    // dialog did not keep the slot, so Quit never left "Quitting…".
    Connections {
        target: ComputerManager
        onQuitAppCompleted: shell.afterQuit(error)
    }

    Component.onCompleted: {
        dropUnavailablePyroWave()
        ensureHud()
        ComputerManager.computerAddCompleted.connect(addComplete)
        computerModel.pairingCompleted.connect(pairComplete)
        computerModel.connectionTestCompleted.connect(testComplete)
        computerModel.wakeCompleted.connect(wakeComplete)
        noteComputersChanged()
        if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0 && selectedIndex < 0 && computerModel.computerCount() > 0)
            selectHost(0, false)
        focusNav()
    }

    onModalOpenChanged: if (!modalOpen) focusNav()
    onQueryChanged: rebuildSlots()

    // Component.onDestruction is Qt 5.10. Preferences are written when the
    // settings sheet closes and when the window closes.

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
                Rectangle {
                    id: updateHit
                    visible: shell.updateUrl !== "" || (AutoUpdateChecker.availableVersion !== "")
                    width: visible ? updateLabel.implicitWidth + 28 : 0
                    height: 36
                    radius: 18
                    color: updateArea.containsMouse ? theme.fillStrong : theme.fill
                    border.width: shell.headerArmed("update") ? 2 : 1
                    border.color: shell.headerArmed("update") ? theme.accent : theme.stroke
                    anchors.verticalCenter: parent.verticalCenter
                    TwTextV2 {
                        id: updateLabel
                        anchors.centerIn: parent
                        theme: shell.theme
                        text: qsTr("Update %1").arg(shell.updateVersion !== "" ? shell.updateVersion : AutoUpdateChecker.availableVersion)
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: theme.accent
                    }
                    MouseArea {
                        id: updateArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            shell.navZone = "header"
                            if (Window.window && Window.window.openUpdatePrompt)
                                Window.window.openUpdatePrompt()
                            else if (shell.updateUrl !== "")
                                Qt.openUrlExternally(shell.updateUrl)
                        }
                    }
                }
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: gearArea.containsMouse ? theme.fillStrong : theme.fill
                    border.width: shell.headerArmed("settings") ? 2 : 1
                    border.color: shell.headerArmed("settings") ? theme.accent : theme.stroke
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
                        border.width: shell.navZone === "hosts" && shell.navActive && shell.selectedIndex === index ? 2 : 0
                        border.color: theme.accent

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
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: {
                                shell.navZone = "hosts"
                                if (mouse.button === Qt.RightButton) {
                                    shell.selectHost(index, false)
                                    shell.hostSheetOpen = true
                                }
                                else {
                                    shell.selectHost(index, true)
                                }
                                shell.focusNav()
                            }
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
                    border.width: shell.navZone === "addHost" && shell.navActive ? 2 : 1
                    border.color: (addArea.containsMouse || (shell.navZone === "addHost" && shell.navActive)) ? theme.accent : theme.stroke
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
                        onClicked: {
                            shell.navZone = "addHost"
                            shell.addOpen = true
                        }
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
                            onActiveFocusChanged: if (activeFocus) shell.navZone = "search"
                            Keys.onDownPressed: {
                                shell.navZone = "apps"
                                shell.focusNav()
                            }
                            Keys.onEscapePressed: {
                                text = ""
                                shell.navZone = "apps"
                                shell.focusNav()
                            }
                            Keys.onUpPressed: {
                                shell.navZone = "header"
                                shell.headerPos = 0
                                shell.focusNav()
                            }
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
                        id: appFlick
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
                                border.width: shell.navZone === "apps" && shell.navActive && shell.slotByIndex[shell.desktopIndex] === shell.appCursor ? 2 : 1
                                border.color: shell.navZone === "apps" && shell.navActive && shell.slotByIndex[shell.desktopIndex] === shell.appCursor ? theme.accent : theme.stroke
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
                                Column {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Rectangle {
                                        id: streamButton
                                        width: streamLabel.implicitWidth + 36
                                        height: 40
                                        radius: 12
                                        color: theme.accent
                                        TwTextV2 {
                                            id: streamLabel
                                            anchors.centerIn: parent
                                            theme: shell.theme
                                            text: {
                                                var rev = shell.appRevision
                                                return shell.appModel && shell.appModel.appRunningAt(shell.desktopIndex) ? qsTr("Resume") : qsTr("Stream")
                                            }
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
                                    Row {
                                        spacing: 8
                                        anchors.right: parent.right
                                        Rectangle {
                                            visible: {
                                                var rev = shell.appRevision
                                                return shell.appModel && shell.appModel.appRunningAt(shell.desktopIndex)
                                            }
                                            width: visible ? desktopQuitLabel.implicitWidth + 24 : 0
                                            height: 32
                                            radius: 10
                                            color: theme.danger
                                            TwTextV2 {
                                                id: desktopQuitLabel
                                                anchors.centerIn: parent
                                                theme: shell.theme
                                                text: qsTr("Quit")
                                                color: "#FFFFFF"
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: shell.requestQuitOnly()
                                            }
                                        }
                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 10
                                            color: theme.fill
                                            border.width: 1
                                            border.color: theme.stroke
                                            opacity: shell.canHideApp(shell.desktopIndex) ? 1 : 0.4
                                            SymbolV2 {
                                                anchors.centerIn: parent
                                                symbol: shell.appModel && shell.appModel.appHiddenAt(shell.desktopIndex) ? "eye" : "eye.slash"
                                                pointSize: 14
                                                theme: shell.theme
                                                tint: theme.ink
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: shell.trySetHidden(shell.desktopIndex, !(shell.appModel && shell.appModel.appHiddenAt(shell.desktopIndex)))
                                            }
                                        }
                                    }
                                }
                            }

                            Grid {
                                id: appGrid
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
                                                border.width: (model.running || (shell.navZone === "apps" && shell.navActive && shell.slotByIndex[index] === shell.appCursor)) ? 2 : 1
                                                border.color: (model.running || (shell.navZone === "apps" && shell.navActive && shell.slotByIndex[index] === shell.appCursor)) ? theme.accent : theme.stroke
                                                clip: true
                                                Image {
                                                    anchors.fill: parent
                                                    asynchronous: true
                                                    fillMode: Image.PreserveAspectCrop
                                                    source: model.boxart
                                                    opacity: model.hidden ? 0.4 : 1
                                                }
                                                MouseArea {
                                                    z: 0
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                    onClicked: {
                                                        shell.navZone = "apps"
                                                        shell.appCursor = shell.slotByIndex[index] !== undefined ? shell.slotByIndex[index] : shell.appCursor
                                                        if (mouse.button === Qt.RightButton)
                                                            shell.openAppMenu(index)
                                                        else if (!model.running)
                                                            shell.startApp(index, true)
                                                        else
                                                            shell.openAppMenu(index)
                                                        shell.focusNav()
                                                    }
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
                                                        onClicked: shell.trySetDirect(index, !model.directLaunch)
                                                    }
                                                }
                                                Rectangle {
                                                    z: 3
                                                    anchors.left: parent.left
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: 8
                                                    width: 28
                                                    height: 28
                                                    radius: 14
                                                    color: Qt.rgba(0, 0, 0, 0.45)
                                                    opacity: shell.canHideApp(index) ? 1 : 0.4
                                                    SymbolV2 {
                                                        anchors.centerIn: parent
                                                        symbol: model.hidden ? "eye" : "eye.slash"
                                                        pointSize: 13
                                                        theme: shell.theme
                                                        tint: "#FFFFFF"
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: shell.trySetHidden(index, !model.hidden)
                                                    }
                                                }
                                                Rectangle {
                                                    z: 3
                                                    visible: model.running
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: 8
                                                    width: quitTileLabel.implicitWidth + 16
                                                    height: 28
                                                    radius: 14
                                                    color: theme.danger
                                                    TwTextV2 {
                                                        id: quitTileLabel
                                                        anchors.centerIn: parent
                                                        theme: shell.theme
                                                        text: qsTr("Quit")
                                                        color: "#FFFFFF"
                                                        font.pixelSize: 12
                                                        font.weight: Font.DemiBold
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: shell.requestQuitOnly()
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
        keysOn: shell.hostSheetOpen && !shell.renameOpen && !shell.deleteOpen && !shell.pairOpen && !shell.errorOpen && !shell.testOpen && !shell.quitOpen && !shell.addOpen && !shell.leaveOpen && !shell.settingsOpen && !shell.appMenuOpen
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
        onQuitRequested: shell.requestQuitOnly()
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
        message: shell.quitOnly
                ? qsTr("Quit %1? Unsaved progress on the host will be lost.").arg(shell.quitAppName)
                : qsTr("Quit %1 before starting %2? Unsaved progress on the host will be lost.").arg(shell.quitAppName).arg(shell.pendingAppName)
        confirmText: shell.quitOnly ? qsTr("Quit") : qsTr("Quit and stream")
        danger: true
        onConfirmed: shell.confirmQuit()
        onCanceled: {
            if (shell.quitting)
                return
            shell.quitOnly = false
            shell.quitOpen = false
        }
    }

    DialogCardV2 {
        theme: shell.theme
        open: shell.errorOpen
        title: qsTr("Something went wrong")
        message: shell.errorMessage
        helpUrl: shell.errorHelpUrl
        helpText: shell.errorHelpText
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
        overlayZ: 60
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
        overlayZ: 60
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

    MenuCardV2 {
        theme: shell.theme
        open: shell.appMenuOpen
        title: shell.menuAppIndex >= 0 && shell.appModel ? shell.appModel.appNameAt(shell.menuAppIndex) : ""
        entries: shell.appMenuEntries
        onPicked: shell.pickAppMenu(entryId)
        onDismissed: shell.appMenuOpen = false
    }

    Item {
        id: navSink
        focus: !shell.modalOpen && shell.navZone !== "search"
        onActiveFocusChanged: shell.navActive = activeFocus
        Keys.onPressed: {
            if (shell.modalOpen || shell.navZone === "search")
                return
            var handled = false
            if (event.key === Qt.Key_Hangup) {
                shell.settingsOpen = true
                handled = true
            }
            else if (event.key === Qt.Key_Menu) {
                if (shell.navZone === "apps") {
                    var appIndex = shell.appIndexForCursor()
                    if (appIndex >= 0)
                        shell.openAppMenu(appIndex)
                }
                else if (shell.selectedIndex >= 0)
                    shell.hostSheetOpen = true
                handled = true
            }
            else if (event.key === Qt.Key_Delete) {
                if (shell.navZone !== "apps" && shell.selectedIndex >= 0)
                    shell.deleteOpen = true
                handled = true
            }
            else if (shell.navZone === "header") {
                if (event.key === Qt.Key_Left)
                    shell.moveHeader(-1)
                else if (event.key === Qt.Key_Right)
                    shell.moveHeader(1)
                else if (event.key === Qt.Key_Down)
                    shell.navZone = computerModel.computerCount() > 0 ? "hosts" : "addHost"
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                    shell.activateHeader()
                else
                    return
                handled = true
            }
            else if (shell.navZone === "apps") {
                if (event.key === Qt.Key_Left)
                    shell.moveApp(-1, 0)
                else if (event.key === Qt.Key_Right)
                    shell.moveApp(1, 0)
                else if (event.key === Qt.Key_Up)
                    shell.moveApp(0, -1)
                else if (event.key === Qt.Key_Down)
                    shell.moveApp(0, 1)
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                    shell.activateApp()
                else
                    return
                handled = true
            }
            else {
                if (event.key === Qt.Key_Up)
                    shell.moveHost(-1)
                else if (event.key === Qt.Key_Down)
                    shell.moveHost(1)
                else if (event.key === Qt.Key_Right)
                    shell.enterApps()
                else if (event.key === Qt.Key_Left)
                    shell.navZone = "hosts"
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                    shell.activateHost()
                else
                    return
                handled = true
            }
            event.accepted = handled
        }
    }
}
