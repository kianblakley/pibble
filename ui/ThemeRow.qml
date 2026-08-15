import QtQuick
import "root:/config"
import "root:/services"

// Theme picker: one card per preset plus the two computed schemes
// ("Dynamic" and "Custom"), each showing the palette it would apply.
Item {
    id: root

    property string hint: ""
    width: 780
    height: 80 + (hint ? hintLabel.height + 2 : 0)
    readonly property string current: Settings.theme
    function setVal(v: string) {
        Settings.theme = v;
        Settings.save();
    }

    SettingLabel {
        anchors.left: parent.left
        anchors.verticalCenter: undefined
        y: 6
        content: "Color theme"
    }
    Row {
        anchors.right: parent.right
        height: 28
        spacing: 8

        ResetButton {
            key: "theme"
        }
    }
    SettingHint {
        id: hintLabel
        visible: root.hint !== ""
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        content: root.hint
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 34
        spacing: 8

        Repeater {
            model: Theme.presets

            Rectangle {
                id: card
                required property var modelData
                readonly property var pal: modelData.id === "matugen" ? Theme.dynamic
                    : modelData.id === "custom" ? Theme.custom : modelData
                readonly property bool active: root.current === modelData.id
                width: 80
                height: 80
                radius: Theme.radius(12)
                color: Qt.alpha(Theme.accent, active ? 0.16 : 0.06)
                border.width: active ? 2 : 1
                border.color: active ? Theme.accent : Qt.alpha(Theme.accent, 0.25)

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 5
                        Repeater {
                            model: [card.pal.accent, card.pal.fg, card.pal.muted]
                            Rectangle {
                                required property var modelData
                                width: 18
                                height: 18
                                radius: Theme.radius(5)
                                color: modelData
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.15)
                            }
                        }
                    }
                    ScrambleText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        // the card is a fixed 80x80 and this Column is centred
                        // in it, so the label's own box has to hold still or
                        // the swatches above it drift as the noise rerolls
                        width: restWidth
                        height: restHeight
                        horizontalAlignment: Text.AlignHCenter
                        content: card.modelData.name
                        color: card.active ? Theme.fg : Theme.muted
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.setVal(card.modelData.id)
                }
            }
        }
    }
}
