import QtQuick
import "root:/services"

// Everything that floats above the panes: the swipe-to-power and
// swipe-to-reboot pull indicators and their confirmation prompts, the
// swipe-to-go-back pill, and the corner settings button.
//
// The gestures themselves are tracked in LauncherWindow's background
// MouseArea and live in LauncherState; this is only their read-out.
Item {
    id: root

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.5 * Math.max(LauncherState.powerProgress, LauncherState.rebootProgress)
    }
    Item {
        id: powerRing
        visible: LauncherState.powerRaw > 1
        anchors.horizontalCenter: parent.horizontalCenter
        // "lands higher than the stock *2.6 spot" used to be a
        // separate `- 200 * powerProgress` term, but powerProgress
        // is linear-then-hard-capped-at-1 while powerPull is a
        // smooth exponential - subtracting one from the other left
        // a kink right at the threshold (progress's contribution to
        // the rate stops instantly, pull's doesn't), which read as
        // the ring slowing then suddenly speeding back up.
        // powerRingScale folds that same "-200 at the threshold"
        // target into a single multiplier on powerPull instead, so
        // the resting depth is unchanged but the expression is one
        // smooth curve throughout - the rate can only ever shrink
        // (resistance) and never kinks or reverses
        y: -height + LauncherState.powerPull * LauncherState.powerRingScale
        width: 36
        height: 36
        opacity: Math.min(1, LauncherState.powerRaw / 80)

        Canvas {
            id: powerCanvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2, cy = height / 2, r = 10;
                // p drives the sweep growth and stops at 1 - past
                // the arm threshold the shape (and its gaps) is
                // done growing. Instead, overshoot dragging spins
                // the whole completed assembly (tail, head, dash)
                // rigidly together, capped with the same
                // diminishing-returns curve as powerPull, so the
                // gaps around the dash stay fixed instead of
                // stretching apart
                const p = Math.min(1, LauncherState.powerRaw / LauncherState.powerThreshold);
                // 0.5 of a full turn: the dash ends up pointing
                // straight down (180° from its resting 12 o'clock)
                // once the spin is fully wound up
                const maxOvershoot = 0.5;
                const excess = Math.max(0, LauncherState.powerRaw - LauncherState.powerThreshold);
                const rot = maxOvershoot * (1 - Math.exp(-excess / 260)) * Math.PI * 2;
                // a fixed dash marks 12 o'clock the whole time; the
                // ring never closes onto it - both ends pull away
                // from the dash as the drag progresses, landing with
                // an equal gap to either side of it once complete
                const finalGap = 1.1;
                const tail = -Math.PI / 2 + (finalGap / 2) * p + rot;
                const head = tail + (Math.PI * 2 - finalGap) * p;
                ctx.lineWidth = 3.3;
                ctx.lineCap = "butt";
                ctx.strokeStyle = Theme.accent;
                ctx.beginPath();
                ctx.arc(cx, cy, r, tail, head, false);
                ctx.stroke();

                // the dash itself: perpendicular to the ring (i.e.
                // radial), leading a constant finalGap/2 ahead of
                // the head - so it rides along with the head,
                // landing exactly at 12 o'clock once the head
                // completes its sweep. Held back until the drag is
                // two thirds of the way through, then grows from a
                // sliver
                if (p > 2 / 3) {
                    const dashAngle = head + finalGap / 2;
                    const dx = Math.cos(dashAngle), dy = Math.sin(dashAngle);
                    const dcx = cx + (r - 2) * dx, dcy = cy + (r - 2) * dy;
                    const halfLen = (0.05 + 4.55 * (p - 2 / 3) / (1 / 3));
                    ctx.beginPath();
                    ctx.moveTo(dcx - dx * halfLen, dcy - dy * halfLen);
                    ctx.lineTo(dcx + dx * halfLen, dcy + dy * halfLen);
                    ctx.stroke();
                }
            }
        }
        Connections {
            target: LauncherState
            // powerRaw (not powerProgress, which clamps at 1)
            // drives the paint so dragging past the threshold keeps
            // repainting the overshoot spin
            function onPowerRawChanged() {
                powerCanvas.requestPaint();
            }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: powerRing.y + powerRing.height + 12
        text: "power off?"
        color: Theme.fg
        // start the fade as the ring nears closed: the pull easing
        // crawls through its last few percent, so waiting for exactly
        // 1.0 reads as a long pause after the circle looks complete
        opacity: LauncherState.powerProgress >= 0.85 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Anim.menu(160); easing.type: Easing.OutCubic }
        }
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(18); letterSpacing: 2 }
    }

    // reboot ring: mirror of powerRing, riding up from the bottom
    // edge instead of down from the top.
    Item {
        id: rebootRing
        visible: LauncherState.rebootRaw > 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // scaled powerPull-style, not a separate capped term - see
        // the comment on powerRing's y above
        anchors.bottomMargin: -height + LauncherState.rebootPull * LauncherState.rebootRingScale
        width: 36
        height: 36
        opacity: Math.min(1, LauncherState.rebootRaw / 80)

        Canvas {
            id: rebootCanvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2, cy = height / 2, r = 10;
                // unlike powerRing, this one never lets the arc
                // close: past maxArc of a full turn the tail chases
                // the head at the same rate instead of staying
                // pinned at the top, so the gap holds steady and the
                // ring reads as a snake that can't catch its tail.
                // headFrac keeps advancing past the arm threshold
                // instead of freezing there, but the extra spin is
                // capped with the same diminishing-returns curve as
                // rebootPull, so it matches the drag's own
                // overshoot limits rather than spinning forever
                const maxArc = 0.82;
                // mirror of powerRing's maxOvershoot - see the comment there
                const maxOvershoot = 0.5;
                const excess = Math.max(0, LauncherState.rebootRaw - LauncherState.rebootThreshold);
                const headFrac = Math.min(1, LauncherState.rebootRaw / LauncherState.rebootThreshold)
                    + maxOvershoot * (1 - Math.exp(-excess / 260));
                const tailFrac = Math.max(0, headFrac - maxArc);
                const start = -Math.PI / 2 + Math.PI * 2 * tailFrac;
                const end = -Math.PI / 2 + Math.PI * 2 * headFrac;
                ctx.lineWidth = 3.3;
                ctx.lineCap = "butt";
                ctx.strokeStyle = Theme.accent;
                ctx.beginPath();
                ctx.arc(cx, cy, r, start, end, false);
                ctx.stroke();

                // leading arrowhead, oriented along the direction of travel
                if (headFrac > 0.02) {
                    const hx = cx + r * Math.cos(end);
                    const hy = cy + r * Math.sin(end);
                    const tangent = end + Math.PI / 2;
                    const nx = Math.cos(tangent + Math.PI / 2);
                    const ny = Math.sin(tangent + Math.PI / 2);
                    // grows over the course of the drag, from a
                    // small nub to the full arrowhead - capped so
                    // it doesn't keep bloating during overshoot
                    const arrowScale = 0.3 + 0.7 * Math.min(1, headFrac);
                    const tipX = hx + Math.cos(tangent) * 4.5 * arrowScale;
                    const tipY = hy + Math.sin(tangent) * 4.5 * arrowScale;
                    const backX = hx - Math.cos(tangent) * 3 * arrowScale;
                    const backY = hy - Math.sin(tangent) * 3 * arrowScale;
                    ctx.beginPath();
                    ctx.moveTo(tipX, tipY);
                    ctx.lineTo(backX + nx * 5 * arrowScale, backY + ny * 5 * arrowScale);
                    ctx.lineTo(backX - nx * 5 * arrowScale, backY - ny * 5 * arrowScale);
                    ctx.closePath();
                    ctx.fillStyle = Theme.accent;
                    ctx.fill();
                }
            }
        }
        Connections {
            target: LauncherState
            // rebootRaw (not rebootProgress, which clamps at 1)
            // drives the paint so dragging past the threshold keeps
            // repainting the overshoot spin
            function onRebootRawChanged() {
                rebootCanvas.requestPaint();
            }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // trails above the ring by the same gap powerText trails
        // below powerRing, mirrored around the bottom edge (scaled
        // powerPull-style - see the comment on powerRing's y above)
        anchors.bottomMargin: LauncherState.rebootPull * LauncherState.rebootRingScale + 12
        text: "reboot?"
        color: Theme.fg
        opacity: LauncherState.rebootProgress >= 0.85 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Anim.menu(160); easing.type: Easing.OutCubic }
        }
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(18); letterSpacing: 2 }
    }

    // Swipe-to-go-back pill: rides in from the right edge as
    // LauncherState.backRaw grows, tracking LauncherState.backPull's resistance curve
    // (see the property block on win for the math). A byte-for-byte
    // copy of cornerButton below - same fixed size, same
    // color/border/hover-alpha formula, same icon color - just
    // substituting the completed-drag state for its hover state.
    // The drag/release-to-go-back behavior itself is bgArea's
    // backTracking.
    Item {
        id: backPill
        visible: LauncherState.backRaw > 1
        anchors.right: parent.right
        // spawns at the height the drag actually started from
        // (LauncherState.backGrabY, set once per drag in bgArea's onPressed)
        // rather than always centering vertically - clamped so it
        // can't render partly off the top/bottom edge for a drag
        // that started near a screen corner
        y: Math.max(0, Math.min(parent.height - height, LauncherState.backGrabY - height / 2))
        // -width at rest (fully off-screen), sliding to flush with
        // the edge once backPull reaches its own width, then a
        // little further on overshoot - see LauncherState.backPull
        anchors.rightMargin: LauncherState.backPull - width
        width: 56
        height: 56
        opacity: Math.min(1, LauncherState.backRaw / 30)

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: Qt.alpha(Theme.accent, LauncherState.backProgress >= 1 ? 0.2 : 0.11)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.33)
        }
        Text {
            anchors.centerIn: parent
            text: Icons.chevronLeft
            color: Theme.fg
            font { family: Icons.family; pixelSize: Theme.fontSize(22) }
        }
    }

    // Corner settings button: pops up when hovering the
    // bottom-right corner, or while the settings pane is open, and
    // activates on click.
    MouseArea {
        id: cornerZone
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 260
        height: 180
        hoverEnabled: true
        readonly property bool revealed: containsMouse || pressed || LauncherState.pane === "settings"
        // the button's hit rect in this Item's own coordinate space
        // - mirrors cornerButton's anchors below (right/bottom, 32
        // margin, 56 size) - deliberately independent of cornerButton's
        // reveal opacity/scale animation so a click lands on it
        // even mid pop-in, not just once it's fully grown.
        function inButtonRect(x: real, y: real): bool {
            return x >= width - 88 && x <= width - 32 && y >= height - 88 && y <= height - 32;
        }
        readonly property bool overButton: inButtonRect(mouseX, mouseY)
        onClicked: if (overButton)
            LauncherState.toggleSettings()

        Rectangle {
            id: cornerButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 32
            width: 56
            height: 56
            radius: 28
            antialiasing: true
            color: Qt.alpha(Theme.accent, cornerZone.overButton ? 0.2 : 0.11)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.33)
            opacity: cornerZone.revealed ? 1 : 0
            scale: cornerZone.revealed ? 1 : 0.5
            Behavior on opacity {
                NumberAnimation { duration: Anim.menu(160); easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: Anim.menu(260); easing.type: Easing.OutBack; easing.overshoot: 2 }
            }

            Text {
                anchors.centerIn: parent
                text: Icons.settings
                color: Theme.fg
                font { family: Icons.family; pixelSize: Theme.fontSize(22) }
            }
        }
    }
}
