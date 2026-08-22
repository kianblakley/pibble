import QtQuick
import "root:/services"

// The declarative half of the custom-page contract (the other half, the
// `pibble` object, is PageContext.qml next door): wrap anything tile-shaped
// in one of these and it plays the same entrance the built-in grids do -
// hidden until its first spring, popping in with whatever style, stagger
// and durations Settings > Animations says, and replaying on its own
// whenever the page comes back on screen. Reach it with a qualified import:
//
//   import "root:/ui" as Pibble
//
//   Pibble.PageTile {
//       id: tile
//       pibble: root.pibble
//       slot: index; cols: 7            // stagger position in a group
//       replayOn: [root.viewMonth]      // replay when any of these change
//       width: 56; height: 56
//       color: pibble.tileColor         // it's a Rectangle - style it, or
//       radius: pibble.radius(8)        // leave it transparent and use it
//                                       // as a plain wrapper
//       Text { text: tile.scrambled("hi") }
//   }
//
// The qualified import is deliberate: ui/ holds the shell's own controls
// too, and only PageTile (plus PageContext's members) is promised to keep
// working across pibble updates.
Rectangle {
    id: root

    // The contract object your page's root was handed - wire it in once per
    // tile (`pibble: root.pibble`). Without it the tile just shows its
    // content statically, so a half-wired page still renders.
    property var pibble: null
    // Which position this tile holds, out of how many columns, when it's
    // one of a group - the group's entrances stagger off these, left to
    // right, row by row. Leave them alone for a lone tile.
    property int slot: 0
    property int cols: 1
    // Bind a value - or an array of values - and the tile replays its
    // entrance whenever any of it changes:
    //   replayOn: [root.viewYear, root.viewMonth]
    property var replayOn
    // pibble.scramble() with this tile's slot/cols already filled in, so a
    // label resolves exactly as the tile carrying it lands. Use it in a
    // binding, never a one-time assignment (see scramble's own doc):
    //   Text { text: tile.scrambled(modelData.name) }
    function scrambled(source: string): string {
        return root.pibble ? root.pibble.scramble(source, root.slot, root.cols) : (source ?? "");
    }
    // Replays the entrance by hand, for a trigger replayOn can't express.
    function play(): void {
        if (root.created && root.pibble)
            spring.restart();
    }

    color: "transparent"
    // Hidden from the first frame so nothing flashes before the first
    // spring resets opacity anyway; onCompleted below unhides the
    // no-contract case instead of leaving it invisible forever.
    opacity: 0

    onReplayOnChanged: root.play()
    onPibbleChanged: root.play()
    // the same replay the built-in grids get when their pane comes back
    readonly property bool pageActive: root.pibble ? root.pibble.pageActive : false
    onPageActiveChanged: {
        if (root.pageActive)
            root.play();
    }
    // Gates play() until construction is done: initial bindings (replayOn,
    // pibble) fire their change handlers while the tile is still being
    // built, and restarting the spring there would run it against a
    // half-initialized item - one play from onCompleted covers all of them.
    property bool created: false
    Component.onCompleted: {
        root.created = true;
        if (root.pibble)
            root.play();
        else
            root.opacity = 1;
    }

    // a Translate rather than y itself, so the spring never fights whatever
    // actually positions the tile (anchors, a Grid, explicit bindings, ...)
    transform: Translate { id: offset }

    SequentialAnimation {
        id: spring
        PropertyAction { target: root; property: "opacity"; value: 0 }
        PropertyAction { target: root; property: "scale"; value: Anim.fromScale }
        PropertyAction { target: offset; property: "y"; value: Anim.fromY }
        PauseAnimation { duration: Anim.stagger(root.slot, root.cols, 60) }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: Anim.fadeDuration; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "scale"; to: 1; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
            NumberAnimation { target: offset; property: "y"; to: 0; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
        }
    }
}
