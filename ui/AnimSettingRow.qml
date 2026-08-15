import QtQuick
import "root:/config"
import "root:/services"

// A SettingRow with a live preview of what the value does standing under
// it - the shape every row on the Animations tab takes, and the shape the tile
// picker already takes on the Pages tab (a header line, then the thing itself).
// Same `key` contract as SettingRow: SettingsSchema reads, steps and resets it.
//
// The preview is the row's default property, so a caller writes the box it
// wants inside the row rather than naming it through a property:
//
//   AnimSettingRow { key: "volAnim"; label: "Volume"; VolumePreview {} }
Column {
    id: root

    default property alias preview: previewSlot.data
    property string key
    property string label
    property int valueWidth: 190
    width: 780
    spacing: 8
    // Where the preview sits: centred under the ‹ › stepper it answers to,
    // rather than under the column. The 34 is the reset button this row's
    // controls end with, which the preview is no more aligned to than the
    // chip rows elsewhere are (see ChipRow's targetWidth): what a preview
    // stands under is the pair of arrows that change it.
    readonly property real previewShift: root.width / 2 - 34 - (controls.width - 34) / 2

    Item {
        width: parent.width
        height: 34

        SettingLabel {
            anchors.left: parent.left
            content: root.label
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
    // sized to whatever preview it was handed (each one centres itself in
    // here), so a row is exactly as tall as the thing it demonstrates. The
    // slot keeps the column's full width and is shifted whole, rather than
    // being narrowed onto the stepper: a preview only ever has to centre
    // itself in its parent, and a slot narrowed to the stepper's width would
    // pull every preview in from its edges too.
    Item {
        id: previewSlot
        x: root.previewShift
        width: parent.width
        // the preview's *bottom* edge, not its height: a preview whose picture
        // starts partway down its stage is pulled up by that inset (see
        // AnimPreview.contentTop), so the empty band it carries is spent
        // closing the gap to the stepper rather than added to the column.
        height: childrenRect.y + childrenRect.height
    }
}
