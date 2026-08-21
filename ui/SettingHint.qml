import QtQuick
import "root:/services"

// muted helper line rendered directly beneath the row it explains. Callers
// bind `content`, not `text` - see ScrambleText.
ScrambleText {
    id: root

    // The column this line has to stay inside - the full width of a settings
    // row, since a hint starts at the row's left edge and has nothing to its
    // right. It is a cap, not a width: a hint that fits keeps its own natural
    // extent and nothing about the layout changes.
    //
    // A hint is one line by construction (no wrapMode, so nothing here wraps),
    // which means without a cap a long one simply keeps going and is cut off
    // by the filmstrip's clip mid-word, with no sign that anything is missing.
    // A translated hint is routinely longer than the English it came from, so
    // the cap elides instead: still one line, still inside the column, and the
    // ellipsis is the visible cue that this translation wants shortening (see
    // the note in services/Translations.qml).
    property real maxWidth: 780
    measuresFit: true
    width: Math.min(fitWidth, root.maxWidth)
    elide: Text.ElideRight
    // What is past the ellipsis is off screen, so the resolve is paced across
    // the head that can actually be seen rather than across the whole string -
    // see ScrambleText.paceWidth, which is why this is the same figure as the
    // width above rather than a second one that could drift from it.
    paceWidth: root.maxWidth

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
