import QtQuick
import "root:/config"
import "root:/services"

// A label, a ‹ value › stepper and a reset button - the shape almost every
// setting takes. `key` is what SettingsSchema reads, steps and resets.
Item {
    id: root

    property string key
    property string label
    property string hint: ""
    property int valueWidth: 190
    // The controls' total span - ‹ + value + › + reset, gaps included - for
    // anything else in the column that has to line its own right-aligned block
    // up with this row's controls rather than with the column's edge (see
    // ChipRow's targetWidth).
    readonly property real controlsWidth: controls.width
    width: 780
    height: 34 + (hint ? hintLabel.height + 2 : 0)
    Item {
        id: mainLine
        width: parent.width
        height: 34
        SettingLabel {
            anchors.left: parent.left
            // the row's width less the controls opposite, and an 8px gap - the
            // same one the controls keep between themselves
            maxWidth: root.width - controls.width - 8
            content: Strings.tr(root.label)
        }
        Row {
            id: controls
            anchors.right: parent.right
            spacing: 8
            height: parent.height
            StepperButton {
                icon: Icons.chevronLeft
                onPressed: SettingsSchema.adjust(root.key, -1)
            }
            SettingValue {
                content: SettingsSchema.display(root.key)
                width: root.valueWidth
            }
            StepperButton {
                icon: Icons.chevronRight
                onPressed: SettingsSchema.adjust(root.key, 1)
            }
            ResetButton {
                key: root.key
            }
        }
    }
    SettingHint {
        id: hintLabel
        visible: root.hint !== ""
        anchors.top: mainLine.bottom
        anchors.topMargin: 2
        // the whole row: a hint starts at the left edge with nothing to its
        // right, so the column's own width is all the bound it needs
        maxWidth: root.width
        content: Strings.tr(root.hint)
    }
}
