import QtQuick
import "root:/config"
import "root:/services"

// The power-off prompt arming: the screen dimming and sinking away, the ring
// riding down from the top edge *stroking itself closed as it comes*, and the
// prompt landing under it once the ring is all but shut. The keybind plays
// exactly this on the real thing (LauncherState.playPower drops powerRaw
// straight to the threshold and lets its Behavior ride it down), so the preview
// replays the keybind's version rather than a drag nobody can perform against a
// 100px box.
//
// The ring is a Canvas because the real one is: the arc is what carries the
// whole gesture, and a plain circle outline - which is what this drew first -
// says nothing about how far along the prompt is. The sweep below is
// PowerOverlay's powerCanvas at a smaller radius, minus its overshoot spin,
// which only exists for a drag that keeps going past the threshold.
//
// Every duration goes through Anim.power(), the same switch this row sets. The
// reboot prompt is this mirrored around the bottom edge; one of the two is
// enough to read the setting.
AnimPreview {
    id: root

    replayOn: Settings.powerAnimations

    // 0..1, resting armed - the pose the prompt holds while it waits for the
    // Return that confirms it
    property real progress: 1
    onProgressChanged: ringCanvas.requestPaint()

    // the launcher behind the prompt, sinking away from the pull. Taller than
    // the stage by the distance it sinks, so its top edge stays past the top of
    // the screen the whole way down - shifting a screen-sized fill left a band
    // of bare (and, under the dim below, noticeably darker) tile along the top
    // edge, which read as part of the picture rather than as the fill having
    // moved.
    Rectangle {
        y: (root.progress - 1) * root.u(5)
        width: parent.width
        height: parent.height + root.u(5)
        color: Qt.alpha(Theme.muted, 0.16)
    }
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.45 * root.progress
    }

    Canvas {
        id: ringCanvas
        anchors.horizontalCenter: parent.horizontalCenter
        y: -height + root.progress * (height + root.u(4))
        width: root.u(20)
        height: root.u(20)
        // the arc is drawn at the size this ends up, not scaled to it: a Canvas
        // is a texture, and it is the one thing in the set that a transform
        // would soften
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2, r = root.u(7);
            const p = Math.max(0, Math.min(1, root.progress));
            // a fixed dash marks 12 o'clock the whole time; the ring never
            // closes onto it - both ends pull away from the dash as the pull
            // progresses, landing with an equal gap either side of it
            const finalGap = 1.1;
            const tail = -Math.PI / 2 + (finalGap / 2) * p;
            const head = tail + (Math.PI * 2 - finalGap) * p;
            ctx.lineWidth = root.u(2.2);
            ctx.lineCap = "butt";
            ctx.strokeStyle = Theme.accent;
            ctx.beginPath();
            ctx.arc(cx, cy, r, tail, head, false);
            ctx.stroke();

            // the dash: radial, a constant finalGap/2 ahead of the head, so it
            // rides along and lands at 12 o'clock as the head completes. Held
            // back until the pull is two thirds through, then grows from a
            // sliver.
            if (p > 2 / 3) {
                const dashAngle = head + finalGap / 2;
                const dx = Math.cos(dashAngle), dy = Math.sin(dashAngle);
                const dcx = cx + (r - root.u(1.5)) * dx, dcy = cy + (r - root.u(1.5)) * dy;
                const halfLen = root.u(0.05 + 3.2 * (p - 2 / 3) / (1 / 3));
                ctx.beginPath();
                ctx.moveTo(dcx - dx * halfLen, dcy - dy * halfLen);
                ctx.lineTo(dcx + dx * halfLen, dcy + dy * halfLen);
                ctx.stroke();
            }
        }
    }

    ScrambleText {
        anchors.horizontalCenter: parent.horizontalCenter
        y: ringCanvas.y + ringCanvas.height + root.u(4)
        content: "power off?"
        color: Theme.fg
        // the prompt answers to the power switch, not to the settings pane this
        // preview happens to sit in - see PowerOverlay's copy of this
        scrambleSection: "power"
        // pinned to the resting box, as the prompt itself is: a centred label
        // must not shuffle about on every reroll
        width: restWidth
        height: restHeight
        opacity: root.progress >= 0.85 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.slow(Anim.power(160)); easing.type: Easing.OutCubic }
        }
        font { family: Theme.fontFamily; pixelSize: root.uf(10); letterSpacing: root.u(1) }
    }

    onStarted: powerIn.restart()
    NumberAnimation {
        id: powerIn
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.slow(Anim.power(320))
        easing.type: Easing.OutCubic
    }
}
