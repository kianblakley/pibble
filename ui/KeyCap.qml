import QtQuick
import "root:/services"

// one physical-looking key in a keybinding chord (keybindings tab): a
// flat "cap" over a slightly darker "base" peeking out underneath reads
// as a root without needing a dedicated icon font - tabler-icons only
// ships a matching glyph for a couple of keys (Return's corner-down-left
// arrow being the clean one), so most labels just render as text.
Item {
    id: root

    property string label: ""
    // Return and the arrow keys always get a glyph; every other key
    // renders as plain text.
    property string glyph: label === "Return" ? Icons.cornerDownLeft
        : label === "Left" ? Icons.arrowLeft
        : label === "Right" ? Icons.arrowRight
        : label === "Up" ? Icons.arrowUp
        : label === "Down" ? Icons.arrowDown
        : ""
    implicitWidth: Math.max(28, capText.implicitWidth + 16)
    implicitHeight: 26

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        radius: 6
        color: Qt.alpha(Theme.fg, 0.16)
    }
    Rectangle {
        width: parent.width
        height: parent.height - 3
        radius: 6
        color: Qt.alpha(Theme.accent, 0.14)
        border.width: 1
        border.color: Qt.alpha(Theme.accent, 0.4)
    }
    Text {
        id: capText
        anchors.centerIn: parent
        text: root.glyph || root.label
        color: Theme.fg
        font.family: root.glyph ? Icons.family : Theme.fontFamily
        font.pixelSize: Theme.fontSize(12)
    }
}
