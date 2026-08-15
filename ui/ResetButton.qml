import QtQuick
import "root:/config"
import "root:/services"

// Restores one setting (or one group of them) to its factory value.
Rectangle {
    id: root

    property string key
    width: 24
    height: 24
    radius: Theme.radius(12)
    color: "transparent"
    anchors.verticalCenter: parent.verticalCenter
    Text {
        anchors.centerIn: parent
        text: Icons.refresh
        color: hover.containsMouse ? Theme.fg : Theme.muted
        font { family: Icons.family; pixelSize: Theme.fontSize(13) }
    }
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: SettingsSchema.reset(root.key)
    }
}
