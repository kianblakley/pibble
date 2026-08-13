pragma Singleton
import QtQuick
import Quickshell
import "root:/config"

// Motion vocabulary for the whole shell, in one place so a tile in the apps
// grid, a bar in the wallpaper carousel and a custom page's own tiles all move
// alike.
//
// Three independent "off" switches, deliberately not folded into one: the tile
// style (Settings.animStyle === "none") zeroes grid and pane entrances, the
// launch style (Settings.launchAnimation === "none") zeroes the open/close
// reveal, and Settings.hiddenMenuAnimations zeroes the settings pane and the
// power/reboot prompts. Picking one never silently flattens another.
Singleton {
    id: root

    // bloom: staggered spring cascade (default). pop: all tiles spring at once.
    // fade: soft fade, all at once. cascade: fade's soft fade, but staggered
    // like bloom. slide: rows slide up. none: instant.
    readonly property string style: Settings.animStyle

    readonly property real fromScale: root.style === "bloom" || root.style === "pop" ? 0.4 : 1
    readonly property int fromY: root.style === "slide" ? 46 : (root.style === "fade" || root.style === "cascade") ? 6 : root.style === "none" ? 0 : 14
    readonly property int duration: (root.style === "fade" || root.style === "cascade") ? 220 : root.style === "slide" ? 320 : root.style === "none" ? 0 : 400
    readonly property int fadeDuration: root.style === "none" ? 0 : 180
    readonly property int easing: root.style === "bloom" || root.style === "pop" ? Easing.OutBack : Easing.OutCubic

    // Exit mirrors entrance: tiles spring back out toward the same from-state
    // (fromScale/fromY) they sprang in from, so "bloom"/"pop" (bounce) read as
    // the reverse of their entrance instead of all sharing one
    // bounce-then-shrink shape.
    readonly property bool outBounce: root.style === "bloom" || root.style === "pop"
    readonly property int outDuration: (root.style === "fade" || root.style === "cascade") ? 180 : root.style === "slide" ? 260 : 320
    readonly property int outEasing: root.outBounce ? Easing.InQuad : Easing.InCubic

    // Grid/pane entrance duration: zeroed by the tile style alone.
    function tile(ms: int): int {
        return root.style === "none" ? 0 : ms;
    }
    // Launcher open/close reveal duration: zeroed by the launch style alone.
    function launch(ms: int): int {
        return Settings.launchAnimation === "none" ? 0 : ms;
    }
    // Settings pane and power/reboot prompt duration: zeroed by
    // Settings.hiddenMenuAnimations alone - neither is a grid.
    function menu(ms: int): int {
        return Settings.hiddenMenuAnimations ? ms : 0;
    }

    function stagger(slot: int, cols: int, slideStep: int): int {
        return root.staggering ? root.staggerOffset(slot, cols, slideStep) : 0;
    }
    // The offsets themselves, with no staggering window over them. A tile
    // spring reads stagger() once, as it starts, and keeps that value for its
    // whole run - anything that instead re-reads its offset every frame (the
    // text scramble a custom page asks for, which is a binding, not an
    // animation) has to use this: through stagger() the same label's offset
    // would silently collapse to 0 the moment the window closed mid-run, and
    // every label still waiting would snap straight to resolved.
    function staggerOffset(slot: int, cols: int, slideStep: int): int {
        switch (root.style) {
        case "bloom":
        case "cascade":
            return slot * 35;
        case "slide":
            return Math.floor(slot / cols) * slideStep;
        }
        return 0;
    }

    // Tile stagger applies when a pane opens or a grid page turns, not on every
    // keystroke - re-staggering while filtering makes tiles blink out and pause.
    property bool staggering: false
    function beginStagger(): void {
        root.staggering = true;
        staggerWindow.restart();
    }
    // Arm the stagger when a navigation moves between pages (guarding the zero
    // page-size case the page getters guard against too).
    function staggerIfPageChanged(pageSize: int, before: int, after: int): void {
        if (pageSize > 0 && Math.floor(before / pageSize) !== Math.floor(after / pageSize))
            root.beginStagger();
    }

    Timer {
        id: staggerWindow
        interval: 600
        onTriggered: root.staggering = false
    }

    // ---------- text scramble ----------

    // Every label on an opening pane resolves out of a run of random glyphs
    // (see ui/ScrambleText.qml). One clock drives all of them rather than a
    // timer per label: a pane can hold dozens, and the run overlaps the
    // entrance spring, which is already the most expensive frame the shell
    // draws.
    //
    // Rides the tile style rather than carrying a third "off" switch of its
    // own - "none" means the pane arrives with no entrance to decorate - but
    // keeps a switch of its own on top of it, since the scramble is a much
    // louder effect than the spring it rides.
    readonly property bool scrambleOn: Settings.textScramble && root.style !== "none"

    // Bumped once per *pane* run, and mixed into each label's own seed, so a
    // label draws different noise on every open instead of replaying one
    // pattern for the whole session. Every label also re-arms off this - see
    // ScrambleText - so it is bumped last in beginScramble(), and so
    // wakeScramble() below deliberately leaves it alone.
    property int scrambleRun: 0
    property bool scrambleActive: false
    // ms since the current run started, as ScrambleText reads it
    property int scrambleElapsed: 0
    property real scrambleStarted: 0

    // When the clock may stop. Not a fixed window: labels don't share one
    // start, they each begin as they come on screen (a tile's caption waits
    // out that tile's stagger and spring), so how long a run lasts is however
    // long the last of them takes to arrive and resolve. scrambled() below
    // pushes this out for as long as anything is still asking for noise, which
    // means a 42-tile custom page's cascade keeps the clock alive to its end
    // while a two-label pane still lets it stop early.
    property int scrambleUntil: 0
    // Where the current run began on that timeline. The clock outlives a
    // single run (see beginScramble), so the backstop below is measured from
    // here rather than from zero.
    property int scrambleRunStarted: 0
    // How long a fresh run waits for its first label with nothing holding it
    // yet: the launch reveal has to finish exposing them, and under the "grow"
    // styles that is the whole reveal.
    readonly property int scrambleLead: 900
    // Backstop against a page that keeps handing scrambled() a string that
    // never settles - nothing in the shell does, but a custom page can.
    readonly property int scrambleMaxRun: 10000
    // how long one noise glyph holds before it rerolls
    readonly property int scrambleHold: 45
    // Symbols rather than letters: noise made of letters reads as a word that
    // hasn't loaded, where shapes and punctuation read as static - which is
    // the point, and stays clearly distinct from the string landing
    // underneath it. Weighted towards the geometric shapes, since those are
    // what carry the effect at a glance.
    //
    // Three things every candidate has to clear, all of which otherwise show
    // up as the label growing and shrinking as the noise rerolls - which is
    // what the effect looks like when it goes wrong, and unmissable on a line
    // of small text:
    //
    //  - it has to sit inside the band ordinary text occupies. Measured
    //    against the em, every glyph here runs from 0% to about 74%, the same
    //    band a digit or a capital fills. That rules out the shading and part
    //    blocks (░▒▓█▌▐▄▀, -30% to 102%), which make a label visibly taller
    //    than the letters they stand in for, and it rules out descenders
    //    (¶§@µ$¢/\|†‡, down to -18%), which put ink below a baseline that a
    //    line of caps - the clock's date - otherwise keeps clean.
    //  - it should be in the shell font rather than reached by substitution.
    //    A substituted glyph doesn't just bring its own width - it brings its
    //    own ascent into the line, which shifts the *whole* string's baseline
    //    for as long as it is on screen. The quadrant and shaded squares
    //    (▣▤▥▦▧▨▩), half circles (◐◑) and corner triangles (◢◣◤◥) are missing
    //    from common monospace faces (JetBrains Mono among them) and are out
    //    for that reason; the plain squares, diamonds and circles are in every
    //    one of them.
    //  - no <, > or &: a couple of labels render as StyledText (the clipboard
    //    previews), where those would be read as markup rather than drawn.
    //
    // Every glyph is BMP, so charAt() below indexes whole characters.
    readonly property string scrambleAlphabet: "■□▪▫◆◇◈●○◉▲▼◀▶¤£°±×÷¬•~=+*#%?!^"
    readonly property string scrambleDigits: "0123456789"
    // Narrow characters get narrow stand-ins, so a string keeps its silhouette
    // while it resolves: a colon replaced by a full square is four times its
    // width, which on the clock shoves the rest of the time out of a label
    // sized for "19:25". Same in-band rule as the set above - no descenders,
    // which is why ; , and _ aren't here.
    readonly property string scrambleThin: ":.-~^'"

    function beginScramble(): void {
        if (!root.scrambleOn)
            return;
        // The timeline only goes back to zero when the clock was stopped. A
        // run beginning over one that is still going - a pane change behind a
        // notification card that is still resolving - has to leave it where it
        // is: every label already running holds a start on that timeline, and
        // rewinding underneath them reads as a start hundreds of ms in the
        // future, i.e. full noise on a label that never moved.
        if (!root.scrambleActive) {
            root.scrambleStarted = Date.now();
            root.scrambleElapsed = 0;
            root.scrambleHolds.length = 0;
            root.scrambleActive = true;
            scrambleClock.restart();
        }
        root.scrambleRunStarted = root.scrambleElapsed;
        root.scrambleUntil = root.scrambleElapsed + root.scrambleLead;
        // Last, and after the clock is already running: labels reset and
        // re-arm off this, and one that is on screen already arms itself
        // there and then.
        root.scrambleRun++;
    }

    // Put the clock back in motion for a single label that arrived on its own
    // rather than with a pane: a tile springing back in as a filter widens, or
    // a grid slot taking a different entry on a page turn (see
    // ScrambleText.replay()). A no-op while a run is already going - the label
    // simply takes the clock where it is.
    //
    // Unlike beginScramble() this does not bump scrambleRun: that is every
    // label's cue to start over, which is exactly wrong here, since the labels
    // that didn't move should stay resolved.
    function wakeScramble(): void {
        if (!root.scrambleOn || root.scrambleActive)
            return;
        root.scrambleStarted = Date.now();
        root.scrambleElapsed = 0;
        root.scrambleRunStarted = 0;
        // No lead: whatever woke the clock is on screen already (that is what
        // arming means), and holds the run open from its first frame. Anything
        // arriving later - the rest of a staggered wave - wakes the clock again
        // if this run has ended by the time it gets there.
        root.scrambleUntil = 0;
        root.scrambleHolds.length = 0;
        root.scrambleActive = true;
        scrambleClock.restart();
    }

    // Keep the clock alive until at least `untilMs` on its own timeline.
    //
    // Requests are queued and folded into scrambleUntil by the clock rather
    // than compared against it here: scrambled() calls this from inside a
    // binding, and a binding that read the deadline it extends would depend on
    // its own write - a binding loop, and a page's worth of labels writing in
    // one pass makes it a loud one. Mutating this array (never reassigning it)
    // emits no change of its own, so nothing re-evaluates off a hold.
    readonly property var scrambleHolds: []
    function holdScramble(untilMs: int): void {
        root.scrambleHolds.push(untilMs);
    }

    // Where the "grow" launch styles' reveal circle has got to, in the scene
    // coordinates ScrambleText maps itself into. Written by LauncherWindow -
    // this is a service, so it can't reach up for it - and negative whenever
    // nothing is masking: a "fade"/"none" launch, or a reveal that has landed.
    property real maskX: 0
    property real maskY: 0
    property real maskRadius: -1
    // Whether a point is out from under that circle yet, i.e. actually on
    // screen. Opacity can't answer this: the reveal masks content into the
    // circle rather than fading it, so a label behind the mask is fully opaque
    // and completely invisible.
    function unmasked(x: real, y: real): bool {
        return root.maskRadius < 0 || Math.hypot(x - root.maskX, y - root.maskY) < root.maskRadius;
    }

    Timer {
        id: scrambleClock
        // ~2 frames: the wavefront reads as smooth well below 60Hz, and every
        // visible label relays its text out on each tick
        interval: 32
        repeat: true
        // Wall clock rather than a tick count: this run overlaps the pane
        // entrance, which can easily eat several intervals, and a run that
        // stretched with the stall would read as the shell hanging.
        onTriggered: {
            root.scrambleElapsed = Date.now() - root.scrambleStarted;
            // drained before the stop check, so a hold asked for on the last
            // tick can't be missed by the one that ends the run
            for (const until of root.scrambleHolds)
                root.scrambleUntil = Math.min(Math.max(root.scrambleUntil, until), root.scrambleRunStarted + root.scrambleMaxRun);
            root.scrambleHolds.length = 0;
            if (root.scrambleElapsed >= root.scrambleUntil) {
                root.scrambleActive = false;
                scrambleClock.stop();
            }
        }
    }

    // How long a string of `len` characters spends resolving. Long strings
    // resolve faster per character rather than dragging the run out, so a
    // clipboard preview and an app name finish within sight of each other -
    // and the floor is deliberately near a tile's own entrance (root.duration,
    // 400ms), because a label that resolves quicker than the tile carrying it
    // has finished before that tile is fully on screen. A calendar's two-digit
    // day numbers were the case that showed this up: they landed looking
    // untouched while every longer label around them was visibly resolving.
    //
    // The 460ms ceiling is what holds a wave together, and `cap` lifts it for
    // a label resolving on its own instead: a notification body is the only
    // long string on its card, with nobody to finish alongside, and under the
    // shared ceiling three lines of it get wiped through in the time a
    // six-letter caption takes - the same "it never scrambled" the pacing
    // below is there to fix, one step further out. 0 takes the shared ceiling,
    // which is what everything in a grid wants.
    function scrambleSpan(len: int, cap: int): int {
        return Math.min(300 + len * 14, cap > 0 ? cap : 460);
    }

    // `source` as it looks `elapsed` ms into the run (negative while a label
    // is still waiting out its stagger delay): characters resolve left to
    // right, and every one that hasn't yet stands in as a random glyph that
    // rerolls every scrambleHold ms.
    //
    // `paceLen` is how many characters the span is spread across, for a label
    // where only the head of the string is ever on screen - a notification
    // body clipped to three lines. Paced across the whole string, the part
    // that can actually be seen is finished within its own fraction of the
    // span (three lines out of twelve: 115ms of a 460ms run), which reads as a
    // body that never scrambled at all. Everything past `paceLen` comes back
    // resolved from the first frame instead; by the caller's own account
    // nothing can see it. 0 paces across the whole string, as everything but
    // that one label wants.
    function scrambled(source: string, elapsed: int, seed: int, paceLen: int, spanCap: int): string {
        const len = paceLen > 0 && paceLen < source.length ? paceLen : source.length;
        const span = root.scrambleSpan(len, spanCap);
        if (len === 0 || elapsed >= span)
            return source;
        // Anything still asking for noise is what keeps the clock running -
        // there is no fixed window, since a label that hasn't come on screen
        // yet hasn't even started (see scrambleUntil). Called from a binding,
        // which is why this is a max rather than an assignment: several labels
        // hold the same clock, and the longest one wins.
        root.holdScramble(root.scrambleElapsed + span - elapsed + root.scrambleHold);
        const frame = Math.floor(Math.max(0, elapsed) / root.scrambleHold);
        let out = "";
        for (let i = 0; i < source.length; i++) {
            const ch = source.charAt(i);
            // whitespace is left alone: it's what holds word shapes and line
            // breaks still while everything around it churns
            if (i >= len || ch === " " || ch === "\n" || ch === "\t" || elapsed >= (i + 1) / len * span) {
                out += ch;
                continue;
            }
            // digits stand in for digits, so the clock reads as a clock
            // flipping through times rather than as symbols
            const alphabet = ch >= "0" && ch <= "9" ? root.scrambleDigits
                : root.scrambleThin.indexOf(ch) >= 0 ? root.scrambleThin : root.scrambleAlphabet;
            out += alphabet.charAt(root.scrambleHash(seed, i, frame) % alphabet.length);
        }
        return out;
    }

    // Deterministic per (label, character, frame) rather than Math.random():
    // the string is rebuilt from scratch on every tick, so a glyph picked at
    // random would reroll every frame and the hold above would do nothing.
    function scrambleHash(seed: int, i: int, frame: int): int {
        let h = Math.imul(seed ^ 0x9e3779b9, 0x85ebca6b);
        h = Math.imul(h ^ i, 0xc2b2ae35);
        h = Math.imul(h ^ frame, 0x27d4eb2f);
        // Masked to 30 bits rather than made unsigned with >>> 0: this returns
        // a QML int, which is signed 32-bit, so half of all unsigned values
        // come back through it negative - and a negative index into charAt()
        // is the empty string, which silently deleted every second character
        // of the noise instead of drawing it.
        return (h ^ (h >>> 15)) & 0x3fffffff;
    }
}
