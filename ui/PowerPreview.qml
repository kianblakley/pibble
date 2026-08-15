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
// The ring is a Canvas because the arc is what carries the gesture: a circle
// that simply appears says nothing about how far along the prompt is, so it
// strokes itself closed as the pull comes down and lands as a plain closed
// circle. The prompt under it is a bar, as every other stand-in for text in
// these previews is - the words are the power row's business, not this
// setting's, and at this size they were a smear of glyphs either way.
//
// Every duration goes through Anim.power(), the same switch this row sets. The
// reboot prompt is this mirrored around the bottom edge; one of the two is
// enough to read the setting.
AnimPreview {
    id: root

    replayOn: Settings.powerAnimations
    // the dim and the sinking launcher behind it both fill the stage (and the
    // latter overhangs it), so the corners are the stage's own to round
    stageRadius: Theme.radius(root.u(6))
    // 0..1, resting armed - the pose the prompt holds while it waits for the
    // Return that confirms it
    property real progress: 1
    onProgressChanged: ringCanvas.requestPaint()

    // the ring, the gap under it and the prompt bar, moved as one so the pair
    // lands centred rather than each being centred on its own
    readonly property real ringSize: root.u(20)
    readonly property real promptGap: root.u(4)
    readonly property real promptHeight: root.u(3.5)
    readonly property real groupHeight: root.ringSize + root.promptGap + root.promptHeight
    // centred in the stage rather than hanging from its top edge as the real
    // prompt hangs from the top of the screen - see VolumePreview's copy of
    // this
    readonly property real groupRestY: (root.stageHeight - root.groupHeight) / 2
    // rides in from above the stage's own top edge, which is where the real
    // prompt is pulled down from
    readonly property real groupY: -root.ringSize + root.progress * (root.ringSize + root.groupRestY)

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
        y: root.groupY
        width: root.ringSize
        height: root.ringSize
        // the arc is drawn at the size this ends up, not scaled to it: a Canvas
        // is a texture, and it is the one thing in the set that a transform
        // would soften
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2, r = root.u(7);
            const p = Math.max(0, Math.min(1, root.progress));
            // opened at 12 o'clock and closing onto it, so a pull half done is
            // half a circle and a finished one is the whole of it
            const tail = -Math.PI / 2;
            ctx.lineWidth = root.u(2.2);
            ctx.lineCap = "butt";
            ctx.strokeStyle = Theme.accent;
            ctx.beginPath();
            ctx.arc(cx, cy, r, tail, tail + Math.PI * 2 * p, false);
            ctx.stroke();
        }
    }

    // the prompt: a bar under the ring, arriving once the ring is all but shut,
    // exactly as the words do on the real thing
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: ringCanvas.y + ringCanvas.height + root.promptGap
        width: root.u(34)
        height: root.promptHeight
        radius: Theme.radius(root.promptHeight / 2)
        color: Qt.alpha(Theme.muted, 0.6)
        opacity: root.progress >= 0.85 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.slow(Anim.power(160)); easing.type: Easing.OutCubic }
        }
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
