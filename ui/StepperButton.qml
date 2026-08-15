import QtQuick
import "root:/services"

// One arrow of a ‹ value › stepper. Uses the icon font rather than a text
// glyph - ‹ › sit at different baselines/widths across UI fonts, which
// misaligned the stepper depending on the user's chosen font.
Rectangle {
    id: root

    property string icon
    signal pressed
    width: 28
    height: 28
    radius: Theme.radius(8)
    color: Qt.alpha(Theme.accent, hover.containsMouse ? 0.22 : 0.11)
    border.width: 1
    border.color: Qt.alpha(Theme.accent, 0.33)
    anchors.verticalCenter: parent.verticalCenter
    Text {
        anchors.centerIn: parent
        text: root.icon
        color: Theme.accent
        font { family: Icons.family; pixelSize: Theme.fontSize(15) }
    }
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.pressed()
    }
}
