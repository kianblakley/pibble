import QtQuick
import "root:/config"
import "root:/launcher"
import "root:/services"
import "root:/ui"

// One slide of the settings filmstrip. `root.slideIndex` is where this tab sits in
// SettingsPane.tabOrder and `root.activeIndex` which slide is showing; the two
// together are the whole of the horizontal tab transition.
// Navigation: the keybindings, and the two switches that change how tiles
// and gestures respond.
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

    Repeater {
        id: bindRepeater
        model: [
            { action: "cycle", label: "Cycle pages" },
            { action: "reverseCycle", label: "Cycle pages (reverse)" },
            { action: "navLeft", label: "Navigate left" },
            { action: "navRight", label: "Navigate right" },
            { action: "navUp", label: "Navigate up" },
            { action: "navDown", label: "Navigate down" },
            { action: "pagePrev", label: "Previous page of tiles" },
            { action: "pageNext", label: "Next page of tiles" },
            { action: "launch", label: "Activate" },
            { action: "settings", label: "Settings" },
            { action: "power", label: "Power off prompt" },
            { action: "reboot", label: "Reboot prompt" },
            { action: "exit", label: "Exit / back" }
        ]

        Item {
            id: bindRow
            required property var modelData
            width: 780
            height: 34

            SettingLabel {
                anchors.left: parent.left
                // the chord box opposite, plus the reset button past it and
                // the gap between them
                maxWidth: bindRow.width - 34 - Metrics.keybindBoxWidth - 8
                content: Strings.tr(bindRow.modelData.label)
            }
            ResetButton {
                key: "bind:" + bindRow.modelData.action
                anchors.right: parent.right
            }
            Rectangle {
                id: bindBox
                readonly property bool capturing: LauncherState.capturingBind === bindRow.modelData.action
                readonly property string bindStr: Settings.keybinds[bindRow.modelData.action] ?? LauncherState.bindDefaults[bindRow.modelData.action] ?? ""
                readonly property var keyTokens: bindStr.split("+")
                // while capturing, render whatever's currently held (via
                // LauncherState.captureLive) in the same KeyCap style as the settled
                // chip, instead of dropping to plain text - only the
                // "nothing held yet" moment has no keys to render, so that's
                // the one case still showing a plain hint
                readonly property var displayTokens: capturing ? (LauncherState.captureLive ? LauncherState.captureLive.split("+") : []) : keyTokens
                anchors.right: parent.right
                anchors.rightMargin: 34
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.keybindBoxWidth
                height: 34
                radius: Theme.radius(8)
                color: Qt.alpha(Theme.accent, capturing ? 0.3 : 0.11)
                border.width: 1
                border.color: capturing ? Theme.accent : Qt.alpha(Theme.accent, 0.33)

                ScrambleText {
                    anchors.centerIn: parent
                    visible: bindBox.displayTokens.length === 0
                    // shown only while the box is waiting on a key, so it
                    // arrives when the user clicks into the box and resolves
                    // there, the same as any other label coming on screen
                    content: Strings.tr("press a key…")
                    color: Theme.fg
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                }
                Row {
                    id: chordRow
                    anchors.centerIn: parent
                    visible: bindBox.displayTokens.length > 0
                    spacing: 4
                    Repeater {
                        model: bindBox.displayTokens
                        Row {
                            id: keyPair
                            required property string modelData
                            required property int index
                            spacing: 4
                            KeyCap {
                                label: keyPair.modelData
                                // a cap standing in for a key the user is
                                // holding down right now is feedback, not an
                                // arrival - see KeyCap.scramble
                                scramble: !bindBox.capturing
                            }
                            KeyPlus {
                                visible: keyPair.index < bindBox.displayTokens.length - 1
                            }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        LauncherState.capturingBind = bindRow.modelData.action;
                        LauncherState.focusInput();
                    }
                }
            }
        }
    }

    SettingRow {
        key: "singleClickActivate"
        label: "Single click to activate"
        hint: "activates tile without requiring two clicks"
        valueWidth: Metrics.shortValueWidth
    }
    SettingRow {
        key: "gestures"
        label: "Navigation gestures"
        hint: "left/right: cycle pages · up/down: scroll tiles · top edge: power off · bottom edge: reboot · right edge: back"
        valueWidth: Metrics.shortValueWidth
    }
}
