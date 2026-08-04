import QtQuick
import "root:/services"

// The left-hand label of a settings row: muted, vertically centred against
// whatever control sits opposite it.
Text {
    color: Theme.muted
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
    anchors.verticalCenter: parent.verticalCenter
}
