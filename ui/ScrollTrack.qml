import QtQuick
import "root:/services"

// A scroll indicator for the settings pane's wheel-scrolled areas: a thin
// track with a thumb that says how much is showing and where, and that can be
// dragged. It knows nothing about what it scrolls - the owner feeds it three
// lengths and applies `dragged` to whatever `position` reads from.
// Hand-rolled rather than a ScrollBar: a MouseArea with preventStealing is
// what reliably beats the swipe-to-power catcher's own DragHandler for the
// drag grab.
// Qt's hit-test culling skips a whole subtree when the point is outside an
// ancestor's rect, so this has to sit within its parent's bounds to receive a
// press at all.
Item {
    id: root

    // how much is visible, how much there is, and how far in the view is
    required property real viewSize
    required property real contentSize
    required property real position
    signal dragged(target: real)

    readonly property real range: Math.max(0, root.contentSize - root.viewSize)
    // nothing to indicate when everything already fits: the track collapses
    // and the press area stands down with it
    readonly property bool shown: root.range > 0.5

    width: 18

    Rectangle {
        id: track
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        // grows/shrinks in vertically, from the center out, as the content
        // crosses the size that needs scrolling, rather than popping in/out
        height: root.shown ? parent.height : 0
        Behavior on height {
            NumberAnimation { duration: Anim.menu(180); easing.type: Easing.OutCubic }
        }
        radius: Theme.radius(3)
        color: Qt.alpha(Theme.muted, 0.15)

        Rectangle {
            id: thumb
            width: parent.width
            radius: Theme.radius(3)
            color: Qt.alpha(Theme.accent, dragArea.pressed ? 0.85 : 0.6)
            // floored so it stays grabbable once the content is long enough
            // that the honest proportional size would be a sliver - no
            // ceiling, since capping the top end would misrepresent how much
            // is visible (e.g. 6 of 7 rows shown should read as a thumb
            // spanning ~85% of the track, not a stub). Also capped to the
            // track's own (animating) height, so the floor doesn't leave the
            // thumb poking out past a track that's mid-shrink or fully
            // collapsed
            height: Math.min(track.height, Math.max(12, (root.contentSize > 0 ? Math.min(1, root.viewSize / root.contentSize) : 1) * track.height))
            // progress through the scrollable range, not through the content:
            // with the height floored above, position/contentSize would stop
            // short of the track's bottom edge
            y: (root.range > 0 ? Math.max(0, Math.min(1, root.position / root.range)) : 0) * (track.height - height)
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: root.shown
        preventStealing: true
        property real pressY: 0
        property real pressThumbY: 0
        onPressed: mouse => {
            pressY = mouse.y;
            pressThumbY = thumb.y;
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const usable = Math.max(1, track.height - thumb.height);
            const newY = Math.max(0, Math.min(usable, pressThumbY + (mouse.y - pressY)));
            root.dragged((newY / usable) * root.range);
        }
    }
}
