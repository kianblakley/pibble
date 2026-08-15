import QtQuick
import "root:/services"

// The left-hand label of a settings row: muted, vertically centred against
// whatever control sits opposite it. Callers bind `content`, not `text` - see
// ScrambleText.
ScrambleText {
    color: Theme.muted
    // see SettingValue: centred against the row, so the box has to hold still
    // while the noise pulls in fallback glyphs with line metrics of their own
    height: restHeight
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
    anchors.verticalCenter: parent.verticalCenter
}
