import QtQuick
import "root:/services"

// The current value between a stepper's two arrows.
Text {
    color: Theme.fg
    width: 90
    horizontalAlignment: Text.AlignHCenter
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
    anchors.verticalCenter: parent.verticalCenter
}
