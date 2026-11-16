import QtQuick
import "root:/config"
import "root:/services"

// The tools menu with nothing drawn: what the actions are (search, copy text,
// scan a code, translate, record, record an area, pick a color - see
// services/ScreenTools.qml - and, while a recording runs, its pause and stop
// on an inner ring), which one is chosen,
// how the pointer and the keys choose, and the one clock (`reveal`) every part
// of it animates off. What it looks like is ToolsPie.
//
// It is a pie that opens where the pointer is. The pointer itself goes, and a
// small face with eyes stands in for it at the middle of the pie; moving the
// mouse leans the face that way, its eyes look that way, and the tool lying in
// that direction is the chosen one. A click runs it. The choice is made by
// how far the pointer has moved since the pie opened, not where it is - so it
// works the same when the pie had to be put somewhere else to fit on the
// screen, or when where the pointer was could not be known (see `place`).
//
// It is drawn in two places, and this is the part they share. Opened with
// `pibble toggle tools` while the launcher is up it stands on the launcher
// (see launcher/PowerOverlay.qml); with nothing up it is on the tools overlay
// (flyouts/ToolsOverlay.qml). Whoever hosts it says whether it
// is `open`, and is told when it
// should close (`dismissed`) and what was picked (`picked`) - what happens
// next differs, since the launcher has to get off the screen before any tool
// can look at it.
Item {
    id: root

    // the host's say on whether the menu is out
    property bool open: false

    signal dismissed
    signal picked(string action)

    // In the order they sit round the pie, clockwise from the top.
    readonly property var actions: [
        { id: "search", glyph: Icons.search, label: "search", hint: "drag over anything", key: "s" },
        { id: "copy", glyph: Icons.textFields, label: "copy text", hint: "drag over the words", key: "x" },
        { id: "code", glyph: Icons.qrScanner, label: "scan code", hint: "drag over the code", key: "q" },
        { id: "translate", glyph: Icons.translate, label: "translate", hint: "drag over the text", key: "t" },
        { id: "record", glyph: Icons.videocam, label: "record", hint: "the whole screen", key: "r" },
        { id: "area", glyph: Icons.screenshotRegion, label: "record area", hint: "drag a rectangle", key: "a" },
        { id: "color", glyph: Icons.eyedropper, label: "pick color", hint: "copies its hex", key: "c" }
    ]
    // While a recording runs, its two controls, on a small ring of their own
    // between the face and the tools: pause at the top, stop at the bottom.
    // They take the record keys, the two record tools being out of use
    // until it ends.
    readonly property bool recording: Recorder.recording
    readonly property var controls: [
        { id: "pause", glyph: Icons.pause, label: "pause", key: "r", inner: true },
        { id: "stop", glyph: Icons.stop, label: "stop", key: "a", inner: true }
    ]
    // Every choice is one number: the tools are 0 onwards in their order,
    // and the controls follow on after them.
    readonly property int count: root.actions.length + (root.recording ? root.controls.length : 0)
    function entry(index: int): var {
        if (index < 0 || index >= root.count)
            return null;
        return index < root.actions.length ? root.actions[index] : root.controls[index - root.actions.length];
    }
    // the one chosen, or -1 while the pointer has not moved far enough to
    // say
    property int current: -1
    // a recording ending with one of its controls chosen leaves nothing chosen
    onCountChanged: {
        if (root.current >= root.count)
            root.current = -1;
    }

    // "pop", "fade", "slide" or "none" - the volume OSD's four
    readonly property string anim: Defaults.toolsAnims.includes(Settings.toolsAnim) ? Settings.toolsAnim : Defaults.toolsAnim
    readonly property bool still: root.anim === "none"

    // 0 with nothing on screen, 1 with the pie fully out. It runs linearly
    // and each part maps a stretch of it onto its own motion, so that an
    // entrance is one number going up, an exit is the same number coming
    // down faster, and a stagger is parts reading different stretches of it.
    property real reveal: 0
    // anything of the menu is on screen - for a host that holds the pointer
    // for as long as this says so
    readonly property bool up: root.open || root.reveal > 0

    // ---------- what the menu asks about an action ----------

    // Out of use, and so not choosable: the two record tools while a
    // recording runs (there is one recorder), and its controls once it is
    // saving.
    function off(entry: var): bool {
        if (entry.inner)
            return Recorder.stopping;
        return root.recording && (entry.id === "record" || entry.id === "area");
    }
    function glyph(entry: var): string {
        if (entry.id === "pause" && Recorder.paused)
            return Icons.play;
        return entry.glyph;
    }
    function label(entry: var): string {
        if (entry.id === "pause" && Recorder.paused)
            return Strings.tr("resume");
        return Strings.tr(entry.label);
    }
    // how the recording stands, for beside its controls
    function status(): string {
        if (Recorder.stopping)
            return Strings.tr("saving…");
        if (Recorder.paused)
            return Strings.trf("paused at %1", Recorder.clock(Recorder.elapsed));
        return Recorder.clock(Recorder.elapsed);
    }
    // The one colour here that is not the tools' palette: a recording is
    // red.
    readonly property color alarm: "#ff4d4d"

    // ---------- motion ----------

    // A duration, or nothing with the menu's animation off - for everything
    // that moves after the entrance (the choice moving, the face leaning).
    function ms(duration: int): int {
        return root.still ? 0 : duration;
    }
    // how far `t` is through the stretch from..to, held at 0 before and 1 after
    function span(t: real, from: real, to: real): real {
        return Math.max(0, Math.min(1, (t - from) / (to - from)));
    }
    // decelerating into place
    function cubic(t: real): real {
        const u = 1 - t;
        return 1 - u * u * u;
    }
    // past the mark by `over` and back onto it
    function back(t: real, over: real): real {
        const u = t - 1;
        return 1 + (over + 1) * u * u * u + over * u * u;
    }
    // How a part arrives, which is the tiles' own recipe (see Anim) read off
    // the menu's setting instead of theirs: under "pop" it springs up from a
    // fraction of its size and overshoots, otherwise it decelerates into place.
    readonly property real fromScale: root.anim === "pop" ? 0.4 : 1
    function settle(t: real): real {
        return root.anim === "pop" ? root.back(t, 1.8) : root.cubic(t);
    }
    function grow(t: real): real {
        return root.fromScale + (1 - root.fromScale) * root.settle(t);
    }

    // ---------- where the pie is ----------

    // The pie's middle, in this item. Kept far enough from the edges that
    // the buttons and the name beside the chosen one are on the screen.
    property point center: Qt.point(root.width / 2, root.height / 2)
    // Where the pointer was, from the middle - the face sets out from there
    // and settles into the middle as the pie opens, so a pie that had to be
    // put elsewhere to fit still visibly comes from the pointer.
    property point setOut: Qt.point(0, 0)
    // the pie has been put somewhere and may start coming out
    property bool placed: false

    // How far the pointer has moved since the pie opened, the length held at
    // `tether`: past that the point it is measured from is dragged along
    // behind it, so turning back the other way answers at once instead of
    // after the whole way back.
    property real pullX: 0
    property real pullY: 0
    // Long enough that the heading is the way the hand went, not the last
    // few pixels of it curling off as it slows down.
    readonly property real tether: 110
    // inside this nothing is chosen - the pointer resting, or a hand's tremor
    readonly property real dead: 28
    // How far past the edge of the chosen tool's slice the heading has to go
    // before the next one takes over, in degrees. Without it a heading lying
    // near the edge flickers between the two with every pixel.
    readonly property real stick: 16
    // While recording, how far the pull reaches says which ring: a short
    // one the controls, a long one the tools. Crossing over takes going
    // past the middle by a margin either way, for the same reason as
    // `stick`; with nothing chosen yet the middle itself decides.
    readonly property real ringEdge: 66
    readonly property real ringStick: 12
    property real fromX: 0
    property real fromY: 0
    property bool fromKnown: false
    property real lastX: 0
    property real lastY: 0

    // `at` is where the pointer is when that is known, or null. The pointer
    // can be unknown here: out on the desktop the overlay only hears of the
    // pointer once it moves over the surface, which the compositor may not
    // say until it moves at all. The first movement then becomes the point
    // the pull is measured from, and the pie is where it was put.
    function place(at: var): void {
        const spot = at ?? Qt.point(root.width / 2, root.height / 2);
        root.center = Qt.point(Math.max(pie.roomX, Math.min(root.width - pie.roomX, spot.x)), Math.max(pie.roomY, Math.min(root.height - pie.roomY, spot.y)));
        root.setOut = Qt.point(spot.x - root.center.x, spot.y - root.center.y);
        root.fromKnown = at !== null;
        if (at !== null) {
            root.fromX = at.x;
            root.fromY = at.y;
            root.lastX = at.x;
            root.lastY = at.y;
        }
        root.placed = true;
        waiting.stop();
        enter.restart();
    }
    // A short wait for the pointer before giving up on it and opening in the
    // middle - long enough for the compositor's word on where it is, short
    // enough not to read as lag.
    Timer {
        id: waiting
        interval: 150
        onTriggered: root.place(null)
    }

    // Each ring's slots share the circle evenly, clockwise from straight up.
    function inner(index: int): bool {
        return index >= root.actions.length;
    }
    function direction(index: int): point {
        const slots = root.inner(index) ? root.controls.length : root.actions.length;
        const at = root.inner(index) ? index - root.actions.length : index;
        const angle = (-90 + at * 360 / slots) * Math.PI / 180;
        return Qt.point(Math.cos(angle), Math.sin(angle));
    }
    // the slot of `slots` nearest a heading, in degrees clockwise from
    // straight up
    function nearest(degrees: real, slots: int): int {
        return ((Math.round(degrees / (360 / slots)) % slots) + slots) % slots;
    }
    // which ring a pull this long is asking for
    function wantsInner(length: real): bool {
        if (!root.recording)
            return false;
        if (root.current < 0)
            return length < root.ringEdge;
        return length < root.ringEdge + (root.inner(root.current) ? root.ringStick : -root.ringStick);
    }

    function track(x: real, y: real): void {
        if (!root.open)
            return;
        if (!root.placed) {
            root.place(Qt.point(x, y));
            return;
        }
        root.lastX = x;
        root.lastY = y;
        if (!root.fromKnown) {
            root.fromX = x;
            root.fromY = y;
            root.fromKnown = true;
            return;
        }
        let dx = x - root.fromX;
        let dy = y - root.fromY;
        const length = Math.hypot(dx, dy);
        if (length > root.tether) {
            dx = dx / length * root.tether;
            dy = dy / length * root.tether;
            root.fromX = x - dx;
            root.fromY = y - dy;
        }
        root.pullX = dx;
        root.pullY = dy;
        const pulled = Math.hypot(dx, dy);
        if (pulled > root.dead)
            root.choose(Math.atan2(dy, dx) * 180 / Math.PI + 90, root.wantsInner(pulled));
    }
    function choose(heading: real, inner: bool): void {
        const first = inner ? root.actions.length : 0;
        const slots = inner ? root.controls.length : root.actions.length;
        const pitch = 360 / slots;
        if (root.current >= first && root.current < first + slots) {
            const off = ((heading - (root.current - first) * pitch) % 360 + 540) % 360 - 180;
            if (Math.abs(off) <= pitch / 2 + root.stick)
                return;
        }
        const index = first + root.nearest(heading, slots);
        root.current = root.off(root.entry(index)) ? -1 : index;
    }

    // A key's choice: the face leans the way the pointer would have, and the
    // point the pull is measured from moves to match, so the next nudge of
    // the mouse carries on from here rather than snapping back.
    function aim(index: int): void {
        const toward = root.direction(index);
        const reach = root.inner(index) ? root.ringEdge - root.ringStick - 10 : root.tether;
        root.current = index;
        root.pullX = toward.x * reach;
        root.pullY = toward.y * reach;
        root.fromX = root.lastX - root.pullX;
        root.fromY = root.lastY - root.pullY;
    }

    // One along, round the tools and on through the controls, passing over
    // what is out of use.
    function step(by: int): void {
        const count = root.count;
        let index = root.current < 0 ? (by > 0 ? -1 : count) : root.current;
        for (let tries = 0; tries < count; tries++) {
            index = ((index + by) % count + count) % count;
            if (!root.off(root.entry(index))) {
                root.aim(index);
                return;
            }
        }
    }

    function run(index: int): void {
        const entry = root.entry(index);
        if (!entry || root.off(entry))
            return;
        root.current = index;
        root.picked(entry.id);
    }

    // The host hands every key here while the menu is open. The arrows step
    // round, one tool at a time, the way they would down a list: Right and
    // Down to the next tool clockwise, Left and Up back. Pointing instead
    // (Up for the tool at the top) left the tools between the four
    // directions out of reach of any arrow.
    function key(event: var): void {
        if (event.key === Qt.Key_Escape)
            root.dismissed();
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down)
            root.step(1);
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up)
            root.step(-1);
        else if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))
            root.step(1);
        // Shift+Tab is its own key (Backtab) on most keymaps, and Tab with
        // Shift held on the rest
        else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Tab)
            root.step(-1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (root.current >= 0)
                root.run(root.current);
        } else {
            // the first that is in use, so that while recording the record
            // keys reach its controls
            const typed = event.text.toLowerCase();
            for (let index = 0; index < root.count; index++) {
                const entry = root.entry(index);
                if (entry.key === typed && !root.off(entry)) {
                    root.run(index);
                    break;
                }
            }
        }
    }

    // ---------- coming and going ----------

    NumberAnimation {
        id: enter
        target: root
        property: "reveal"
        to: 1
        duration: root.ms(pie.spawn)
    }
    NumberAnimation {
        id: leave
        target: root
        property: "reveal"
        to: 0
        duration: ScreenTools.menuExit
    }
    onOpenChanged: {
        if (root.open) {
            leave.stop();
            root.reveal = 0;
            root.current = -1;
            root.pullX = 0;
            root.pullY = 0;
            root.placed = false;
            if (hover.hovered)
                root.place(hover.point.position);
            else
                waiting.restart();
        } else {
            waiting.stop();
            enter.stop();
            leave.restart();
        }
    }

    // Where the pointer is while it is over this item at all, open or not -
    // on the launcher that is all the time, so a keybind opens the pie right
    // under it.
    HoverHandler {
        id: hover
    }

    // The whole item is the pie's while it is open: the pointer is hidden
    // over it (the face is the pointer now), every movement is a pull, a
    // click runs the chosen tool, and any other button closes it.
    MouseArea {
        anchors.fill: parent
        // gone, not just disabled, while the menu is closed: a disabled
        // MouseArea still sets its cursor, and over the launcher that would
        // be every cursor the launcher's own controls ask for
        visible: root.open
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
        onEntered: root.track(mouseX, mouseY)
        onPositionChanged: mouse => root.track(mouse.x, mouse.y)
        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton)
                root.dismissed();
        }
        // On the release rather than the press, so press, flick and let go
        // works as well as move then click. Released with nothing chosen it
        // closes, as a click on nothing would.
        onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton || !root.open)
                return;
            if (root.current >= 0)
                root.run(root.current);
            else
                root.dismissed();
        }
        // One notch is one step round, gathered up the way the launcher's
        // grid does it so a touchpad's stream of small deltas is not a step
        // apiece; scrolling down goes clockwise.
        property real gathered: 0
        onWheel: wheel => {
            gathered += wheel.angleDelta.y;
            while (gathered >= 120) {
                root.step(-1);
                gathered -= 120;
            }
            while (gathered <= -120) {
                root.step(1);
                gathered += 120;
            }
        }
    }

    // Built all along, not on demand: building it on the keypress that opens
    // it would be a hitch in the first frames of its entrance.
    ToolsPie {
        id: pie
        menu: root
        visible: root.up && root.placed
    }
}
