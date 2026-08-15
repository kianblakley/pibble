import QtQuick
import Quickshell.Widgets
import "root:/config"
import "root:/services"
import "root:/ui"

// The clipboard pane: a masonry grid of variable-height tiles, the expanded
// card one of them grows into, and the two empty states (nothing in history
// at all vs. nothing matching the query).
Item {
    id: root

    anchors.fill: parent

    // Called on every launcher open. A pane keeps whatever opacity its last
    // entrance animation ended at, so it has to be put back *before* the pane
    // change that restarts that animation - otherwise the restart is clobbered
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
        // extra top/bottom room for the optional query label and page dots,
        // reserved only when each is on so a disabled one leaves no gap
        readonly property int queryH: Settings.pageIndicatorEnabled("query") ? 32 : 0
        readonly property int dotsH: Settings.pageIndicatorEnabled("dots") ? 20 : 0
        width: Settings.clipsCols * 240 + (Settings.clipsCols - 1) * 16 + 52
        height: Math.max(masonry.height, 120) + 52 + drawer.queryH + drawer.dotsH
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

        PageQueryLabel {
            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            queryText: LauncherState.query
        }

        Row {
            id: masonry
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 26 + drawer.queryH
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

                            // This cell's place in the *text* wave, i.e. its
                            // slot with every image tile ahead of it taken out.
                            // An image tile carries nothing to resolve but its
                            // dimensions, so counting them spends the wave's
                            // first beats on tiles with no text on them: a page
                            // of screenshots reads as a pause before anything
                            // scrambles at all. They keep their place in the
                            // grid - this is only what the scramble is staggered
                            // by, never the tile springs, which are a wave of
                            // the tiles themselves and want every one of them.
                            //
                            // An image tile takes no beat of its own: its
                            // dimensions resolve in step with the last text
                            // tile before it, which is the beat the wave is
                            // actually on as it passes. Counting straight would
                            // instead put it on the *next* one, a beat early,
                            // and a run of them would then arrive together
                            // ahead of the text they're standing among. Images
                            // leading the page have no text tile behind them
                            // and fall on the wave's first beat, alongside the
                            // first that does.
                            readonly property int waveSlot: {
                                const base = LauncherState.clipPage * LauncherState.clipPageSize;
                                let n = 0;
                                for (let i = 0; i < cell.slot; i++) {
                                    const c = LauncherState.clipMatches[base + i];
                                    if (c && !c.image)
                                        n++;
                                }
                                const self = LauncherState.clipMatches[base + cell.slot];
                                return self && self.image ? Math.max(0, n - 1) : n;
                            }

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
                                        // below isn't the one doing it - see
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

                            // What this tile paints when there's no query on.
                            // cliphist's own list preview is a single line cut
                            // at ~100 characters with an ellipsis of its own,
                            // so a tile with room for a dozen lines used to
                            // show that cut line and leave the rest of its box
                            // empty - the tile has to fill before it truncates.
                            // The decoded text (which the scan already carries
                            // for the search) is what it fills with.
                            //
                            // Cut to clipTileChars, which is also what a query's
                            // snippet is cut to, so the two views of a clip are
                            // the same size. Trimmed because `full` is raw
                            // where `preview` arrives trimmed, and a clip
                            // opening on a blank line would otherwise spend the
                            // tile's first line on nothing.
                            readonly property string bodyText: {
                                const c = cell.shownClip;
                                if (!c || c.image)
                                    return "";
                                return (c.full || c.preview).slice(0, LauncherState.clipTileChars).trim();
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
                                // the string that is actually painted, which
                                // under a query is the snippet built around the
                                // match (hiText, see LauncherState's clipMatches)
                                // and not cliphist's one-line preview. Measuring the
                                // preview instead sized every highlighted tile
                                // to the wrong string, leaving it short of its
                                // snippet - the match itself often fell on the
                                // first line past the bottom edge, so all that
                                // showed of the highlight was the top of its box.
                                // Raw, not escaped: escapeHtml turns "\n" into
                                // <br>, which breaks a line exactly as the "\n"
                                // does here, and leaves everything else a
                                // character for a character.
                                text: {
                                    const c = cell.shownClip;
                                    if (!c || c.image)
                                        return "";
                                    return c.hiSpans ? c.hiText : cell.bodyText;
                                }
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                            }
                            // The same measurement of this clip's *resting*
                            // string, i.e. the height this tile has with no
                            // query on. It caps the one above: a query is a
                            // different view of a clip, not a bigger one, so
                            // filtering moves the text inside the tile rather
                            // than growing the tile under it. The snippet is
                            // already cut to about this length, so what this
                            // turns away is the line or two that wrapping can
                            // still add - taken off the tail, where the
                            // match (which the snippet is centred on) isn't.
                            Text {
                                id: measureRest
                                visible: false
                                width: 214
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                text: cell.bodyText
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                            }
                            // The height this image's own aspect asks for, taken
                            // on the clipping box's width (the picture is drawn
                            // into a box inset by 4 on every side, so the
                            // aspect goes on 240-8, not on the tile's full
                            // width) and carried back out to the tile by adding
                            // that inset back on. Taken on 240 the box came out
                            // fractionally too flat for the image, and
                            // PreserveAspectFit answered by pillarboxing it: a
                            // landscape screenshot sat a few pixels short of
                            // both sides.
                            readonly property int imgNatH: {
                                const c = shownClip;
                                if (!c || !c.image)
                                    return 0;
                                const d = (c.dims || "").split("x");
                                const iw = parseInt(d[0]) || 16;
                                const ih = parseInt(d[1]) || 9;
                                return Math.round(232 * ih / iw) + 8;
                            }
                            // The shortest tile the grid draws: a text tile with
                            // one line in it, which is the floor a wide image
                            // shares rather than one of its own. A fixed 70 had
                            // every landscape shot noticeably wider than 16:9
                            // letterboxed inside a box taller than it asked
                            // for, while the tile beside it holding one line of
                            // text was shorter still.
                            readonly property int minTileH: Math.max(44, Math.ceil(cell.lineHpx) + 26)
                            // Whether the clamps below had to hand this image a
                            // box of the wrong shape - a panorama wants less
                            // height than a single line of text, a phone
                            // screenshot far more than 320. That's the one case
                            // the picture can't fill its box and keep its
                            // aspect, and it's what the Image's fillMode turns
                            // on.
                            readonly property bool imgClamped: imgNatH > 0 && (imgNatH < cell.minTileH || imgNatH > 320)
                            readonly property real lineHpx: measureText.lineCount > 0
                                ? measureText.paintedHeight / measureText.lineCount
                                : Theme.fontSize(16)
                            readonly property int tileH: {
                                const c = shownClip;
                                if (!c)
                                    return 0;
                                if (c.image)
                                    return Math.max(cell.minTileH, Math.min(320, cell.imgNatH));
                                // capped on whole lines rather than on raw pixels:
                                // a snippet too long for the tile is cut by the
                                // highlight's clip either way (TextEdit can't
                                // elide), but stopping on a line boundary means
                                // the last line it does show is a whole one
                                // instead of a strip of glyph tops.
                                const lines = Math.max(1, measureText.lineCount);
                                const rest = Math.max(1, measureRest.lineCount);
                                const fits = Math.max(1, Math.floor((240 - 26) / lineHpx));
                                return Math.max(cell.minTileH, Math.ceil(Math.min(lines, rest, fits) * lineHpx) + 26);
                            }
                            // whole lines of the painted string this tile has
                            // room for, i.e. where the label truncates
                            readonly property int shownLines: Math.max(1, Math.floor((tileH - 26) / Math.max(1, lineHpx)))
                            // Roughly how many characters of that string are on
                            // screen, for the scramble to be paced across - see
                            // paceLength in ui/ScrambleText.qml. Now that a tile
                            // fills with the decoded text rather than cliphist's
                            // one-line preview, most of what it holds can be
                            // past the truncation, and a resolve spread over the
                            // whole string hands the visible part back finished
                            // within its own fraction of the span. Estimated off
                            // the line counts, which is what the label's own
                            // truncation goes by. 0 for a string that fits
                            // whole, which paces across all of it.
                            readonly property int visibleChars: {
                                const lines = Math.max(1, measureText.lineCount);
                                if (lines <= shownLines)
                                    return 0;
                                return Math.max(1, Math.round(measureText.text.length * shownLines / lines));
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
                            ScrambleText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: tile.y + cell.tileH + 6
                                opacity: tile.opacity
                                scale: tile.scale
                                // pinned to the resting string's width - see
                                // the app tile's caption
                                width: restWidth
                                content: {
                                    const c = cell.shownClip;
                                    if (!c)
                                        return "";
                                    return c.image ? c.dims : c.bytes + " chars";
                                }
                                // a slot taking a different clip leaves the
                                // tile where it is (see the isNew branch
                                // above), so the text resolving again is the
                                // whole transition
                                replayOnChange: true
                                replayStagger: Anim.stagger(cell.waveSlot, Settings.clipsCols, 60)
                                color: Theme.fg
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
                            }

                            Rectangle {
                                id: tile
                                width: parent.width
                                height: cell.tileH
                                radius: Theme.radius(12)
                                opacity: 0
                                color: Qt.alpha(Theme.accent, cell.isSelected ? 0.22 : 0.11)
                                border.width: 1
                                border.color: cell.isSelected ? Theme.accent : Qt.alpha(Theme.accent, 0.33)

                                Rectangle {
                                    visible: cell.isSelected
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    radius: Theme.radius(17)
                                    color: "transparent"
                                    border.width: 3
                                    border.color: Qt.alpha(Theme.accent, 0.33)
                                }

                                ClippingRectangle {
                                    visible: cell.shownClip !== null && cell.shownClip.image === true
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: Theme.radius(9)
                                    color: "transparent"

                                    Image {
                                        anchors.fill: parent
                                        asynchronous: true
                                        // Crop everywhere the box already has
                                        // the image's own aspect (tileH above
                                        // gives it that), so the picture meets
                                        // all four edges with nothing thrown
                                        // away, the way the wallpaper tiles fill
                                        // their fixed 16:9 boxes.
                                        //
                                        // At the clamps it can't have
                                        // both, and there the aspect wins: the
                                        // shapes that reach a clamp are extreme
                                        // enough that cropping to the box keeps
                                        // barely a tenth of the picture - a
                                        // 5120x183 strip came down to a
                                        // 232-wide window on 13% of its width,
                                        // which reads as a different image
                                        // rather than a tight crop of this one.
                                        // Fitting leaves a band of empty tile
                                        // above and below instead, which is at
                                        // least the clip the user copied.
                                        fillMode: cell.imgClamped ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                                        sourceSize: Qt.size(480, 640)
                                        source: {
                                            const c = cell.shownClip;
                                            return c && c.image && c.thumb ? "file://" + c.thumb : "";
                                        }
                                    }
                                }
                                // plain (non-searching) preview: elide is only reliable on the
                                // lightweight Text item, so this stays a plain Text and only
                                // shows when there's no highlight to render - but it keeps
                                // running the scramble either way, and the highlight below
                                // renders off its `text` (see screenItem)
                                ScrambleText {
                                    id: preview
                                    visible: cell.shownClip !== null && cell.shownClip.image !== true && !cell.shownClip.hiSpans
                                    anchors.fill: parent
                                    anchors.margins: 13
                                    // Always the raw string, and painted as plain text. Under a
                                    // highlight it has to be raw, since the markup below is
                                    // built by slicing it at the match's own offsets and
                                    // escaping would shift them (highlightMarkup escapes each
                                    // slice itself). Without one there is no markup to render
                                    // at all, and escaping for a rich-text pass this label no
                                    // longer needs only hands the scramble entities and <br>
                                    // tags to churn through - which StyledText then reads as
                                    // markup of its own halfway through a run. A body full of
                                    // line breaks (which is what the tile fills with now) made
                                    // that unmissable.
                                    content: {
                                        const c = cell.shownClip;
                                        if (!c)
                                            return "";
                                        return c.hiSpans ? c.hiText : cell.bodyText;
                                    }
                                    // Under a highlight this label is hidden and the TextEdit
                                    // below is what's on screen, so that is what decides when
                                    // the effect may start - a hidden label never arms.
                                    screenItem: cell.shownClip && cell.shownClip.hiSpans ? highlight : null
                                    // see the caption above
                                    replayOnChange: true
                                    replayStagger: Anim.stagger(cell.waveSlot, Settings.clipsCols, 60)
                                    paceLength: cell.visibleChars
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    maximumLineCount: cell.shownLines
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
                                    id: highlight
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
                                        // preview.text, not c.hiText: the same snippet part-way
                                        // through the scramble, so the highlight resolves with
                                        // the rest of the tile instead of sitting there
                                        // finished. Safe to slice at the match's own offsets -
                                        // the noise stands in character for character, so
                                        // every span still covers the run it marked.
                                        return c && c.hiSpans ? Clipboard.highlightMarkup(preview.text, c.hiSpans) : "";
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
                                // cell's slot permanently reserved in the masonry column -
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

        PageDots {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            pageCount: LauncherState.clipPageSize > 0
                ? Math.ceil(LauncherState.clipMatches.length / LauncherState.clipPageSize) : 0
            currentPage: LauncherState.clipPage
        }

        ClipExpandCard {
            id: expandCard

            pane: drawer
        }
    }

    // Clipboard empty states: siblings of the drawer (not nested inside it) so
    // anchors.centerIn: parent centers on the pane instead of the drawer's box,
    // which stays sized to the full grid regardless of clip/match count.
    ScrambleText {
        visible: LauncherState.pane === "clips" && Clipboard.entries.length === 0
        anchors.centerIn: parent
        transform: Translate {
            y: LauncherState.powerPull - LauncherState.rebootPull
        }
        // pinned to the resting string's box, so this centered label doesn't
        // shuffle about on every reroll - see the apps pane's copy of this
        width: restWidth
        height: restHeight
        content: "clipboard history is empty"
        color: Theme.muted
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
    }
    // Fades in only once the last exiting tile has fully sprung out
    // (Anim.tile(240), matching springOut) instead of popping in on
    // top of tiles still animating away. wantShow is a plain
    // reactive binding (always correct for the *current* query) -
    // debouncedShow just delays acting on it by one springOut's
    // worth of time, via a Timer that restarts/cancels on every
    // change instead of an imperative restart()/stop() pair racing
    // against whichever keystroke's onClipMatchesChanged fires last.
    ScrambleText {
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
        width: restWidth
        height: restHeight
        content: "no matches"
        color: Theme.muted
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }

        Timer {
            id: emptyDelay
            interval: Anim.tile(240)
            onTriggered: emptyLabel.debouncedShow = true
        }
    }
}
