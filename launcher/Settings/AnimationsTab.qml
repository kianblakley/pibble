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
    // live animations, and a tab that can't be seen must not be running seven
    // of them. Read by every AnimPreview below, which also takes this becoming
    // true as its cue to play - so arriving on the tab is what demonstrates it.
    readonly property bool previewsActive: root.slideIndex === root.activeIndex

    x: 20 + (root.slideIndex - root.activeIndex) * 840
    Behavior on x {
        NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
    }

    spacing: 14

    // playDelay staggers the arrival replay down the column, in the same
    // 35ms-a-slot beat Anim.staggerOffset gives a "bloom" grid

    AnimSettingRow {
        key: "launchAnimation"
        label: "Launch animation"
        LaunchPreview { playDelay: 0 }
    }

    AnimSettingRow {
        key: "animStyle"
        label: "Pages"
        PagesPreview { playDelay: 35 }
    }

    AnimSettingRow {
        key: "volAnim"
        label: "Volume"
        VolumePreview { playDelay: 70 }
    }

    AnimSettingRow {
        key: "notifAnim"
        label: "Notifications"
        NotifPreview { playDelay: 105 }
    }

    AnimSettingRow {
        key: "hiddenMenuAnimations"
        label: "Settings"
        MenuPreview { playDelay: 140 }
    }

    AnimSettingRow {
        key: "powerAnimations"
        label: "Power prompts"
        PowerPreview { playDelay: 175 }
    }

    // The scramble is the one row that isn't a single switch: a master on/off
    // plus one chip per surface, since the effect is welcome on a pane the user
    // opened and unwelcome on a notification that arrived while they were doing
    // something else. Fewer chips than there are rows above - the launch reveal
    // has no text of its own, and the two flyouts share one (see
    // SettingsSchema.scrambleSectionChips).
    AnimSettingRow {
        key: "textScramble"
        label: "Text scramble"
        ScramblePreview { playDelay: 210 }
    }

    Item {
        width: 780
        height: 28

        ChipRow {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            // dimmed, not disabled, while the master switch is off: the chips
            // still say what the effect would cover, and a user turning it back
            // on gets the set they left rather than a reset one
            opacity: Settings.textScramble ? 1 : 0.45
            Behavior on opacity {
                NumberAnimation { duration: Anim.menu(150); easing.type: Easing.OutCubic }
            }
            items: SettingsSchema.scrambleSectionChips
            isOn: Settings.scrambleEnabled
            toggle: SettingsSchema.toggleScrambleSection
        }
    }
}
