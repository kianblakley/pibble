import QtQuick

// Sibling component for main.qml, reached via `Local.Settings {}` there
// (see the `import "." as Local` note in main.qml) - an unqualified
// `Settings {}` would fail to resolve ("Settings is not a type") even
// though this file sits right next to main.qml, since quickshell's own
// qmldir handling shadows the implicit same-directory import a plain
// Qt/QML app would get for free.
Item {
    id: row
    property var pibble: null
    property int incrementBy: 1
    signal incrementChanged(int value)

    width: 780
    height: 34

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Increment by"
        color: row.pibble.muted
        font.family: row.pibble.font
        font.pixelSize: Math.round(14 * row.pibble.fontScale)
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Rectangle {
            width: 28
            height: 28
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: minusArea.containsMouse ? row.pibble.fillActive : row.pibble.fill
            border.width: 1
            border.color: row.pibble.border

            Text {
                anchors.centerIn: parent
                text: "‹"
                color: row.pibble.accent
                font.family: row.pibble.font
                font.pixelSize: Math.round(15 * row.pibble.fontScale)
                font.bold: true
            }
            MouseArea {
                id: minusArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: row.incrementChanged(Math.max(1, row.incrementBy - 1))
            }
        }

        Text {
            width: 24
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: String(row.incrementBy)
            color: row.pibble.fg
            font.family: row.pibble.font
            font.pixelSize: Math.round(14 * row.pibble.fontScale)
        }

        Rectangle {
            width: 28
            height: 28
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: plusArea.containsMouse ? row.pibble.fillActive : row.pibble.fill
            border.width: 1
            border.color: row.pibble.border

            Text {
                anchors.centerIn: parent
                text: "›"
                color: row.pibble.accent
                font.family: row.pibble.font
                font.pixelSize: Math.round(15 * row.pibble.fontScale)
                font.bold: true
            }
            MouseArea {
                id: plusArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: row.incrementChanged(Math.min(10, row.incrementBy + 1))
            }
        }
    }
}
