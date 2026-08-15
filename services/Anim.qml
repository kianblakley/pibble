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
    // Nothing here is picked or dropped for how big it looks, because size is
    // not what moves a label: Qt lays a line out on the font's metrics, and
    // ink is free to overflow the em box in every direction without shifting
    // anything around it. A full block is no more disruptive than a full stop
    // so long as both are drawn from the same face.
    //
    // What does move a label is a glyph the shell font doesn't have. Reaching
    // one by substitution pulls a second face into the line, and that face
    // brings its own metrics with it: the string gets wider (the shaded
    // squares and corner triangles come back two cells wide out of the faces
    // JetBrains Mono falls back to) and the line's baseline moves to clear
    // whichever of the two ascents is taller, which drags the *whole* string
    // down - characters that have already landed included. That is the
    // repositioning, and it is a question about the user's font rather than
    // about the glyph, since Theme.fontFamily is a setting.
    //
    // So this is the pool of everything worth showing, and the alphabet is
    // whatever survives being measured against the shell font
    // (rebuildScrambleAlphabet below). Under a face that has the shaded
    // squares they take part; under one that doesn't they are dropped, rather
    // than shifting every label unlucky enough to draw one.
    //
    // The one rule measuring can't discover: no <, > or &, since a couple of
    // labels render as StyledText (the clipboard previews), where those would
    // be read as markup rather than drawn.
    //
    // Every glyph is BMP, so charAt() below indexes whole characters.
    readonly property string scrambleCandidates: "■□▪▫◆◇◈●○◉▲▼◀▶¤£°±×÷¬•~=+*#%?!^"
        + "░▒▓█▌▐▄▀"           // full-em blocks
        + "▣▤▥▦▧▨▩◧◨◩◪"        // shaded and part-filled squares
        + "◐◑◒◓◢◣◤◥"           // half circles, corner triangles
        + "¶§@µ$¢/\\|†‡◊"       // descenders
        + "⬛⬜⬥⬦⧫⏹⏺"           // outsized shapes
    // Plain ASCII, so no face is without it. The floor the probe can never
    // take the alphabet below: a font with none of the shapes still scrambles,
    // and so does a label drawn in the frames before there is a resolved font
    // family to measure anything against.
    readonly property string scrambleCore: "~=+*#%?!^"
    // Filled in by rebuildScrambleAlphabet() - not a binding, since building
    // it means writing to the probes below and reading them back, which is
    // exactly the kind of round trip a binding can't express.
    property string scrambleAlphabet: root.scrambleCore

    // Which of the candidates the shell font can actually draw without moving
    // the line, rebuilt whenever that font changes - the answer belongs to the
    // font, and the font is a setting the user can turn (and one that arrives
    // late, since the settings file loads async, so the first run of this is
    // against whatever Qt defaulted to and the real one follows).
    Component.onCompleted: root.rebuildScrambleAlphabet()
    Connections {
        target: Theme
        function onFontFamilyChanged(): void {
            root.rebuildScrambleAlphabet();
        }
    }
    function rebuildScrambleAlphabet(): void {
        // The font's own ascent, which is what a line of it puts its baseline
        // at. Every candidate has to leave it exactly where it is.
        const baseline = root.scrambleBaseline("M");
        // The widest an ordinary character gets here - the cell, in the
        // monospace face this is usually pointed at. A stand-in wider than
        // half again as much is a glyph that came back occupying *two* of
        // them, which is what the shaded squares and corner triangles do out
        // of a fallback and what visibly stretches the string; anything under
        // that is ordinary variation, which ScrambleText.restWidth already
        // ratchets over once rather than breathing on every reroll.
        let cell = 0;
        for (const ref of "MW@%0")
            cell = Math.max(cell, root.scrambleAdvance(ref));
        cell *= 1.5;

        let alphabet = root.scrambleCore;
        for (const ch of root.scrambleCandidates) {
            if (alphabet.indexOf(ch) >= 0)
                continue;
            if (root.scrambleAdvance(ch) > cell + 0.5)
                continue;
            // Measured in both kinds of company, because the two ways a
            // substituted ascent can differ show up in different ones: mixed
            // into shell-font text only a *taller* fallback wins the line, but
            // the opening frames of a run are all noise, with no shell-font
            // run left to set the line's metrics, and there a shorter one
            // lifts the baseline just as visibly.
            if (Math.abs(root.scrambleBaseline("M" + ch + "M") - baseline) > 0.5)
                continue;
            if (Math.abs(root.scrambleBaseline(ch + ch + ch + ch) - baseline) > 0.5)
                continue;
            alphabet += ch;
        }
        root.scrambleAlphabet = alphabet;
    }
    // Advance off TextMetrics and baseline off a Text, each because the other
    // can't say it: a Text's implicitWidth includes ink overhang, so a glyph
    // painting past its cell (which the full blocks do, by design) reads a
    // pixel wider than the cell it actually occupies - and overhang is the
    // whole thing this is trying not to punish. TextMetrics has no baseline at
    // all, and its boundingRect carries the same overhang.
    function scrambleAdvance(text: string): real {
        widthProbe.text = text;
        return widthProbe.advanceWidth;
    }
    function scrambleBaseline(text: string): real {
        baselineProbe.text = text;
        return baselineProbe.baselineOffset;
    }
    // Measured far larger than anything the shell draws at, so a difference of
    // a fraction of a percent is still whole pixels here rather than something
    // rounding hides. Which face a glyph is reached through doesn't depend on
    // the size it was asked for, so one probe size answers for every label.
    TextMetrics {
        id: widthProbe
        font.family: Theme.fontFamily
        font.pixelSize: 96
    }
    Text {
        id: baselineProbe
        font: widthProbe.font
    }

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

    // How long any label spends resolving - one duration for every string in
    // the shell, whatever its length and wherever it sits. Everything that
    // arrives together therefore lands together, and no label can be given a
    // longer run than its neighbours.
    //
    // It used to grow with the string (a floor, a per-character term and a
    // ceiling, with one label overriding the ceiling for itself), which kept
    // long text legible as it resolved but meant "how long does this take"
    // had a different answer per label. Flat is the deliberate choice, and
    // these are the two things it costs - both known, neither a bug to fix by
    // reintroducing a curve:
    //
    //  - long strings sweep fast. The resolve crosses the string left to
    //    right in this same duration however many characters there are, so a
    //    three-line notification body arrives faster than it can be read.
    //    ScrambleText.paceLength narrows *which* characters the sweep is
    //    spread across, which is the remaining lever for that, and it doesn't
    //    touch the duration.
    //  - short strings can no longer finish early, which is what the old
    //    floor was protecting: 460ms comfortably outlasts a tile's own 400ms
    //    entrance (root.duration), so a two-character label still can't
    //    resolve before the tile carrying it has landed.
    //
    // 575ms: a quarter longer than the 460 the effect was first tuned to,
    // which is where it landed after being made adjustable and tried at a
    // range of lengths. A constant rather than a setting on purpose - it is
    // the one number the whole effect is timed against, and the point of
    // having a single number is that nothing, a label or a user, can put one
    // label out of step with the rest.
    readonly property int scrambleSpan: 575

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
    //
    // Note this narrows the sweep without lengthening the run: the duration is
    // the same flat figure either way (see scrambleSpan), so a label using
    // this still lands alongside everything else.
    function scrambled(source: string, elapsed: int, seed: int, paceLen: int): string {
        const len = paceLen > 0 && paceLen < source.length ? paceLen : source.length;
        const span = root.scrambleSpan;
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
            // One alphabet for everything the label holds. Digits and narrow
            // punctuation used to be routed to sets of their own - digits to
            // digits so the clock read as a clock flipping through times, a
            // colon to another narrow character so a string kept its
            // silhouette - but both stood the effect down exactly where it is
            // most visible, and the width worry behind the second one was
            // misplaced: the faces this is drawn in are monospace, so a colon
            // and a full square occupy the same cell, and a proportional one
            // is what ScrambleText.restWidth's ratchet is already for.
            const alphabet = root.scrambleAlphabet;
            // On the last frame before this character locks, the real one is
            // held out of the noise: drawn there it is still there after the
            // lock, so the instant the character lands reads as a glyph that
            // failed to reroll rather than as the character arriving. Only
            // that frame - a real character turning up earlier in the run is
            // gone again 45ms later, which reads as a flicker, not a landing.
            //
            // indexOf is -1 for anything the alphabet doesn't hold, which is
            // now everything but the punctuation it happens to overlap (% and
            // ~ among them), and scrambleIndex takes that as "nothing to hold
            // out".
            const lastFrame = (frame + 1) * root.scrambleHold >= (i + 1) / len * span;
            out += root.scrambleGlyph(alphabet, seed, i, frame, lastFrame ? alphabet.indexOf(ch) : -1);
        }
        return out;
    }

    // The glyph character `i` shows on `frame`: a pick out of `alphabet` that
    // is never the glyph that character showed on the frame before, and never
    // `avoid` (-1 for none). A reroll that lands on the glyph already there
    // reads as a dropped frame, and how often that happens is the alphabet's
    // length: rare across the sixty-odd glyphs a full face yields, but one
    // reroll in nine on a font pared back to scrambleCore, which is
    // unmissable on a label that does nothing else.
    //
    // Walked forward from frame 0 rather than derived against the previous
    // frame's hash, because what that frame *drew* is not what its hash alone
    // says: the pick may itself have been displaced by this same rule, and
    // holding out the raw value instead would let the displaced one through.
    //
    // The walk is bounded by the run rather than by the clock: scrambled()
    // hands back the finished string once elapsed reaches the span, so `frame`
    // never gets past the span divided by the hold - ten steps at the default
    // duration - and only characters still showing noise are asked at all.
    function scrambleGlyph(alphabet: string, seed: int, i: int, frame: int, avoid: int): string {
        let idx = -1;
        for (let f = 0; f <= frame; f++)
            idx = root.scrambleIndex(root.scrambleHash(seed, i, f), alphabet.length, idx, f === frame ? avoid : -1);
        return alphabet.charAt(idx);
    }

    // `h` folded into [0, n) with up to two indices held out of it, so that
    // every glyph still allowed stays equally likely - rerolling until the
    // pick differs would need somewhere to keep the rejected ones, and this
    // has to stay a pure function of the frame (see scrambleHash). The two are
    // skipped in ascending order, which is what puts the shifted pick where an
    // even spread would have. The alphabet is far longer than two even pared
    // back to scrambleCore, so there is always something left to land on.
    function scrambleIndex(h: int, n: int, banA: int, banB: int): int {
        const lo = Math.min(banA, banB);
        const hi = Math.max(banA, banB);
        const first = lo >= 0 ? lo : hi;
        const second = (lo >= 0 && hi > lo) ? hi : -1;
        let idx = h % (n - (first >= 0 ? 1 : 0) - (second >= 0 ? 1 : 0));
        if (first >= 0 && idx >= first)
            idx++;
        if (second >= 0 && idx >= second)
            idx++;
        return idx;
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
