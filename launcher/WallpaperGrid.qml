import QtQuick
import QtMultimedia
import Quickshell.Widgets
import "root:/config"
import "root:/services"

// Wallpaper selector, "grid" style: a paged grid of thumbnails. Only the
// selected tile plays a .gif/.mp4; every other one stays a still frame, so
// scrolling the grid never decodes a movie per cell.
Item {
    id: root

    // Called on every launcher open. A pane keeps whatever opacity its last
    // entrance animation ended at, so it has to be put back *before* the pane
    // change that restarts that animation — otherwise the restart is clobbered
    // right back to 0.004 by a reset running after it. Invisible with a real
    // duration (the animation keeps writing opacity every frame regardless) but
    // it leaves the pane stuck dim when the tile style is "none" and the
    // restart completes synchronously.
    function resetEntrance(): void {
        root.opacity = 0.004;
    }
    anchors.centerIn: parent
    width: Settings.wallsCols * 240 + (Settings.wallsCols - 1) * 24 + 52
    height: grid.height + 52
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
            if (LauncherState.pane === "walls" && Settings.wallpaperStyle === "grid")
                enterAnim.restart();
        }
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Anim.tile(200); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; from: 0.9; to: 1; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        NumberAnimation { target: root; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
    }

    Grid {
        id: grid
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 26
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
                            // arrives — see AppsPage's identical branch
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

                        // Only the selected tile plays its .gif/.mp4
                        // (from the source file, not the static
                        // thumbnail); every other tile stays a still
                        // frame so scrolling the grid doesn't decode
                        // a movie per cell.
                        //
                        // gated on this grid being the style in use,
                        // and on the launcher being up: the grid's
                        // `visible: false` in carousel mode hides
                        // these tiles but keeps every binding under
                        // them live, so without the check the hidden
                        // grid was still building a MediaPlayer for
                        // the selected video (~80ms) and tearing it
                        // down again (~65ms) on each carousel step
                        // past one — a stall landing mid-slide, on a
                        // player nobody could see.
                        readonly property bool tileLive: Settings.wallpaperStyle === "grid" && LauncherState.shown
                        readonly property bool gifAnimating: cell.isSelected && tileLive && !!cell.shownWall?.gif
                        readonly property bool videoAnimating: cell.isSelected && tileLive && !!cell.shownWall?.video

                        Image {
                            // stays visible underneath even while
                            // animating/videoAnimating — the layers
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
                        // MediaPlayer's own backend init (opening/
                        // probing the file) has a real cost —
                        // instantiated only via this Loader, gated
                        // the same way AnimatedImage is above, so at
                        // most one exists across the whole grid at a
                        // time instead of every tile carrying its own
                        // idle MediaPlayer permanently.
                        Loader {
                            anchors.fill: parent
                            active: thumb.videoAnimating
                            asynchronous: true
                            sourceComponent: Component {
                                VideoOutput {
                                    id: videoSurface
                                    anchors.fill: parent
                                    fillMode: VideoOutput.PreserveAspectCrop
                                    MediaPlayer {
                                        source: cell.shownWall ? "file://" + cell.shownWall.path : ""
                                        loops: MediaPlayer.Infinite
                                        autoPlay: true
                                        videoOutput: videoSurface
                                        audioOutput: AudioOutput { muted: true }
                                        onErrorOccurred: (error, errorString) => Notifier.mediaBackendFailure(errorString)
                                    }
                                }
                            }
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
                    // the image eats the bottom (and right) stroke —
                    // same image-over-border effect as the carousel's
                    // the carousel cell's thumbnail stroke below.
                    Rectangle {
                        anchors.fill: thumb
                        radius: 14
                        color: "transparent"
                        border.width: 1
                        border.color: cell.isSelected ? Theme.accent : Qt.alpha(Theme.accent, 0.33)
                    }
                    Text {
                        anchors.top: thumb.bottom
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, 220)
                        height: 16
                        text: cell.shownWall ? LauncherState.wallpaperName(cell.shownWall) : ""
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
}
