import QtQuick
import "root:/config"
import "root:/services"

// palette editor for the "custom" theme; always shown so the palette
// can be tuned before (or without) switching to it
Item {
    id: root

    width: 780
    height: pickerRow.y + pickerRow.height
    // which of the three swatches the picker below is currently editing
    property string slot: "accent"
    readonly property string slotHex: slot === "fg" ? Settings.customFg : slot === "muted" ? Settings.customMuted : Settings.customAccent
    // intermediate `color`-typed property so we can read Qt's built-in
    // hsvHue/hsvSaturation/hsvValue instead of hand-rolling conversions
    property color slotColorVal: root.slotHex
    // hue is kept as its own state rather than purely derived from the
    // color: it's undefined for achromatic colors (hsvHue reports -1 at
    // zero saturation), and hex is only 8 bits per channel, so
    // round-tripping through it near-losslessly recovers hue everywhere
    // except very close to that zero-saturation edge, where a tiny
    // quantization error swings hue wildly. Resyncing is skipped there
    // (saturation floor below) so dragging the SV square doesn't jitter
    // the hue slider - but it otherwise stays reactive (rather than
    // only resyncing at explicit moments like a slot switch), because
    // the settings file loads asynchronously: this row can finish
    // constructing - and read back the adapter's declared defaults -
    // before the real persisted color has arrived.
    property real hue: 0
    readonly property real sat: slotColorVal.hsvSaturation
    readonly property real val: slotColorVal.hsvValue
    function syncHueFromColor() {
        if (slotColorVal.hsvHue >= 0 && slotColorVal.hsvSaturation > 0.05)
            hue = slotColorVal.hsvHue;
    }
    onSlotColorValChanged: syncHueFromColor()
    Component.onCompleted: syncHueFromColor()

    function setSlotHex(hex: string) {
        switch (slot) {
        case "fg": Settings.customFg = hex; break;
        case "muted": Settings.customMuted = hex; break;
        default: Settings.customAccent = hex; break;
        }
    }
    function setSlotHsv(h: real, s: real, v: real) {
        setSlotHex(Qt.hsva(h, s, v, 1).toString());
    }

    // label sits beside the picker rather than stacked above it - same
    // convention as ThemeRow's label beside its (much shorter) swatch
    // row, just offset less since the picker is a lot taller
    SettingLabel {
        id: label
        anchors.left: parent.left
        anchors.verticalCenter: undefined
        y: 6
        text: "Custom colors"
    }
    Row {
        id: resetRow
        anchors.right: parent.right
        // pinned to the label's vertical center explicitly, rather
        // than relying on the label and a height:28 row happening to
        // line up
        anchors.verticalCenter: label.verticalCenter
        height: 28
        spacing: 8

        ResetButton {
            key: "customColors"
        }
    }

    Row {
        id: pickerRow
        // right-anchored with the same margin as the theme swatches
        // above, so the SV square's left edge lines up with theirs;
        // top-anchored to the reset button's vertical center (not its
        // top), per request
        anchors.right: parent.right
        anchors.rightMargin: 34
        anchors.top: resetRow.verticalCenter
        spacing: 20

        // SV square + hue slider + hex entry, editing whichever swatch
        // is selected on the right
        Column {
            spacing: 16

            Item {
                id: shadeSquare
                width: 330
                height: 330

                Canvas {
                    id: shadeCanvas
                    anchors.fill: parent
                    property real paintHue: root.hue
                    onPaintHueChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        const g1 = ctx.createLinearGradient(0, 0, width, 0);
                        g1.addColorStop(0, "#ffffff");
                        g1.addColorStop(1, Qt.hsva(paintHue, 1, 1, 1).toString());
                        ctx.fillStyle = g1;
                        ctx.fillRect(0, 0, width, height);
                        const g2 = ctx.createLinearGradient(0, 0, 0, height);
                        g2.addColorStop(0, "rgba(0,0,0,0)");
                        g2.addColorStop(1, "#000000");
                        ctx.fillStyle = g2;
                        ctx.fillRect(0, 0, width, height);
                    }
                }
                MouseArea {
                    id: shadeArea
                    anchors.fill: parent
                    preventStealing: true
                    function apply(mx: real, my: real) {
                        const s = Math.max(0, Math.min(1, mx / width));
                        const v = Math.max(0, Math.min(1, 1 - my / height));
                        root.setSlotHsv(root.hue, s, v);
                    }
                    onPressed: mouse => shadeArea.apply(mouse.x, mouse.y)
                    onPositionChanged: mouse => { if (pressed) shadeArea.apply(mouse.x, mouse.y); }
                    onReleased: Settings.save()
                }
                // "circle" crosshair: a white ring with a thin dark
                // outer ring for contrast against light colors
                Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.45)
                    x: root.sat * shadeSquare.width - width / 2
                    y: (1 - root.val) * shadeSquare.height - height / 2
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: "#ffffff"
                    }
                }
            }

            Item {
                id: hueSlider
                width: shadeSquare.width
                height: 22

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        // deliberately desaturated so the bar reads
                        // softer than the primaries it actually picks -
                        // the hue it selects is unaffected, since that
                        // comes from the x position, not this fill
                        GradientStop { position: 0.0; color: Qt.hsva(0 / 6, 0.5, 0.85, 1) }
                        GradientStop { position: 0.17; color: Qt.hsva(1 / 6, 0.5, 0.85, 1) }
                        GradientStop { position: 0.33; color: Qt.hsva(2 / 6, 0.5, 0.85, 1) }
                        GradientStop { position: 0.5; color: Qt.hsva(3 / 6, 0.5, 0.85, 1) }
                        GradientStop { position: 0.67; color: Qt.hsva(4 / 6, 0.5, 0.85, 1) }
                        GradientStop { position: 0.83; color: Qt.hsva(5 / 6, 0.5, 0.85, 1) }
                        GradientStop { position: 1.0; color: Qt.hsva(6 / 6, 0.5, 0.85, 1) }
                    }
                }
                MouseArea {
                    id: hueArea
                    anchors.fill: parent
                    preventStealing: true
                    function apply(mx: real) {
                        const h = Math.max(0, Math.min(1, mx / width));
                        // set directly rather than waiting for the
                        // round-tripped color to report it back: at
                        // zero saturation (e.g. the Mono defaults) hue
                        // has no effect on the resulting color at all,
                        // so the handle would otherwise never move
                        root.hue = h;
                        root.setSlotHsv(h, root.sat, root.val);
                    }
                    onPressed: mouse => hueArea.apply(mouse.x)
                    onPositionChanged: mouse => { if (pressed) hueArea.apply(mouse.x); }
                    onReleased: Settings.save()
                }
                Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.hue * hueSlider.width - width / 2
                    color: Qt.hsva(root.hue, 0.5, 0.85, 1)
                    border.width: 2
                    border.color: "#ffffff"
                }
            }

            Rectangle {
                width: shadeSquare.width
                height: 42
                radius: 8
                color: Qt.alpha(Theme.accent, 0.06)
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.2)

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.slotHex
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "#"
                        color: Qt.alpha(Theme.muted, 0.6)
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
                    }
                    TextInput {
                        id: hexInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: 220
                        text: root.slotHex.replace("#", "").toUpperCase()
                        color: Theme.fg
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
                        selectByMouse: true
                        maximumLength: 6
                        // the binding above (declarative `text:`) only
                        // reacts to slotHex/slot changes; user keystrokes
                        // set `text` directly, so gate on activeFocus to
                        // tell the two apart and avoid feeding a half
                        // typed hex back into Settings
                        onTextChanged: {
                            if (!activeFocus)
                                return;
                            const clean = text.replace(/[^0-9a-fA-F]/g, "").toUpperCase();
                            if (clean !== text) {
                                text = clean;
                                return;
                            }
                            if (clean.length === 6)
                                root.setSlotHex("#" + clean);
                        }
                        onEditingFinished: {
                            Settings.save();
                            text = Qt.binding(() => root.slotHex.replace("#", "").toUpperCase());
                        }
                    }
                }
            }
        }

        // Accent / Text / Muted slots, top-aligned like the swatch
        // picker they sit under
        Column {
            spacing: 10

            Repeater {
                model: [
                    { key: "accent", label: "Accent" },
                    { key: "fg", label: "Text" },
                    { key: "muted", label: "Muted" }
                ]

                Rectangle {
                    id: slotChip
                    required property var modelData
                    readonly property bool active: root.slot === modelData.key
                    readonly property string hex: modelData.key === "fg" ? Settings.customFg : modelData.key === "muted" ? Settings.customMuted : Settings.customAccent
                    width: 170
                    height: 46
                    radius: 10
                    color: Qt.alpha(Theme.accent, active ? 0.16 : 0.06)
                    border.width: active ? 2 : 1
                    border.color: active ? Theme.accent : Qt.alpha(Theme.accent, 0.25)

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: slotChip.hex
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.15)
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: slotChip.modelData.label
                                color: slotChip.active ? Theme.fg : Theme.muted
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
                            }
                            Text {
                                text: slotChip.hex.toUpperCase()
                                color: Qt.alpha(Theme.muted, 0.8)
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.slot = slotChip.modelData.key
                    }
                }
            }
        }
    }
}
