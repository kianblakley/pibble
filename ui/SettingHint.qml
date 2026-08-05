import QtQuick
import "root:/services"

// muted helper line rendered directly beneath the row it explains
Text {
    color: Qt.alpha(Theme.muted, 0.7)
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(11) }
}
