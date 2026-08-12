import QtQuick

// This page's own tab in pibble's Settings, reached from main.qml's
// `settingsTab` Component. main.qml owns the settings' persisted copy;
// this only reports what was clicked via `picked`.
Item {
    id: root

    required property var pibble
    required property string chevronLeft
    required property string chevronRight
    property bool startMonday: true
    property bool showWeeks: true
    signal picked(string key, bool value)

    function px(size: int): int {
        return Math.round(size * pibble.fontScale);
    }

    width: 780
    height: rows.implicitHeight

    Column {
        id: rows
        width: parent.width
        spacing: 12

        Repeater {
            model: [
                {
                    key: "startMonday",
                    label: "Week starts on",
                    current: root.startMonday,
                    options: [{ label: "Sunday", value: false }, { label: "Monday", value: true }]
                },
                {
                    key: "showWeeks",
                    label: "Week numbers",
                    current: root.showWeeks,
                    options: [{ label: "Off", value: false }, { label: "On", value: true }]
                }
            ]

            Item {
                id: settingRow
                required property var modelData

                readonly property var option: modelData.options.find(o => o.value === modelData.current)

                function step(delta: int): void {
                    const options = modelData.options;
                    const at = options.indexOf(option);
                    root.picked(modelData.key, options[(at + delta + options.length) % options.length].value);
                }

                width: rows.width
                height: 34

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: settingRow.modelData.label
                    color: root.pibble.secondaryTextColor
                    font.family: root.pibble.font
                    font.pixelSize: root.px(14)
                }
                Row {
                    anchors.right: parent.right
                    height: parent.height
                    spacing: 8

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 8
                        color: prevArea.containsMouse ? root.pibble.tileBgActive : root.pibble.tileBg
                        border.width: 1
                        border.color: root.pibble.tileBorder

                        Text {
                            anchors.centerIn: parent
                            text: root.chevronLeft
                            color: root.pibble.accent
                            font.family: root.pibble.iconFont
                            font.pixelSize: root.px(15)
                        }
                        MouseArea {
                            id: prevArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: settingRow.step(-1)
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 90
                        horizontalAlignment: Text.AlignHCenter
                        text: settingRow.option.label
                        color: root.pibble.textColor
                        font.family: root.pibble.font
                        font.pixelSize: root.px(14)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 8
                        color: nextArea.containsMouse ? root.pibble.tileBgActive : root.pibble.tileBg
                        border.width: 1
                        border.color: root.pibble.tileBorder

                        Text {
                            anchors.centerIn: parent
                            text: root.chevronRight
                            color: root.pibble.accent
                            font.family: root.pibble.iconFont
                            font.pixelSize: root.px(15)
                        }
                        MouseArea {
                            id: nextArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: settingRow.step(1)
                        }
                    }
                }
            }
        }
    }
}
