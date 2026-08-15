import QtQuick
import "root:/config"
import "root:/services"

// A SettingRow with a live preview of what the value does centred underneath
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
    // everything this row is besides the preview under it - the header line
    // and the gap over the preview. Read by the Animations tab, which sizes
    // every preview off the height its rows *don't* take (see previewUnit).
    readonly property real fixedHeight: 34 + root.spacing

    Item {
        width: parent.width
        height: 34

        SettingLabel {
            anchors.left: parent.left
            content: root.label
        }
        Row {
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
    // here), so a row is exactly as tall as the thing it demonstrates
    Item {
        id: previewSlot
        width: parent.width
        height: childrenRect.height
    }
}
