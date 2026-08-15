import QtQuick
import "root:/config"
import "root:/services"
import "root:/ui"

// One slide of the settings filmstrip. `root.slideIndex` is where this tab sits in
// SettingsPane.tabOrder and `root.activeIndex` which slide is showing; the two
// together are the whole of the horizontal tab transition.
// Animations: every motion switch in one place - the launcher's own entrance,
// the tile grids, both flyouts, both hidden menus, and the text scramble that
// rides all of them - each over a small live preview of what it does, since
// "bloom" and "cascade" are not names anybody can picture. The previews sit
// under their rows and carry the explaining that a line of hint text used to
// (see ui/AnimPreview.qml).
Column {
    id: root

    required property int slideIndex
    required property int activeIndex
    // The height this tab is asked to come out at - the General tab's, which is
    // the tallest of the built-ins and therefore what the filmstrip's viewport
    // is sized to anyway. Injected by SettingsPane rather than reached for from
    // here, same as every other cross-tab figure.
    required property real targetHeight
    // Every tab is laid out at once and the inactive ones are slid out behind
    // the filmstrip's clip, at full opacity - so nothing else tells a label in
    // here that it can't be seen. Every ScrambleText below this item reads it
    // (see ui/ScrambleText.qml) and sits the run out until this tab is the one
    // showing, which is what makes a tab switch its labels' arrival.
    readonly property bool scrambleSuppressed: root.slideIndex !== root.activeIndex
    // The previews' half of the same problem, and the same answer: they are
    // live animations, and a tab that can't be seen must not be running seven
    // of them. Read by every AnimPreview below, which also takes this becoming
    // true as its cue to play - so arriving on the tab is what demonstrates it.
    readonly property bool previewsActive: root.slideIndex === root.activeIndex

    x: 20 + (root.slideIndex - root.activeIndex) * 840
    Behavior on x {
        NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
    }

    spacing: 14

    // How much bigger than their design size the previews are drawn. Everything
    // else on this tab is fixed - six header lines, the tile grid (which is
    // drawn at the picker's size, not this one), the whole scramble row (its
    // chips, and a sample drawn at the size of the text it is a sample of) and
    // the gaps between them - so whatever General's column has over that is the
    // previews', divided between them in proportion to the sizes they were
    // drawn at. Solved rather than picked by hand: the rows grow with the
    // user's type scale, and a figure tuned against one scale would leave the
    // tab short at another. Never below 1, so a font scale that leaves no slack
    // shrinks nothing.
    //
    // Nothing here may depend on previewUnit, or the two would define each
    // other - which is the whole reason the scramble sample is sized off its
    // own font rather than off the unit (see ScramblePreview).
    readonly property real fixedHeight: 6 * launchRow.fixedHeight + tilesPreview.height + scrambleRow.height + root.spacing * 6
    readonly property real previewBase: launchPreview.baseHeight + volumePreview.baseHeight + notifPreview.baseHeight + menuPreview.baseHeight + powerPreview.baseHeight
    readonly property real previewUnit: Math.max(1, (root.targetHeight - root.fixedHeight) / root.previewBase)

    // playDelay staggers the arrival replay down the column, in the same
    // 35ms-a-slot beat Anim.staggerOffset gives a "bloom" grid

    AnimSettingRow {
        id: launchRow
        key: "launchAnimation"
        label: "Launch animation"
        LaunchPreview { id: launchPreview; playDelay: 0; unit: root.previewUnit }
    }

    AnimSettingRow {
        key: "animStyle"
        label: "Tiles"
        // no unit: these are the grid picker's own tiles, at its size
        TilesPreview { id: tilesPreview; playDelay: 35 }
    }

    AnimSettingRow {
        key: "volAnim"
        label: "Volume"
        VolumePreview { id: volumePreview; playDelay: 70; unit: root.previewUnit }
    }

    AnimSettingRow {
        key: "notifAnim"
        label: "Notifications"
        NotifPreview { id: notifPreview; playDelay: 105; unit: root.previewUnit }
    }

    AnimSettingRow {
        key: "hiddenMenuAnimations"
        label: "Settings"
        MenuPreview { id: menuPreview; playDelay: 140; unit: root.previewUnit }
    }

    AnimSettingRow {
        key: "powerAnimations"
        label: "Power prompts"
        PowerPreview { id: powerPreview; playDelay: 175; unit: root.previewUnit }
    }

    // The scramble is the one row that isn't a switch at all: one chip per
    // surface the effect shows up on, and there are more of those than there
    // are rows above it, so they run over two lines - the launcher's four pages
    // on the first, the two menus and the two flyouts on the second (see
    // SettingsSchema.scrambleSectionChips). There was a master on/off over
    // them; it said nothing that unticking all of them doesn't, and two
    // switches for one effect only raised the question of which was in charge
    // (an old config's "off" folds into the chips - see Settings.heal).
    //
    // One grid rather than a line each, so the two lines share their column
    // widths and every tick box on the second sits under one on the first -
    // eight chips of eight different lengths otherwise land eight different
    // ways, which reads as two unrelated rows that happen to be near each
    // other. The slack that buys falls inside whichever column's word is the
    // shorter of its pair.
    //
    // The sample under it makes this an AnimSettingRow in every way but what
    // sits opposite the label, so it is built as one by hand: the same Column
    // holding a header block and a preview, over the same 3 of slack a 28px
    // stepper button gets inside that row's 34px line. The gap between the two
    // is the one figure that isn't AnimSettingRow's own - see the spacing.
    Column {
        id: scrambleRow
        width: 780
        // AnimSettingRow's 8, less the slack a chip carries under its tick box:
        // a stepper button is a drawn rectangle filling its whole 28px height,
        // where a chip's 18px box is centred in the same height and leaves five
        // empty pixels under it. Measured from the layout box the two gaps are
        // equal and the sample still sits visibly further from the chips than
        // any other preview does from its arrows - so this is measured from the
        // ink, which is the only edge the eye can see.
        spacing: 8 - (chipGrid.lineHeight - chipGrid.boxSize) / 2

        Item {
            id: chipBlock
            width: parent.width
            height: chipGrid.height + 6

            // The label and the reset button belong to the first line of chips
            // rather than to the block as a whole: centred against both lines
            // they sat half a line low, level with nothing, which read as a
            // caption under the pages rather than as this row's name. Given a
            // box one chip line tall instead, so each centres against that line
            // exactly as every other row's label centres against its stepper
            // (both anchor themselves to their parent's centre - see
            // SettingLabel).
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 3
                height: chipGrid.lineHeight

                SettingLabel {
                    anchors.left: parent.left
                    content: "Text scramble"
                }
                ResetButton {
                    key: "textScramble"
                    anchors.right: parent.right
                }
            }
            ChipRow {
                id: chipGrid
                // right-aligned as a block, so the grid ends flush with every
                // stepper up the column
                anchors.right: parent.right
                anchors.rightMargin: 34
                anchors.top: parent.top
                anchors.topMargin: 3
                columns: SettingsSchema.scrambleChipColumns
                // tighter than the 40 a two-chip row can afford: four of these
                // to a line, and "notifications" is not a short word
                columnSpacing: 22
                rowSpacing: 2
                items: SettingsSchema.scrambleSectionChips
                isOn: Settings.scrambleEnabled
                toggle: SettingsSchema.toggleScrambleSection
            }
        }
        // the sample sits under the chips rather than between them and their
        // label, so the row reads top to bottom as what the effect covers and
        // then what it looks like
        Item {
            width: parent.width
            height: childrenRect.height

            // no unit: the sample is drawn at the size of the text it samples,
            // not at the tab's leftover height (see ScramblePreview)
            ScramblePreview {
                id: scramblePreview
                playDelay: 210
            }
        }
    }
}
