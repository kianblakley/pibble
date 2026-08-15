import QtQuick
import "root:/config"
import "root:/services"

// The text scramble itself, on one word - the one preview that isn't a picture
// of a surface, because the effect *is* text and there is nothing else to draw
// it as. Nothing here reimplements it either: this is an ordinary ScrambleText
// replayed on cue, so it resolves at exactly the span, hold and alphabet every
// label in the shell resolves at (which is also why this is the one preview
// slowdown can't reach - Anim.scrambleSpan is one shared figure that nothing is
// allowed to lengthen for itself).
//
// It answers to the same switches as everything else: the chips it sits under,
// and - since this label lives inside the settings pane like every other
// control here - that pane's own chip among them. Unticking "settings" stops
// the sample along with the rest of the pane's labels, which is the honest
// answer to "what does this look like now".
AnimPreview {
    id: root

    replayOn: Settings.scrambleSections
    screen: false
    // a fixed box the word is centred in, rather than one sized to the word:
    // the tab solves its preview sizes off these design figures, and a box that
    // measured its own text would resize as the effect ran
    baseWidth: 120
    baseHeight: 26

    onStarted: sample.replay()

    ScrambleText {
        id: sample
        anchors.centerIn: parent
        // pinned to the resting box: a label whose noise pulls in a fallback
        // glyph would otherwise walk out of centre on every reroll
        width: restWidth
        height: restHeight
        content: "Preview"
        color: Theme.fg
        font { family: Theme.fontFamily; pixelSize: root.uf(15) }
    }
}
