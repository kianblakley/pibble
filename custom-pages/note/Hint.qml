import QtQuick

// Deliberately tiny: its whole job is demonstrating that a page can be
// split across sibling files, which resolve only through a qualified
// `import "." as Local` - a bare `Hint {}` in main.qml would fail, because
// quickshell shadows the implicit directory import an ordinary QML app
// would get for free.
Text {
    id: root

    required property var pibble

    color: root.pibble.mutedTextColor
    font.family: root.pibble.font
    font.pixelSize: root.pibble.px(12)
}
