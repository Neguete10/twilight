import QtQuick 2.9

Image {
    id: icon
    property var theme: null
    property string symbol: "moon.stars"
    property int pointSize: 16
    property color tint: theme ? theme.ink : "#F2F2F7"

    function hexChannel(value) {
        var n = Math.max(0, Math.min(255, Math.round(value * 255)))
        var h = n.toString(16)
        return h.length < 2 ? "0" + h : h
    }

    source: "image://sfsymbol/" + symbol + "/" + pointSize + "/" + hexChannel(tint.r) + hexChannel(tint.g) + hexChannel(tint.b)
    sourceSize: Qt.size(pointSize * 2, pointSize * 2)
    width: pointSize
    height: pointSize
    fillMode: Image.PreserveAspectFit
    horizontalAlignment: Image.AlignHCenter
    verticalAlignment: Image.AlignVCenter
    smooth: true
    mipmap: true
    asynchronous: true
    cache: true
}
