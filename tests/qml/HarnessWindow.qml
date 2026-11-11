import QtQuick 2.9
import QtQuick.Window 2.2

// Stand-in for the real main window. The shell reads these update fields
// from Window.window. They stay empty here so the load does not prompt.
Window {
    id: host
    width: 1440
    height: 900
    visible: true

    property bool updatePromptOpen: false
    property bool updateInfoOpen: false
    property string pendingUpdateUrl: ""
    property string pendingUpdateVersion: ""
    property string updateInfoTitle: ""
    property string updateInfoMessage: ""

    function updatePromptMessage() { return "" }
    function updateConfirmText() { return "Download" }
    function acceptPendingUpdate() {}
    function dismissPendingUpdate() {}
    function dismissUpdateInfo() {}

    Loader {
        anchors.fill: parent
        source: Qt.resolvedUrl("../../app/gui/ui/v2/ShellV2.qml")
    }
}
