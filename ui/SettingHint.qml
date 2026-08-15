import QtQuick
import "root:/services"

// muted helper line rendered directly beneath the row it explains. Callers
// bind `content`, not `text` - see ScrambleText.
ScrambleText {
    color: Qt.alpha(Theme.muted, 0.7)
    // Rows size themselves off this line (`height: 34 + hintLabel.height + 2`
    // and friends), so it is pinned to its resting box - a noise glyph reached
    // by font substitution brings its own line metrics, and left free that
    // would have every row below this one shuffling down the column and back
    // for the length of the run. Callers read `height`, not implicitHeight,
    // for the same reason.
    height: restHeight
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(11) }
}
