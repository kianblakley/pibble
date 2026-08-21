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
//
// Every caller's labels are English source strings; this is where they are
// translated (see Strings), so no caller has to say so and the chips of a row
// declared as a plain list of ids and words still follow the language.
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
    // The widest this block of chips may become, for a row whose words can
    // grow: a chip row is right-aligned against the column's edge and its
    // caller's label is anchored to the other, so an overlong set of chips
    // does not overflow the pane - it runs back underneath that label, where
    // two lines of text sit on top of each other. Translations are exactly
    // that case, since nothing about a language guarantees its words are as
    // short as the English they replace.
    //
    // The block absorbs the difference in two stages, cheapest first: the gaps
    // between the chips close down to minSpacing, and only past that do the
    // labels themselves elide (see labelCap). 0 - the default - is a caller
    // that has room to spare and doesn't have to say how much.
    property real maxWidth: 0
    // How close the chips may be pushed before the gaps have given all they
    // can. Below this the tick boxes stop reading as separate controls.
    readonly property real minSpacing: 10
    // The natural gap between chips on a line, for a caller that wants them
    // tighter than the default (four to a line rather than two). Separate from
    // `spacing` so setting it leaves the squeeze above in charge of the gap
    // that is actually used, where writing columnSpacing at the call site
    // would replace it.
    property real chipSpacing: root.spacing

    // Each column's width, i.e. the widest chip in it - which is what a Grid
    // lays a column out to. Read off the chips themselves rather than
    // remeasured, so this is the real layout and not a guess at it. The
    // Repeater is a child too and is zero-width; skipping the zero-width ones
    // is what keeps the remaining children in step with the grid's own
    // row-major order. Every child is read, which is also what keeps this
    // subscribed as a label's metrics settle.
    readonly property var columnWidths: {
        const cols = Math.max(1, root.columns);
        const widths = new Array(cols).fill(0);
        let slot = 0;
        for (let i = 0; i < root.children.length; i++) {
            const w = root.children[i].width;
            if (w <= 0)
                continue;
            widths[slot % cols] = Math.max(widths[slot % cols], w);
            slot++;
        }
        return widths;
    }
    // What the chips themselves take up, so the spacing can make up the rest.
    readonly property real chipsWidth: root.columnWidths.reduce((a, b) => a + b, 0)

    // The share of maxWidth one chip's label may take before it elides.
    // Derived from maxWidth alone rather than from what the chips currently
    // measure, which would close the loop chip width → chipsWidth → labelCap →
    // chip width. An equal share per column is the rule that makes the cap
    // loop-free, and it is also the only share that can be guaranteed: a
    // column allowed to borrow from a shorter neighbour is a column whose cap
    // depends on that neighbour's word. Nothing elides while the row fits,
    // since a label under its share keeps its natural width.
    readonly property real labelCap: root.maxWidth > 0
        ? Math.max(48, root.maxWidth / Math.max(1, root.columns) - root.boxSize - 6 - root.minSpacing)
        : 0

    columns: root.items ? root.items.length : 1
    spacing: 40
    columnSpacing: {
        if (root.columns <= 1)
            return root.chipSpacing;
        // an explicit target wins: that caller is lining these up with a
        // control elsewhere in the column, which is a stronger claim on the
        // gaps than either the natural spacing or the cap below
        if (root.targetWidth > 0)
            return Math.max(root.minSpacing, (root.targetWidth - root.chipsWidth) / (root.columns - 1));
        if (root.maxWidth > 0 && root.chipsWidth + (root.columns - 1) * root.chipSpacing > root.maxWidth)
            return Math.max(root.minSpacing, (root.maxWidth - root.chipsWidth) / (root.columns - 1));
        return root.chipSpacing;
    }
    verticalItemAlignment: Grid.AlignVCenter

    Repeater {
        model: root.items

        Item {
            id: chip
            required property var modelData
            readonly property bool on: root.isOn(modelData.id)
            readonly property string label: Strings.tr(chip.modelData.label)
            // the resting label's width: the chips sit in a positioner, so one
            // that grew with its noise would slide every chip after it sideways
            width: chipBox.width + 6 + (root.labelCap > 0 ? Math.min(chipText.fitWidth, root.labelCap) : chipText.fitWidth)
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
                // the chip is sized off fitWidth, so the label has to measure
                // one - see ScrambleText
                measuresFit: true
                // ticked, so this label is one of the ones the row is a preview
                // *of*: it runs on arrival whatever the switches say. Unticked,
                // it is an ordinary settings-pane label again and answers to
                // them like every other - only the hover below overrides that.
                ignoresSections: root.scramblePreview && chip.on
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: chipBox.right
                anchors.leftMargin: 6
                width: chip.width - chipBox.width - 6
                height: restHeight
                elide: Text.ElideRight
                // paced across the head that survives the elide rather than
                // across the whole word - see ScrambleText.paceWidth. 0 while
                // there is no cap, which is a label that isn't eliding.
                paceWidth: root.labelCap
                content: chip.label
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
