import QtQuick
import QtQuick.Shapes
import "root:/config"
import "root:/services"

// The tools menu as drawn (see ToolsMenu for what it does): round buttons
// round a small mark that stands in for the pointer. The mark leans the way
// the pointer is pulling and shows which way that is; the button that way
// lights up, and its name comes out beside it.
//
// The mark is Settings.toolsFace, one of:
//   face     a dark face with two eyes that look along the pull (and blink)
//   visor    the face with one wide bar of an eye
//   cat      the face with two ears
//   sprout   the face with a sprout growing out of it
//
// While a recording runs, its pause and stop sit on a small ring of their
// own between the mark and the tools, which move out to make room, and a red
// arc round the mark goes round once a minute of recording.
//
// All of them are drawn the same way: the dark of the face with white for
// its details, and no outline. The eyes leave a streak as they move (see
// EyePair).
//
// Coloured from Theme.tools - black and white unless Settings > Tools hands
// it to the theme - and the face from Theme.toolsFace: the same dark with
// white eyes, or turned round (a light face, dark eyes) by "Tools menu
// pointer inverted".
//
// This item sits on the pie's middle, so everything in it is laid out from
// (0, 0) outwards.
Item {
    id: root

    required property var menu
    readonly property int spawn: 340

    // from the middle to each button's centre - Settings > Tools, held to
    // where five buttons still clear one another
    readonly property real spread: Math.max(Defaults.toolsSpreadMin, Math.min(Defaults.toolsSpreadMax, Settings.toolsSpread))
    readonly property real size: 54
    // Settings > Tools: the pointer face as a multiple of its own size. The
    // recording's arc round it grows with it, and the controls' ring moves
    // out by as much as the arc does, so a big face never sits on them.
    readonly property real faceScale: Math.max(Defaults.toolsFaceSizeMin, Math.min(Defaults.toolsFaceSizeMax, Settings.toolsFaceSize)) / 100
    readonly property real arcRadius: 28 * root.faceScale
    // the recording's controls: their ring, and how big each is
    readonly property real innerOrbit: 60 + Math.max(0, root.arcRadius - 28)
    readonly property real innerSize: 38
    // the tools' ring - out past the controls' while they are there
    readonly property real orbit: root.menu.recording ? Math.max(root.spread, root.innerOrbit + root.innerSize / 2 + 12 + root.size / 2) : root.spread
    // how far the mark can lean out of the middle: most of the way to the
    // chosen button, short of touching it however close the buttons are set,
    // and only a little with the controls (and the arc it wears) close by
    readonly property real travel: root.menu.recording ? 8 : Math.max(6, Math.min(26, root.orbit - root.size * 0.55 - 26 * root.faceScale))

    readonly property var colors: Theme.tools
    readonly property var face: Theme.toolsFace

    // How far the pie reaches from its middle, the chosen one's name
    // included - the room ToolsMenu keeps between the middle and the
    // screen's edges. Sideways that is the widest name there can be.
    readonly property real roomX: root.labelled ? root.orbit + root.size / 2 + 14 + widest.implicitWidth + 24 + 10 + 8 : root.roomY
    readonly property real roomY: root.orbit + root.size / 2 + (root.labelled ? 14 + 32 + 8 : 16)
    // Settings > Tools: the chosen tool's name, and its key, beside it
    readonly property bool labelled: Settings.toolsHint !== "off"
    readonly property bool keyed: Settings.toolsHint === "full"
    Column {
        id: widest
        visible: false
        Repeater {
            // a control's line is its name and the recording's status, at
            // its longest
            model: root.menu.actions.concat(root.menu.controls)
            Text {
                required property var modelData
                text: Strings.tr(modelData.label) + "  " + (modelData.inner ? Strings.trf("paused at %1", "0:00:00") : modelData.key.toUpperCase())
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize(13)
            }
        }
    }

    x: menu.center.x
    y: menu.center.y

    // ---------- the buttons ----------

    Repeater {
        model: root.menu.actions

        Item {
            id: slot
            required property var modelData
            required property int index
            readonly property point toward: root.menu.direction(slot.index)
            readonly property bool chosen: slot.index === root.menu.current
            // each comes out a little after the one before it, clockwise
            readonly property real arrive: root.menu.span(root.menu.reveal, slot.index * 0.06, 0.62 + slot.index * 0.06)
            // how far out from the middle: all the way at once under "fade"
            readonly property real out: root.menu.anim === "fade" ? 1 : root.menu.settle(slot.arrive)

            x: slot.toward.x * root.orbit * slot.out - root.size / 2
            y: slot.toward.y * root.orbit * slot.out - root.size / 2
            width: root.size
            height: root.size
            opacity: (root.menu.anim === "fade" ? slot.arrive : root.menu.span(slot.arrive, 0, 0.4)) * (root.menu.off(slot.modelData) ? 0.35 : 1)
            scale: root.menu.grow(slot.arrive)
            Behavior on x {
                enabled: root.menu.open && slot.arrive >= 1
                NumberAnimation { duration: root.menu.ms(220); easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: root.menu.open && slot.arrive >= 1
                NumberAnimation { duration: root.menu.ms(220); easing.type: Easing.OutCubic }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius(root.size / 2)
                // the chosen one keeps its dark and wears a ring in the accent
                color: root.colors.ink
                border.color: root.colors.accent
                border.width: slot.chosen ? 2.5 : 0
                scale: slot.chosen ? 1.1 : 1
                Behavior on border.width {
                    NumberAnimation { duration: root.menu.ms(110) }
                }
                Behavior on scale {
                    NumberAnimation { duration: root.menu.ms(220); easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.menu.glyph(slot.modelData)
                    color: root.colors.glyph
                    font.family: Icons.family
                    font.pixelSize: Theme.fontSize(22)
                }
            }
        }
    }

    // The recording's controls, coming out after the tools. Stop is the
    // recording's red, and its ring when chosen is red rather than the
    // accent.
    Repeater {
        model: root.menu.recording ? root.menu.controls : []

        Item {
            id: control
            required property var modelData
            required property int index
            readonly property int choice: root.menu.actions.length + control.index
            readonly property point toward: root.menu.direction(control.choice)
            readonly property bool chosen: control.choice === root.menu.current
            readonly property bool red: control.modelData.id === "stop"
            readonly property real arrive: root.menu.span(root.menu.reveal, 0.3 + control.index * 0.06, 0.85 + control.index * 0.06)
            readonly property real out: root.menu.anim === "fade" ? 1 : root.menu.settle(control.arrive)

            x: control.toward.x * root.innerOrbit * control.out - root.innerSize / 2
            y: control.toward.y * root.innerOrbit * control.out - root.innerSize / 2
            width: root.innerSize
            height: root.innerSize
            opacity: (root.menu.anim === "fade" ? control.arrive : root.menu.span(control.arrive, 0, 0.4)) * (root.menu.off(control.modelData) ? 0.35 : 1)
            scale: root.menu.grow(control.arrive)

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius(root.innerSize / 2)
                color: root.colors.ink
                border.color: control.red ? root.menu.alarm : root.colors.accent
                border.width: control.chosen ? 2 : 0
                scale: control.chosen ? 1.12 : 1
                Behavior on border.width {
                    NumberAnimation { duration: root.menu.ms(110) }
                }
                Behavior on scale {
                    NumberAnimation { duration: root.menu.ms(220); easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.menu.glyph(control.modelData)
                    color: control.red ? root.menu.alarm : root.colors.glyph
                    font.family: Icons.family
                    font.pixelSize: Theme.fontSize(17)
                }
            }
        }
    }

    // ---------- the chosen one's name ----------

    // Out past the chosen button, the way it points, and kept on the screen
    // when that way runs off it - past the tools' ring for a control too, so
    // as not to land on a tool. While recording with nothing chosen it is
    // the recording's own, over the top, saying how long it has run.
    Rectangle {
        id: tag
        readonly property var entry: root.menu.entry(root.menu.current)
        // the recording's status goes in the key's place
        readonly property bool telling: tag.entry ? tag.entry.inner === true : root.menu.recording
        readonly property point toward: root.menu.direction(Math.max(0, root.menu.current))
        // past the button, then far enough along the same way that the tag's
        // nearest edge clears it whichever way that is
        readonly property real reach: root.orbit + root.size / 2 + 14 + Math.abs(tag.toward.x) * tag.width / 2 + Math.abs(tag.toward.y) * tag.height / 2
        readonly property real wantX: tag.toward.x * tag.reach - tag.width / 2
        readonly property real wantY: tag.toward.y * tag.reach - tag.height / 2

        x: Math.max(8 - root.menu.center.x, Math.min(root.menu.width - 8 - tag.width - root.menu.center.x, tag.wantX))
        y: Math.max(8 - root.menu.center.y, Math.min(root.menu.height - 8 - tag.height - root.menu.center.y, tag.wantY))
        width: tagRow.implicitWidth + 24
        height: 32
        radius: Theme.radius(16)
        color: root.colors.ink
        opacity: (tag.entry || root.menu.recording) && root.labelled ? root.menu.span(root.menu.reveal, 0.5, 1) : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: root.menu.ms(120) }
        }

        Row {
            id: tagRow
            anchors.centerIn: parent
            spacing: 10
            // a red dot for the recording's own tag
            Rectangle {
                visible: !tag.entry && root.menu.recording
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: root.menu.alarm
                opacity: Recorder.paused ? 0.4 : 1
            }
            ToolsLabel {
                menu: root.menu
                anchors.verticalCenter: parent.verticalCenter
                color: root.colors.fg
                content: tag.entry ? root.menu.label(tag.entry) : root.menu.recording ? Strings.tr("recording") : ""
                replayOnChange: true
            }
            // the key that does the same, or the running clock in its place -
            // the clock even with keys turned off, being news rather than a
            // reminder
            ToolsLabel {
                menu: root.menu
                visible: root.keyed || tag.telling
                anchors.verticalCenter: parent.verticalCenter
                size: 11
                color: root.colors.muted
                content: tag.telling ? root.menu.status() : tag.entry ? tag.entry.key.toUpperCase() : ""
                replayOnChange: !tag.telling
            }
        }
    }

    // ---------- the mark ----------

    // Where the pointer was, and now is in its place. Everything that differs
    // between the styles reads these. The outline setting does not reach it:
    // the mark is the pointer, and a pointer with a hairline round it reads
    // as a button.
    Item {
        id: mark
        // the pull as a fraction of its longest, each way
        readonly property real leanX: root.menu.pullX / root.menu.tether
        readonly property real leanY: root.menu.pullY / root.menu.tether
        // 1 open, near 0 shut - the blink, for the styles with eyes
        property real lid: 1
        // eyes leave a fading streak behind them as they move
        readonly property bool trails: !root.menu.still && Settings.toolsTrail !== "off"

        // Eased while the pie is out, but not while it is shut: opening
        // resets the lean with `reveal` at 0, and easing that would slide
        // the face in from wherever it leaned last time.
        x: mark.leanX * root.travel
        y: mark.leanY * root.travel
        Behavior on x {
            enabled: root.menu.reveal > 0
            NumberAnimation { duration: root.menu.ms(90); easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: root.menu.reveal > 0
            NumberAnimation { duration: root.menu.ms(90); easing.type: Easing.OutCubic }
        }
        scale: root.menu.grow(root.menu.span(root.menu.reveal, 0, 0.55))
        opacity: root.menu.span(root.menu.reveal, 0, 0.3)

        readonly property var styles: ({
                face: faceStyle,
                visor: visorStyle,
                cat: catStyle,
                sprout: sproutStyle
            })
        readonly property bool blinks: Settings.toolsFace !== "visor"

        // The recording's arc: once round a minute of it, behind the face so
        // that what a style wears on its head stays in front. Dimmed while
        // paused.
        Shape {
            visible: root.menu.recording
            opacity: Recorder.paused || Recorder.stopping ? 0.4 : 1
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.alpha(root.menu.alarm, 0.25)
                strokeWidth: 3
                fillColor: "transparent"
                PathAngleArc { radiusX: root.arcRadius; radiusY: root.arcRadius; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: root.menu.alarm
                strokeWidth: 3
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                // never quite nothing, so a fresh recording still shows a dot
                PathAngleArc { radiusX: root.arcRadius; radiusY: root.arcRadius; startAngle: -90; sweepAngle: Math.max(4, Recorder.elapsed % 60 * 6) }
            }
        }

        Loader {
            // centred on the mark's own point, whatever its size
            x: -width / 2
            y: -height / 2
            // Settings > Tools > "Tools menu pointer size", about its middle
            scale: root.faceScale
            sourceComponent: mark.styles[Settings.toolsFace] ?? faceStyle
        }

        // A blink every few seconds, at no fixed beat.
        SequentialAnimation {
            id: blink
            NumberAnimation { target: mark; property: "lid"; to: 0.1; duration: 70; easing.type: Easing.InQuad }
            NumberAnimation { target: mark; property: "lid"; to: 1; duration: 110; easing.type: Easing.OutQuad }
        }
        Timer {
            running: root.menu.open && !root.menu.still && mark.blinks
            interval: 2600
            repeat: true
            onTriggered: {
                interval = 2200 + Math.random() * 3800;
                blink.restart();
            }
        }
    }

    // A pair of eyes (or one, for the visor) that look along the pull, with
    // tracers: a streak behind the part that moves, back along where it was
    // over the last few frames, shrinking as it goes. The trail is kept in
    // screen terms - the face's own movement included, through baseX/baseY -
    // so a face swinging across leaves its eyes' streaks where they were.
    // Still, there is no trail and nothing shows.
    //
    //   pill   upright pills
    //   visor  one wide bar
    component EyePair: Item {
        id: pair
        property string kind: "pill"
        // where the moving part is headed, from its rest
        property real lookX: 0
        property real lookY: 0
        // the mark's position, for the trail to be kept in screen terms
        property real baseX: 0
        property real baseY: 0
        property real lid: 1
        property bool trails: true
        readonly property bool solid: Settings.toolsTrail === "solid"
        // White in either color mode (the ink, with the face inverted): the
        // eyes are what the pointer has become, and have to stand out on the
        // face whatever the theme makes of the rest.
        property color white: root.face.eyes
        property real gap: 7

        // where the moving part is now: eased after the look rather than
        // jumping with each report of the pointer, which is what draws the
        // trail out into a streak instead of a couple of stamps
        property real shownX: pair.lookX
        property real shownY: pair.lookY
        Behavior on shownX {
            enabled: pair.trails
            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }
        Behavior on shownY {
            enabled: pair.trails
            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }

        // Settings > Tools: what shape the eyes are - "pill" (upright
        // pills) or "apostrophe" (a round head with a tail curling down to
        // the left, like ’). The visor's one bar of an eye stays a bar.
        readonly property string shape: pair.kind === "visor" ? "pill" : Settings.toolsEyes
        readonly property int count: pair.kind === "visor" ? 1 : 2
        readonly property real eyeW: pair.kind === "visor" ? 22 : 8
        readonly property real eyeH: pair.kind === "visor" ? 7 : 15
        readonly property real partW: pair.eyeW
        readonly property real partH: Math.max(2, pair.eyeH * pair.lid)
        readonly property color partColor: pair.white

        width: pair.eyeW * pair.count + pair.gap * (pair.count - 1)
        height: pair.eyeH

        // Where the moving part has been, newest first, one entry a frame -
        // sampled only while there is a trail to draw.
        property var trail: []
        FrameAnimation {
            running: pair.trails && pair.visible
            onTriggered: {
                const kept = pair.trail.slice(0, 19);
                kept.unshift({ x: pair.shownX, y: pair.shownY, baseX: pair.baseX, baseY: pair.baseY });
                pair.trail = kept;
            }
        }

        // Where the middle of eye `eye` has been, in this item, newest (where
        // it is now) first - points closer than a pixel to the last kept are
        // dropped, so a still eye has no trail at all. At most `frames` long.
        function path(eye: int, frames: int): var {
            const cx = eye * (pair.eyeW + pair.gap) + pair.eyeW / 2;
            const cy = pair.eyeH / 2;
            const points = [Qt.point(cx + pair.shownX, cy + pair.shownY)];
            for (const at of pair.trail.slice(0, frames)) {
                // the face's movement is in the pie's pixels, the eyes' in
                // the (scaled) face's
                const point = Qt.point(cx + at.x + (at.baseX - pair.baseX) / root.faceScale, cy + at.y + (at.baseY - pair.baseY) / root.faceScale);
                const last = points[points.length - 1];
                if (Math.hypot(point.x - last.x, point.y - last.y) >= 0.75)
                    points.push(point);
            }
            // Smoothed, all but the head (which is where the eye is): the
            // face and the eyes each ease after the pointer on their own, and
            // every report of it starts both again, so the way they have come
            // kinks from frame to frame - and a streak drawn true to that has
            // an edge that wobbles in and out.
            for (let pass = 0; pass < 2; pass++) {
                const was = points.slice();
                for (let k = 1; k + 1 < was.length; k++)
                    points[k] = Qt.point((was[k - 1].x + 2 * was[k].x + was[k + 1].x) / 4, (was[k - 1].y + 2 * was[k].y + was[k + 1].y) / 4);
            }
            return points;
        }

        // The streak, as the eye swept back along where it has been: a copy
        // of the eye at every point of the path, shrinking towards the far
        // end, with a bridge from each to the next - all of it one filled
        // shape. It used to be a single outline drawn down one side of the
        // path and back up the other, which folded over itself wherever the
        // eye turned back (any back and forth), and the folds cut holes and
        // hairline outlines into it; small moves left needle-thin slivers out
        // of its pointed end. Pieces wound the same way under the winding
        // rule cannot cancel out wherever they overlap, and a swept eye ends
        // in a little rounded eye rather than a point.
        //
        // Returns the pieces (each a closed polyline), and the head and reach
        // for the fade.
        function streak(eye: int): var {
            // A solid streak, with no fade to soften it, is shorter and
            // thinner: full strength all the way, as long and as wide as a
            // fading one it reads as a second, heavier eye.
            const points = pair.path(eye, pair.solid ? 8 : 13);
            if (points.length < 2)
                return { pieces: [], head: Qt.point(0, 0), reach: 0 };
            const w = pair.partW;
            const h = pair.partH;
            const last = points.length - 1;
            // how big the eye is at each point: its own size at the head down
            // to a small dot at the far end - a solid one dropping straight to
            // about half the eye's size behind it
            const sizes = points.map((_, k) => k === 0 ? 1 : pair.solid ? 0.1 + 0.45 * (1 - k / last) : 1 - 0.8 * k / last);
            // The copies are of the eye's outline with any hollow in it filled
            // (an apostrophe's, under its head): a bridge between two copies
            // reaches only from the outermost points of each, so what a hollow
            // shape's tail swept through between them would be left out, as
            // slivers through the streak. The eye itself is drawn true over the
            // head of it (see drawnEye), and the copy there is left out so the
            // filled shape does not show through a streak you can see through -
            // but kept in a solid one, which the eye runs into as one shape,
            // and through which the eye's own hollow would show as a sliver.
            const outlines = points.map((point, k) => pair.filled(pair.outline(point, w * sizes[k], h * sizes[k], 8)));
            const pieces = [];
            for (let k = 0; k <= last; k++) {
                if (k > 0 || pair.shape !== "apostrophe" || pair.solid)
                    pieces.push(pair.wound(outlines[k]));
                if (k === last)
                    break;
                // the bridge to the next one: from the outermost point of
                // each to either side of the way between them
                const next = points[k + 1];
                const length = Math.hypot(next.x - points[k].x, next.y - points[k].y);
                const nx = -(next.y - points[k].y) / length;
                const ny = (next.x - points[k].x) / length;
                const a = pair.outermost(points[k], outlines[k], nx, ny, w * sizes[k], h * sizes[k]);
                const b = pair.outermost(next, outlines[k + 1], nx, ny, w * sizes[k + 1], h * sizes[k + 1]);
                const c = pair.outermost(next, outlines[k + 1], -nx, -ny, w * sizes[k + 1], h * sizes[k + 1]);
                const d = pair.outermost(points[k], outlines[k], -nx, -ny, w * sizes[k], h * sizes[k]);
                pieces.push(pair.wound([a, b, c, d, a]));
            }
            const head = points[0];
            const reach = Math.max(...points.map(point => Math.hypot(point.x - head.x, point.y - head.y)));
            return { pieces: pieces, head: head, reach: reach };
        }
        // The outline of an eye w by h round its middle at `center`, in the
        // eyes' shape, its curves in pieces `steps` to a quarter turn.
        function outline(center: point, w: real, h: real, steps: int): var {
            return pair.shape === "apostrophe" ? pair.apostropheAt(center, w, h, steps) : pair.eyeAt(center, w, h, Theme.radius(Math.min(w, h) / 2), steps);
        }
        // The point of the eye w by h round `center`, whose outline is
        // `outline`, that is furthest out along (nx, ny) - on the outline, so
        // that a bridge from it meets the eye without a corner standing out
        // past it. For a pill that is the middle of the corner that way, out
        // by the corner's round: worked out rather than picked from the
        // outline, whose straight sides would tie. An apostrophe has none, and
        // its outline's furthest point is the one.
        function outermost(center: point, outline: var, nx: real, ny: real, w: real, h: real): point {
            if (pair.shape !== "apostrophe") {
                const radius = Theme.radius(Math.min(w, h) / 2);
                return Qt.point(center.x + Math.sign(nx) * (w / 2 - radius) + nx * radius, center.y + Math.sign(ny) * (h / 2 - radius) + ny * radius);
            }
            let best = outline[0];
            for (const point of outline)
                if ((point.x - best.x) * nx + (point.y - best.y) * ny > 0)
                    best = point;
            return best;
        }
        // `outline` with any hollow in it filled: the smallest outline round
        // it with none (its convex hull), running the same way round. A pill
        // has no hollow and comes back as it was.
        function filled(outline: var): var {
            if (pair.shape !== "apostrophe")
                return outline;
            const points = outline.slice().sort((a, b) => a.x - b.x || a.y - b.y);
            const turn = (o, a, b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
            const lower = [];
            for (const point of points) {
                while (lower.length >= 2 && turn(lower[lower.length - 2], lower[lower.length - 1], point) <= 0)
                    lower.pop();
                lower.push(point);
            }
            const upper = [];
            for (const point of points.reverse()) {
                while (upper.length >= 2 && turn(upper[upper.length - 2], upper[upper.length - 1], point) <= 0)
                    upper.pop();
                upper.push(point);
            }
            const hull = lower.slice(0, -1).concat(upper.slice(0, -1));
            hull.push(hull[0]);
            return hull;
        }
        // An apostrophe w by h round `center`: drawn in an 8 by 15 box (the
        // pill's), a round head at the top and a tail from it curling down
        // and to the left to a point.
        function apostropheAt(center: point, w: real, h: real, steps: int): var {
            const across = w / 8;
            const down = h / 15;
            const outline = [];
            // the head, from its right round over the top to its lower left
            const turn = -250 * Math.PI / 180;
            for (let step = 0; step <= steps * 3; step++) {
                const angle = turn * step / (steps * 3);
                outline.push({ x: Math.cos(angle) * 4, y: -3.5 + Math.sin(angle) * 4 });
            }
            // then the tail's inside down to its point, and its outside back
            // up to where the head began
            const curve = (from, through, to) => {
                for (let step = 1; step <= steps * 2; step++) {
                    const t = step / (steps * 2);
                    const u = 1 - t;
                    outline.push({ x: u * u * from.x + 2 * u * t * through.x + t * t * to.x, y: u * u * from.y + 2 * u * t * through.y + t * t * to.y });
                }
            };
            const tip = { x: -2.6, y: 7.5 };
            curve(outline[outline.length - 1], { x: 0.4, y: 3.6 }, tip);
            curve(tip, { x: 4.3, y: 3.4 }, outline[0]);
            return outline.map(point => Qt.point(center.x + point.x * across, center.y + point.y * down));
        }
        // The outline of an eye w by h with corners of `radius`, round its
        // middle at `center`, each corner in `steps` straight pieces.
        function eyeAt(center: point, w: real, h: real, radius: real, steps: int): var {
            const outline = [];
            steps = radius > 0.5 ? steps : 0;
            const corners = [[1, 1], [-1, 1], [-1, -1], [1, -1]];
            for (let q = 0; q < 4; q++) {
                const ox = center.x + corners[q][0] * (w / 2 - radius);
                const oy = center.y + corners[q][1] * (h / 2 - radius);
                for (let step = 0; step <= steps; step++) {
                    const angle = (q + (steps > 0 ? step / steps : 0.5)) * Math.PI / 2;
                    outline.push(Qt.point(ox + Math.cos(angle) * radius, oy + Math.sin(angle) * radius));
                }
            }
            outline.push(outline[0]);
            return outline;
        }
        // `outline` turned, if it has to be, to run the same way round as
        // every other piece - which is what keeps the winding rule from
        // reading an overlap of two pieces as a hole
        function wound(outline: var): var {
            let area = 0;
            for (let k = 0; k + 1 < outline.length; k++)
                area += outline[k].x * outline[k + 1].y - outline[k + 1].x * outline[k].y;
            return area < 0 ? outline.reverse() : outline;
        }

        // one streak per eye back along where it has been, shrinking from
        // the eye's own size and fading with how far from the eye it is - by
        // distance rather than along a line from one end to the other,
        // which a streak that has doubled back has no good line for.
        //
        // Drawn by the geometry renderer, which merges the overlapping
        // pieces into one outline before it fills, and smoothed by drawing
        // that into a layer at twice the size it is shown at, multisampled,
        // and shrinking it back down - multisampling alone smooths an edge
        // in only a few steps, coarse beside everything else on the face,
        // which Qt smooths finely. The curve renderer smooths each
        // piece's own edges instead, and with the pieces a fast move makes -
        // long and thin, a new set every frame - it left those edges showing
        // inside the streak as pale seams (worst where it leaves the eye) and
        // the outline unsmoothed.
        Item {
            id: streaks
            // How far round the eyes a streak can reach - the layer stops at
            // its edges. The eyes look at most 9 either way, and the face
            // leans at most 26 either way of the pie's middle, which in the
            // eyes' terms is more the smaller the face is drawn.
            readonly property real room: 22 + 2 * 26 / root.faceScale
            x: -streaks.room
            y: -streaks.room
            width: pair.width + 2 * streaks.room
            height: pair.height + 2 * streaks.room
            visible: pair.trails
            layer.enabled: pair.trails
            layer.samples: 8
            // shrunk back down by plain linear sampling, which at exactly
            // half size is each pixel the average of its 2x2 - mipmapping
            // brings in the next size down as well, and blurs the edges
            layer.smooth: true
            // twice the size it is shown at, the face's own scale included
            readonly property real supersample: 2 * root.faceScale * Screen.devicePixelRatio
            layer.textureSize: Qt.size(Math.ceil(streaks.width * streaks.supersample), Math.ceil(streaks.height * streaks.supersample))

            Repeater {
                model: pair.trails ? pair.count : 0
                Shape {
                    id: tail
                    required property int index
                    readonly property var streak: pair.streak(tail.index)
                    // back on the eyes' own (0, 0), which the pieces are laid out from
                    x: streaks.room
                    y: streaks.room
                    preferredRendererType: Shape.GeometryRenderer
                    visible: tail.streak.pieces.length > 0 && tail.streak.reach >= 1
                    ShapePath {
                        strokeColor: "transparent"
                        fillRule: ShapePath.WindingFill
                        fillGradient: RadialGradient {
                            centerX: tail.streak.head.x
                            centerY: tail.streak.head.y
                            centerRadius: Math.max(1, tail.streak.reach)
                            focalX: tail.streak.head.x
                            focalY: tail.streak.head.y
                            // "solid" (Settings > Tools) keeps the taper but not the fade
                            GradientStop { position: 0; color: Qt.alpha(pair.partColor, pair.solid ? 1 : 0.75) }
                            GradientStop { position: 1; color: Qt.alpha(pair.partColor, pair.solid ? 1 : 0) }
                        }
                        PathMultiline { paths: tail.streak.pieces }
                    }
                }
            }

            // The eyes themselves, while there are streaks: in the same layer
            // as them rather than over it. Drawn over it, the eye's smoothed
            // edge and the streak's, on the same line where the streak leaves
            // the eye, each let half of what is behind them through, and
            // together showed as a pale seam round the eye; in the layer every
            // sample is either covered or not, and there is no seam to show.
            Repeater {
                model: pair.trails ? pair.count : 0
                Shape {
                    id: drawnEye
                    required property int index
                    x: streaks.room
                    y: streaks.room
                    preferredRendererType: Shape.GeometryRenderer
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: pair.partColor
                        PathPolyline {
                            path: pair.outline(Qt.point(drawnEye.index * (pair.eyeW + pair.gap) + pair.eyeW / 2 + pair.shownX, pair.eyeH / 2 + pair.shownY), pair.partW, pair.partH, 12)
                        }
                    }
                }
            }
        }

        // the eyes themselves, while there are no streaks (see above for
        // while there are): apostrophes drawn as their outline...
        Repeater {
            model: pair.trails || pair.shape !== "apostrophe" ? 0 : pair.count
            Shape {
                id: stillEye
                required property int index
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: pair.partColor
                    PathPolyline {
                        path: pair.outline(Qt.point(stillEye.index * (pair.eyeW + pair.gap) + pair.eyeW / 2 + pair.shownX, pair.eyeH / 2 + pair.shownY), pair.partW, pair.partH, 12)
                    }
                }
            }
        }
        // ...and pills as rounded rectangles
        Repeater {
            model: pair.trails || pair.shape === "apostrophe" ? 0 : pair.count
            Rectangle {
                required property int index
                x: index * (pair.eyeW + pair.gap) + pair.shownX
                y: (pair.eyeH - pair.partH) / 2 + pair.shownY
                width: pair.partW
                height: pair.partH
                radius: Theme.radius(Math.min(width, height) / 2)
                color: pair.partColor
            }
        }
    }

    // the dark disc the face styles are drawn on
    component Disc: Rectangle {
        width: 44
        height: 44
        radius: Theme.radius(22)
        color: root.face.skin
    }

    Component {
        id: faceStyle
        Disc {
            EyePair {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -2
                lookX: mark.leanX * 9
                lookY: mark.leanY * 9
                baseX: mark.x
                baseY: mark.y
                lid: mark.lid
                trails: mark.trails
            }
        }
    }

    // The face with a little something on its head. The face sits at the
    // middle of the item, as every style's does, with the room above it for
    // what is worn; every add-on is the face's own dark, with white for
    // its details, so it reads as one figure.
    component Topped: Item {
        id: topped
        // what is worn, drawn behind the face
        default property alias addon: behind.data
        width: 52
        height: 72
        Item {
            id: behind
            anchors.fill: parent
        }
        Disc {
            x: 4
            y: 14
            EyePair {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                lookX: mark.leanX * 9
                lookY: mark.leanY * 8
                baseX: mark.x
                baseY: mark.y
                lid: mark.lid
                trails: mark.trails
            }
        }
    }
    // a filled outline in the face's dark, for the add-ons
    component Patch: ShapePath {
        fillColor: root.face.skin
        strokeColor: "transparent"
        joinStyle: ShapePath.RoundJoin
    }

    Component {
        id: catStyle
        Topped {
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                Patch {
                    startX: 7; startY: 28
                    PathLine { x: 8; y: 5 }
                    PathLine { x: 23; y: 17 }
                    PathLine { x: 7; y: 28 }
                }
                Patch {
                    startX: 45; startY: 28
                    PathLine { x: 44; y: 5 }
                    PathLine { x: 29; y: 17 }
                    PathLine { x: 45; y: 28 }
                }
            }
        }
    }
    Component {
        id: sproutStyle
        Topped {
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // The stem: a little crooked, thicker where it comes out of
                // the head and narrowing to a rounded tip, like a twig rather
                // than a pole. Its foot is hidden behind the face.
                Patch {
                    startX: 24.6; startY: 17
                    PathQuad { x: 26.0; y: 4.6; controlX: 22.4; controlY: 11 }
                    PathArc { x: 27.8; y: 4.2; radiusX: 1; radiusY: 1; direction: PathArc.Clockwise }
                    PathQuad { x: 28.2; y: 17; controlX: 25.4; controlY: 11 }
                    PathLine { x: 24.6; y: 17 }
                }
                Patch {
                    startX: 26; startY: 8
                    PathQuad { x: 13; y: 1; controlX: 17; controlY: 10 }
                    PathQuad { x: 26; y: 8; controlX: 21; controlY: -3 }
                }
                Patch {
                    startX: 26; startY: 10
                    PathQuad { x: 38; y: 4; controlX: 35; controlY: 13 }
                    PathQuad { x: 26; y: 10; controlX: 31; controlY: -1 }
                }
            }
        }
    }
    // one wide bar of an eye that slides across, like a visor
    Component {
        id: visorStyle
        Disc {
            EyePair {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -2
                kind: "visor"
                lookX: mark.leanX * 9
                lookY: mark.leanY * 12
                baseX: mark.x
                baseY: mark.y
                trails: mark.trails
            }
        }
    }
}
