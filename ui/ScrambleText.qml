import QtQuick
import "root:/services"

// A Text whose string resolves out of a run of random glyphs every time a
// pane opens, off Anim's shared scramble clock (see the block at the foot of
// Anim.qml for the clock itself).
//
// Callers bind the real string to `content`, not to `text`: `text` is what
// the effect renders, so binding it at the call site and having the effect
// write it would tear that binding down on the first frame of the first run.
// Everything else is a plain Text - font, color, elide, wrapping and anchors
// all behave exactly as they do on one.
//
// Each label starts its own run the moment it is actually on screen, rather
// than all of them starting together when the clock does. That is what keeps
// the effect in step with whatever brought the label in: a tile's caption
// waits out that tile's stagger and entrance spring, and under a "grow"
// launch every label waits for the reveal circle to reach it. A shared start
// with fixed offsets can't do either - the offsets have to guess at the
// entrance, and anything the guess is late for arrives with its text already
// resolved.
Text {
    id: root

    property string content: ""
    // Extra hold once this label is on screen, for a cascade *within* one
    // group that all comes into view at once (the clock's segments). Leave it
    // at 0 for anything that arrives on its own schedule - the arrival is the
    // stagger there, and a delay on top of it double-counts.
    property int scrambleDelay: 0

    // The width to hold, for callers that size themselves off the label
    // (`width: Math.min(restWidth, 76)` and friends): the resting string's,
    // since a noise glyph is not as wide as the character it stands in for and
    // sizing off implicitWidth mid-run leaves the label breathing wider and
    // narrower on every reroll - but never *less* than the widest the noise has
    // actually needed, because a Text laid out into too little width drops the
    // overflow rather than overflowing (which is how the clock came to lose its
    // last digit whenever a wide symbol landed in it).
    //
    // The noise half only ratchets up, and resets between runs, so the label
    // settles into its widest once instead of shuffling on every reroll.
    readonly property real restWidth: Math.max(sizer.advanceWidth, root.noiseWidth)
    property real noiseWidth: 0

    // The height this label has when it isn't scrambling, for callers whose
    // layout is driven by it (the clock's rows, anything centered). The noise
    // routinely pulls in glyphs the shell font doesn't have, and a fallback
    // font's line metrics are not the shell font's - so implicitHeight changes
    // from reroll to reroll and the label grows and shrinks under whatever is
    // positioning it. Pinning `height: restHeight` holds the box still; a
    // taller fallback glyph simply paints past it, which nothing clips.
    //
    // Snapshotted from the item itself rather than measured, so it is exactly
    // the height this label would have had, and it holds still for the length
    // of a run.
    property real restHeight: 0
    onImplicitHeightChanged: root.snapRestHeight()
    Component.onCompleted: root.snapRestHeight()
    function snapRestHeight(): void {
        if (root.startedAt < 0 || !Anim.scrambleActive)
            root.restHeight = root.implicitHeight;
    }

    // Fixed per instance and mixed with Anim.scrambleRun below, so two labels
    // showing the same string don't churn through the same glyphs in
    // lockstep.
    readonly property int scrambleSeed: Math.floor(Math.random() * 0x10000)

    // Opacity with every ancestor's folded in. An entrance spring fades the
    // *tile* in, never the label inside it, so this label's own opacity says
    // nothing about whether it can be seen. Reading each ancestor's opacity
    // here is also what subscribes to it, so this re-runs as any of them
    // animates.
    readonly property real stackedOpacity: {
        let o = 1;
        for (let item = root; item; item = item.parent)
            o *= item.opacity;
        return o;
    }
    // Position is read fresh here but not subscribed to (mapToItem reaches
    // through items in C++, out of sight of QML's binding capture) - the mask
    // radius it's checked against is a real property read, though, and that
    // ticks every frame of a reveal, which is the only time this can change
    // its answer.
    //
    // Measured off the resting metrics rather than the item's own width and
    // height: those come from `text` on a label that isn't given a width, and
    // `text` comes from this - a binding loop, and one that only some of the
    // labels would trip. (restWidth is no good here either: its noise half is
    // fed by `text`, closing the same circle.) The vertical is left at the
    // item's top edge; a label is shallow enough that its top and middle are
    // reached within a frame or two of each other.
    readonly property bool unmasked: {
        const center = root.mapToItem(null, sizer.advanceWidth / 2, 0);
        return Anim.unmasked(center.x, center.y);
    }
    readonly property bool onScreen: root.visible && root.stackedOpacity > 0.05 && root.unmasked

    // Where on the shared clock this label's own run began, or -1 for one that
    // hasn't come on screen yet (and so hasn't started).
    property int startedAt: -1
    onOnScreenChanged: root.armScramble()
    function armScramble(): void {
        if (root.startedAt >= 0 || !Anim.scrambleActive || !root.onScreen)
            return;
        root.startedAt = Anim.scrambleElapsed;
    }
    Connections {
        target: Anim
        // A fresh run: forget the last one's start, and take this one's
        // straight away if this label is already on screen (a pane switch,
        // where nothing has to be revealed first).
        function onScrambleRunChanged(): void {
            root.startedAt = -1;
            root.noiseWidth = 0;
            root.armScramble();
        }
        // back to the resting string, so back to the resting width
        function onScrambleActiveChanged(): void {
            if (!Anim.scrambleActive)
                root.noiseWidth = 0;
        }
    }

    text: Anim.scrambleActive && root.startedAt >= 0
        ? Anim.scrambled(root.content, Anim.scrambleElapsed - root.startedAt - root.scrambleDelay, root.scrambleSeed ^ Anim.scrambleRun)
        : root.content

    TextMetrics {
        id: sizer
        font: root.font
        text: root.content
    }
    // What the noise currently laid out to, feeding the ratchet above. Only
    // ever measures during a run: outside one `text` is `content`, which
    // sizer already has.
    TextMetrics {
        id: noiseSizer
        font: root.font
        text: root.text
        onAdvanceWidthChanged: {
            if (root.startedAt >= 0 && Anim.scrambleActive && advanceWidth > root.noiseWidth)
                root.noiseWidth = advanceWidth;
        }
    }
}
