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
// It answers to the same switches as everything else: the master one this row
// sets, and - since this label sits inside the settings pane like every other
// control here - that pane's own chip. Unticking "settings" below stops the
// sample along with the rest of the pane's labels, which is the honest answer
// to "what does this look like now".
AnimPreview {
    id: root

    // both halves of the row: the master switch and the chips under it, either
    // of which changes what the sample does
    replayOn: [Settings.textScramble, Settings.scrambleSections]
    screen: false
    width: sample.restWidth
    height: sample.restHeight

    onStarted: sample.replay()

    ScrambleText {
        id: sample
        // pinned to the resting box: a label whose noise pulls in a fallback
        // glyph would otherwise shuffle the row on every reroll
        width: restWidth
        height: restHeight
        content: "scramble"
        color: Theme.fg
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
    }
}
