import QtQuick
import "root:/services"

// "+" joiner between the caps of a multi-key chord (e.g. Shift+Tab);
// height matches KeyCap.implicitHeight so it centers against the caps
// in the Row they share, which doesn't reposition child y itself.
Text {
    text: "+"
    height: 26
    verticalAlignment: Text.AlignVCenter
    color: Theme.muted
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
}
