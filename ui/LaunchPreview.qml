import QtQuick
import "root:/config"
import "root:/services"

// The launcher's own open, on a 16:9 screen wearing the tile picker's styling:
// the "grow" styles sweep a circle of accent out of the matching corner until
// the tile is filled, "fade" fades the fill in whole, "off" simply has it
// there. Same origin table and the same reveal curve the window itself uses
// (Anim.launchOrigin, and LauncherWindow's fadeIn), slowed so the sweep can be
// followed rather than merely noticed.
//
// The real reveal clips the whole scene into that circle with a MultiEffect
// mask. Not what is drawn here: a mask needs its shape rendered to a layer of
// its own, off-screen, and this stage is clipped, which is exactly where an
// off-screen layer's contents are not guaranteed to survive. The circle is
// drawn as the revealed ground instead - and since the whole screen is what
// arrives, that is the same picture either way.
AnimPreview {
    id: root

    replayOn: Settings.launchAnimation

    readonly property bool fadeMode: Settings.launchAnimation === "fade"
    readonly property bool noneMode: Settings.launchAnimation === "none"
    readonly property bool growMode: !root.fadeMode && !root.noneMode
    readonly property var originFraction: Anim.launchOrigin()
    readonly property real originX: root.originFraction[0] * root.stageWidth
    readonly property real originY: root.originFraction[1] * root.stageHeight
    // the farthest corner from the origin, so reveal 1 covers the whole screen
    readonly property real maxRadius: Math.max(Math.hypot(root.originX, root.originY), Math.hypot(root.stageWidth - root.originX, root.originY), Math.hypot(root.originX, root.stageHeight - root.originY), Math.hypot(root.stageWidth - root.originX, root.stageHeight - root.originY))

    // 1 (settled) between runs, exactly as the launcher rests open
    property real reveal: 1
    property real fill: 1
    readonly property real diameter: 2 * root.maxRadius * root.reveal

    onStarted: launchIn.restart()
    ParallelAnimation {
        id: launchIn
        NumberAnimation {
            target: root
            property: "fill"
            from: 0
            to: 1
            duration: root.slow(Anim.launch(root.fadeMode ? 320 : 450))
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "reveal"
            from: 0
            to: 1
            duration: root.slow(Anim.launch(520))
            // the window's own curve, chosen there for its ratio of peak to
            // average edge travel - see LauncherWindow's fadeIn
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.35, 0.3, 0.55, 1.0, 1.0, 1.0]
        }
    }

    // "fade"/"off": the screen fills whole, with no circle to follow
    Rectangle {
        visible: !root.growMode
        anchors.fill: parent
        color: Qt.alpha(Theme.accent, 0.35)
        opacity: root.fill
    }
    Rectangle {
        visible: root.growMode
        x: root.originX - root.diameter / 2
        y: root.originY - root.diameter / 2
        width: root.diameter
        height: root.diameter
        radius: width / 2
        antialiasing: true
        color: Qt.alpha(Theme.accent, 0.35)
    }
}
