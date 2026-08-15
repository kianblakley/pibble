import QtQuick
import "root:/config"
import "root:/services"

// Small dot row a tile-grid pane shows below its tiles, marking which page
// of *tiles* is showing (not which pibble page/pane) - one muted dot per
// page, with an accent "blob" riding over the current one. Moving pages
// doesn't just recolor a dot: the blob stretches to bridge its old and new
// position (covering every dot it passes, however many pages the jump
// spans) and then contracts back to a plain circle over the new one - a
// lava-lamp-bubble morph rather than a snap or a plain slide.
//
// A page count *change* morphs too: growing a dot springs it in from
// nothing, shrinking one shrinks it back down to nothing, rather than either
// popping into/out of existence. `shownCount` is what the Repeater's model
// actually uses - it tracks `pageCount` immediately on growth (so the new
// delegate exists to spring into), but lags behind on shrink until
// shrinkTimer fires, giving the trailing dot(s) time to actually play their
// shrink before the model drops them for real.
//
// The whole row is invisible whenever there's only one page, or the
// setting's off - callers pass the raw page count/index; the toggle lives
// here rather than in every caller.
Item {
    id: root

    property int pageCount: 0
    property int currentPage: 0

    readonly property int dotSize: 6
    readonly property int gap: 6
    readonly property real pitch: dotSize + gap

    property int shownCount: 0
    onPageCountChanged: {
        if (root.pageCount >= root.shownCount) {
            shrinkTimer.stop();
            root.shownCount = root.pageCount;
        } else {
            shrinkTimer.restart();
        }
    }
    Timer {
        id: shrinkTimer
        // matches the dot delegate's own opacity/scale Behavior duration
        // below, so the model only drops a trailing dot once it has
        // actually finished shrinking out of view
        interval: 200
        onTriggered: root.shownCount = root.pageCount
    }

    // shownCount, not pageCount: mid-shrink the row still has to hold its
    // wider, pre-shrink footprint for exiting dots to shrink within,
    // instead of the anchor point jumping the instant pageCount drops
    width: root.shownCount > 0 ? root.shownCount * root.dotSize + Math.max(0, root.shownCount - 1) * root.gap : 0
    height: root.dotSize
    visible: opacity > 0
    opacity: Settings.pageIndicatorEnabled("dots") && root.pageCount > 1 ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    Repeater {
        model: root.shownCount

        Rectangle {
            id: dot
            required property int index
            // beyond the current logical count: either a genuinely fresh
            // dot from a page-count grow (not yet sprung in) or a trailing
            // one riding shrinkTimer's lag out (already springing out)
            readonly property bool isGhost: dot.index >= root.pageCount
            x: dot.index * root.pitch
            y: 0
            width: root.dotSize
            height: root.dotSize
            radius: Theme.radius(root.dotSize / 2)
            color: Qt.alpha(Theme.accent, 0.28)

            // starts invisible/collapsed regardless of isGhost's initial
            // value - applyState() below is what actually reveals it, and
            // Behaviors never animate a property's very first assignment,
            // so this has to be the true creation-time value
            opacity: 0
            scale: 0
            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            }

            function applyState(): void {
                dot.opacity = dot.isGhost ? 0 : 1;
                dot.scale = dot.isGhost ? 0 : 1;
            }
            Component.onCompleted: dot.applyState()
            onIsGhostChanged: dot.applyState()
        }
    }

    // resting position/size track currentPage declaratively until the first
    // morph, whose explicit x/width animations then own both from then on -
    // see morphTo()
    Rectangle {
        id: blob
        y: 0
        height: root.dotSize
        radius: Theme.radius(height / 2)
        color: Theme.accent
        x: root.currentPage * root.pitch
        width: root.dotSize
    }

    onCurrentPageChanged: root.morphTo(root.currentPage)

    function morphTo(page: int): void {
        const toX = page * root.pitch;
        const fromX = blob.x;
        stretch.targetX = Math.min(fromX, toX);
        stretch.targetW = Math.abs(toX - fromX) + root.dotSize;
        settle.targetX = toX;
        morph.restart();
    }

    SequentialAnimation {
        id: morph
        // phase 1: stretch into a capsule spanning old -> new, covering
        // every dot in between - the blob's leading edge reaches the
        // destination while its tail is still back at the origin
        ParallelAnimation {
            id: stretch
            property real targetX: 0
            property real targetW: root.dotSize
            NumberAnimation { target: blob; property: "x"; to: stretch.targetX; duration: 140; easing.type: Easing.OutQuad }
            NumberAnimation { target: blob; property: "width"; to: stretch.targetW; duration: 140; easing.type: Easing.OutQuad }
        }
        // phase 2: the tail catches up and the capsule contracts back to a
        // plain dot over the destination - the overshoot is what gives the
        // catch-up its little wobble instead of a flat slide
        ParallelAnimation {
            id: settle
            property real targetX: 0
            NumberAnimation { target: blob; property: "x"; to: settle.targetX; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            NumberAnimation { target: blob; property: "width"; to: root.dotSize; duration: 220; easing.type: Easing.OutCubic }
        }
    }
}
