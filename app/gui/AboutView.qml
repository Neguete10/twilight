import QtQuick 2.9
import QtQuick.Controls 2.2

Flickable {
    id: page
    objectName: qsTr("About")

    contentWidth: width
    contentHeight: (notices.item ? notices.item.height : 0) + 48
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }

    Loader {
        id: notices
        x: 24
        y: 24
        width: Math.max(0, page.width - 48)
        source: "qrc:/gui/AboutNotices.qml"
        onLoaded: item.width = notices.width
        onWidthChanged: if (item) item.width = width
    }
}
