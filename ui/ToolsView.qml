import QtQuick
import QtQuick.Shapes
import "root:/config"
import "root:/services"

// Where the screen tools' gestures happen (see services/ScreenTools.qml for
// what they are): a frozen frame of the screen with a rectangle dragged over
// it, and whatever came of that - the card of things to do with what was
// read, or the translated paragraphs laid over the ones they replace.
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

    // One of the result card's actions: glyph, word, and the key that does the
    // same thing.
    component Chip: Rectangle {
        id: chip
        property string glyph: ""
        property string label: ""
        property string key: ""
        signal triggered

        implicitWidth: chipRow.implicitWidth + 22
        implicitHeight: 34
        radius: Theme.radius(10)
        color: Qt.alpha(Theme.tools.accent, chipHover.containsMouse ? 0.24 : 0.11)
        border.width: 1
        border.color: Qt.alpha(Theme.tools.accent, chipHover.containsMouse ? 0.6 : 0.33)

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.glyph
                color: Theme.tools.accent
                font.family: Icons.family
                font.pixelSize: Theme.fontSize(17)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: Theme.tools.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize(13)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.key !== ""
                text: chip.key
                color: Theme.tools.muted
                font.family: chip.key === Icons.cornerDownLeft ? Icons.family : Theme.fontFamily
                font.pixelSize: Theme.fontSize(chip.key === Icons.cornerDownLeft ? 14 : 11)
            }
        }
        MouseArea {
            id: chipHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.triggered()
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

    // Focus is taken as the gesture starts rather than declared: whoever
    // hosts this has keys of its own the rest of the time.
    onActiveChanged: {
        view.drawing = false;
        view.peek = false;
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
    // or Escape (see keys) gives the screen back.
    MouseArea {
        id: pointer
        anchors.fill: parent
        // not merely disabled while idle: a disabled MouseArea still sets
        // its cursor, and the crosshair would flash up over whatever this
        // view is drawn on as a gesture ends
        visible: view.active
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor

        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                ScreenTools.close();
                return;
            }
            if (!view.markable)
                return;
            // a second rectangle starts from a clean frame: the first one's
            // card, selection and word on what it held go the moment the
            // pointer comes down
            if (ScreenTools.reading && (ScreenTools.phase !== "select" || ScreenTools.selection.width > 0 || ScreenTools.notice !== ""))
                ScreenTools.reselect();
            view.from = Qt.point(mouse.x, mouse.y);
            view.to = Qt.point(mouse.x, mouse.y);
            view.drawing = true;
        }
        onPositionChanged: mouse => {
            if (view.drawing)
                view.to = Qt.point(Math.max(0, Math.min(view.width, mouse.x)), Math.max(0, Math.min(view.height, mouse.y)));
        }
        onReleased: mouse => {
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

    // What was marked, framed.
    Rectangle {
        id: frame
        x: view.marked.x
        y: view.marked.y
        width: view.marked.width
        height: view.marked.height
        visible: view.hasMark
        color: "transparent"
        radius: 0
        border.width: 2
        border.color: Theme.tools.accent
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

    // ---------- translate: the page, repainted ----------

    // Something is being read, or translated: a small pill that says
    // which, with a spinner. Over the middle of the selection - or, for a
    // translation, just above it, out of the way of the boxes that start
    // landing in it while it is still at it. The same pill, without the
    // spinner, says what a rectangle came back without, and stays until the
    // next one is begun.
    Rectangle {
        id: loading
        readonly property bool working: ScreenTools.phase === "working"
        readonly property bool atMark: view.hasMark && ScreenTools.reading
        readonly property bool beside: ScreenTools.mode === "translate"
        visible: view.up && (loading.working || (ScreenTools.phase === "select" && ScreenTools.notice !== "" && !view.drawing))
        x: loading.atMark ? Math.max(8, Math.min(view.width - width - 8, view.marked.x + (view.marked.width - width) / 2)) : (view.width - width) / 2
        y: {
            if (!loading.atMark)
                return 24;
            if (!loading.beside)
                return Math.max(8, Math.min(view.height - height - 8, view.marked.y + (view.marked.height - height) / 2));
            const above = view.marked.y - height - 10;
            return above >= 8 ? above : Math.min(view.height - height - 8, view.marked.y + view.marked.height + 10);
        }
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
                text: {
                    if (!loading.working)
                        return ScreenTools.notice;
                    if (ScreenTools.mode === "code")
                        return Strings.tr("Looking for a code…");
                    if (ScreenTools.mode === "translate" && ScreenTools.queue.length > 0)
                        return Strings.tr("Translating…");
                    return Strings.tr("Reading…");
                }
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
    Item {
        anchors.fill: parent
        visible: ScreenTools.mode === "translate"
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

    // ---------- search and code: what was read, and what to do with it ----------

    Rectangle {
        id: card
        readonly property bool code: ScreenTools.mode === "code"
        readonly property bool shown: (ScreenTools.mode === "search" || card.code) && ScreenTools.phase === "result"
        readonly property bool hasText: ScreenTools.text !== ""
        readonly property real gap: 14
        width: Math.min(view.width - 32, 520)
        height: cardColumn.implicitHeight + 32
        x: Math.max(16, Math.min(view.width - width - 16, view.marked.x + view.marked.width / 2 - width / 2))
        // under the selection where there is room, over it where there is
        // not, and failing both inside its bottom edge
        y: {
            const below = view.marked.y + view.marked.height + card.gap;
            if (below + card.height <= view.height - 16)
                return below;
            const above = view.marked.y - card.height - card.gap;
            if (above >= 16)
                return above;
            return view.height - card.height - 16;
        }
        radius: Theme.radius(18)
        color: Theme.flyoutSurface
        opacity: card.shown ? 1 : 0
        scale: card.shown ? 1 : 0.92
        visible: opacity > 0
        transformOrigin: Item.Top
        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        }

        // a press on the card is for the card, not the start of a circle
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Column {
            id: cardColumn
            x: 18
            y: 16
            width: parent.width - 36
            spacing: 12

            Text {
                width: parent.width
                text: card.hasText ? ScreenTools.text : ScreenTools.notice
                color: card.hasText ? Theme.tools.fg : Theme.tools.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize(14)
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
            }

            // the translation, once asked for, under a rule
            Rectangle {
                visible: translation.visible
                width: parent.width
                height: 1
                color: Qt.alpha(Theme.tools.accent, 0.2)
            }
            Text {
                id: translation
                visible: card.hasText && (ScreenTools.translating || ScreenTools.translation !== "" || ScreenTools.notice !== "")
                width: parent.width
                text: ScreenTools.translating ? Strings.tr("Translating…") : ScreenTools.translation || ScreenTools.notice
                color: ScreenTools.translation !== "" && !ScreenTools.translating ? Theme.tools.accent : Theme.tools.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize(14)
                wrapMode: Text.Wrap
                maximumLineCount: 8
                elide: Text.ElideRight
            }

            Flow {
                width: parent.width
                spacing: 8
                Chip {
                    visible: ScreenTools.isLink
                    glyph: Icons.openInNew
                    label: Strings.tr("open")
                    key: Icons.cornerDownLeft
                    onTriggered: ScreenTools.openCode()
                }
                Chip {
                    visible: card.hasText && !ScreenTools.isLink
                    glyph: ""
                    label: Strings.tr("search")
                    key: Icons.cornerDownLeft
                    onTriggered: ScreenTools.searchText()
                }
                Chip {
                    visible: card.hasText
                    glyph: Icons.copy
                    label: Strings.tr("copy")
                    key: "C"
                    onTriggered: ScreenTools.copyText()
                }
                Chip {
                    visible: card.hasText && ScreenTools.translation === "" && !card.code
                    glyph: ""
                    label: Strings.tr("translate")
                    key: "T"
                    onTriggered: ScreenTools.translateText()
                }
                Chip {
                    visible: !card.code
                    glyph: ""
                    label: card.hasText ? Strings.tr("image") : Strings.tr("image search")
                    key: card.hasText ? "I" : Icons.cornerDownLeft
                    onTriggered: ScreenTools.searchImage()
                }
                Chip {
                    visible: !card.hasText
                    glyph: Icons.copy
                    label: Strings.tr("copy image")
                    key: "C"
                    onTriggered: ScreenTools.copyImage()
                }
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
            if (event.key === Qt.Key_Escape) {
                ScreenTools.close();
                return;
            }
            if (ScreenTools.phase !== "result")
                return;
            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
            if (ScreenTools.mode === "translate") {
                if (event.key === Qt.Key_Space)
                    view.peek = true;
                else if (event.key === Qt.Key_C)
                    ScreenTools.copyTranslation();
                return;
            }
            if (ScreenTools.mode === "code") {
                if (enter)
                    ScreenTools.openCode();
                else if (event.key === Qt.Key_C)
                    ScreenTools.copyText();
                return;
            }
            if (ScreenTools.mode !== "search")
                return;
            if (enter)
                card.hasText ? ScreenTools.searchText() : ScreenTools.searchImage();
            else if (event.key === Qt.Key_C)
                card.hasText ? ScreenTools.copyText() : ScreenTools.copyImage();
            else if (event.key === Qt.Key_T)
                ScreenTools.translateText();
            else if (event.key === Qt.Key_I)
                ScreenTools.searchImage();
        }
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Space && !event.isAutoRepeat)
                view.peek = false;
        }
    }
}
