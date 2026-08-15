import QtQuick
import "root:/services"
import "root:/ui"

// One slide of the settings filmstrip. `root.slideIndex` is where this tab sits in
// SettingsPane.tabOrder and `root.activeIndex` which slide is showing; the two
// together are the whole of the horizontal tab transition.
// Animations: every motion switch in one place - the launcher's own entrance,
// the tile grids, the text scramble that rides them, the hidden menus, and both
// flyouts' entrances.
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

    x: 20 + (root.slideIndex - root.activeIndex) * 840
    Behavior on x {
        NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
    }

    spacing: 14

    SettingRow { key: "launchAnimation"; label: "Launch animation" }

    SettingRow { key: "animStyle"; label: "Grid animation" }

    SettingRow { key: "textScramble"; label: "Text scramble" }

    SettingRow { key: "hiddenMenuAnimations"; label: "Hidden menu animations"; hint: "settings pane and power-off/reboot prompts" }

    SettingRow { key: "volAnim"; label: "Volume animation" }

    SettingRow { key: "notifAnim"; label: "Notification animation" }
}
