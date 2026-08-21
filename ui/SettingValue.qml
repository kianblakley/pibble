import QtQuick
import "root:/services"

// The current value between a stepper's two arrows. Callers bind `content`,
// not `text` - see ScrambleText.
ScrambleText {
    id: root

    color: Theme.fg
    width: 90
    // Pinned to the resting box: this is centred against the Row it shares
    // with the two arrows, so a line height that changed with whatever font
    // ends up carrying a noise symbol would have the value bobbing for the
    // length of the run. The width is the caller's either way, so the noise
    // stays centred in the same box the value rests in.
    height: restHeight
    horizontalAlignment: Text.AlignHCenter
    // The box is fixed and the string in it is not: the narrow rows are sized
    // to the longest value the current language can put in them (see
    // ui/Metrics.qml), but a value that comes from outside pibble - a font
    // family, an icon theme - has no such bound. Without this such a value is
    // laid out at its natural width and painted straight over the arrows on
    // either side of it, since a Text given too little width overhangs rather
    // than wrapping.
    elide: Text.ElideRight
    // paced across the head that survives the elide, not the whole string -
    // see ScrambleText.paceWidth
    paceWidth: root.width
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
    anchors.verticalCenter: parent.verticalCenter
}
