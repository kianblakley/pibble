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
    // Every tab is laid out at once and the inactive ones are slid out behind
    // the filmstrip's clip, at full opacity - so nothing else tells a label in
    // here that it can't be seen. Every ScrambleText below this item reads it
    // (see ui/ScrambleText.qml) and sits the run out until this tab is the one
    // showing, which is what makes a tab switch its labels' arrival.
    readonly property bool scrambleSuppressed: root.slideIndex !== root.activeIndex
    // The previews' half of the same problem, and the same answer: they are
    // live animations, and a tab that can't be seen must not be running six
    // of them. Read by every AnimPreview below, which also takes this becoming
    // true as its cue to play - so arriving on the tab is what demonstrates it.
    readonly property bool previewsActive: root.slideIndex === root.activeIndex

    x: 20 + (root.slideIndex - root.activeIndex) * 840
    Behavior on x {
        NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
    }

    spacing: 14

    // How much bigger than their design size the previews are drawn. One
    // figure, picked here, for every preview on the tab. This was solved
    // instead - the tab was handed the Pages tab's height and the previews took
    // whatever the rows left over - which tied one tab's size to another's
    // contents and meant a row added over there resized the pictures over here.
    // A tab is as tall as what is on it; this one now is too.
    readonly property real previewUnit: 1.5

    // The scramble is the one row that isn't a switch at all: one chip per
    // surface the effect shows up on, and there are more of those than one line
    // of chips can hold, so they run over two - the launcher's four pages
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
    // It is also the one row whose preview isn't a picture standing under it:
    // the chips are the preview (see ChipRow's scramblePreview). Every other
    // setting here is a motion done *to* something, so a preview has to draw
    // that something; this one is done to text, and the words naming the
    // surfaces are already text sitting right where the user is looking. A
    // sample card under them said the same thing twice, in a second place, and
    // still had to be told to run when every box was off.
    Item {
        id: scrambleRow
        width: 780
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
            scramblePreview: true
            items: SettingsSchema.scrambleSectionChips
            isOn: Settings.scrambleEnabled
            toggle: SettingsSchema.toggleScrambleSection
        }
    }

    // How a preview is asked for a repeat, said once for the column rather
    // than under each of six boxes. Nothing about a picture that has finished
    // moving says it can be made to move again.
    SettingHint { content: "hover an element to replay its animation" }

    // playDelay staggers the arrival replay down the column, in the same
    // 35ms-a-slot beat Anim.staggerOffset gives a "bloom" grid

    AnimSettingRow {
        key: "launchAnimation"
        label: "Launch animation"
        LaunchPreview { playDelay: 0; unit: root.previewUnit }
    }

    AnimSettingRow {
        key: "animStyle"
        label: "Tiles"
        // no unit: these are the grid picker's own tiles, at its size
        TilesPreview { playDelay: 70 }
    }

    AnimSettingRow {
        key: "hiddenMenuAnimations"
        label: "Settings"
        MenuPreview { playDelay: 105; unit: root.previewUnit }
    }

    AnimSettingRow {
        key: "powerAnimations"
        label: "Power prompts"
        PowerPreview { playDelay: 140; unit: root.previewUnit }
    }

    AnimSettingRow {
        key: "notifAnim"
        label: "Notifications"
        NotifPreview { playDelay: 175; unit: root.previewUnit }
    }

    AnimSettingRow {
        key: "volAnim"
        label: "Volume"
        VolumePreview { playDelay: 210; unit: root.previewUnit }
    }
}
