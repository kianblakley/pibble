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
    // Off for a cap standing in for keys the user is holding down right now
    // (see the capture box on the Navigation tab): that cap is feedback for a
    // key press, and feedback that spends a third of a second resolving reads
    // as the key not having registered.
    property bool scramble: true
    // Return and the arrow keys always get a glyph; every other key
    // renders as plain text.
    property string glyph: label === "Return" ? Icons.cornerDownLeft
        : label === "Left" ? Icons.arrowLeft
        : label === "Right" ? Icons.arrowRight
        : label === "Up" ? Icons.arrowUp
        : label === "Down" ? Icons.arrowDown
        : ""
    // the resting string's width, not the noise's: a cap that grew and shrank
    // as its label resolved would push every cap after it along the chord, and
    // Metrics measures a pair of these to size every chord box in the tab
    implicitWidth: Math.max(28, capText.restWidth + 16)
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
    ScrambleText {
        id: capText
        anchors.centerIn: parent
        content: root.glyph || root.label
        // a cap rendering its key as an icon sits this one out: the noise is
        // drawn from the shell font, and running it under Icons.family asks
        // for codepoints that font doesn't have - a run of tofu where the
        // arrow should be
        scramble: root.scramble && !root.glyph
        // A rebind rebuilds the whole chord from a plain JS array, so a cap
        // can arrive at full opacity inside a box that never moved - nothing
        // fades it in, and `content` landing on it is the only cue that these
        // are different keys to the ones that were here a moment ago.
        replayOnChange: true
        color: Theme.fg
        font.family: root.glyph ? Icons.family : Theme.fontFamily
        font.pixelSize: Theme.fontSize(12)
    }
}
