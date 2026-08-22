import QtQuick

// The content of this page's Settings tab, reached from main.qml's
// `settingsTab` Component - in its own file to show the split: main.qml
// reaches it with `import "." as Local` and Local.Settings (a bare
// `Settings {}` would not resolve - quickshell shadows the implicit
// directory import an ordinary QML app would get for free). main.qml owns
// the persisted copy of the setting; this only reports what was clicked,
// via `picked`.
Item {
    id: root

    required property var pibble
    property int size: 100
    signal picked(int size)

    function step(delta: int): void {
        picked(Math.max(50, Math.min(200, size + delta)));
    }

    width: 780
    height: 34

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Box size"
        color: root.pibble.mutedTextColor
        font.family: root.pibble.font
        font.pixelSize: root.pibble.px(14)
    }
    Row {
        anchors.right: parent.right
        height: parent.height
        spacing: 8

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: root.pibble.radius(8)
            color: shrinkArea.containsMouse ? root.pibble.activeTileColor : root.pibble.tileColor
            border.width: 1
            border.color: root.pibble.borderColor

            Text {
                anchors.centerIn: parent
                // a named glyph from pibble's icon font - the promised
                // names are listed on PageContext's icon()
                text: root.pibble.icon("chevron-left")
                color: root.pibble.accentColor
                font.family: root.pibble.iconFont
                font.pixelSize: root.pibble.px(15)
            }
            MouseArea {
                id: shrinkArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.step(-25)
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 90
            horizontalAlignment: Text.AlignHCenter
            text: root.size + "%"
            color: root.pibble.textColor
            font.family: root.pibble.font
            font.pixelSize: root.pibble.px(14)
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: root.pibble.radius(8)
            color: growArea.containsMouse ? root.pibble.activeTileColor : root.pibble.tileColor
            border.width: 1
            border.color: root.pibble.borderColor

            Text {
                anchors.centerIn: parent
                text: root.pibble.icon("chevron-right")
                color: root.pibble.accentColor
                font.family: root.pibble.iconFont
                font.pixelSize: root.pibble.px(15)
            }
            MouseArea {
                id: growArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.step(25)
            }
        }
    }
}
