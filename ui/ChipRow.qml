import QtQuick
import "root:/services"

// row of checkbox chips (label + tick box) toggling boolean flags in a
// Settings.* object, e.g. the Flyouts/Pibble alerts rows in the flyouts tab
Row {
    id: root

    property var items // [{id, label}]
    property var isOn // function(id): bool
    property var toggle // function(id): void
    spacing: 40

    Repeater {
        model: root.items

        Item {
            id: chip
            required property var modelData
            readonly property bool on: root.isOn(modelData.id)
            width: chipBox.width + 6 + chipText.implicitWidth
            height: 28
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: chipBox
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                radius: 4
                color: chip.on ? Qt.alpha(Theme.accent, 0.85) : "transparent"
                border.width: 1
                border.color: chip.on ? Theme.accent : Qt.alpha(Theme.muted, 0.6)

                Text {
                    anchors.centerIn: parent
                    visible: chip.on
                    text: Icons.check
                    color: "#141210"
                    font { family: Icons.family; pixelSize: 13 }
                }
            }
            Text {
                id: chipText
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: chipBox.right
                anchors.leftMargin: 6
                text: chip.modelData.label
                color: chip.on ? Theme.fg : Theme.muted
                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.toggle(chip.modelData.id)
            }
        }
    }
}
