import QtQuick
// the same controls the built-in tabs are built from, so these rows keep
// matching them (size, spacing, type scale) without restating any of it
import "root:/services"
import "root:/ui"

// This page's own tab in pibble's Settings, reached from main.qml's
// `settingsTab` Component. It only reports what was clicked - main.qml owns
// both the property and its persisted copy, so there's one writer for each.
Item {
    id: root

    required property var pibble
    property bool startMonday: true
    property bool showWeeks: true
    signal picked(string key, bool value)

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

                // wraps, so a two-value setting steps the same either way
                function step(delta: int): void {
                    const options = modelData.options;
                    const at = options.indexOf(option);
                    root.picked(modelData.key, options[(at + delta + options.length) % options.length].value);
                }

                width: rows.width
                height: 34

                SettingLabel {
                    anchors.left: parent.left
                    text: settingRow.modelData.label
                }
                Row {
                    anchors.right: parent.right
                    height: parent.height
                    spacing: 8

                    StepperButton {
                        icon: Icons.chevronLeft
                        onPressed: settingRow.step(-1)
                    }
                    SettingValue {
                        text: settingRow.option.label
                        width: Metrics.shortValueWidth
                    }
                    StepperButton {
                        icon: Icons.chevronRight
                        onPressed: settingRow.step(1)
                    }
                }
            }
        }
    }
}
