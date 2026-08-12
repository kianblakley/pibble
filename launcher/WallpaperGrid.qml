import QtQuick
import Quickshell.Widgets
import "root:/config"
import "root:/services"
import "root:/ui"

// Wallpaper selector, "grid" style: a paged grid of thumbnails. Only the
// selected tile animates - its .gif from the source file, its .mp4 through the
// one shared video surface below the Grid - so scrolling the grid never decodes
// a movie per cell.
Item {
    id: root

    // Called on every launcher open. A pane keeps whatever opacity its last
    // entrance animation ended at, so it has to be put back *before* the pane
    // change that restarts that animation - otherwise the restart is clobbered
    // right back to 0.004 by a reset running after it. Invisible with a real
    // duration (the animation keeps writing opacity every frame regardless) but
    // it leaves the pane stuck dim when the tile style is "none" and the
    // restart completes synchronously.
    function resetEntrance(): void {
        root.opacity = 0.004;
    }
    anchors.centerIn: parent
    // extra top/bottom room for the optional query label and page dots,
    // reserved only when each is on so a disabled one leaves no gap
    readonly property int queryH: Settings.pageIndicatorEnabled("query") ? 32 : 0
    readonly property int dotsH: Settings.pageIndicatorEnabled("dots") ? 20 : 0
    width: Settings.wallsCols * 240 + (Settings.wallsCols - 1) * 24 + 52
    height: grid.height + 52 + root.queryH + root.dotsH
    // Its own instance of the shared power/reboot rubber band: one Translate
    // per pane, all bound to the same pull, so no pane has to reach across the
    // tree for a sibling's transform.
    transform: Translate {
        y: LauncherState.powerPull - LauncherState.rebootPull
    }
    opacity: 0.004
    // during warm-up, show the pane only after all thumbnail
    // textures are uploaded, so its first frame reuses them
    visible: Settings.wallpaperStyle === "grid"
        && (LauncherState.pane === "walls" || (LauncherState.warmingWallpapers && LauncherState.wallpaperWarmTick > Wallpapers.list.length))
    Connections {
        target: LauncherState
        function onPaneChanged() {
            if (LauncherState.pane === "walls" && Settings.wallpaperStyle === "grid") {
                enterAnim.restart();
                // the tiles replay their entrance spring below; the
                // shared video surface has none, so keep it out
                // until the one it stands over has landed (see
                // root.settled)
                root.unsettle();
            }
        }
        // a query refills the tiles, which springs any that were
        // empty back in - and moves the selection to the top match,
        // i.e. to a different tile
        function onWallpaperMatchesChanged() {
            root.unsettle();
        }
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Anim.tile(200); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; from: 0.9; to: 1; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        NumberAnimation { target: root; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
    }

    PageQueryLabel {
        anchors.top: parent.top
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        queryText: LauncherState.query
    }

    Grid {
        id: grid
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 26 + root.queryH
        columns: Settings.wallsCols
        columnSpacing: 24
        rowSpacing: 24

        Repeater {
            model: LauncherState.wallpaperPageSize

            Item {
                id: cell
                required property int index
                readonly property int wallIndex: LauncherState.wallpaperPage * LauncherState.wallpaperPageSize + index
                readonly property var wall: LauncherState.wallpaperMatches[wallIndex] ?? null
                readonly property bool isSelected: wall !== null && LauncherState.wallpaperSelected === wallIndex
                width: 240
                height: 159

                visible: !LauncherState.warmingWallpapers || LauncherState.wallpaperWarmTick > Wallpapers.list.length + index + 1

                property var shownWall: null
                property bool filled: false
                onWallChanged: {
                    if (wall) {
                        const wasFilled = filled;
                        const isNew = !wasFilled || !shownWall || shownWall.path !== wall.path;
                        shownWall = wall;
                        filled = true;
                        if (isNew) {
                            springIn.stop();
                            springOut.stop();
                            if (wasFilled) {
                                // direct replacement: snap straight to the
                                // resting state, no animation
                                wrap.opacity = 1;
                                wrap.scale = 1;
                                wrap.y = 0;
                            } else {
                                springIn.restart();
                            }
                        }
                    } else if (filled) {
                        filled = false;
                        springIn.stop();
                        if (LauncherState.pane === "walls") {
                            springOut.restart();
                        } else {
                            // filtered while the pane is off-screen (typing from
                            // the clock queries this pane before switching to
                            // it): drop straight to hidden rather than play an
                            // exit that would only become visible once the pane
                            // arrives - see AppsPage's identical branch
                            springOut.stop();
                            wrap.opacity = 0;
                        }
                    }
                }
                // replay the spring when the selector opens: the
                // cells were already filled while it was hidden
                Connections {
                    target: LauncherState
                    function onPaneChanged() {
                        if (LauncherState.pane === "walls" && cell.filled)
                            springIn.restart();
                    }
                }

                Item {
                    id: wrap
                    width: 240
                    height: 159
                    opacity: 0

                    Rectangle {
                        visible: cell.isSelected
                        anchors.fill: thumb
                        anchors.margins: -5
                        radius: 19
                        color: "transparent"
                        border.width: 3
                        border.color: Qt.alpha(Theme.accent, 0.33)
                    }
                    ClippingRectangle {
                        id: thumb
                        width: 240
                        height: 135
                        radius: 14
                        color: Qt.alpha(Theme.accent, cell.isSelected ? 0.22 : 0.11)

                        // Only the selected tile plays its .gif (from
                        // the source file, not the static thumbnail);
                        // every other tile stays a still frame so
                        // scrolling the grid doesn't decode a movie
                        // per cell. Video is not played per cell at
                        // all - see the single shared surface below
                        // the Grid.
                        //
                        // gated on this grid being the style in use,
                        // and on the launcher being up: the grid's
                        // `visible: false` in carousel mode hides
                        // these tiles but keeps every binding under
                        // them live, so without the check a hidden
                        // grid would still be decoding frames nobody
                        // can see on every carousel step.
                        readonly property bool tileLive: Settings.wallpaperLive && Settings.wallpaperStyle === "grid" && LauncherState.shown
                        readonly property bool gifAnimating: cell.isSelected && tileLive && !!cell.shownWall?.gif

                        Image {
                            // stays visible underneath even while
                            // animating/videoAnimating - the layers
                            // below paint on top once they actually
                            // have a frame ready, so there's no gap
                            // where neither is showing anything (a
                            // decoded gif is close to instant, but
                            // MediaPlayer opening/probing a video file
                            // has real latency before its first frame)
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(480, 270)
                            source: cell.shownWall ? "file://" + cell.shownWall.thumb : ""
                        }
                        AnimatedImage {
                            anchors.fill: parent
                            visible: thumb.gifAnimating
                            playing: thumb.gifAnimating
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            source: thumb.gifAnimating ? "file://" + cell.shownWall.path : ""
                        }
                        // TapHandler + DragHandler split, see the
                        // matching app-tile handlers above
                        TapHandler {
                            enabled: cell.filled
                            onTapped: {
                                if (Settings.singleClickActivate || cell.isSelected)
                                    LauncherState.wallpaperRequested(cell.wall);
                                else
                                    LauncherState.wallpaperSelected = cell.wallIndex;
                            }
                        }
                        DragHandler {
                            target: null
                            enabled: cell.filled && Settings.gesturesEnabled() && !LauncherState.promptOpen
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
                    // Stroke above the image, not a border on thumb
                    // (ClippingRectangle): the clip mask and an
                    // underlying border rasterize a pixel apart, so
                    // the image eats the bottom (and right) stroke -
                    // same image-over-border effect as the carousel's
                    // the carousel cell's thumbnail stroke below.
                    Rectangle {
                        anchors.fill: thumb
                        radius: 14
                        color: "transparent"
                        border.width: 1
                        border.color: cell.isSelected ? Theme.accent : Qt.alpha(Theme.accent, 0.33)
                    }
                    ScrambleText {
                        anchors.top: thumb.bottom
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        // restWidth, not implicitWidth - see the app tile's
                        // caption for why
                        width: Math.min(restWidth, 220)
                        height: 16
                        content: cell.shownWall ? LauncherState.wallpaperName(cell.shownWall) : ""
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.fg
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                    }
                }

                SequentialAnimation {
                    id: springIn
                    PropertyAction { target: wrap; property: "opacity"; value: 0 }
                    PropertyAction { target: wrap; property: "scale"; value: Anim.fromScale }
                    PropertyAction { target: wrap; property: "y"; value: Anim.fromY }
                    PauseAnimation { duration: Anim.stagger(cell.index, Settings.wallsCols, 60) }
                    ParallelAnimation {
                        NumberAnimation { target: wrap; property: "opacity"; to: 1; duration: Anim.fadeDuration; easing.type: Easing.OutCubic }
                        NumberAnimation { target: wrap; property: "scale"; to: 1; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
                        NumberAnimation { target: wrap; property: "y"; to: 0; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
                    }
                }

                SequentialAnimation {
                    id: springOut
                    ParallelAnimation {
                        NumberAnimation { target: wrap; property: "scale"; to: Anim.outBounce ? 1.08 : 1; duration: Anim.outBounce ? Anim.tile(80) : 0; easing.type: Easing.OutQuad }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: wrap; property: "scale"; to: Anim.fromScale; duration: Anim.tile(Anim.outDuration); easing.type: Anim.outEasing }
                        NumberAnimation { target: wrap; property: "opacity"; to: 0; duration: Anim.tile(Anim.outDuration); easing.type: Anim.outEasing }
                    }
                }
            }
        }
    }

    PageDots {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        pageCount: LauncherState.wallpaperPageSize > 0
            ? Math.ceil(LauncherState.wallpaperMatches.length / LauncherState.wallpaperPageSize) : 0
        currentPage: LauncherState.wallpaperPage
    }

    // One video surface for the whole grid, over whichever tile holds the
    // selection, rather than one inside each tile. Every video wallpaper's
    // player is already open and paused behind this (see WallpaperVideoPool),
    // so landing on a video tile only moves the surface and starts a player
    // that is already sitting on its first frame - the tile used to build a
    // MediaPlayer as the selection arrived and tear it down again as it left,
    // which measured as a 70-115ms GUI-thread stall on every single move on or
    // off a video, and measures as none at all now.
    //
    // Drawing over the tile rather than inside it does mean it can't ride
    // that tile's entrance spring, which is what settled below is for.
    readonly property int selSlot: LauncherState.wallpaperSelected - LauncherState.wallpaperPage * LauncherState.wallpaperPageSize
    readonly property var selWall: LauncherState.wallpaperMatches[LauncherState.wallpaperSelected] ?? null
    // pane checked as well as the style: the grid is only `visible: false`
    // in carousel mode, so its bindings keep running there (same reason the
    // tiles check tileLive above), and a pane away from the selector would
    // otherwise leave a video decoding frames for a window nobody is looking
    // at.
    readonly property bool videoShowing: root.settled && !LauncherState.warmingWallpapers
        && Settings.wallpaperLive && Settings.wallpaperStyle === "grid" && LauncherState.shown && LauncherState.pane === "walls"
        && !!root.selWall?.video

    // Held false for as long as the tile the surface stands over is still
    // playing an entrance spring, since the surface can't ride one. Starts
    // true so a re-open onto the pane the launcher was already on - which
    // replays no springs, because nothing signals a pane change - doesn't sit
    // waiting for a timer that never ran.
    property bool settled: true
    function unsettle(): void {
        root.settled = false;
        settle.restart();
    }
    Timer {
        id: settle
        // the selected tile's own landing time: its stagger slot plus the
        // spring, not the whole grid's
        interval: Anim.stagger(root.selSlot, Settings.wallsCols, 60) + Anim.duration + 40
        onTriggered: root.settled = true
    }

    Item {
        id: videoOverlay
        // the selected tile's thumbnail box, derived from the slot rather
        // than read off the tile: a Grid positions its children itself, so
        // there is nothing to anchor to from outside it
        x: grid.x + (root.selSlot % Settings.wallsCols) * (240 + grid.columnSpacing)
        y: grid.y + Math.floor(root.selSlot / Settings.wallsCols) * (159 + grid.rowSpacing)
        width: 240
        height: 135
        // no fade either way: what the surface hands over from (and back to)
        // is the tile's still frame, which is this video's frame 0, so the
        // cut has nothing to show
        visible: root.videoShowing

        ClippingRectangle {
            anchors.fill: parent
            radius: 14
            color: "transparent"
            WallpaperVideoPool {
                anchors.fill: parent
                current: root.videoShowing && root.selWall ? root.selWall.path : ""
                live: root.videoShowing
                // Only while the launcher is down, so the file opens land with
                // nothing on screen to stutter rather than inside a
                // navigation - measured, an open landing in a navigation
                // freezes the GUI thread for ~700ms on first sight of a file.
                // The style check keeps the carousel's own pool from opening
                // the same files a second time over. Settings.preload off
                // trades that freeze back for the ~150MiB per video this holds;
                // Settings.wallpaperLive off means no video is ever shown here,
                // so there is nothing to pay for either way.
                warming: Settings.wallpaperLive && Settings.preload && Settings.wallpaperStyle === "grid" && !LauncherState.shown
            }
        }
        // the tile's own 1px stroke is underneath this overlay, so redraw it
        // on top, in the color that tile resolves to while selected. Outside
        // the ClippingRectangle for the same reason the tile's is (see wrap
        // above).
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: "transparent"
            border.width: 1
            border.color: Theme.accent
        }
    }
}
