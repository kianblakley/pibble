import QtQuick
import "root:/services"
import "root:/ui"

// A line of the menu's text: the shell's font at the shell's scale, and - on
// the surfaces the user has asked for it on - resolving out of noise as it
// arrives, like every other label the shell draws (see ui/ScrambleText.qml).
// The tools menu is a surface of its own for that ("tools" among the
// Animations tab's chips), and one that is off with the menu's own animation.
ScrambleText {
    id: root

    required property var menu
    // the size as designed, before Settings.fontScale
    property int size: 13

    scrambleSection: "tools"
    // comes and goes on the menu's schedule, not a launcher pane's
    followsPane: false
    scramble: !root.menu.still
    color: Theme.fg
    // pinned to the resting string's box, so nothing laid out against this
    // moves while it is still noise
    width: restWidth
    height: restHeight
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize(root.size)
}
