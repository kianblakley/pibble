import QtQuick
import "root:/services"

// The current value between a stepper's two arrows. Callers bind `content`,
// not `text` - see ScrambleText.
ScrambleText {
    color: Theme.fg
    width: 90
    // Pinned to the resting box: this is centred against the Row it shares
    // with the two arrows, so a line height that changed with whatever font
    // ends up carrying a noise symbol would have the value bobbing for the
    // length of the run. The width is the caller's either way, so the noise
    // stays centred in the same box the value rests in.
    height: restHeight
    horizontalAlignment: Text.AlignHCenter
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
    anchors.verticalCenter: parent.verticalCenter
}
