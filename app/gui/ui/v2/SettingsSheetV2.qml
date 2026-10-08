import QtQuick 2.9
import QtQuick.Window 2.2

import StreamingPreferences 1.0
import SystemProperties 1.0
import ComputerManager 1.0
import AutoUpdateChecker 1.0
import SdlGamepadKeyNavigation 1.0

Item {
    id: sheet
    property var theme
    property bool open: false
    signal closeRequested()
    signal toastRequested(string message)

    property string section: "video"
    property bool escapeEnabled: true
    property var resolutionOptions: []
    property var fpsOptions: []
    property bool customResOpen: false
    property bool customFpsOpen: false
    property int focusPos: 0
    // Not bound to enableMicrophone. Turning the switch on asks macOS
    // first, and the preference stays off until that result arrives.
    property bool micWanted: false

    readonly property string updateUrl: (Window.window && Window.window.pendingUpdateUrl) ? Window.window.pendingUpdateUrl : ""
    readonly property string updateVersion: (Window.window && Window.window.pendingUpdateVersion) ? Window.window.pendingUpdateVersion : ""

    anchors.fill: parent
    visible: open || hideTimer.running
    opacity: open ? 1 : 0
    enabled: open
    z: 30
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    onOpenChanged: {
        if (open) {
            StreamingPreferences.refreshMicrophoneStatus()
            SystemProperties.refreshDisplays()
            rebuildChoices()
            bitrateInput.text = StreamingPreferences.bitrateMbpsText(StreamingPreferences.bitrateKbps)
            SdlGamepadKeyNavigation.setUiNavMode(true)
            focusPos = 0
            paintFocus()
            keySink.forceActiveFocus()
        }
        else {
            SdlGamepadKeyNavigation.setUiNavMode(false)
            customResOpen = false
            customFpsOpen = false
            hideTimer.start()
        }
    }
    onSectionChanged: {
        var list = chain()
        if (focusPos >= list.length)
            focusPos = 0
        paintFocus()
    }
    onCustomResOpenChanged: if (!customResOpen && open && !customFpsOpen) keySink.forceActiveFocus()
    onCustomFpsOpenChanged: if (!customFpsOpen && open && !customResOpen) keySink.forceActiveFocus()
    Timer { id: hideTimer; interval: 180 }

    function resKey(w, h) { return w + "x" + h }

    function addResolution(list, text, w, h) {
        w = parseInt(w, 10)
        h = parseInt(h, 10)
        if (!(w > 0) || !(h > 0))
            return
        for (var i = 0; i < list.length; i++) {
            if (list[i].w === w && list[i].h === h)
                return
        }
        var pixels = w * h
        var index = 0
        for (var j = 0; j < list.length; j++) {
            if (pixels > list[j].w * list[j].h)
                index = j + 1
        }
        list.splice(index, 0, { text: text, value: resKey(w, h), w: w, h: h })
    }

    function addRate(list, rate, text) {
        rate = parseInt(rate, 10)
        if (!(rate > 0))
            return
        for (var i = 0; i < list.length; i++) {
            if (list[i].value === rate)
                return
        }
        var index = 0
        for (var j = 0; j < list.length; j++) {
            if (rate > list[j].value)
                index = j + 1
        }
        list.splice(index, 0, { text: text, value: rate })
    }

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
        var displayIndex = 0
        var guard = 0
        while (guard < 16) {
            var screenRect = SystemProperties.getNativeResolution(displayIndex)
            var safeAreaRect = SystemProperties.getSafeAreaResolution(displayIndex)
            if (!screenRect || screenRect.width === 0) {
                break
            }
            addResolution(resolutions, qsTr("Native (%1×%2)").arg(screenRect.width).arg(screenRect.height), screenRect.width, screenRect.height)
            if (safeAreaRect && safeAreaRect.width > 0)
                addResolution(resolutions, qsTr("Native (Excluding Notch) (%1×%2)").arg(safeAreaRect.width).arg(safeAreaRect.height), safeAreaRect.width, safeAreaRect.height)
            displayIndex = displayIndex + 1
            guard = guard + 1
        }
        var maxRes = SystemProperties.maximumResolution
        var maxPixels = maxRes ? maxRes.width * maxRes.height : 0
        if (maxPixels > 0) {
            var kept = []
            for (var k = 0; k < resolutions.length; k++) {
                if (resolutions[k].w * resolutions[k].h <= maxPixels)
                    kept.push(resolutions[k])
            }
            resolutions = kept
        }
        var savedW = StreamingPreferences.width
        var savedH = StreamingPreferences.height
        var haveSize = false
        for (var s = 0; s < resolutions.length; s++) {
            if (resolutions[s].w === savedW && resolutions[s].h === savedH)
                haveSize = true
        }
        if (!haveSize && savedW > 0 && savedH > 0)
            resolutions.push({ text: qsTr("Custom (%1×%2)").arg(savedW).arg(savedH), value: resKey(savedW, savedH), w: savedW, h: savedH })
        resolutions.push({ text: qsTr("Custom…"), value: "custom", w: 0, h: 0 })
        resolutionOptions = resolutions

        var rates = [
            { text: qsTr("30 FPS"), value: 30 },
            { text: qsTr("60 FPS"), value: 60 }
        ]
        displayIndex = 0
        guard = 0
        while (guard < 16) {
            var refreshRate = SystemProperties.getRefreshRate(displayIndex)
            if (refreshRate === 0)
                break
            addRate(rates, refreshRate, qsTr("%1 FPS").arg(refreshRate))
            displayIndex = displayIndex + 1
            guard = guard + 1
        }
        var savedFps = StreamingPreferences.fps
        var haveFps = false
        for (var f = 0; f < rates.length; f++) {
            if (rates[f].value === savedFps)
                haveFps = true
        }
        if (!haveFps && savedFps > 0)
            rates.push({ text: qsTr("Custom (%1 FPS)").arg(savedFps), value: savedFps })
        rates.push({ text: qsTr("Custom…"), value: "custom" })
        fpsOptions = rates
    }

    function optionSelected(options, value) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].value == value)
                return true
        }
        return false
    }

    function parseDim(text, placeholder) {
        var raw = (text !== undefined && text !== null && ("" + text) !== "") ? ("" + text) : ("" + placeholder)
        if (!/^[0-9]+$/.test(raw))
            return 0
        return parseInt(raw, 10)
    }

    function applyResolution(key) {
        if (key === "custom") {
            customResDialog.fieldText = ""
            customResDialog.field2Text = ""
            customResOpen = true
            return
        }
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
        rebuildChoices()
    }

    function acceptCustomResolution() {
        var w = parseDim(customResDialog.fieldText, customResDialog.fieldPlaceholder)
        var h = parseDim(customResDialog.field2Text, customResDialog.field2Placeholder)
        if (w < 256 || w > 8192 || h < 256 || h > 8192) {
            toastRequested(qsTr("Enter a width and height from 256 to 8192."))
            return
        }
        StreamingPreferences.width = w
        StreamingPreferences.height = h
        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(w, h, StreamingPreferences.fps, StreamingPreferences.enableYUV444)
        StreamingPreferences.save()
        customResOpen = false
        rebuildChoices()
    }

    function applyFps(fps) {
        if (fps === "custom") {
            customFpsDialog.fieldText = ""
            customFpsOpen = true
            return
        }
        var rate = parseInt(fps, 10)
        if (!(rate > 0))
            return
        if (StreamingPreferences.fps === rate)
            return
        StreamingPreferences.fps = rate
        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                    StreamingPreferences.width, StreamingPreferences.height, rate, StreamingPreferences.enableYUV444)
        StreamingPreferences.save()
        rebuildChoices()
    }

    function acceptCustomFps() {
        var rate = parseDim(customFpsDialog.fieldText, customFpsDialog.fieldPlaceholder)
        if (rate < 10 || rate > 9999) {
            toastRequested(qsTr("Enter a frame rate from 10 to 9999."))
            return
        }
        applyFps(rate)
        customFpsOpen = false
    }

    function commitBitrateKbps(kbps) {
        if (kbps > 150000)
            StreamingPreferences.unlockBitrate = true
        StreamingPreferences.bitrateKbps = kbps
        bitrateInput.text = StreamingPreferences.bitrateMbpsText(kbps)
    }

    function commitBitrateText(raw) {
        var kbps = StreamingPreferences.bitrateKbpsFromMbpsText(raw)
        var shown = StreamingPreferences.bitrateMbpsText(StreamingPreferences.bitrateKbps)
        if (kbps < 0) {
            bitrateInput.text = shown
            if ((raw + "").trim() !== shown) {
                toastRequested(qsTr("Enter a bitrate from %1 to %2 Mb/s. That number was not applied.")
                               .arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.minimumBitrateKbps()))
                               .arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.maximumBitrateKbps())))
            }
            return
        }
        commitBitrateKbps(kbps)
    }

    function commitSliderBitrate(kbps) {
        var current = StreamingPreferences.bitrateKbps
        var floor = StreamingPreferences.minimumBitrateKbps()
        var cap = StreamingPreferences.maximumBitrateKbps()
        if (current < floor || current > cap) {
            toastRequested(qsTr("The slider replaced the saved %1 Mb/s. It only sets values from %2 to %3.")
                           .arg(StreamingPreferences.bitrateMbpsText(current))
                           .arg(StreamingPreferences.bitrateMbpsText(floor))
                           .arg(StreamingPreferences.bitrateMbpsText(cap)))
        }
        commitBitrateKbps(kbps)
    }

    function requestClose() {
        // Dropping focus commits the field. forceActiveFocus() would break
        // keySink's focus binding.
        if (bitrateInput.activeFocus)
            bitrateInput.focus = false
        closeRequested()
    }

    function applyUnlimited() {
        var cap = StreamingPreferences.maximumBitrateKbps()
        var current = StreamingPreferences.bitrateKbps
        if (current === cap)
            return
        if (current > cap) {
            toastRequested(qsTr("Unlimited sends %1 Mb/s. %2 Mb/s is more than this client will ask a host for, so it was not kept.")
                           .arg(StreamingPreferences.bitrateMbpsText(cap))
                           .arg(StreamingPreferences.bitrateMbpsText(current)))
        }
        commitBitrateKbps(cap)
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

    function chain() {
        var ids = []
        if (updateUrl !== "")
            ids.push("update")
        ids.push("close")
        if (sectionNav) {
            for (var s = 0; s < sectionNav.count; s++) {
                var sectionItem = sectionNav.itemAt(s)
                if (sectionItem)
                    ids.push("section:" + sectionItem.navId)
            }
        }
        if (section === "video") {
            ids.push("res")
            ids.push("fps")
            ids.push("bitrate")
            ids.push("bitrateUnlimited")
            ids.push("vsync")
            ids.push("pace")
            ids.push("window")
            ids.push("hdr")
            ids.push("yuv")
        }
        else if (section === "audio") {
            ids.push("audio")
            ids.push("spatial")
            ids.push("head")
            ids.push("muteHost")
            ids.push("muteBack")
            if (Qt.platform.os === "osx")
                ids.push("mic")
        }
        else if (section === "input") {
            ids.push("absolute")
            if (Qt.platform.os === "osx")
                ids.push("corehid")
            ids.push("touch")
            ids.push("syskeys")
            ids.push("swapMouse")
            ids.push("scroll")
            ids.push("swapFace")
            ids.push("padMouse")
            ids.push("bgPad")
            ids.push("multi")
        }
        else if (section === "network") {
            ids.push("mdns")
            ids.push("blocking")
            ids.push("warnings")
        }
        else if (section === "advanced") {
            ids.push("codec")
            if (SystemProperties.hasPyroWaveMetal && SystemProperties.hasPyroWaveVulkan)
                ids.push("pyro")
            ids.push("decoder")
            ids.push("optim")
            ids.push("quitAfter")
            ids.push("awake")
            ids.push("presence")
            ids.push("classicHud")
            ids.push("twilightHud")
            if (SystemProperties.hasDesktopEnvironment)
                ids.push("uiMode")
        }
        else if (section === "about") {
            ids.push("checkUpdate")
            if (SystemProperties.hasBrowser)
                ids.push("aboutSource")
        }
        return ids
    }

    function currentFocusId() {
        var ids = chain()
        if (ids.length === 0)
            return ""
        if (focusPos < 0 || focusPos >= ids.length)
            return ids[0]
        return ids[focusPos]
    }

    function itemFor(id) {
        if (id === "update") return updateRow
        if (id === "close") return closeHit
        if (id === "checkUpdate") return checkUpdateHit
        if (id === "aboutSource") return aboutSource
        if (id === "res") return resChoice
        if (id === "fps") return fpsChoice
        if (id === "bitrate") return bitrateRow
        if (id === "bitrateUnlimited") return unlimitedChip
        if (id === "vsync") return vsyncSwitch
        if (id === "pace") return paceSwitch
        if (id === "window") return windowChoice
        if (id === "hdr") return hdrSwitch
        if (id === "yuv") return yuvSwitch
        if (id === "audio") return audioChoice
        if (id === "spatial") return spatialChoice
        if (id === "head") return headSwitch
        if (id === "muteHost") return muteHostSwitch
        if (id === "muteBack") return muteBackSwitch
        if (id === "mic") return micSwitch
        if (id === "absolute") return absoluteSwitch
        if (id === "corehid") return coreHidSwitch
        if (id === "touch") return touchSwitch
        if (id === "syskeys") return sysKeysChoice
        if (id === "swapMouse") return swapMouseSwitch
        if (id === "scroll") return scrollSwitch
        if (id === "swapFace") return swapFaceSwitch
        if (id === "padMouse") return padMouseSwitch
        if (id === "bgPad") return bgPadSwitch
        if (id === "multi") return multiSwitch
        if (id === "mdns") return mdnsSwitch
        if (id === "blocking") return blockingSwitch
        if (id === "warnings") return warningsSwitch
        if (id === "codec") return codecChoice
        if (id === "pyro") return pyroChoice
        if (id === "decoder") return decoderChoice
        if (id === "optim") return optimSwitch
        if (id === "quitAfter") return quitAfterSwitch
        if (id === "awake") return awakeSwitch
        if (id === "presence") return presenceSwitch
        if (id === "classicHud") return classicHudSwitch
        if (id === "twilightHud") return twilightHudSwitch
        if (id === "uiMode") return uiModeChoice
        if (id.indexOf("section:") === 0 && sectionNav) {
            var wanted = id.substring(8)
            for (var s = 0; s < sectionNav.count; s++) {
                if (sectionNav.itemAt(s) && sectionNav.itemAt(s).navId === wanted)
                    return sectionNav.itemAt(s)
            }
        }
        return null
    }

    function insidePage(item) {
        var cursor = item
        while (cursor) {
            if (cursor === page)
                return true
            cursor = cursor.parent
        }
        return false
    }

    function ensureVisible(item) {
        if (!item || !insidePage(item))
            return
        var pos = item.mapToItem(scroller.contentItem, 0, 0)
        if (!pos)
            return
        var top = pos.y
        var bottom = pos.y + item.height
        if (top < scroller.contentY)
            scroller.contentY = Math.max(0, top - 12)
        else if (bottom > scroller.contentY + scroller.height)
            scroller.contentY = Math.max(0, bottom - scroller.height + 12)
    }

    function paintFocus() {
        var id = currentFocusId()
        if (updateRow) updateRow.keyed = id === "update"
        if (closeHit) closeHit.keyed = id === "close"
        if (checkUpdateHit) checkUpdateHit.keyed = id === "checkUpdate"
        if (aboutSource) aboutSource.keyed = id === "aboutSource"
        if (sectionNav) {
            for (var s = 0; s < sectionNav.count; s++) {
                var sectionItem = sectionNav.itemAt(s)
                if (sectionItem)
                    sectionItem.keyed = id === ("section:" + sectionItem.navId)
            }
        }
        resChoice.keyed = id === "res"
        fpsChoice.keyed = id === "fps"
        windowChoice.keyed = id === "window"
        audioChoice.keyed = id === "audio"
        spatialChoice.keyed = id === "spatial"
        sysKeysChoice.keyed = id === "syskeys"
        codecChoice.keyed = id === "codec"
        pyroChoice.keyed = id === "pyro"
        decoderChoice.keyed = id === "decoder"
        uiModeChoice.keyed = id === "uiMode"
        if (id !== "res") resChoice.clearKey()
        if (id !== "fps") fpsChoice.clearKey()
        if (id !== "window") windowChoice.clearKey()
        if (id !== "audio") audioChoice.clearKey()
        if (id !== "spatial") spatialChoice.clearKey()
        if (id !== "syskeys") sysKeysChoice.clearKey()
        if (id !== "codec") codecChoice.clearKey()
        if (id !== "pyro") pyroChoice.clearKey()
        if (id !== "decoder") decoderChoice.clearKey()
        if (id !== "uiMode") uiModeChoice.clearKey()
        bitrateSlider.keyed = id === "bitrate"
        unlimitedChip.keyed = id === "bitrateUnlimited"
        vsyncSwitch.keyed = id === "vsync"
        paceSwitch.keyed = id === "pace"
        hdrSwitch.keyed = id === "hdr"
        yuvSwitch.keyed = id === "yuv"
        headSwitch.keyed = id === "head"
        muteHostSwitch.keyed = id === "muteHost"
        muteBackSwitch.keyed = id === "muteBack"
        micSwitch.keyed = id === "mic"
        absoluteSwitch.keyed = id === "absolute"
        coreHidSwitch.keyed = id === "corehid"
        touchSwitch.keyed = id === "touch"
        swapMouseSwitch.keyed = id === "swapMouse"
        scrollSwitch.keyed = id === "scroll"
        swapFaceSwitch.keyed = id === "swapFace"
        padMouseSwitch.keyed = id === "padMouse"
        bgPadSwitch.keyed = id === "bgPad"
        multiSwitch.keyed = id === "multi"
        mdnsSwitch.keyed = id === "mdns"
        blockingSwitch.keyed = id === "blocking"
        warningsSwitch.keyed = id === "warnings"
        optimSwitch.keyed = id === "optim"
        quitAfterSwitch.keyed = id === "quitAfter"
        awakeSwitch.keyed = id === "awake"
        presenceSwitch.keyed = id === "presence"
        classicHudSwitch.keyed = id === "classicHud"
        twilightHudSwitch.keyed = id === "twilightHud"
        ensureVisible(itemFor(id))
    }

    function moveFocus(delta) {
        var ids = chain()
        if (ids.length === 0)
            return
        var next = focusPos + delta
        if (next < 0)
            next = 0
        if (next >= ids.length)
            next = ids.length - 1
        focusPos = next
        paintFocus()
    }

    function focusId(id) {
        var ids = chain()
        for (var i = 0; i < ids.length; i++) {
            if (ids[i] === id) {
                focusPos = i
                paintFocus()
                return
            }
        }
    }

    function horizontal(dir) {
        var id = currentFocusId()
        if (id === "res") resChoice.moveKey(dir)
        else if (id === "fps") fpsChoice.moveKey(dir)
        else if (id === "window") windowChoice.moveKey(dir)
        else if (id === "audio") audioChoice.moveKey(dir)
        else if (id === "spatial") spatialChoice.moveKey(dir)
        else if (id === "syskeys") sysKeysChoice.moveKey(dir)
        else if (id === "codec") codecChoice.moveKey(dir)
        else if (id === "pyro") pyroChoice.moveKey(dir)
        else if (id === "decoder") decoderChoice.moveKey(dir)
        else if (id === "uiMode") uiModeChoice.moveKey(dir)
        else if (id === "bitrate") bitrateSlider.nudge(dir)
    }

    function activateFocus() {
        var id = currentFocusId()
        if (id === "update") {
            if (updateUrl !== "") {
                if (Window.window && Window.window.openUpdatePrompt)
                    Window.window.openUpdatePrompt()
                else
                    Qt.openUrlExternally(updateUrl)
            }
        }
        else if (id === "close")
            requestClose()
        else if (id === "checkUpdate")
            AutoUpdateChecker.checkNow()
        else if (id === "aboutSource" && SystemProperties.hasBrowser)
            Qt.openUrlExternally("https://github.com/Neguete10/twilight")
        else if (id.indexOf("section:") === 0)
            section = id.substring(8)
        else if (id === "res") resChoice.pickKey()
        else if (id === "fps") fpsChoice.pickKey()
        else if (id === "window") windowChoice.pickKey()
        else if (id === "audio") audioChoice.pickKey()
        else if (id === "spatial") spatialChoice.pickKey()
        else if (id === "syskeys") sysKeysChoice.pickKey()
        else if (id === "codec") codecChoice.pickKey()
        else if (id === "pyro") pyroChoice.pickKey()
        else if (id === "decoder") decoderChoice.pickKey()
        else if (id === "uiMode") uiModeChoice.pickKey()
        else if (id === "bitrateUnlimited") sheet.applyUnlimited()
        else if (id === "vsync") vsyncSwitch.activate()
        else if (id === "pace") paceSwitch.activate()
        else if (id === "hdr") hdrSwitch.activate()
        else if (id === "yuv") yuvSwitch.activate()
        else if (id === "head") headSwitch.activate()
        else if (id === "muteHost") muteHostSwitch.activate()
        else if (id === "muteBack") muteBackSwitch.activate()
        else if (id === "mic") micSwitch.activate()
        else if (id === "absolute") absoluteSwitch.activate()
        else if (id === "corehid") coreHidSwitch.activate()
        else if (id === "touch") touchSwitch.activate()
        else if (id === "swapMouse") swapMouseSwitch.activate()
        else if (id === "scroll") scrollSwitch.activate()
        else if (id === "swapFace") swapFaceSwitch.activate()
        else if (id === "padMouse") padMouseSwitch.activate()
        else if (id === "bgPad") bgPadSwitch.activate()
        else if (id === "multi") multiSwitch.activate()
        else if (id === "mdns") mdnsSwitch.activate()
        else if (id === "blocking") blockingSwitch.activate()
        else if (id === "warnings") warningsSwitch.activate()
        else if (id === "optim") optimSwitch.activate()
        else if (id === "quitAfter") quitAfterSwitch.activate()
        else if (id === "awake") awakeSwitch.activate()
        else if (id === "presence") presenceSwitch.activate()
        else if (id === "classicHud") classicHudSwitch.activate()
        else if (id === "twilightHud") twilightHudSwitch.activate()
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
        MouseArea { anchors.fill: parent; onClicked: sheet.requestClose() }
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
                        id: sectionNav
                        model: ListModel {
                            ListElement { sectionId: "video"; label: qsTr("Video"); symbol: "display" }
                            ListElement { sectionId: "audio"; label: qsTr("Audio"); symbol: "speaker.wave.3" }
                            ListElement { sectionId: "input"; label: qsTr("Input"); symbol: "gamecontroller" }
                            ListElement { sectionId: "network"; label: qsTr("Network"); symbol: "network" }
                            ListElement { sectionId: "advanced"; label: qsTr("Advanced"); symbol: "slider.horizontal.3" }
                            ListElement { sectionId: "about"; label: qsTr("About"); symbol: "info.circle" }
                        }

                        Rectangle {
                            property string navId: model.sectionId
                            property bool keyed: false
                            width: parent.width
                            height: 36
                            radius: 10
                            border.width: keyed ? 2 : 0
                            border.color: sheet.theme.accent
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
                                onClicked: {
                                    sheet.section = model.sectionId
                                    sheet.focusId("section:" + model.sectionId)
                                }
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

                    Rectangle {
                        id: updateRow
                        property bool keyed: false
                        visible: sheet.updateUrl !== ""
                        width: parent.width
                        height: visible ? 44 : 0
                        radius: 12
                        color: sheet.theme.selection
                        border.width: keyed ? 2 : 1
                        border.color: keyed ? sheet.theme.ink : sheet.theme.accent
                        TwTextV2 {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            verticalAlignment: Text.AlignVCenter
                            theme: sheet.theme
                            text: qsTr("Update available: Version %1").arg(sheet.updateVersion)
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: sheet.theme.accent
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Window.window && Window.window.openUpdatePrompt)
                                    Window.window.openUpdatePrompt()
                                else
                                    Qt.openUrlExternally(sheet.updateUrl)
                            }
                        }
                    }

                    TwTextV2 {
                        text: sheet.section === "video" ? qsTr("Video")
                              : sheet.section === "audio" ? qsTr("Audio")
                              : sheet.section === "input" ? qsTr("Input")
                              : sheet.section === "network" ? qsTr("Network")
                              : sheet.section === "about" ? qsTr("About")
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
                            id: resChoice
                            width: parent.width
                            theme: sheet.theme
                            options: sheet.resolutionOptions
                            current: sheet.resKey(StreamingPreferences.width, StreamingPreferences.height)
                            onPicked: sheet.applyResolution(value)
                        }

                        TwTextV2 { theme: sheet.theme; text: qsTr("Frame rate"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            id: fpsChoice
                            width: parent.width
                            theme: sheet.theme
                            options: sheet.fpsOptions
                            current: StreamingPreferences.fps
                            onPicked: sheet.applyFps(value)
                        }

                        TwTextV2 {
                            theme: sheet.theme
                            text: StreamingPreferences.bitrateKbps === StreamingPreferences.maximumBitrateKbps()
                                  ? qsTr("Bitrate · Unlimited")
                                  : qsTr("Bitrate · %1 Mb/s").arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.bitrateKbps))
                            color: sheet.theme.secondary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Item {
                            id: bitrateRow
                            width: parent.width
                            height: 36

                            Rectangle {
                                id: unlimitedChip
                                property bool keyed: false
                                property bool on: StreamingPreferences.bitrateKbps === StreamingPreferences.maximumBitrateKbps()
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: unlimitedLabel.implicitWidth + 28
                                height: 32
                                radius: 10
                                color: on ? sheet.theme.accent : sheet.theme.fill
                                border.width: keyed ? 2 : 1
                                border.color: keyed ? sheet.theme.ink : (on ? sheet.theme.accent : sheet.theme.stroke)
                                TwTextV2 {
                                    id: unlimitedLabel
                                    anchors.centerIn: parent
                                    theme: sheet.theme
                                    text: qsTr("Unlimited")
                                    font.pixelSize: 13
                                    font.weight: unlimitedChip.on ? Font.DemiBold : Font.Normal
                                    color: unlimitedChip.on ? sheet.theme.accentInk : sheet.theme.ink
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sheet.applyUnlimited()
                                }
                            }

                            Rectangle {
                                id: bitrateField
                                anchors.right: unlimitedChip.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 108
                                height: 32
                                radius: 10
                                color: sheet.theme.field
                                border.width: bitrateInput.activeFocus ? 2 : 1
                                border.color: bitrateInput.activeFocus ? sheet.theme.accent : sheet.theme.stroke

                                TextInput {
                                    id: bitrateInput
                                    anchors.left: parent.left
                                    anchors.right: bitrateUnit.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 4
                                    verticalAlignment: TextInput.AlignVCenter
                                    horizontalAlignment: TextInput.AlignRight
                                    clip: true
                                    selectByMouse: true
                                    color: sheet.theme.ink
                                    font.family: sheet.theme.fontFamily
                                    font.pixelSize: 14
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                    Component.onCompleted: text = StreamingPreferences.bitrateMbpsText(StreamingPreferences.bitrateKbps)
                                    onEditingFinished: sheet.commitBitrateText(text)
                                    Keys.onReturnPressed: {
                                        focus = false
                                        event.accepted = true
                                    }
                                    Keys.onEnterPressed: {
                                        focus = false
                                        event.accepted = true
                                    }
                                    Keys.onEscapePressed: {
                                        text = StreamingPreferences.bitrateMbpsText(StreamingPreferences.bitrateKbps)
                                        focus = false
                                        event.accepted = true
                                    }
                                }

                                TwTextV2 {
                                    id: bitrateUnit
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    theme: sheet.theme
                                    text: qsTr("Mb/s")
                                    color: sheet.theme.secondary
                                    font.pixelSize: 12
                                }
                            }

                            SliderV2 {
                                id: bitrateSlider
                                anchors.left: parent.left
                                anchors.right: bitrateField.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                theme: sheet.theme
                                from: StreamingPreferences.minimumBitrateKbps()
                                to: StreamingPreferences.maximumBitrateKbps()
                                value: Math.max(from, Math.min(to, StreamingPreferences.bitrateKbps))
                                onMoved: sheet.commitSliderBitrate(value)
                            }

                            Connections {
                                target: StreamingPreferences
                                onBitrateChanged: bitrateInput.text = StreamingPreferences.bitrateMbpsText(StreamingPreferences.bitrateKbps)
                            }
                        }
                        TwTextV2 {
                            width: parent.width
                            theme: sheet.theme
                            color: sheet.theme.secondary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            text: (StreamingPreferences.bitrateKbps < StreamingPreferences.minimumBitrateKbps()
                                   || StreamingPreferences.bitrateKbps > StreamingPreferences.maximumBitrateKbps())
                                  ? qsTr("Saved %1 Mb/s is outside %2–%3. It is still sent until you change it. The slider stops at %4 Mb/s. GeForce Experience will not encode above %5 Mb/s.")
                                    .arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.bitrateKbps))
                                    .arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.minimumBitrateKbps()))
                                    .arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.maximumBitrateKbps()))
                                    .arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.maximumBitrateKbps()))
                                    .arg(StreamingPreferences.gfeBitrateCapKbps() / 1000)
                                  : qsTr("%1–%2 Mb/s. Unlimited sends %3 Mb/s, the most this client asks a host for. GeForce Experience will not encode above %4 Mb/s.")
                                    .arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.minimumBitrateKbps()))
                                    .arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.maximumBitrateKbps()))
                                    .arg(StreamingPreferences.bitrateMbpsText(StreamingPreferences.maximumBitrateKbps()))
                                    .arg(StreamingPreferences.gfeBitrateCapKbps() / 1000)
                        }

                        SettingRowV2 {
                            width: parent.width
                            theme: sheet.theme
                            title: qsTr("V-Sync")
                            subtitle: qsTr("Turn off for lower latency. You may see tearing.")
                            SwitchV2 {
                                id: vsyncSwitch
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
                                id: paceSwitch
                                theme: sheet.theme
                                enabled: StreamingPreferences.enableVsync
                                checked: StreamingPreferences.enableVsync && StreamingPreferences.framePacing
                                onToggled: StreamingPreferences.framePacing = next
                            }
                        }

                        TwTextV2 { theme: sheet.theme; text: qsTr("Display mode"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            id: windowChoice
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
                                id: hdrSwitch
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
                                id: yuvSwitch
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
                            id: audioChoice
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
                            id: spatialChoice
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
                                id: headSwitch
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
                                id: muteHostSwitch
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
                                id: muteBackSwitch
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
                                id: micSwitch
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
                            subtitle: qsTr("Absolute mouse, no capture. Right for the desktop, wrong for most games. Toggle while streaming with Ctrl+Alt+Shift+M.")
                            SwitchV2 {
                                id: absoluteSwitch
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
                                id: coreHidSwitch
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
                                id: touchSwitch
                                theme: sheet.theme
                                checked: !StreamingPreferences.absoluteTouchMode
                                onToggled: StreamingPreferences.absoluteTouchMode = !next
                            }
                        }
                        TwTextV2 { theme: sheet.theme; text: qsTr("Capture system shortcuts"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold; topPadding: 8 }
                        ChoiceV2 {
                            id: sysKeysChoice
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
                                id: swapMouseSwitch
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
                                id: scrollSwitch
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
                                id: swapFaceSwitch
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
                                id: padMouseSwitch
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
                                id: bgPadSwitch
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
                                id: multiSwitch
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
                                id: mdnsSwitch
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
                                id: blockingSwitch
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
                                id: warningsSwitch
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
                            id: codecChoice
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
                            id: pyroChoice
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
                            id: decoderChoice
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
                                id: optimSwitch
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
                                id: quitAfterSwitch
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
                                id: awakeSwitch
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
                                id: presenceSwitch
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
                                id: classicHudSwitch
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
                                id: twilightHudSwitch
                                theme: sheet.theme
                                checked: StreamingPreferences.showTwilightHud
                                onToggled: StreamingPreferences.showTwilightHud = next
                            }
                        }

                        TwTextV2 { theme: sheet.theme; text: qsTr("Window when Twilight opens"); color: sheet.theme.secondary; font.pixelSize: 12; font.weight: Font.DemiBold }
                        ChoiceV2 {
                            id: uiModeChoice
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
                            text: qsTr("The window mode applies the next time the app opens. Packet size keeps the value already saved.")
                        }

                    }

                    Column {
                        id: aboutBlock
                        width: parent.width
                        spacing: 14
                        visible: sheet.section === "about"

                        TwTextV2 {
                            width: parent.width
                            theme: sheet.theme
                            text: qsTr("Version %1").arg(SystemProperties.versionString)
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }

                        TwTextV2 {
                            width: parent.width
                            theme: sheet.theme
                            color: sheet.theme.secondary
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                            text: qsTr("Twilight is a modified version of Moonlight Qt. It is not the upstream Moonlight project. This program is free software under the GNU General Public License, version 3, and it comes with absolutely no warranty. The source for this version is on GitHub.")
                        }

                        TwTextV2 {
                            width: parent.width
                            theme: sheet.theme
                            color: sheet.theme.secondary
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            text: qsTr("Twilight can look for a newer release. Nothing is downloaded until you choose to update. A pending update also appears at the top of Settings.")
                        }

                        Rectangle {
                            id: checkUpdateHit
                            property bool keyed: false
                            width: checkUpdateLabel.implicitWidth + 28
                            height: 32
                            radius: 10
                            color: checkUpdateArea.containsMouse ? sheet.theme.fillStrong : "transparent"
                            border.width: keyed ? 2 : 1
                            border.color: keyed ? sheet.theme.accent : sheet.theme.stroke
                            TwTextV2 {
                                id: checkUpdateLabel
                                anchors.centerIn: parent
                                theme: sheet.theme
                                text: AutoUpdateChecker.checking ? qsTr("Checking…") : qsTr("Check for Updates")
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: checkUpdateArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    sheet.focusId("checkUpdate")
                                    AutoUpdateChecker.checkNow()
                                }
                            }
                        }

                        Rectangle {
                            id: aboutSource
                            property bool keyed: false
                            visible: SystemProperties.hasBrowser
                            width: visible ? sourceLabel.implicitWidth + 28 : 0
                            height: visible ? 32 : 0
                            radius: 10
                            color: sourceArea.containsMouse ? sheet.theme.fillStrong : "transparent"
                            border.width: keyed ? 2 : 1
                            border.color: keyed ? sheet.theme.accent : sheet.theme.stroke
                            TwTextV2 {
                                id: sourceLabel
                                anchors.centerIn: parent
                                theme: sheet.theme
                                text: qsTr("Source")
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: sheet.theme.accent
                            }
                            MouseArea {
                                id: sourceArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    sheet.focusId("aboutSource")
                                    Qt.openUrlExternally("https://github.com/Neguete10/twilight")
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: closeHit
            property bool keyed: false
            z: 2
            width: 32
            height: 32
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                border.width: closeHit.keyed ? 2 : 0
                border.color: sheet.theme.accent
            }
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
                onClicked: sheet.requestClose()
            }
        }
    }

    DialogCardV2 {
        id: customResDialog
        theme: sheet.theme
        open: sheet.customResOpen
        digitsOnly: true
        field: true
        field2: true
        fieldMinimum: 256
        fieldMaximum: 8192
        field2Minimum: 256
        field2Maximum: 8192
        fieldPlaceholder: "" + StreamingPreferences.width
        field2Placeholder: "" + StreamingPreferences.height
        title: qsTr("Custom resolution")
        message: qsTr("Custom resolutions are not officially supported by GeForce Experience, so it will not set your host display resolution. You will need to set it manually while in game.")
                 + "\n\n"
                 + qsTr("Resolutions that are not supported by your client or host PC may cause streaming errors.")
        confirmText: qsTr("Use this size")
        onConfirmed: sheet.acceptCustomResolution()
        onCanceled: sheet.customResOpen = false
    }

    DialogCardV2 {
        id: customFpsDialog
        theme: sheet.theme
        open: sheet.customFpsOpen
        digitsOnly: true
        field: true
        fieldMinimum: 10
        fieldMaximum: 9999
        fieldPlaceholder: "" + StreamingPreferences.fps
        title: qsTr("Custom frame rate")
        message: qsTr("Enter a custom frame rate. Very high rates can stall the stream if the host or the network cannot keep up.")
        confirmText: qsTr("Use this rate")
        onConfirmed: sheet.acceptCustomFps()
        onCanceled: sheet.customFpsOpen = false
    }

    Shortcut {
        sequence: "Escape"
        enabled: sheet.open && sheet.escapeEnabled && !sheet.customResOpen && !sheet.customFpsOpen && !bitrateInput.activeFocus
        onActivated: sheet.requestClose()
    }

    Item {
        id: keySink
        focus: sheet.open && !sheet.customResOpen && !sheet.customFpsOpen && !bitrateInput.activeFocus
        Keys.onPressed: {
            if (!sheet.open || sheet.customResOpen || sheet.customFpsOpen || bitrateInput.activeFocus)
                return
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                sheet.requestClose()
                event.accepted = true
            }
            else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab
                     || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                sheet.moveFocus(-1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                sheet.moveFocus(1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Left) {
                sheet.horizontal(-1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Right) {
                sheet.horizontal(1)
                event.accepted = true
            }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                sheet.activateFocus()
                event.accepted = true
            }
            else if (event.key === Qt.Key_Hangup || event.key === Qt.Key_Menu) {
                event.accepted = true
            }
        }
    }
}
