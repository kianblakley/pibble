import QtQuick
import "root:/services"

// row of checkbox chips (label + tick box) toggling boolean flags in a
// Settings.* object, e.g. the Flyouts/Pibble alerts rows in the flyouts tab
//
// A Grid rather than a Row for the sake of the one caller that wraps: a Grid
// sizes each column to its widest item, so a set of chips broken over two lines
// (the Animations tab's scramble chips) lines up column for column, with the
// slack falling to whichever line's word is shorter. At the default one line
// per item it lays out exactly as a Row does.
Grid {
    id: root

    property var items // [{id, label}]
    property var isOn // function(id): bool
    property var toggle // function(id): void
    // One line of chips, and the tick box centred in it - the lowest and
    // highest ink a chip draws, so a caller lining anything up against a chip
    // knows both where the line sits and how much of it is empty (see
    // AnimationsTab's scramble row, which needs both).
    readonly property int lineHeight: 28
    readonly property int boxSize: 18
    columns: root.items ? root.items.length : 1
    spacing: 40
    verticalItemAlignment: Grid.AlignVCenter

    Repeater {
        model: root.items

        Item {
            id: chip
            required property var modelData
            readonly property bool on: root.isOn(modelData.id)
            // the resting label's width: the chips sit in a positioner, so one
            // that grew with its noise would slide every chip after it sideways
            width: chipBox.width + 6 + chipText.restWidth
            height: root.lineHeight

            Rectangle {
                id: chipBox
                anchors.verticalCenter: parent.verticalCenter
                width: root.boxSize
                height: root.boxSize
                radius: Theme.radius(4)
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
            ScrambleText {
                id: chipText
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: chipBox.right
                anchors.leftMargin: 6
                height: restHeight
                content: chip.modelData.label
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
