import QtQuick
import Quickshell.Widgets
import "root:/config"
import "root:/services"

// The clipboard pane: a masonry grid of variable-height tiles, the expanded
// card one of them grows into, and the two empty states (nothing in history
// at all vs. nothing matching the query).
Item {
    id: root

    anchors.fill: parent

    // Called on every launcher open. A pane keeps whatever opacity its last
    // entrance animation ended at, so it has to be put back *before* the pane
    // change that restarts that animation — otherwise the restart is clobbered
    // right back to 0.004 by a reset running after it. Invisible with a real
    // duration (the animation keeps writing opacity every frame regardless) but
    // it leaves the pane stuck dim when the tile style is "none" and the
    // restart completes synchronously.
    function resetEntrance(): void {
        drawer.opacity = 0.004;
    }

    // While a clip is expanded the wheel scrolls its text rather than the grid
    // underneath. The event is caught by the launcher's full-screen background
    // area (a plain MouseArea is the only thing that reliably receives wheel on
    // a layer-shell surface), which forwards it here.
    function scrollExpanded(delta: real): void {
        expandCard.scrollBy(delta);
    }

    Item {
        id: drawer
        anchors.centerIn: parent
        width: Settings.clipsCols * 240 + (Settings.clipsCols - 1) * 16 + 52
        height: Math.max(masonry.height, 120) + 52
        // a filtered-out tile collapsing to 0 height shrinks
        // masonry, which (via centerIn: parent below) would
        // otherwise snap the whole drawer's top edge down instantly;
        // animate the resize instead so it reads as a settle
        Behavior on height {
            NumberAnimation { duration: Anim.tile(240); easing.type: Easing.OutCubic }
        }
        transform: Translate {
            y: LauncherState.powerPull - LauncherState.rebootPull
        }
        opacity: 0.004
        visible: LauncherState.pane === "clips"
        Connections {
            target: LauncherState
            function onPaneChanged() {
                if (LauncherState.pane === "clips")
                    enterAnim.restart();
            }
        }

        ParallelAnimation {
            id: enterAnim
            NumberAnimation { target: drawer; property: "opacity"; from: 0; to: 1; duration: Anim.tile(200); easing.type: Easing.OutCubic }
            NumberAnimation { target: drawer; property: "scale"; from: 0.9; to: 1; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
            NumberAnimation { target: drawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        }

        Row {
            id: masonry
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 26
            // pinned directly rather than left implicit: even with
            // each column's own width fixed at 240, relying on
            // Row to sum them back up is one more layer that could
            // drift when a column empties out, so state the total
            // outright to match drawer's own (also fixed) width
            width: Settings.clipsCols * 240 + (Settings.clipsCols - 1) * 16
            spacing: 16

            Repeater {
                model: Settings.clipsCols

                Column {
                    id: column
                    required property int index
                    // fixed, not implicit: an empty column (fewer
                    // matches than clipsCols) would otherwise
                    // collapse to 0 width, shrinking masonry and
                    // shifting the other columns sideways to stay
                    // centered in drawer's fixed-width box
                    width: 240
                    spacing: 16
                    // a tile above collapsing to 0 height (see
                    // springOut.onStopped) shifts every cell
                    // below it up within the column; animate that
                    // reflow instead of letting it snap
                    move: Transition {
                        NumberAnimation { property: "y"; duration: Anim.tile(220); easing.type: Easing.OutCubic }
                    }

                    Repeater {
                        model: LauncherState.clipRows

                        Item {
                            id: cell
                            required property int index
                            // round-robin: slot order matches the
                            // row-major order vMove navigates
                            readonly property int slot: index * Settings.clipsCols + column.index
                            readonly property int clipIndex: LauncherState.clipPage * LauncherState.clipPageSize + slot
                            readonly property var clip: LauncherState.clipMatches[clipIndex] ?? null
                            readonly property bool isSelected: clip !== null && LauncherState.clipSelected === clipIndex

                            property var shownClip: null
                            property bool filled: false
                            onClipChanged: {
                                if (clip) {
                                    const wasFilled = filled;
                                    const isNew = !wasFilled || !shownClip || shownClip.id !== clip.id;
                                    shownClip = clip;
                                    filled = true;
                                    if (isNew) {
                                        springIn.stop();
                                        springOut.stop();
                                        if (wasFilled) {
                                            // direct replacement: snap straight to the
                                            // resting state, no animation
                                            tile.opacity = 1;
                                            tile.scale = 1;
                                            tile.y = 0;
                                        } else {
                                            springIn.restart();
                                        }
                                    }
                                } else if (filled) {
                                    filled = false;
                                    springIn.stop();
                                    if (LauncherState.pane === "clips") {
                                        springOut.restart();
                                    } else {
                                        // filtered while the pane is off-screen
                                        // (typing from the clock queries this
                                        // pane before switching to it): drop
                                        // straight to hidden, clearing shownClip
                                        // by hand since springOut's onStopped
                                        // below isn't the one doing it — see
                                        // AppsPage's identical branch
                                        springOut.stop();
                                        tile.opacity = 0;
                                        cell.shownClip = null;
                                    }
                                }
                            }
                            Connections {
                                target: LauncherState
                                function onPaneChanged() {
                                    if (LauncherState.pane === "clips" && cell.filled)
                                        springIn.restart();
                                }
                            }

                            // text tiles grow with content up to a square;
                            // image tiles keep their real aspect ratio
                            // measure the wrapped text for an exact fit:
                            // the tile hugs the content, truncating only
                            // once it would exceed a square
                            Text {
                                id: measureText
                                visible: false
                                width: 214
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                text: {
                                    const c = cell.shownClip;
                                    return c && !c.image ? c.preview : "";
                                }
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                            }
                            readonly property real lineHpx: measureText.lineCount > 0
                                ? measureText.paintedHeight / measureText.lineCount
                                : Theme.fontSize(16)
                            readonly property int tileH: {
                                const c = shownClip;
                                if (!c)
                                    return 0;
                                if (c.image) {
                                    const d = (c.dims || "").split("x");
                                    const iw = parseInt(d[0]) || 16;
                                    const ih = parseInt(d[1]) || 9;
                                    return Math.max(70, Math.min(320, Math.round(240 * ih / iw)));
                                }
                                return Math.max(44, Math.min(240, Math.ceil(measureText.paintedHeight) + 26));
                            }
                            width: 240
                            height: tileH > 0 ? tileH + 24 : 0
                            visible: tileH > 0

                            // expanding one clip animates the rest away
                            opacity: LauncherState.expandedClip !== null ? 0 : 1
                            scale: LauncherState.expandedClip !== null ? 0.85 : 1
                            Behavior on opacity {
                                NumberAnimation { duration: Anim.tile(180); easing.type: Easing.OutCubic }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: Anim.tile(220); easing.type: Easing.OutCubic }
                            }
                            // report the tile position so the expand
                            // animation can grow out of it
                            Connections {
                                target: LauncherState
                                function onExpandedClipChanged() {
                                    if (LauncherState.expandedClip && cell.isSelected) {
                                        const p = cell.mapToItem(drawer, cell.width / 2, cell.height / 2);
                                        LauncherState.expandOrigin = Qt.point(p.x, p.y);
                                    }
                                }
                            }

                            // caption line, like app/wallpaper labels
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: tile.y + cell.tileH + 6
                                opacity: tile.opacity
                                scale: tile.scale
                                text: {
                                    const c = cell.shownClip;
                                    if (!c)
                                        return "";
                                    return c.image ? c.dims : c.bytes + " chars";
                                }
                                color: Theme.fg
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
                            }

                            Rectangle {
                                id: tile
                                width: parent.width
                                height: cell.tileH
                                radius: 12
                                opacity: 0
                                color: Qt.alpha(Theme.accent, cell.isSelected ? 0.22 : 0.11)
                                border.width: 1
                                border.color: cell.isSelected ? Theme.accent : Qt.alpha(Theme.accent, 0.33)

                                Rectangle {
                                    visible: cell.isSelected
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    radius: 17
                                    color: "transparent"
                                    border.width: 3
                                    border.color: Qt.alpha(Theme.accent, 0.33)
                                }

                                ClippingRectangle {
                                    visible: cell.shownClip !== null && cell.shownClip.image === true
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: 9
                                    color: "transparent"

                                    Image {
                                        anchors.fill: parent
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                        sourceSize: Qt.size(480, 640)
                                        source: {
                                            const c = cell.shownClip;
                                            return c && c.image && c.thumb ? "file://" + c.thumb : "";
                                        }
                                    }
                                }
                                // plain (non-searching) preview: elide is only reliable on the
                                // lightweight Text item, so this stays a plain Text and only
                                // shows when there's no highlight to render
                                Text {
                                    visible: cell.shownClip !== null && cell.shownClip.image !== true && !cell.shownClip.hiSpans
                                    anchors.fill: parent
                                    anchors.margins: 13
                                    text: cell.shownClip ? Format.escapeHtml(cell.shownClip.preview) : ""
                                    textFormat: Text.StyledText
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    maximumLineCount: Math.max(1, Math.floor((cell.tileH - 26) / Math.max(1, cell.lineHpx)))
                                    color: Theme.fg
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                                }
                                // highlighted snippet: QML's plain Text only paints rich-text
                                // foreground formatting (color/bold/etc), not span background
                                // colors, so the highlight box needs TextEdit's fuller rich-text
                                // support instead - readOnly/non-interactive/disabled so it's
                                // purely a display element and taps still reach the TapHandler/
                                // DragHandler below. No elide here (TextEdit doesn't support it),
                                // but clip:true plus the fixed tileH still guarantees the tile
                                // itself never grows - overflow is just clipped, not "…"-truncated
                                TextEdit {
                                    visible: cell.shownClip !== null && cell.shownClip.image !== true && !!cell.shownClip.hiSpans
                                    anchors.fill: parent
                                    anchors.margins: 13
                                    clip: true
                                    enabled: false
                                    readOnly: true
                                    selectByMouse: false
                                    persistentSelection: false
                                    text: {
                                        const c = cell.shownClip;
                                        return c && c.hiSpans ? Clipboard.highlightMarkup(c.hiText, c.hiSpans) : "";
                                    }
                                    textFormat: TextEdit.RichText
                                    wrapMode: TextEdit.Wrap
                                    color: Theme.fg
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                                }

                                // TapHandler + DragHandler split, see the
                                // matching app-tile handlers above
                                TapHandler {
                                    enabled: cell.filled && LauncherState.expandedClip === null
                                    onTapped: {
                                        if (Settings.singleClickActivate || cell.isSelected) {
                                            LauncherState.clipSelected = cell.clipIndex;
                                            LauncherState.clipExpandRequested(cell.clip);
                                        } else {
                                            LauncherState.clipSelected = cell.clipIndex;
                                        }
                                    }
                                }
                                DragHandler {
                                    target: null
                                    enabled: cell.filled && LauncherState.expandedClip === null && Settings.gesturesEnabled() && !LauncherState.promptOpen
                                    property real grabX: 0
                                    property real grabY: 0
                                    onActiveChanged: {
                                        if (active) {
                                            grabX = centroid.scenePosition.x;
                                            grabY = centroid.scenePosition.y;
                                        } else {
                                            LauncherState.gestureRelease(centroid.scenePosition.x - grabX, centroid.scenePosition.y - grabY);
                                        }
                                    }
                                }
                            }

                            SequentialAnimation {
                                id: springIn
                                PropertyAction { target: tile; property: "opacity"; value: 0 }
                                PropertyAction { target: tile; property: "scale"; value: Anim.fromScale }
                                PropertyAction { target: tile; property: "y"; value: Anim.fromY }
                                PauseAnimation { duration: Anim.stagger(cell.slot, Settings.clipsCols, 60) }
                                ParallelAnimation {
                                    NumberAnimation { target: tile; property: "opacity"; to: 1; duration: Anim.fadeDuration; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: tile; property: "scale"; to: 1; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 1.6 }
                                    NumberAnimation { target: tile; property: "y"; to: 0; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 1.6 }
                                }
                            }
                            SequentialAnimation {
                                id: springOut
                                ParallelAnimation {
                                    NumberAnimation { target: tile; property: "scale"; to: Anim.outBounce ? 1.08 : 1; duration: Anim.outBounce ? Anim.tile(80) : 0; easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: tile; property: "scale"; to: Anim.fromScale; duration: Anim.tile(Anim.outDuration); easing.type: Anim.outEasing }
                                    NumberAnimation { target: tile; property: "opacity"; to: 0; duration: Anim.tile(Anim.outDuration); easing.type: Anim.outEasing }
                                }
                                // clear shownClip once the tile is actually gone, not just
                                // invisible: tileH (and so this cell's visible/height) is
                                // derived from shownClip, so leaving it set would keep this
                                // cell's slot permanently reserved in the masonry column —
                                // stale layout space a later "no matches" state reads as
                                // tiles still being there. Guarded by filled: a re-match
                                // arriving mid-exit already called .stop() on us via the
                                // isNew branch above and has its own shownClip in place, so
                                // stopping here from that must not clobber it.
                                onStopped: if (!cell.filled) cell.shownClip = null;
                            }
                        }
                    }
                }
            }
        }

        ClipExpandCard {
            id: expandCard

            pane: drawer
        }
    }

    // Clipboard empty states: siblings of the drawer (not nested inside it) so
    // anchors.centerIn: parent centers on the pane instead of the drawer's box,
    // which stays sized to the full grid regardless of clip/match count.
    Text {
        visible: LauncherState.pane === "clips" && Clipboard.entries.length === 0
        anchors.centerIn: parent
        transform: Translate {
            y: LauncherState.powerPull - LauncherState.rebootPull
        }
        text: "clipboard history is empty"
        color: Theme.muted
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
    }
    // Fades in only once the last exiting tile has fully sprung out
    // (Anim.tile(240), matching springOut) instead of popping in on
    // top of tiles still animating away. wantShow is a plain
    // reactive binding (always correct for the *current* query) —
    // debouncedShow just delays acting on it by one springOut's
    // worth of time, via a Timer that restarts/cancels on every
    // change instead of an imperative restart()/stop() pair racing
    // against whichever keystroke's onClipMatchesChanged fires last.
    Text {
        id: emptyLabel
        readonly property bool wantShow: Clipboard.entries.length > 0 && LauncherState.clipMatches.length === 0
        property bool debouncedShow: false
        onWantShowChanged: {
            if (wantShow)
                emptyDelay.restart();
            else {
                emptyDelay.stop();
                debouncedShow = false;
            }
        }
        visible: LauncherState.pane === "clips" && opacity > 0
        anchors.centerIn: parent
        transform: Translate {
            y: LauncherState.powerPull - LauncherState.rebootPull
        }
        opacity: debouncedShow ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Anim.tile(220); easing.type: Easing.OutCubic }
        }
        text: "no matches"
        color: Theme.muted
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }

        Timer {
            id: emptyDelay
            interval: Anim.tile(240)
            onTriggered: emptyLabel.debouncedShow = true
        }
    }
}
