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
    // Whether these chips are themselves the preview of the text scramble, as
    // the Animations tab's row is. There is nothing else to draw a sample of
    // the effect on - the words *are* what the boxes switch it on for - so the
    // labels demonstrate it themselves, three ways:
    //
    //  - arriving on the tab runs the ticked ones, which is what that row
    //    actually looks like now (an unticked box has nothing to show, and a
    //    row of eight all resolving at once said only that the effect exists);
    //  - ticking one on runs that one, as its answer to the click;
    //  - hovering runs whichever is under the pointer, ticked or not - that is
    //    the user asking what ticking it would do, so it answers past the
    //    switches (see ScrambleText.replay's `force`).
    property bool scramblePreview: false
    // The width to lay one line of chips out to, for a row that has to line up
    // with something other than the chip rows near it: the Pages tab's helper
    // elements sit directly over a ‹› stepper and share its left edge, which is
    // a question about that row's controls rather than about these chips' own
    // words. The gaps between them absorb the difference. 0 - the default - is
    // the natural spacing below.
    property real targetWidth: 0
    // What the chips themselves take up, so the spacing can make up the rest.
    // Every child is read (the Repeater among them, which is zero-width), which
    // is also what keeps this subscribed as a label's metrics settle.
    readonly property real chipsWidth: {
        let w = 0;
        for (let i = 0; i < root.children.length; i++)
            w += root.children[i].width;
        return w;
    }
    columns: root.items ? root.items.length : 1
    spacing: 40
    columnSpacing: root.targetWidth > 0 && root.columns > 1
        ? Math.max(8, (root.targetWidth - root.chipsWidth) / (root.columns - 1))
        : root.spacing
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
            // ticking a box on is the cue to draw the effect on its own word;
            // ticking one off leaves nothing to demonstrate
            onOnChanged: if (root.scramblePreview && chip.on)
                chipText.replay(true)
            ScrambleText {
                id: chipText
                // ticked, so this label is one of the ones the row is a preview
                // *of*: it runs on arrival whatever the switches say. Unticked,
                // it is an ordinary settings-pane label again and answers to
                // them like every other - only the hover below overrides that.
                ignoresSections: root.scramblePreview && chip.on
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
                hoverEnabled: root.scramblePreview
                onEntered: if (root.scramblePreview)
                    chipText.replay(true)
                onClicked: root.toggle(chip.modelData.id)
            }
        }
    }
}
