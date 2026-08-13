import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "root:/config"
import "root:/services"
import "root:/ui"

// Volume OSD: a pill (or an equalizer) sliding up from the bottom edge.
//
// A persistent window of fixed size whose card animates inside it - always
// loaded, only mapped while showing. Mapping a pre-built window costs a frame
// or two where a full rebuild costs far more, so rapid volume changes never
// lag; and layer-shell margins never animate, since a margin change needs a
// compositor round trip per step and stutters.
Scope {
    id: root

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: root.sink && root.sink.audio ? root.sink.audio.volume : 0
    readonly property bool muted: root.sink && root.sink.audio ? root.sink.audio.muted : false

    // ignore the initial property churn while pipewire connects
    property bool ready: false
    Timer {
        interval: 2000
        running: true
        onTriggered: root.ready = true
    }
    onVolumeChanged: if (root.ready)
        root.ping()
    onMutedChanged: if (root.ready)
        root.ping()

    property bool show: false
    property bool leaving: false
    property bool entered: false
    function ping() {
        if (!Settings.flyoutEnabled("volume"))
            return;
        leaving = false;
        if (!show) {
            // onto whichever monitor is in use, and only ever while the window
            // is still unmapped: a layer surface's output is fixed when it's
            // created, so this can only move between showings. (Also what
            // breaks the seeding binding on window.screen, before the first
            // map, so a monitor switch mid-OSD can't remap it out from under
            // the animation.)
            if (ActiveOutput.screen)
                window.screen = ActiveOutput.screen;
            show = true;
            // entered flips a tick later so the first frame renders the
            // hidden pose and the entry actually animates
            entered = false;
            Qt.callLater(() => entered = true);
        }
        hideTimer.restart();
    }
    Timer {
        id: hideTimer
        interval: Settings.volTimeout
        onTriggered: root.leaving = true
    }
    // Fallback unmap. Normally the window unmaps the instant the exit
    // animation reports the card gone (see card's watchers), which
    // avoids a lingering blurred remnant after the pill has left; this
    // just guarantees teardown if no frame reports it.
    Timer {
        interval: 500
        running: root.leaving
        onTriggered: root.finishHide()
    }
    function finishHide() {
        show = false;
        leaving = false;
    }

    // Always loaded, only mapped while showing: mapping a pre-built
    // window costs a frame or two, unlike the full rebuild a LazyLoader
    // pays, so rapid volume changes never lag. The card moves inside the
    // fixed window; layer margins never animate (margin changes need a
    // compositor round trip per step and stutter).
    PanelWindow {
        id: window
        readonly property string mode: Settings.volAnim
        readonly property bool eq: Settings.volStyle !== "pill"
        // seeded here, then owned by ping() from the first showing on
        screen: ActiveOutput.screen
        visible: root.show || root.leaving
        anchors.bottom: true
        implicitWidth: Settings.volWidth + 8
        implicitHeight: 280
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "pibble-volume"
        // the OSD never takes input
        mask: Region {}

        // ~90ms animation tick drives the equalizer bar motion, only
        // while the OSD is on screen (pill needs no tick)
        property int tick: 0
        Timer {
            interval: 90
            running: window.eq && (root.show || root.leaving)
            repeat: true
            onTriggered: window.tick++
        }
        readonly property bool pct: Settings.volShowPercent
        // Mute fades the wave down to the floor instead of snapping to it.
        // Only toggles on mute/unmute (not per-tick), so this Behavior
        // doesn't fight the "no per-bar height Behaviors" perf constraint
        // below - it's a brief transition, not a continuous one.
        property real muteBlend: root.muted ? 1 : 0
        Behavior on muteBlend {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
        // Half-height (px) of one sine-wave bar (mirrored above/below the
        // centre). The volume factor dominates (the wobble is a narrow
        // band on top) and the amplitude spans most of the card, so a
        // volume change reads clearly as taller/shorter bars.
        function volBarHalf(i: int, n: int): int {
            const eff = root.volume * 100;
            let full;
            if (eff <= 0) {
                full = 2; // 4px floor
            } else {
                // square-root response: steep below ~50% so quiet-range
                // volume steps read clearly, flattening toward full volume
                const v = Math.sqrt(Math.min(1, eff / 100));
                const wobble = 0.78 + 0.22 * Math.sin(tick * 0.35 + i * 0.85 + 2);
                full = Math.max(4, v * 84 * wobble) / 2;
            }
            return Math.round(full + (2 - full) * muteBlend);
        }

        Rectangle {
            id: card
            readonly property bool on: root.show && !root.leaving && root.entered
            x: (parent.width - width) / 2
            width: Settings.volWidth
            // equalizer variants need a taller card than the pill
            height: window.eq ? 108 : 56
            radius: window.eq ? 18 : 28
            // rests 90px above the screen bottom; the slide exit drops it
            // past the window (= screen) bottom edge. Bounce is built in:
            // the exit overshoot lands off-screen, so only the entry
            // shows it.
            readonly property real restY: parent.height - height - 90
            y: window.mode === "slide" ? (on ? restY : parent.height) : restY
            Behavior on y {
                NumberAnimation {
                    duration: window.mode === "slide" ? 340 : 0
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }
            // the sine bars render straight on the wallpaper; the pill
            // style keeps a card behind the level bar so it reads as a
            // pill rather than a bare line
            color: window.eq ? "transparent" : Theme.flyoutSurface
            antialiasing: true
            opacity: window.mode === "slide" ? 1 : (on ? 1 : 0)
            scale: window.mode === "pop" ? (on ? 1 : 0.8) : 1
            // unmap the window the instant the card has left, so no
            // blurred remnant lingers between the anim ending and the
            // fallback timer (fixes the "small square" on non-slide exits)
            onOpacityChanged: if (root.leaving && opacity <= 0.02) root.finishHide()
            onYChanged: if (root.leaving && window.mode === "slide" && y >= parent.height - 2) root.finishHide()
            Behavior on opacity {
                NumberAnimation { duration: window.mode === "none" ? 0 : 200; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: window.mode === "none" ? 0 : 240; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }

            // optional numeric readout on the right edge; the bar/eq
            // content shifts left to make room. Fixed width so the layout
            // doesn't jitter as the digit count changes.
            ScrambleText {
                id: percentText
                // The showing state is part of this, not just window.pct: an
                // unmapped window's items still read as visible, so without it
                // the readout would count as on screen for the whole session,
                // arm once at startup and never resolve again (see
                // ui/ScrambleText.qml - a label starts when it *arrives*).
                visible: window.pct && (root.show || root.leaving)
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize(42)
                horizontalAlignment: Text.AlignRight
                content: Math.round(root.volume * 100) + "%"
                // Every step of a held volume key changes this string, and a
                // readout that re-resolved on each one would never be legible
                // while it mattered - so no replayOnChange: the effect plays as
                // the OSD arrives and the number is plain from then on.
                scramble: window.mode !== "none"
                // this OSD comes and goes on its own schedule, with no part in
                // the launcher's - see followsPane in ui/ScrambleText.qml
                followsPane: false
                color: root.muted ? Theme.active.muted : Theme.active.fg
                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(15); weight: Font.DemiBold }
                Behavior on color {
                    ColorAnimation { duration: 260; easing.type: Easing.OutCubic }
                }
            }
            readonly property real pctSpace: window.pct ? percentText.width + 16 : 0

            // "pill" style: a plain level bar. Anchored directly to
            // percentText rather than derived from card.pctSpace, so the
            // gap to the slider is an explicit margin instead of drifting
            // with that formula.
            Item {
                visible: !window.eq
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: window.pct ? percentText.left : parent.right
                anchors.rightMargin: window.pct ? 12 : 30
                height: 8

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: Qt.alpha(Theme.active.accent, 0.15)
                }
                Rectangle {
                    width: parent.width * Math.min(1, root.volume)
                    height: parent.height
                    radius: 4
                    color: root.muted ? Qt.alpha(Theme.active.muted, 0.8) : Theme.active.accent
                    Behavior on width {
                        NumberAnimation { duration: 70; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }
                }
            }

            // sine-wave visualizer:
            // fixed-width bars (the design's 6px) mirrored above and below
            // a horizontal centre axis, following the flyout accent colour
            // (neutral when muted / 0). The card width sets how many bars
            // fit - resizing adds/removes bars at the design's ~26px pitch
            // instead of stretching them - and the row still spans edge to
            // edge like the pill's bar. No per-bar height Behaviors: the
            // ~90ms tick already paces the motion, and animating the bars
            // at 60fps kept the compositor re-blurring the backdrop every
            // frame, which showed up as input lag.
            Row {
                id: eqRow
                visible: window.eq
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: -card.pctSpace / 2
                readonly property real avail: card.width - 48 - card.pctSpace
                readonly property real barW: 6
                // bar pitch (px between bar centres) is fixed: dense
                // enough to read as a waveform at any card width
                readonly property real pitch: 14
                readonly property int nBars: Math.max(2, Math.floor((avail + pitch - barW) / pitch))
                spacing: nBars > 1 ? (avail - barW * nBars) / (nBars - 1) : 0

                Repeater {
                    model: eqRow.nBars
                    Item {
                        id: eqBar
                        required property int index
                        width: eqRow.barW
                        height: 60
                        readonly property real half: window.volBarHalf(index, eqRow.nBars)
                        readonly property color barColor: (root.muted || root.volume <= 0)
                            ? Theme.active.muted : Theme.active.accent

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.verticalCenter
                            width: eqRow.barW
                            radius: 3
                            height: eqBar.half
                            color: eqBar.barColor
                            Behavior on color {
                                ColorAnimation { duration: 260; easing.type: Easing.OutCubic }
                            }
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.verticalCenter
                            width: eqRow.barW
                            radius: 3
                            height: eqBar.half
                            color: eqBar.barColor
                            opacity: 0.55
                            Behavior on color {
                                ColorAnimation { duration: 260; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }
        }
    }
}
