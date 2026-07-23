import QtQuick
// see the Settings.qml note for why this import has to be explicit and
// aliased instead of a bare `Settings {}` reference
import "." as Local

// Example custom page for pibble: a click counter with Click/Reset tiles.
// See DOCS.md's "API reference" for the pibble contract exercised here.
Item {
    id: root
    width: 280
    height: 260

    // assigned by pibble after loading; register the tile-entrance
    // animation once it is (onPibbleChanged, not Component.onCompleted,
    // since pibble isn't assigned until the whole page has loaded)
    property var pibble: null
    onPibbleChanged: {
        pibble.tileIn(clickTile, 0, 2);
        pibble.tileIn(resetTile, 1, 2);
    }

    // true while this page is the one on screen; written by pibble
    property bool active: false

    // per-page persistent settings, namespaced automatically by pibble
    property int clicks: pibble ? pibble.getSetting("clicks", 0) : 0
    property int incrementBy: pibble ? pibble.getSetting("incrementBy", 1) : 1

    function bump() {
        clicks += incrementBy;
        pibble.setSetting("clicks", clicks);
    }
    function reset() {
        clicks = 0;
        pibble.setSetting("clicks", 0);
    }
    function setIncrement(value) {
        incrementBy = value;
        pibble.setSetting("incrementBy", value);
    }

    Column {
        anchors.centerIn: parent
        spacing: 16

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(root.clicks)
            color: root.pibble.fg
            font.family: root.pibble.font
            // same size/weight as the launcher's own big clock (see
            // shell.qml's clockLine.bigTime)
            font.pixelSize: Math.round(120 * root.pibble.fontScale)
            font.weight: Font.DemiBold
        }

        Row {
            id: buttonRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Rectangle {
                id: clickTile
                width: 90
                height: 34
                radius: 10
                opacity: 0
                color: clickArea.containsMouse ? root.pibble.fillActive : root.pibble.fill
                border.width: 1
                border.color: root.pibble.border

                Text {
                    anchors.centerIn: parent
                    text: "Click"
                    color: root.pibble.accent
                    font.family: root.pibble.font
                    font.pixelSize: Math.round(13 * root.pibble.fontScale)
                }
                MouseArea {
                    id: clickArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.bump()
                }
            }

            Rectangle {
                id: resetTile
                width: 90
                height: 34
                radius: 10
                opacity: 0
                color: resetArea.containsMouse ? root.pibble.fillActive : root.pibble.fill
                border.width: 1
                border.color: root.pibble.border

                Text {
                    anchors.centerIn: parent
                    text: "Reset"
                    color: root.pibble.accent
                    font.family: root.pibble.font
                    font.pixelSize: Math.round(13 * root.pibble.fontScale)
                }
                MouseArea {
                    id: resetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.reset()
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "+" + root.incrementBy + " per click - change it in Settings"
            color: root.pibble.muted
            font.family: root.pibble.font
            font.pixelSize: Math.round(11 * root.pibble.fontScale)
        }
    }

    // gives this page its own Settings tab, next to General/Pages/etc.
    readonly property Component settingsTab: Component {
        Local.Settings {
            pibble: root.pibble
            incrementBy: root.incrementBy
            onIncrementChanged: value => root.setIncrement(value)
        }
    }
}
