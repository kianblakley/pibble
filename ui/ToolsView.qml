import QtQuick
import QtQuick.Shapes
import "root:/config"
import "root:/services"

// Where the screen tools' gestures happen (see services/ScreenTools.qml for
// what they are): a frozen frame of the screen with a rectangle dragged over
// it, and whatever came of that - the words read, lit where they sit and
// selectable like a document's, a bar of things to do with them on the
// rectangle's corner, and the translated paragraphs laid over the ones they
// replace.
//
// It is drawn in two places, like the color picker's view. With nothing
// else up it fills the tools overlay (flyouts/ToolsOverlay.qml); started
// with the launcher up it is the launcher's, drawn over the launcher as it
// stands (see ScreenTools.host), so a tool used on one of pibble's pages
// reads that page and leaves it open. Whoever hosts it fills it to the whole
// output and says when it is `active`.
//
// This file decides nothing. It reports what the pointer did in the frame's
// own pixels and paints what ScreenTools says is there.
Item {
    id: view

    property bool active: false

    // One of the bar's actions: a word, and the key that does the same
    // thing. The one Enter does is ringed, and says so on its key.
    component BarChip: Item {
        id: chip
        property string label: ""
        property string key: ""
        property bool primary: false
        property bool enabled: true
        signal triggered

        implicitWidth: chipRow.implicitWidth + 24
        implicitHeight: 28
        opacity: chip.enabled ? 1 : 0.5

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius(14)
            color: chipHover.containsMouse && chip.enabled ? Qt.alpha(Theme.tools.accent, 0.14) : "transparent"
            border.width: chip.primary ? 2 : 0
            border.color: Theme.tools.accent
        }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: Theme.tools.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize(13)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.key !== ""
                implicitWidth: Math.max(18, capText.implicitWidth + 8)
                implicitHeight: 18
                width: implicitWidth
                height: implicitHeight
                radius: Theme.radius(4)
                color: Qt.alpha(Theme.tools.fg, 0.07)
                border.width: 1
                border.color: Qt.alpha(Theme.tools.fg, 0.16)
                Text {
                    id: capText
                    anchors.centerIn: parent
                    text: chip.primary ? Icons.cornerDownLeft : chip.key
                    color: Theme.tools.muted
                    font.family: chip.primary ? Icons.family : Theme.fontFamily
                    font.pixelSize: Theme.fontSize(chip.primary ? 12 : 10)
                }
            }
        }
        MouseArea {
            id: chipHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (chip.enabled)
                    chip.triggered();
            }
        }
    }

    // Frame pixels per logical pixel - what every coordinate crossing
    // between this view and ScreenTools is multiplied or divided by. Taken off
    // the image, like the picker's, rather than asked of the compositor.
    readonly property real ratio: frozen.sourceSize.width > 0 && view.width > 0 ? frozen.sourceSize.width / view.width : 1
    readonly property bool decoded: frozen.status === Image.Ready && frozen.sourceSize.width >= view.width && frozen.sourceSize.height >= view.height
    // whether there is anything of this view's on screen yet: the frame
    // for the gestures that freeze, the bare dim for the one that does not
    readonly property bool up: view.active && (ScreenTools.mode === "region" ? ScreenTools.phase === "select" : view.decoded)
    // a rectangle can be dragged: the one gesture that only ever takes one,
    // or any of the others again after the first
    readonly property bool markable: view.active && ((ScreenTools.reading && ["select", "working", "result"].includes(ScreenTools.phase)) || (ScreenTools.mode === "region" && ScreenTools.phase === "select"))

    function report(): void {
        if (view.active && view.decoded && ScreenTools.phase === "frame")
            ScreenTools.frameReady(frozen.sourceSize.width, frozen.sourceSize.height, view.ratio);
    }
    onDecodedChanged: view.report()

    // the two corners a rectangle is being dragged between (logical pixels)
    property bool drawing: false
    property point from: Qt.point(0, 0)
    property point to: Qt.point(0, 0)
    // translate: Space is held, and the page shows through untranslated
    property bool peek: false

    // What is marked, in this view's pixels: the rectangle under the
    // pointer while one is being dragged, else whatever ScreenTools has taken as
    // the selection. Zero-sized while there is neither.
    readonly property rect marked: {
        if (view.drawing)
            return Qt.rect(Math.min(view.from.x, view.to.x), Math.min(view.from.y, view.to.y), Math.abs(view.to.x - view.from.x), Math.abs(view.to.y - view.from.y));
        if (ScreenTools.reading && ScreenTools.selection.width > 0)
            return Qt.rect(ScreenTools.selection.x / view.ratio, ScreenTools.selection.y / view.ratio, ScreenTools.selection.width / view.ratio, ScreenTools.selection.height / view.ratio);
        return Qt.rect(0, 0, 0, 0);
    }
    readonly property bool hasMark: view.marked.width > 0 && view.marked.height > 0

    // ---------- the words read ----------

    // what was read is up, with words in it, and not covered by its own
    // translation - so they can be selected
    readonly property bool selectable: view.active && ScreenTools.phase === "result" && ScreenTools.words.length > 0 && ScreenTools.translate !== "shown"

    // Every line of words, as a band across this view's pixels: the first
    // and last of its words (indices into ScreenTools.words) and its box.
    readonly property var lines: {
        const out = [];
        const words = ScreenTools.words;
        for (let i = 0; i < words.length; i++) {
            const word = words[i];
            const last = out.length > 0 ? out[out.length - 1] : null;
            if (!last || last.line !== word.line) {
                out.push({ line: word.line, first: i, last: i, x0: word.x / view.ratio, x1: (word.x + word.w) / view.ratio, y0: word.y / view.ratio, y1: (word.y + word.h) / view.ratio });
                continue;
            }
            last.last = i;
            last.x0 = Math.min(last.x0, word.x / view.ratio);
            last.x1 = Math.max(last.x1, (word.x + word.w) / view.ratio);
            last.y0 = Math.min(last.y0, word.y / view.ratio);
            last.y1 = Math.max(last.y1, (word.y + word.h) / view.ratio);
        }
        return out;
    }

    // The line under a point in this view's pixels, or failing that the
    // nearest one: nearest up and down first, then across - two columns'
    // lines at one height are told apart by which the point is nearer.
    function lineAt(x: real, y: real): var {
        let best = null;
        let bestDy = 1e9;
        let bestDx = 1e9;
        for (const line of view.lines) {
            const dy = y < line.y0 ? line.y0 - y : y > line.y1 ? y - line.y1 : 0;
            const dx = x < line.x0 ? line.x0 - x : x > line.x1 ? x - line.x1 : 0;
            if (dy < bestDy - 0.5 || (Math.abs(dy - bestDy) <= 0.5 && dx < bestDx)) {
                best = line;
                bestDy = dy;
                bestDx = dx;
            }
        }
        return best;
    }
    // The word a point picks: the one on its line it is over, or in the
    // space after; before a line's first word, that one. -1 with no words.
    function wordAt(x: real, y: real): int {
        const line = view.lineAt(x, y);
        if (!line)
            return -1;
        let picked = line.first;
        for (let i = line.first; i <= line.last; i++) {
            if (ScreenTools.words[i].x / view.ratio <= x)
                picked = i;
        }
        return picked;
    }
    function inMark(x: real, y: real): bool {
        return view.hasMark && x >= view.marked.x && x <= view.marked.x + view.marked.width && y >= view.marked.y && y <= view.marked.y + view.marked.height;
    }

    // Focus is taken as the gesture starts rather than declared: whoever
    // hosts this has keys of its own the rest of the time.
    onActiveChanged: {
        view.drawing = false;
        view.peek = false;
        pointer.picking = false;
        if (view.active)
            keys.forceActiveFocus();
    }
    Connections {
        target: ScreenTools
        function onPhaseChanged(): void {
            view.report();
        }
    }

    // ---------- the frame ----------

    // Straight off the capture file and unsmoothed, standing in for the
    // screen it was taken from: it must not come out softer than what it
    // replaced.
    Image {
        id: frozen
        anchors.fill: parent
        source: ScreenTools.shotPath ? "file://" + ScreenTools.shotPath : ""
        visible: view.active && status === Image.Ready
        fillMode: Image.Stretch
        cache: false
        smooth: false
    }

    // The dim, as four bands around whatever is marked so that the marked
    // part alone stays at full brightness. With nothing marked the bottom
    // band is the whole screen and the other three have no height.
    Item {
        id: dim
        anchors.fill: parent
        // The marked part is left at full brightness, which is also where a
        // translation's boxes go: they are painted in colors sampled from
        // the page, and only an undimmed page still matches them.
        opacity: !view.up ? 0 : view.hasMark ? 0.55 : 0.3
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Rectangle { color: "black"; x: 0; y: 0; width: parent.width; height: view.marked.y }
        Rectangle { color: "black"; x: 0; y: view.marked.y + view.marked.height; width: parent.width; height: parent.height - y }
        Rectangle { color: "black"; x: 0; y: view.marked.y; width: view.marked.x; height: view.marked.height }
        Rectangle { color: "black"; x: view.marked.x + view.marked.width; y: view.marked.y; width: parent.width - x; height: view.marked.height }
    }

    // ---------- marking ----------

    // Every gesture is a rectangle dragged over the frame. A right click
    // or Escape (see keys) gives the screen back. Once what a rectangle held
    // has been read, a drag inside it selects words instead, the way it would
    // in a document - a double click a word, a triple click its line, and a
    // click on its own nothing - and a drag outside it starts another.
    MouseArea {
        id: pointer
        anchors.fill: parent
        // not merely disabled while idle: a disabled MouseArea still sets
        // its cursor, and the crosshair would flash up over whatever this
        // view is drawn on as a gesture ends
        visible: view.active
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: view.selectable && view.inMark(pointer.mouseX, pointer.mouseY) ? Qt.IBeamCursor : Qt.CrossCursor

        // selecting words: the word the press came down on, and whether
        // the pointer has gone anywhere since
        property bool picking: false
        property int anchor: -1
        property point pressedAt: Qt.point(0, 0)
        property bool moved: false
        // clicks in a row, close together in time and place
        property int clicks: 0
        property double lastClick: 0
        property point lastClickAt: Qt.point(0, 0)

        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                ScreenTools.close();
                return;
            }
            if (!view.markable)
                return;
            if (view.selectable && view.inMark(mouse.x, mouse.y)) {
                pointer.picking = true;
                pointer.moved = false;
                pointer.pressedAt = Qt.point(mouse.x, mouse.y);
                pointer.anchor = view.wordAt(mouse.x, mouse.y);
                return;
            }
            // a press inside a rectangle with nothing to select in it is not
            // the start of another, which would throw this one away for a
            // stray click
            if (ScreenTools.phase === "result" && view.inMark(mouse.x, mouse.y))
                return;
            // a second rectangle starts from a clean frame: the first one's
            // bar, selection and word on what it held go the moment the
            // pointer comes down
            if (ScreenTools.reading && (ScreenTools.phase !== "select" || ScreenTools.selection.width > 0 || ScreenTools.notice !== ""))
                ScreenTools.reselect();
            view.from = Qt.point(mouse.x, mouse.y);
            view.to = Qt.point(mouse.x, mouse.y);
            view.drawing = true;
        }
        onPositionChanged: mouse => {
            if (pointer.picking) {
                if (!pointer.moved && Math.hypot(mouse.x - pointer.pressedAt.x, mouse.y - pointer.pressedAt.y) < 4)
                    return;
                pointer.moved = true;
                ScreenTools.pick(pointer.anchor, view.wordAt(mouse.x, mouse.y));
                return;
            }
            if (view.drawing)
                view.to = Qt.point(Math.max(0, Math.min(view.width, mouse.x)), Math.max(0, Math.min(view.height, mouse.y)));
        }
        onReleased: mouse => {
            if (pointer.picking && mouse.button === Qt.LeftButton) {
                pointer.picking = false;
                if (pointer.moved) {
                    pointer.clicks = 0;
                    return;
                }
                const now = Date.now();
                const near = Math.hypot(mouse.x - pointer.lastClickAt.x, mouse.y - pointer.lastClickAt.y) < 6;
                pointer.clicks = now - pointer.lastClick < 400 && near ? pointer.clicks + 1 : 1;
                pointer.lastClick = now;
                pointer.lastClickAt = Qt.point(mouse.x, mouse.y);
                if (pointer.clicks === 2) {
                    ScreenTools.pick(pointer.anchor, pointer.anchor);
                } else if (pointer.clicks >= 3) {
                    const line = view.lineAt(mouse.x, mouse.y);
                    if (line)
                        ScreenTools.pick(line.first, line.last);
                } else {
                    ScreenTools.pick(-1, -1);
                }
                return;
            }
            if (!view.drawing || mouse.button !== Qt.LeftButton)
                return;
            view.drawing = false;
            const x = Math.min(view.from.x, view.to.x);
            const y = Math.min(view.from.y, view.to.y);
            const w = Math.abs(view.to.x - view.from.x);
            const h = Math.abs(view.to.y - view.from.y);
            if (ScreenTools.mode === "region") {
                // a click with no drag in it asks for the whole output
                if (w < 12 || h < 12)
                    ScreenTools.chooseRegion(0, 0, 0, 0);
                else
                    ScreenTools.chooseRegion(x, y, w, h);
                return;
            }
            // too small to have been meant - a stray click
            if (w < 12 || h < 12)
                return;
            ScreenTools.select(x * view.ratio, y * view.ratio, w * view.ratio, h * view.ratio);
        }
    }

    // What was marked, framed - while it is being dragged, and for the
    // recorder. A rectangle being read, or read, has only its corners
    // marked instead, so nothing is drawn across the words at its edges.
    readonly property bool cornered: ScreenTools.reading && !view.drawing
    Rectangle {
        id: frame
        x: view.marked.x
        y: view.marked.y
        width: view.marked.width
        height: view.marked.height
        visible: view.hasMark && !view.cornered
        color: "transparent"
        radius: 0
        border.width: 2
        border.color: Theme.tools.accent
    }
    Repeater {
        model: view.hasMark && view.cornered ? 4 : 0
        Item {
            id: corner
            required property int index
            readonly property bool atRight: index % 2 === 1
            readonly property bool low: index > 1
            readonly property real arm: Math.min(18, view.marked.width / 2, view.marked.height / 2)
            x: corner.atRight ? view.marked.x + view.marked.width - corner.arm : view.marked.x
            y: corner.low ? view.marked.y + view.marked.height - corner.arm : view.marked.y
            width: corner.arm
            height: corner.arm
            Rectangle { x: 0; y: corner.low ? corner.arm - 3 : 0; width: corner.arm; height: 3; radius: 1.5; color: Theme.tools.accent }
            Rectangle { x: corner.atRight ? corner.arm - 3 : 0; y: 0; width: 3; height: corner.arm; radius: 1.5; color: Theme.tools.accent }
        }
    }

    // Every line read, faintly lit: this is text, and it can be picked up.
    Repeater {
        model: view.selectable ? view.lines : []
        Rectangle {
            required property var modelData
            x: modelData.x0 - 3
            y: modelData.y0 - 1
            width: modelData.x1 - modelData.x0 + 6
            height: modelData.y1 - modelData.y0 + 2
            radius: Theme.radius(4)
            color: Qt.alpha(Theme.tools.accent, 0.14)
        }
    }
    // The words selected: along each line they cross, one band from the
    // first to the last, the spaces between them included.
    Repeater {
        model: {
            if (!view.selectable || !ScreenTools.picked)
                return [];
            const out = [];
            for (const line of view.lines) {
                const first = Math.max(line.first, ScreenTools.pickFirst);
                const last = Math.min(line.last, ScreenTools.pickLast);
                if (first > last)
                    continue;
                const a = ScreenTools.words[first];
                const b = ScreenTools.words[last];
                out.push({ x0: a.x / view.ratio, x1: (b.x + b.w) / view.ratio, y0: line.y0, y1: line.y1 });
            }
            return out;
        }
        Rectangle {
            required property var modelData
            x: modelData.x0 - 3
            y: modelData.y0 - 1
            width: modelData.x1 - modelData.x0 + 6
            height: modelData.y1 - modelData.y0 + 2
            radius: Theme.radius(4)
            color: Qt.alpha(Theme.tools.accent, 0.45)
        }
    }

    // a rectangle says how big it is while it is being dragged
    Rectangle {
        visible: view.drawing && view.hasMark
        x: Math.max(8, Math.min(view.width - width - 8, view.marked.x + view.marked.width - width))
        y: view.marked.y + view.marked.height + 8 + height > view.height ? view.marked.y - height - 8 : view.marked.y + view.marked.height + 8
        width: sizeText.implicitWidth + 16
        height: sizeText.implicitHeight + 8
        radius: Theme.radius(8)
        color: Theme.flyoutSurface
        Text {
            id: sizeText
            anchors.centerIn: parent
            text: Math.round(view.marked.width) + " × " + Math.round(view.marked.height)
            color: Theme.tools.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize(12)
        }
    }

    // ---------- reading ----------

    // Something is being read: a small pill that says so, with a spinner,
    // over the middle of the selection.
    Rectangle {
        id: loading
        readonly property bool working: ScreenTools.phase === "working"
        visible: view.up && view.hasMark && ScreenTools.reading && loading.working
        x: Math.max(8, Math.min(view.width - width - 8, view.marked.x + (view.marked.width - width) / 2))
        y: Math.max(8, Math.min(view.height - height - 8, view.marked.y + (view.marked.height - height) / 2))
        width: loadingRow.implicitWidth + 28
        height: 36
        radius: Theme.radius(18)
        color: Theme.tools.ink

        Row {
            id: loadingRow
            anchors.centerIn: parent
            spacing: 10
            // a quarter of a ring going round
            Item {
                visible: loading.working
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.alpha(Theme.tools.accent, 0.2)
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.tools.accent
                        strokeWidth: 2
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 8; centerY: 8; radiusX: 7; radiusY: 7; startAngle: -90; sweepAngle: 100 }
                    }
                    RotationAnimator on rotation {
                        running: loading.visible
                        from: 0
                        to: 360
                        duration: 800
                        loops: Animation.Infinite
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Strings.tr("Reading…")
                color: Theme.tools.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize(13)
            }
        }
    }

    // One box per paragraph, over the paragraph it translates, in the
    // page's own colors (ScreenTools samples them from under each box): the aim
    // is that the page reads as having been written in the user's language,
    // not as having had labels stuck on it. The type is the system's sans
    // rather than the shell's own face - that one is monospaced, and a
    // translation set a third wider than the text it replaces does not fit
    // the space that text left.
    // ---------- translate: the page, repainted ----------

    Item {
        anchors.fill: parent
        visible: ScreenTools.translate === "shown" || ScreenTools.translate === "working"
        opacity: view.peek ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
        Repeater {
            model: ScreenTools.blocks
            delegate: Rectangle {
                id: block
                required property real bx
                required property real by
                required property real bw
                required property real bh
                required property real lineHeight
                required property string text
                required property bool same
                required property string paper
                required property string ink

                // a paragraph already in the user's language is left as
                // it was found
                readonly property bool shown: block.text !== "" && !block.same
                // let out past the source text on every side, so no
                // ascender or comma of the original shows around the edge
                readonly property real pad: 5
                x: block.bx / view.ratio - pad
                y: block.by / view.ratio - pad
                width: block.bw / view.ratio + pad * 2
                height: block.bh / view.ratio + pad * 2
                radius: Theme.radius(4)
                color: block.paper
                opacity: block.shown ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: block.pad
                    anchors.rightMargin: block.pad
                    text: block.text
                    color: block.ink
                    font.family: "sans-serif"
                    // Starts at the size of the type it covers and shrinks
                    // until the translation fits the box the source left -
                    // a sentence rarely comes out the length it went in.
                    font.pixelSize: Math.max(9, Math.min(64, Math.round(block.lineHeight / view.ratio * 0.95)))
                    // but not past legible: below that a translation is
                    // cut short rather than set in type nobody can read
                    fontSizeMode: Text.Fit
                    minimumPixelSize: Math.max(10, Math.round(block.lineHeight / view.ratio * 0.7))
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Strings.rtl ? Text.AlignRight : Text.AlignLeft
                }
            }
        }
    }

    // ---------- what to do with what was read ----------

    // A bar on the rectangle's corner: above its top right where there is
    // room, else under its bottom right, else just inside its top. Each
    // action is on a key as well (see keys); the one Enter does is ringed.
    Rectangle {
        id: bar
        readonly property bool shown: view.active && ScreenTools.reading && ScreenTools.phase === "result" && view.hasMark && !view.drawing
        readonly property string translate: ScreenTools.translate
        // what the bar says before its actions: how much is selected, or
        // what the rectangle came back without
        readonly property string says: {
            if (ScreenTools.picked) {
                const count = ScreenTools.pickLast - ScreenTools.pickFirst + 1;
                return count === 1 ? Strings.tr("1 word") : Strings.trf("%1 words", count);
            }
            return ScreenTools.notice;
        }
        height: 36
        width: barRow.implicitWidth + 8
        x: Math.max(8, Math.min(view.width - width - 8, view.marked.x + view.marked.width - width))
        y: {
            const above = view.marked.y - height - 10;
            if (above >= 8)
                return above;
            const below = view.marked.y + view.marked.height + 10;
            if (below + height <= view.height - 8)
                return below;
            return view.marked.y + 10;
        }
        radius: Theme.radius(18)
        color: Theme.tools.ink
        opacity: bar.shown ? 1 : 0
        scale: bar.shown ? 1 : 0.92
        visible: opacity > 0
        transformOrigin: Item.BottomRight
        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        }

        // a press on the bar is for the bar, not the start of a rectangle
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Row {
            id: barRow
            anchors.centerIn: parent
            Item {
                visible: bar.says !== ""
                width: saysText.implicitWidth + 24
                height: 28
                Text {
                    id: saysText
                    anchors.centerIn: parent
                    text: bar.says
                    color: ScreenTools.picked ? Theme.tools.accent : Theme.tools.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize(13)
                }
            }
            BarChip {
                visible: ScreenTools.code !== "" && bar.translate !== "shown"
                label: ScreenTools.isLink ? Strings.tr("open link") : Strings.tr("copy code")
                key: "O"
                primary: ScreenTools.primary === "open"
                onTriggered: ScreenTools.openCode()
            }
            BarChip {
                label: {
                    if (bar.translate === "shown")
                        return Strings.tr("copy translation");
                    if (ScreenTools.picked)
                        return Strings.tr("copy");
                    return ScreenTools.text ? Strings.tr("copy all") : Strings.tr("copy image");
                }
                key: "C"
                primary: ScreenTools.primary === "copy"
                onTriggered: ScreenTools.copy()
            }
            BarChip {
                visible: bar.translate !== "shown"
                label: ScreenTools.picked ? Strings.tr("search") : Strings.tr("image search")
                key: "S"
                primary: ScreenTools.primary === "search"
                onTriggered: ScreenTools.search()
            }
            BarChip {
                visible: ScreenTools.text !== ""
                label: {
                    if (bar.translate === "working")
                        return Strings.tr("translating…");
                    if (bar.translate === "shown")
                        return Strings.tr("original");
                    if (bar.translate === "hidden")
                        return Strings.tr("translation");
                    return Strings.tr("translate");
                }
                key: "T"
                enabled: bar.translate !== "working"
                onTriggered: ScreenTools.toggleTranslation()
            }
        }
    }

    // ---------- keys ----------

    // Focus is put here as the gesture starts (see onActiveChanged).
    Item {
        id: keys
        Keys.onPressed: event => {
            if (!view.active)
                return;
            event.accepted = true;
            // Escape lets go of a selection first, and the screen after
            if (event.key === Qt.Key_Escape) {
                if (ScreenTools.picked)
                    ScreenTools.pick(-1, -1);
                else
                    ScreenTools.close();
                return;
            }
            if (ScreenTools.phase !== "result")
                return;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                ScreenTools.act();
            else if (event.key === Qt.Key_C)
                ScreenTools.copy();
            else if (event.key === Qt.Key_A && ctrl && view.selectable)
                ScreenTools.pick(0, ScreenTools.words.length - 1);
            else if (event.key === Qt.Key_S && !ctrl && ScreenTools.translate !== "shown")
                ScreenTools.search();
            else if (event.key === Qt.Key_T && !ctrl)
                ScreenTools.toggleTranslation();
            else if (event.key === Qt.Key_O && !ctrl)
                ScreenTools.openCode();
            else if (event.key === Qt.Key_Space && ScreenTools.translate === "shown")
                view.peek = true;
        }
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Space && !event.isAutoRepeat)
                view.peek = false;
        }
    }
}
