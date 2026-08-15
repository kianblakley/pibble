import QtQuick
import "root:/config"
import "root:/services"

// The text scramble itself, on one word in a box - the one preview that isn't a
// picture of a surface, because the effect *is* text and there is nothing else
// to draw it as. The box is the card the volume and notification previews stand
// up, in the same fill, so the sample reads as belonging to the same set as the
// pictures above it.
//
// Nothing here reimplements the effect: this is an ordinary ScrambleText
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

    onStarted: sampleText.replay()

    // The ground the sample sits on: sized from the label's *resting* box, not
    // its live one. Bound to the live width it breathed in and out a dozen
    // times a second for the length of a run - the noise routinely pulls in a
    // fallback glyph wider than the one it stands in for, and a centred box
    // takes half of every such change out of its left edge.
    Rectangle {
        anchors.centerIn: sampleText
        width: sampleText.restWidth + root.u(24)
        height: sampleText.restHeight + root.u(6)
        radius: Theme.radius(root.u(6))
        // the volume and notification previews' card, exactly
        color: Qt.alpha(Theme.muted, 0.22)
    }
    ScrambleText {
        id: sampleText
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        // pinned to that same resting box, for the same reason the ground is
        // sized off it: a label free to grow with its noise walks around inside
        // the box it is centred in
        width: restWidth
        height: restHeight
        content: "scramble"
        color: Theme.fg
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(17) }
    }
}
