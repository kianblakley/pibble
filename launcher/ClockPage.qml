import QtQuick
import Quickshell
import "root:/services"
import "root:/ui"

// Idle state: the big clock, plus whichever of date / battery / weather are
// switched on. The outer gate holds it back until the reveal circle is large
// enough to contain it.
Item {
    id: root

    anchors.centerIn: parent
    width: lines.width
    height: lines.height
    // its own instance of the shared power/reboot rubber band - one
    // Translate per pane, all bound to the same pull, so no pane has to
    // reach across the tree for a sibling's transform
    transform: Translate {
        y: LauncherState.powerPull - LauncherState.rebootPull
    }
    visible: LauncherState.pane === "clock"
    onVisibleChanged: if (visible) enterAnim.restart()
    // "grow" styles: fade in only once the hole (from wherever it
    // originates) has grown enough to reach and contain the
    // clock. "fade" has no hole - content's own opacity fade
    // (plus lines's own enterAnim below) is the whole effect.
    opacity: {
        if (LauncherState.fadeMode)
            return 1;
        const rc = (Math.hypot(width, height) + 60) / 2;
        const dist = Math.hypot(LauncherState.originX - LauncherState.screenWidth / 2, LauncherState.originY - LauncherState.screenHeight / 2);
        const radius = LauncherState.revealDiameter / 2;
        return Math.max(0, Math.min(1, (radius - dist - rc * 0.8) / (rc * 0.5)));
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        id: lines
        anchors.centerIn: parent
        spacing: 8
        // a line's own opacity fade (below) changes whether the
        // Column counts it in the layout; animate that reflow
        // too so sibling lines slide to their new spot instead
        // of jumping (e.g. the battery/weather line growing in
        // once weather finishes its first fetch)
        move: Transition {
            NumberAnimation { property: "y"; duration: 240; easing.type: Easing.OutCubic }
        }

        // one line per group in LauncherState.clockVisibleGroups; the
        // "time" line renders big only when it's alone on its
        // line, so merging it with other items falls back to the
        // small line-item size below
        Repeater {
            model: LauncherState.clockVisibleGroups

            Row {
                id: line
                required property var modelData
                // membership in modelData is settings-driven and
                // stable; runtime availability (battery present,
                // weather fetched) only ever fades a segment in
                // place via its own opacity below - it never adds
                // to or removes from this Repeater's model, so
                // Row's move transition can animate every reflow
                // instead of anything popping
                function isAvailable(id) {
                    return id === "time" || id === "date"
                        || (id === "battery" && Battery.text.length > 0)
                        || (id === "weather" && Weather.ok);
                }
                readonly property var availableIds: modelData.filter(isAvailable)
                readonly property bool bigTime: modelData.length === 1 && modelData[0] === "time"
                anchors.horizontalCenter: parent.horizontalCenter
                // a segment appearing/disappearing changes this
                // line's total width, which recenters it; smooth
                // that recenter too so the line doesn't hop
                // sideways while a segment fades
                Behavior on x {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                move: Transition {
                    NumberAnimation { property: "x"; duration: 220; easing.type: Easing.OutCubic }
                }
                spacing: bigTime ? 0 : 8
                // fades the whole line in/out (e.g. weather still
                // loading, or no battery on this machine) rather
                // than popping it in/out of the Column; stays in
                // the layout until nearly invisible so the fade
                // reads as a smooth grow, not a snap
                opacity: availableIds.length > 0 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                Repeater {
                    // static per-line membership - see
                    // line.isAvailable above
                    model: line.modelData

                    Row {
                        id: segment
                        required property string modelData
                        required property int index
                        readonly property bool available: line.isAvailable(modelData)
                        readonly property bool isFirstVisible: line.availableIds.length > 0 && line.availableIds[0] === modelData
                        spacing: segment.modelData === "weather" ? 8 : 5
                        anchors.verticalCenter: parent.verticalCenter
                        // an unavailable segment (no battery, or
                        // weather not fetched yet) fades out in
                        // place instead of leaving the model, same
                        // trick as segmentIcon below, one level up
                        opacity: available ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                        // segmentIcon/segValue fade in/out in place
                        // rather than popping, but Row still
                        // repositions siblings the instant that
                        // happens; animate that reflow too so
                        // nothing jumps while a segment fades
                        move: Transition {
                            NumberAnimation { property: "x"; duration: 220; easing.type: Easing.OutCubic }
                        }

                        Text {
                            visible: !segment.isFirstVisible
                            text: "|"
                            color: Theme.muted
                            anchors.verticalCenter: parent.verticalCenter
                            font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
                        }
                        Text {
                            id: segmentIcon
                            // Row has no exit transition (only "add"/"move"), so
                            // an item mid-fade-out has to stay visible and keep
                            // its old glyph on screen instead of just vanishing:
                            // frozenText holds the last real icon, only updating
                            // the instant a new one arrives, while opacity (not
                            // "visible") tracks whether one should currently show
                            // - dropping out of the layout only once it's faded
                            // low enough not to be noticed
                            readonly property string iconText: segment.modelData === "battery" ? (Battery.charging ? Icons.bolt : "")
                                : segment.modelData === "weather" ? Weather.glyphFor(Weather.text) : ""
                            property string frozenText: iconText
                            onIconTextChanged: if (iconText.length > 0) frozenText = iconText
                            anchors.verticalCenter: parent.verticalCenter
                            visible: opacity > 0.01
                            opacity: iconText.length > 0 ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                            text: frozenText
                            color: segment.modelData === "battery" ? Theme.accent : Theme.muted
                            font { family: Icons.family; pixelSize: Theme.fontSize(16) }
                        }
                        ScrambleText {
                            // same freeze trick as segmentIcon above: hold the
                            // last real value while the segment fades out so
                            // the text doesn't blank before it's gone
                            readonly property string valueText: segment.modelData === "time" ? Qt.formatDateTime(clock.date, "HH:mm")
                                : segment.modelData === "date" ? Qt.formatDateTime(clock.date, "dddd, MMMM d")
                                : segment.modelData === "battery" ? Battery.text : Weather.text
                            property string frozenValue: valueText
                            onValueTextChanged: if (valueText.length > 0) frozenValue = valueText
                            anchors.verticalCenter: parent.verticalCenter
                            content: frozenValue
                            // The one place a scramble delay is worth setting:
                            // a line's segments all arrive together (one
                            // opacity, one line), so nothing else would stagger
                            // them across it. A tile grid needs no such thing -
                            // there each caption starts when its own tile lands.
                            scrambleDelay: segment.index * 45
                            // pinned to the resting string's box: this sits in
                            // a Row inside a centered Column, both of which
                            // animate their reflow, so a segment that grew and
                            // shrank with its noise would have the whole clock
                            // sliding about for the length of the run - across
                            // in step with the glyph widths, and up and down
                            // with the line height of whichever font ends up
                            // carrying a symbol
                            width: restWidth
                            height: restHeight
                            color: segment.modelData === "date" ? Theme.muted
                                : segment.modelData === "battery" ? (Battery.charging ? Theme.accent : Theme.muted)
                                : segment.modelData === "weather" ? Theme.muted : Theme.fg
                            font {
                                family: Theme.fontFamily
                                pixelSize: segment.modelData === "time" && line.bigTime ? Theme.fontSize(120) : Theme.fontSize(segment.modelData === "date" ? 17 : 14)
                                weight: segment.modelData === "time" && line.bigTime ? Font.DemiBold : Font.Normal
                                letterSpacing: segment.modelData === "date" ? 3 : 1
                                capitalization: segment.modelData === "date" ? Font.AllUppercase : Font.MixedCase
                            }
                        }
                    }
                }
            }
        }

        ParallelAnimation {
            id: enterAnim
            NumberAnimation { target: lines; property: "opacity"; from: 0; to: 1; duration: Anim.tile(300); easing.type: Easing.OutCubic }
            NumberAnimation { target: lines; property: "anchors.verticalCenterOffset"; from: 10; to: 0; duration: Anim.tile(300); easing.type: Easing.OutCubic }
        }
    }
}
