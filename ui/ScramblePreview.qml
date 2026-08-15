import QtQuick
import "root:/config"
import "root:/services"

// The text scramble itself, on one word in a box - the one preview that isn't a
// picture of a surface, because the effect *is* text and there is nothing else
// to draw it as. The box is the card the volume and notification previews stand
// up, in the same fill, so the sample reads as belonging to the same set as the
// pictures above it - drawn at the sample's size rather than at theirs (see
// baseWidth below).
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

    // The card is the whole of this preview, rather than a card floating in a
    // 16:9 stage the way the pictures above it are drawn. Every other preview
    // is a picture of a screen, and a screen is the same shape however big it
    // is drawn; this one's subject is a line of shell text at the shell's own
    // size, so a stage around it was empty space by construction - and the eye
    // reads that space as the gap between the chips and the sample, which put
    // the sample nowhere near as close to its row as every other preview is to
    // its own.
    //
    // Which is also why it takes no `unit`: there is nothing here to draw
    // larger, and it is a fixed block in the tab's height budget for the same
    // reason the tile grid is (see AnimationsTab.previewUnit). The padding is
    // off the sample's own line instead, so the card stays the same pill under
    // any type scale.
    readonly property real padY: Math.round(sampleText.restHeight * 0.4)
    readonly property real padX: Math.round(sampleText.restHeight * 1.2)
    // Sized from the label's *resting* box, not its live one. Bound to the live
    // width it breathed in and out a dozen times a second for the length of a
    // run - the noise routinely pulls in a fallback glyph wider than the one it
    // stands in for, and a centred box takes half of every such change out of
    // its left edge.
    baseWidth: sampleText.restWidth + root.padX * 2
    baseHeight: sampleText.restHeight + root.padY * 2
    // nothing to clip: the box is the card, not a screen the card sits on
    screen: false

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius(root.padY)
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
