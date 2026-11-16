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
// it to the theme; the eyes stay white either way.
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
    // the recording's controls: their ring, and how big each is
    readonly property real innerOrbit: 60
    readonly property real innerSize: 38
    // the tools' ring - out past the controls' while they are there
    readonly property real orbit: root.menu.recording ? Math.max(root.spread, root.innerOrbit + root.innerSize / 2 + 12 + root.size / 2) : root.spread
    // how far the mark can lean out of the middle: most of the way to the
    // chosen button, short of touching it however close the buttons are set,
    // and only a little with the controls (and the arc it wears) close by
    readonly property real travel: root.menu.recording ? 8 : Math.max(6, Math.min(26, root.orbit - root.size * 0.55 - 26))

    readonly property var colors: Theme.tools

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
                color: slot.chosen ? root.colors.accent : root.colors.ink
                scale: slot.chosen ? 1.1 : 1
                Behavior on color {
                    ColorAnimation { duration: root.menu.ms(110) }
                }
                Behavior on scale {
                    NumberAnimation { duration: root.menu.ms(220); easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.menu.glyph(slot.modelData)
                    color: slot.chosen ? root.colors.ink : root.colors.glyph
                    font.family: Icons.family
                    font.pixelSize: Theme.fontSize(22)
                }
            }
        }
    }

    // The recording's controls, coming out after the tools. Stop is the
    // recording's red, and lights up red rather than in the accent.
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
                color: !control.chosen ? root.colors.ink : control.red ? root.menu.alarm : root.colors.accent
                scale: control.chosen ? 1.12 : 1
                Behavior on color {
                    ColorAnimation { duration: root.menu.ms(110) }
                }
                Behavior on scale {
                    NumberAnimation { duration: root.menu.ms(220); easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.menu.glyph(control.modelData)
                    color: control.chosen ? root.colors.ink : control.red ? root.menu.alarm : root.colors.glyph
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
        // still on its way in from where the pointer was: 1 at the start of
        // the entrance, 0 once it has arrived
        readonly property real away: 1 - root.menu.cubic(root.menu.span(root.menu.reveal, 0, 0.6))
        // 1 open, near 0 shut - the blink, for the styles with eyes
        property real lid: 1
        // eyes leave a fading streak behind them as they move
        readonly property bool trails: !root.menu.still && Settings.toolsTrail !== "off"

        x: mark.leanX * root.travel + root.menu.setOut.x * mark.away
        y: mark.leanY * root.travel + root.menu.setOut.y * mark.away
        Behavior on x {
            NumberAnimation { duration: root.menu.ms(90); easing.type: Easing.OutCubic }
        }
        Behavior on y {
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
                PathAngleArc { radiusX: 28; radiusY: 28; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: root.menu.alarm
                strokeWidth: 3
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                // never quite nothing, so a fresh recording still shows a dot
                PathAngleArc { radiusX: 28; radiusY: 28; startAngle: -90; sweepAngle: Math.max(4, Recorder.elapsed % 60 * 6) }
            }
        }

        Loader {
            // centred on the mark's own point, whatever its size
            x: -width / 2
            y: -height / 2
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
    // over the last few frames, tapering to a point. The trail is kept in
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
        // White in either color mode: the eyes are what the pointer has
        // become, and have to stand out on the dark face whatever the theme
        // makes of the rest.
        property color white: "#ffffff"
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
                kept.unshift({ x: pair.baseX + pair.shownX, y: pair.baseY + pair.shownY });
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
                const point = Qt.point(cx + at.x - pair.baseX, cy + at.y - pair.baseY);
                const last = points[points.length - 1];
                if (Math.hypot(point.x - last.x, point.y - last.y) >= 0.75)
                    points.push(point);
            }
            return points.length < 3 ? [] : points;
        }

        // The streak's outline: the path pushed out to either side by half
        // of how wide the eye is across the way it is moving - which for the
        // visor, wide and short, is its height moving sideways and its width
        // moving up and down - shrinking to nothing at the far end.
        function streak(eye: int): var {
            return pair.ribbon(pair.path(eye, 13), (tx, ty) => Math.abs(ty) * pair.partW / 2 + Math.abs(tx) * pair.partH / 2);
        }
        // A line through `points` turned into a filled outline, as wide at
        // the head as `half` says for the way it runs there and narrowing to
        // a point at the far end - filled, so that it can fade along its
        // length, which a stroke here cannot.
        function ribbon(points: var, half: var): var {
            if (points.length === 0)
                return [];
            const left = [];
            const right = [];
            let tx = 0, ty = 0;
            for (let k = 0; k < points.length; k++) {
                const before = points[Math.max(0, k - 1)];
                const after = points[Math.min(points.length - 1, k + 1)];
                const length = Math.hypot(after.x - before.x, after.y - before.y);
                if (length > 0.01) {
                    tx = (after.x - before.x) / length;
                    ty = (after.y - before.y) / length;
                }
                const width = half(tx, ty) * (1 - k / (points.length - 1));
                left.push(Qt.point(points[k].x - ty * width, points[k].y + tx * width));
                right.push(Qt.point(points[k].x + ty * width, points[k].y - tx * width));
            }
            return left.concat(right.reverse(), [left[0]]);
        }

        // one streak per eye back along where it has been, tapering from the
        // eye's own size to a point and fading as it goes
        Repeater {
            model: pair.trails ? pair.count : 0
            Shape {
                id: tail
                required property int index
                readonly property var outline: pair.streak(tail.index)
                readonly property point head: tail.outline.length > 0 ? tail.outline[0] : Qt.point(0, 0)
                readonly property point end: tail.outline.length > 0 ? tail.outline[Math.floor(tail.outline.length / 2) - 1] : Qt.point(0, 0)
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                visible: tail.outline.length > 0
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        x1: tail.head.x
                        y1: tail.head.y
                        x2: tail.end.x
                        y2: tail.end.y
                        GradientStop { position: 0; color: Qt.alpha(pair.partColor, 0.75) }
                        GradientStop { position: 1; color: Qt.alpha(pair.partColor, 0) }
                    }
                    PathPolyline { path: tail.outline }
                }
            }
        }

        // the eyes themselves
        Repeater {
            model: pair.count
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
        color: root.colors.ink
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
        fillColor: root.colors.ink
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
            Rectangle {
                x: 25
                y: 5
                width: 2.5
                height: 11
                color: root.colors.ink
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
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
