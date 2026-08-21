import QtQuick
import "root:/services"
import "root:/ui"

// The wallpapers pane. Which of the two selectors shows is
// Settings.wallpaperStyle; the empty state is shared, since only one of
// them is ever visible.
Item {
    id: root

    // LauncherWindow needs the carousel's bounds to decide whether a
    // background drag should scroll the strip or cycle panes.
    readonly property Item carousel: carouselView

    anchors.fill: parent

    // Called on every launcher open. A pane keeps whatever opacity its last
    // entrance animation ended at, so it has to be put back *before* the pane
    // change that restarts that animation - otherwise the restart is clobbered
    // right back to 0.004 by a reset running after it. Invisible with a real
    // duration (the animation keeps writing opacity every frame regardless) but
    // it leaves the pane stuck dim when the tile style is "none" and the
    // restart completes synchronously.
    function resetEntrance(): void {
        grid.resetEntrance();
        carouselView.resetEntrance();
    }

    WallpaperGrid {
        id: grid
    }

    WallpaperCarousel {
        id: carouselView
    }

    // Wallpaper empty state: shared between the tiles grid and the
    // windows carousel, since only one of them is ever visible. Fades
    // in only once the last exiting tile has fully sprung out
    // (Anim.tile(400), matching wallSpringOut/wcSpringOut) instead of
    // popping in on top of tiles still animating away.
    ScrambleText {
        id: emptyLabel
        visible: LauncherState.pane === "walls" && opacity > 0
        anchors.centerIn: parent
        // Its own instance of the shared power/reboot rubber band: one Translate
    // per pane, all bound to the same pull, so no pane has to reach across the
    // tree for a sibling's transform.
    transform: Translate {
        y: LauncherState.powerPull - LauncherState.rebootPull
    }
        opacity: 0
        content: Strings.tr(Wallpapers.list.length === 0 ? "no wallpapers found" : "no matches")
        // pinned to the resting string's box, so this centered label doesn't
        // shuffle about on every reroll - see the apps pane's copy of this
        width: restWidth
        height: restHeight
        color: Theme.muted
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }

        Connections {
            target: LauncherState
            function onWallpaperMatchesChanged() {
                if (LauncherState.wallpaperMatches.length === 0)
                    emptyFade.restart();
                else {
                    emptyFade.stop();
                    emptyLabel.opacity = 0;
                }
            }
            // windows carousel: LauncherState.wallpaperMatches never empties (it always
            // holds the full, unfiltered list - see LauncherState.wallpaperMatches
            // above), so its "nothing matched" state is signaled
            // separately by LauncherState.carouselEmpty instead.
            function onCarouselEmptyChanged() {
                if (LauncherState.carouselEmpty)
                    emptyFade.restart();
                else {
                    emptyFade.stop();
                    emptyLabel.opacity = 0;
                }
            }
        }
        SequentialAnimation {
            id: emptyFade
            PauseAnimation { duration: Anim.tile(400) }
            NumberAnimation { target: emptyLabel; property: "opacity"; to: 1; duration: Anim.tile(220); easing.type: Easing.OutCubic }
        }
    }
}
