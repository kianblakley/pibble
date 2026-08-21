import QtQuick
import "root:/services"

// The left-hand label of a settings row: muted, vertically centred against
// whatever control sits opposite it. Callers bind `content`, not `text` - see
// ScrambleText.
ScrambleText {
    id: root

    // How much of the row this label may take before it elides - the span left
    // over once the controls opposite have had theirs. A label and its
    // controls are two blocks anchored to opposite edges of the same row, so
    // an overlong one does not push anything aside: it grows straight into
    // them and the two overlap. A translated label is the usual way that
    // happens, since nothing about a language guarantees its words are as
    // short as the English they replace. 0 - the default - is a caller with
    // room to spare and nothing to declare.
    property real maxWidth: 0
    measuresFit: true
    width: root.maxWidth > 0 ? Math.min(fitWidth, root.maxWidth) : fitWidth
    elide: Text.ElideRight
    // paced across the head that survives the elide - see ScrambleText
    paceWidth: root.maxWidth

    color: Theme.muted
    // see SettingValue: centred against the row, so the box has to hold still
    // while the noise pulls in fallback glyphs with line metrics of their own
    height: restHeight
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
    anchors.verticalCenter: parent.verticalCenter
}
