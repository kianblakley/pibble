import QtQuick
import "root:/services"

// A Text whose string resolves out of a run of random glyphs every time it
// arrives - a pane opening, a tile springing back in behind a widening
// filter - off Anim's shared scramble clock (see the block at the foot of
// Anim.qml for the clock itself). A label whose *string* is what changed while
// it sat there, rather than the label itself arriving, opts in with
// `replayOnChange` below.
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
    // Per-label off switch, for a label sitting under a motion setting of its
    // own. The flyouts are the case: each has its own "none" animation style,
    // and a notification the user has asked to arrive instantly shouldn't
    // spend half a second resolving. Anim.scrambleOn is the global switch and
    // still wins over this one.
    property bool scramble: true
    // Extra hold once this label is on screen, for a cascade *within* one
    // group that all comes into view at once (the clock's segments). Leave it
    // at 0 for anything that arrives on its own schedule - the arrival is the
    // stagger there, and a delay on top of it double-counts.
    property int scrambleDelay: 0

    // Whether this label belongs to the launcher's stage: it arrives when a
    // pane does, so a fresh pane run is its cue to start over, and the launch
    // reveal is what decides when it can be seen. The flyouts are the
    // exception and turn this off - their windows come and go on a schedule of
    // their own, a pane change behind them is none of their business, and the
    // reveal circle is measured in the launcher window's coordinates, which
    // mean nothing inside theirs. Left on, a notification card still sitting
    // there dissolves back into noise every time the user changes page or
    // opens the launcher.
    property bool followsPane: true

    // How many characters of `content` the resolve is paced across, for a
    // label whose visible extent is only the head of its string - see
    // Anim.scrambled(). 0 (the default) paces across all of it.
    //
    // Deliberately the only lever a label has over the effect, and it moves
    // *which* characters the sweep is spread over, never how long the label
    // gets: the duration is one shared figure (Anim.scrambleSpan) that nothing
    // may lengthen for itself, so everything arriving together lands together.
    property int paceLength: 0

    // Whether a change of `content` replays the effect, for a string swapped
    // under a label that never went anywhere: a grid slot taking a different
    // app on a page turn, or as a filter narrows. Off by default, because a
    // label whose string is *live* rather than swapped - the clock's time, the
    // query echo, the carousel caption tracking a drag - changes content as a
    // matter of course, and would spend all of that time resolving.
    property bool replayOnChange: false
    onContentChanged: {
        if (root.replayOnChange)
            root.replay();
    }
    // Stagger for a replay only. A page turn swaps every caption in the grid
    // in one frame, so without this they all resolve in lockstep - where a
    // pane entrance gets its cascade for free from the tiles arriving one by
    // one. Not scrambleDelay, which would apply to that entrance too and
    // double-count it. Bind it to Anim.stagger(), which is 0 outside a page
    // turn: that is what keeps a filter narrowing on every keystroke from
    // re-staggering (see the note on Anim.staggering). stagger() and not
    // staggerOffset(), unlike everything else that reads a stagger out of a
    // binding, because replay() folds this into startedAt once and keeps it -
    // the window closing mid-run can't take it back out again.
    property int replayStagger: 0

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

    // The item standing in for this label on screen, for a label that paints
    // nothing itself and only runs the effect for something else. The
    // clipboard's highlighted preview is the one case: only TextEdit paints a
    // span's background color, so the label there hands its `text` to a
    // TextEdit beside it and hides. Everything below that asks "can this be
    // seen yet" has to ask about that item instead, or a label that is
    // deliberately invisible never arms - the effect would be off exactly
    // where it was asked for. Null for an ordinary label, which is its own.
    property Item screenItem: null
    readonly property Item shownItem: root.screenItem ?? root

    // Opacity with every ancestor's folded in. An entrance spring fades the
    // *tile* in, never the label inside it, so this label's own opacity says
    // nothing about whether it can be seen. Reading each ancestor's opacity
    // here is also what subscribes to it, so this re-runs as any of them
    // animates.
    readonly property real stackedOpacity: {
        let o = 1;
        for (let item = root.shownItem; item; item = item.parent)
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
    //
    // A screenItem is measured off its own width instead: it is a separate
    // item, sized by whatever lays it out rather than by this label's text, so
    // the circle the resting metrics avoid isn't there to begin with.
    readonly property bool unmasked: {
        if (!root.followsPane)
            return true;
        const item = root.shownItem;
        const center = item.mapToItem(null, (item === root ? sizer.advanceWidth : item.width) / 2, 0);
        return Anim.unmasked(center.x, center.y);
    }
    // Whether an ancestor has declared that nothing beneath it may run the
    // effect - for a reason neither the opacity above nor the reveal circle
    // below can see. The settings pane is both cases:
    //
    //  - its filmstrip lays every tab out at once and slides the inactive ones
    //    sideways behind a clip, at full opacity and fully unmasked. Without
    //    this, four tabs' worth of labels resolve together behind the one on
    //    screen, and the tab the user eventually switches to has been sitting
    //    there settled since the pane opened.
    //  - the pane has a motion switch of its own (Settings.hiddenMenuAnimations,
    //    which Anim.menu rides), and a pane the user has asked to appear
    //    instantly shouldn't spend half a second resolving - the same reason
    //    the flyouts turn `scramble` off per-label.
    //
    // An ancestor declares `scrambleSuppressed` and its whole subtree follows,
    // which is the only way to reach labels nested this far down without
    // threading a property through every control in between. Folded in here
    // rather than into `scramble` so that lifting it reads as an arrival: a
    // label forgets its run on the way out (see onOnScreenChanged) and starts
    // a fresh one when its tab comes back round.
    //
    // Every ancestor is read even once one has said yes, so this stays
    // subscribed to all of them - the same reason stackedOpacity multiplies
    // the whole chain rather than stopping at the first zero. An ancestor that
    // doesn't declare it reads as undefined, which is neither true nor a
    // dependency.
    readonly property bool ancestorSuppressed: {
        let suppressed = false;
        for (let item = root.shownItem; item; item = item.parent) {
            if (item.scrambleSuppressed === true)
                suppressed = true;
        }
        return suppressed;
    }
    readonly property bool onScreen: root.shownItem.visible && root.stackedOpacity > 0.05 && root.unmasked && !root.ancestorSuppressed

    // Where on the shared clock this label's own run began, or -1 for one that
    // hasn't come on screen yet (and so hasn't started).
    property int startedAt: -1
    onOnScreenChanged: {
        if (root.onScreen)
            root.armScramble();
        else
            // Leaving the screen forgets the run this label took part in, so
            // that whatever brings it back - a tile springing in again once
            // the filter widens, a ghosted slot refilling - is an arrival of
            // its own and scrambles like one.
            root.startedAt = -1;
    }
    function armScramble(): void {
        if (root.startedAt >= 0 || !root.scramble || !Anim.scrambleOn || !root.onScreen)
            return;
        // A label can arrive with no run behind it: a tile re-entering a pane
        // that is just sitting there is nobody's pane entrance. Waking the
        // clock is a no-op if something else already has it going.
        Anim.wakeScramble();
        root.startedAt = Anim.scrambleElapsed;
    }
    // Start this label over from full noise, for content that changed under a
    // label already on screen (see replayOnChange). One that *isn't* on screen
    // only disarms: it starts when it arrives, exactly as it does on a pane
    // entrance - which is also what keeps a background clipboard update from
    // running the clock behind a closed launcher.
    function replay(): void {
        root.startedAt = -1;
        root.noiseWidth = 0;
        if (!root.scramble || !Anim.scrambleOn || !root.onScreen)
            return;
        Anim.wakeScramble();
        // Under a stagger this starts in the *future*, which scrambled() reads
        // as a negative elapsed and holds at full noise until it comes round.
        root.startedAt = Anim.scrambleElapsed + root.replayStagger;
    }
    Connections {
        target: Anim
        // A fresh run: forget the last one's start, and take this one's
        // straight away if this label is already on screen (a pane switch,
        // where nothing has to be revealed first). A label off the launcher's
        // stage sits the run out entirely - the clock's timeline carries on
        // across it (see Anim.beginScramble), so a start taken before it is
        // still the start it has now.
        function onScrambleRunChanged(): void {
            if (!root.followsPane)
                return;
            root.startedAt = -1;
            root.noiseWidth = 0;
            root.armScramble();
        }
        // Back to the resting string, so back to the resting width - and
        // nothing left armed. A run that has ended takes the clock's timeline
        // with it: the next one starts from zero again (see Anim's
        // wakeScramble), where a leftover start from this run would read as a
        // label that began hundreds of ms in the future, i.e. full noise on a
        // label that never moved.
        function onScrambleActiveChanged(): void {
            if (!Anim.scrambleActive) {
                root.noiseWidth = 0;
                root.startedAt = -1;
            }
        }
    }

    text: root.scramble && Anim.scrambleActive && root.startedAt >= 0
        ? Anim.scrambled(root.content, Anim.scrambleElapsed - root.startedAt - root.scrambleDelay, root.scrambleSeed ^ Anim.scrambleRun, root.paceLength)
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
