import QtQuick
import "root:/config"
import "root:/services"
import "root:/ui"
import "root:/launcher"

// A label, a field to type a setting into, and a reset button - for the
// settings that are a free string (a path, a URL, a command) rather than one
// of a few choices. `key` is the Settings property it edits and what the reset
// button resets; the field writes back when editing finishes, not per key.
Item {
    id: root

    property string key
    property string label
    property string hint: ""
    // shown in the empty field: what goes there, or what empty means
    property string placeholder: ""
    readonly property int fieldWidth: 444

    width: 780
    height: 38 + (root.hint ? hintLabel.height + 2 : 0)

    Item {
        id: mainLine
        width: parent.width
        height: 38

        SettingLabel {
            anchors.left: parent.left
            maxWidth: parent.width - 34 - root.fieldWidth - 8
            content: Strings.tr(root.label)
        }
        ResetButton {
            key: root.key
            anchors.right: parent.right
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            width: root.fieldWidth
            height: 34
            radius: Theme.radius(8)
            color: Qt.alpha(Theme.accent, field.activeFocus ? 0.16 : 0.08)
            border.width: 1
            border.color: field.activeFocus ? Theme.accent : Qt.alpha(Theme.accent, 0.33)

            ScrambleText {
                anchors.fill: parent
                anchors.margins: 8
                verticalAlignment: Text.AlignVCenter
                visible: field.text.length === 0
                content: Strings.tr(root.placeholder)
                color: Theme.muted
                elide: Text.ElideRight
                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
            }
            TextInput {
                id: field
                anchors.fill: parent
                anchors.margins: 8
                verticalAlignment: TextInput.AlignVCenter
                text: Settings[root.key] ?? ""
                color: Theme.fg
                clip: true
                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                onEditingFinished: {
                    if (text !== Settings[root.key]) {
                        Settings[root.key] = text;
                        Settings.save();
                    }
                    LauncherState.focusInput();
                }
                Keys.onEscapePressed: LauncherState.focusInput()
                // a reset, or a hand edit to settings.json, lands in the field
                // too - the binding above broke the first time it was typed in
                Connections {
                    target: Settings
                    function onSaveRequested(): void {
                        if (!field.activeFocus)
                            field.text = Settings[root.key] ?? "";
                    }
                    function onLoaded(): void {
                        if (!field.activeFocus)
                            field.text = Settings[root.key] ?? "";
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.IBeamCursor
            }
        }
    }
    SettingHint {
        id: hintLabel
        visible: root.hint !== ""
        anchors.top: mainLine.bottom
        anchors.topMargin: 2
        maxWidth: root.width
        content: Strings.tr(root.hint)
    }
}
