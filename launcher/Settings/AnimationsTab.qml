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
    // drawn at the picker's size, not this one), the scramble's chip row and
    // the gaps between them - so whatever General's column has over that is the
    // previews', divided between them in proportion to the sizes they were
    // drawn at. Solved rather than picked by hand: the rows grow with the
    // user's type scale, and a figure tuned against one scale would leave the
    // tab short at another. Never below 1, so a font scale that leaves no slack
    // shrinks nothing.
    readonly property real fixedHeight: 6 * launchRow.fixedHeight + tilesPreview.height + scrambleRow.height + root.spacing * 7
    readonly property real previewBase: launchPreview.baseHeight + volumePreview.baseHeight + notifPreview.baseHeight + menuPreview.baseHeight + powerPreview.baseHeight + scramblePreview.baseHeight
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
    // surface, since the effect is welcome on a pane the user opened and
    // unwelcome on a notification that arrived while they were doing something
    // else. Fewer chips than there are rows above - the launch reveal has no
    // text of its own, and the two flyouts share one (see
    // SettingsSchema.scrambleSectionChips). There was a master on/off over
    // them; it said nothing that unticking all four doesn't, and two switches
    // for one effect only raised the question of which was in charge (an old
    // config's "off" folds into the chips - see Settings.heal).
    Item {
        id: scrambleRow
        width: 780
        height: 34

        SettingLabel {
            anchors.left: parent.left
            content: "Text scramble"
        }
        ResetButton {
            key: "textScramble"
            anchors.right: parent.right
        }
        ChipRow {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            items: SettingsSchema.scrambleSectionChips
            isOn: Settings.scrambleEnabled
            toggle: SettingsSchema.toggleScrambleSection
        }
    }
    // the sample sits under the chips rather than between them and their label,
    // so the row reads top to bottom as what the effect covers and then what it
    // looks like
    Item {
        width: 780
        height: scramblePreview.height

        ScramblePreview {
            id: scramblePreview
            playDelay: 210
            unit: root.previewUnit
        }
    }
}
