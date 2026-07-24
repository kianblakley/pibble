import QtQuick
import QtQuick.Effects
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import Quickshell.Services.UPower

ShellRoot {
    id: root

    component SLabel: Text {
        color: root.muted
        font { family: root.mono; pixelSize: root.fs(14) }
        anchors.verticalCenter: parent.verticalCenter
    }
    component SBtn: Rectangle {
        id: sbtn
        property string label
        signal pressed
        width: 28
        height: 28
        radius: 8
        color: Qt.alpha(root.accent, btnArea.containsMouse ? 0.22 : 0.11)
        border.width: 1
        border.color: Qt.alpha(root.accent, 0.33)
        anchors.verticalCenter: parent.verticalCenter
        Text {
            anchors.centerIn: parent
            text: sbtn.label
            color: root.accent
            font { family: root.mono; pixelSize: root.fs(15); weight: Font.Bold }
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sbtn.pressed()
        }
    }
    component SValue: Text {
        color: root.fg
        width: 90
        horizontalAlignment: Text.AlignHCenter
        font { family: root.mono; pixelSize: root.fs(14) }
        anchors.verticalCenter: parent.verticalCenter
    }

    component ThemeRow: Item {
        id: tr
        property string sub: ""
        width: 780
        height: 80 + (sub ? trSub.implicitHeight + 2 : 0)
        readonly property string current: cfg.theme
        function setVal(v: string) {
            cfg.theme = v;
            root.saveSettings();
        }

        SLabel {
            anchors.left: parent.left
            anchors.verticalCenter: undefined
            y: 6
            text: "Color theme"
        }
        Row {
            anchors.right: parent.right
            height: 28
            spacing: 8

            SReset {
                key: "theme"
            }
        }
        SSub {
            id: trSub
            visible: tr.sub !== ""
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: tr.sub
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 34
            spacing: 8

            Repeater {
                model: root.themes

                Rectangle {
                    id: trCard
                    required property var modelData
                    readonly property var pal: modelData.id === "matugen" ? root.dynTheme
                        : modelData.id === "custom" ? root.customTheme : modelData
                    readonly property bool active: tr.current === modelData.id
                    width: 80
                    height: 80
                    radius: 12
                    color: Qt.alpha(root.accent, active ? 0.16 : 0.06)
                    border.width: active ? 2 : 1
                    border.color: active ? root.accent : Qt.alpha(root.accent, 0.25)

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 5
                            Repeater {
                                model: [trCard.pal.accent, trCard.pal.fg, trCard.pal.muted]
                                Rectangle {
                                    required property var modelData
                                    width: 18
                                    height: 18
                                    radius: 5
                                    color: modelData
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.15)
                                }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: trCard.modelData.name
                            color: trCard.active ? root.fg : root.muted
                            font { family: root.mono; pixelSize: root.fs(12) }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: tr.setVal(trCard.modelData.id)
                    }
                }
            }
        }
    }

    // palette editor for the "custom" theme; always shown so the palette
    // can be tuned before (or without) switching to it
    component CustomColorRow: Item {
        id: ccr
        width: 780
        height: pickerRow.y + pickerRow.height
        // which of the three swatches the picker below is currently editing
        property string slot: "accent"
        readonly property string slotHex: slot === "fg" ? cfg.customFg : slot === "muted" ? cfg.customMuted : cfg.customAccent
        // intermediate `color`-typed property so we can read Qt's built-in
        // hsvHue/hsvSaturation/hsvValue instead of hand-rolling conversions
        property color slotColorVal: ccr.slotHex
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
            case "fg": cfg.customFg = hex; break;
            case "muted": cfg.customMuted = hex; break;
            default: cfg.customAccent = hex; break;
            }
        }
        function setSlotHsv(h: real, s: real, v: real) {
            setSlotHex(Qt.hsva(h, s, v, 1).toString());
        }

        // label sits beside the picker rather than stacked above it - same
        // convention as ThemeRow's label beside its (much shorter) swatch
        // row, just offset less since the picker is a lot taller
        SLabel {
            id: ccrLabel
            anchors.left: parent.left
            anchors.verticalCenter: undefined
            y: 6
            text: "Custom colors"
        }
        Row {
            id: ccrResetRow
            anchors.right: parent.right
            // pinned to the label's vertical center explicitly, rather
            // than relying on the label and a height:28 row happening to
            // line up
            anchors.verticalCenter: ccrLabel.verticalCenter
            height: 28
            spacing: 8

            SReset {
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
            anchors.top: ccrResetRow.verticalCenter
            spacing: 20

            // SV square + hue slider + hex entry, editing whichever swatch
            // is selected on the right
            Column {
                spacing: 16

                Item {
                    id: svSquare
                    width: 330
                    height: 330

                    Canvas {
                        id: svCanvas
                        anchors.fill: parent
                        property real paintHue: ccr.hue
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
                        id: svArea
                        anchors.fill: parent
                        preventStealing: true
                        function apply(mx: real, my: real) {
                            const s = Math.max(0, Math.min(1, mx / width));
                            const v = Math.max(0, Math.min(1, 1 - my / height));
                            ccr.setSlotHsv(ccr.hue, s, v);
                        }
                        onPressed: mouse => svArea.apply(mouse.x, mouse.y)
                        onPositionChanged: mouse => { if (pressed) svArea.apply(mouse.x, mouse.y); }
                        onReleased: root.saveSettings()
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
                        x: ccr.sat * svSquare.width - width / 2
                        y: (1 - ccr.val) * svSquare.height - height / 2
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
                    width: svSquare.width
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
                            ccr.hue = h;
                            ccr.setSlotHsv(h, ccr.sat, ccr.val);
                        }
                        onPressed: mouse => hueArea.apply(mouse.x)
                        onPositionChanged: mouse => { if (pressed) hueArea.apply(mouse.x); }
                        onReleased: root.saveSettings()
                    }
                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: ccr.hue * hueSlider.width - width / 2
                        color: Qt.hsva(ccr.hue, 0.5, 0.85, 1)
                        border.width: 2
                        border.color: "#ffffff"
                    }
                }

                Rectangle {
                    width: svSquare.width
                    height: 42
                    radius: 8
                    color: Qt.alpha(root.accent, 0.06)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.2)

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
                            color: ccr.slotHex
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.15)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "#"
                            color: Qt.alpha(root.muted, 0.6)
                            font { family: root.mono; pixelSize: root.fs(12) }
                        }
                        TextInput {
                            id: hexInput
                            anchors.verticalCenter: parent.verticalCenter
                            width: 220
                            text: ccr.slotHex.replace("#", "").toUpperCase()
                            color: root.fg
                            font { family: root.mono; pixelSize: root.fs(12) }
                            selectByMouse: true
                            maximumLength: 6
                            // the binding above (declarative `text:`) only
                            // reacts to slotHex/slot changes; user keystrokes
                            // set `text` directly, so gate on activeFocus to
                            // tell the two apart and avoid feeding a half
                            // typed hex back into cfg
                            onTextChanged: {
                                if (!activeFocus)
                                    return;
                                const clean = text.replace(/[^0-9a-fA-F]/g, "").toUpperCase();
                                if (clean !== text) {
                                    text = clean;
                                    return;
                                }
                                if (clean.length === 6)
                                    ccr.setSlotHex("#" + clean);
                            }
                            onEditingFinished: {
                                root.saveSettings();
                                text = Qt.binding(() => ccr.slotHex.replace("#", "").toUpperCase());
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
                        readonly property bool active: ccr.slot === modelData.key
                        readonly property string hex: modelData.key === "fg" ? cfg.customFg : modelData.key === "muted" ? cfg.customMuted : cfg.customAccent
                        width: 170
                        height: 46
                        radius: 10
                        color: Qt.alpha(root.accent, active ? 0.16 : 0.06)
                        border.width: active ? 2 : 1
                        border.color: active ? root.accent : Qt.alpha(root.accent, 0.25)

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
                                    color: slotChip.active ? root.fg : root.muted
                                    font { family: root.mono; pixelSize: root.fs(12) }
                                }
                                Text {
                                    text: slotChip.hex.toUpperCase()
                                    color: Qt.alpha(root.muted, 0.8)
                                    font { family: root.mono; pixelSize: root.fs(12) }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: ccr.slot = slotChip.modelData.key
                        }
                    }
                }
            }
        }
    }

    // muted helper line rendered directly beneath the row it explains
    component SSub: Text {
        color: Qt.alpha(root.muted, 0.7)
        font { family: root.mono; pixelSize: root.fs(11) }
    }
    component SettingRow: Item {
        id: sr
        property string key
        property string label
        property string sub: ""
        property int valueWidth: 90
        width: 780
        height: 34 + (sub ? srSub.implicitHeight + 2 : 0)
        Item {
            id: srMain
            width: parent.width
            height: 34
            SLabel {
                anchors.left: parent.left
                text: sr.label
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                height: parent.height
                SBtn {
                    label: "‹"
                    onPressed: win.adjustSetting(sr.key, -1)
                }
                SValue {
                    text: win.settingValue(sr.key)
                    width: sr.valueWidth
                }
                SBtn {
                    label: "›"
                    onPressed: win.adjustSetting(sr.key, 1)
                }
                SReset {
                    key: sr.key
                }
            }
        }
        SSub {
            id: srSub
            visible: sr.sub !== ""
            anchors.top: srMain.bottom
            anchors.topMargin: 2
            text: sr.sub
        }
    }

    readonly property string defaultWallCommand: 'awww img --transition-type fade --transition-duration 1 "$WALL"'

    // pages whose grid size is editable via the tile picker on the Grids
    // settings tab, and the bounds adjustSetting()/the old ‹›-based rows
    // enforced (kept in sync with those cases below)
    readonly property var gridTargets: ({
        apps: { label: "Apps", colsProp: "appsCols", rowsProp: "appsRows", minCols: 3, maxCols: 6, minRows: 2, maxRows: 6, resetKey: "appsGrid" },
        walls: { label: "Wallpapers", colsProp: "wallsCols", rowsProp: "wallsRows", minCols: 2, maxCols: 4, minRows: 2, maxRows: 4, resetKey: "wallsGrid" },
        clips: { label: "Clipboard", colsProp: "clipsCols", rowsProp: "clipsRows", minCols: 2, maxCols: 4, minRows: 2, maxRows: 4, resetKey: "clipsGrid" }
    })
    // largest cols/rows any target needs — the tile picker's canvas is
    // always sized to this, so switching targets never resizes it; only
    // which tiles are in bounds (and thus visible) changes. Cols is also
    // floored at wallsBarSlots so the walls target's "windows" bar picker
    // (see GridSizeTiles) always has a real tile column for every bar.
    readonly property int wallsBarSlots: 9
    readonly property int gridPickerMaxCols: Math.max(root.wallsBarSlots, ...Object.values(root.gridTargets).map(t => t.maxCols))
    readonly property int gridPickerMaxRows: Math.max(...Object.values(root.gridTargets).map(t => t.maxRows))

    component SReset: Rectangle {
        id: sreset
        property string key
        width: 24
        height: 24
        radius: 12
        color: "transparent"
        anchors.verticalCenter: parent.verticalCenter
        Text {
            anchors.centerIn: parent
            text: root.ti.refresh
            color: resetArea.containsMouse ? root.fg : root.muted
            font { family: root.iconFont; pixelSize: root.fs(13) }
        }
        MouseArea {
            id: resetArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: win.resetSetting(sreset.key)
        }
    }

    // row of checkbox chips (label + tick box) toggling boolean flags in a
    // cfg.* object, e.g. the Flyouts/Pibble alerts rows in the flyouts tab
    component ChipRow: Row {
        id: chipRow
        property var items // [{id, label}]
        property var isOn // function(id): bool
        property var toggle // function(id): void
        spacing: 40

        Repeater {
            model: chipRow.items

            Item {
                id: chip
                required property var modelData
                readonly property bool on: chipRow.isOn(modelData.id)
                width: chipBox.width + 6 + chipText.implicitWidth
                height: 28
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    id: chipBox
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    radius: 4
                    color: chip.on ? Qt.alpha(root.accent, 0.85) : "transparent"
                    border.width: 1
                    border.color: chip.on ? root.accent : Qt.alpha(root.muted, 0.6)

                    Text {
                        anchors.centerIn: parent
                        visible: chip.on
                        text: root.ti.check
                        color: "#141210"
                        font { family: root.iconFont; pixelSize: 13 }
                    }
                }
                Text {
                    id: chipText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: chipBox.right
                    anchors.leftMargin: 6
                    text: chip.modelData.label
                    color: chip.on ? root.fg : root.muted
                    font { family: root.mono; pixelSize: root.fs(12) }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: chipRow.toggle(chip.modelData.id)
                }
            }
        }
    }

    // ---------- custom page contract ----------
    // One of these is created per enabled custom page (see the "Custom
    // pages" render block below) and handed to the loaded file's root item
    // as `pibble`, if it declares that property — every member here is
    // optional to use. Properties are live bindings (theme/anim-style
    // changes propagate the same as they do to any built-in pane); the
    // functions are the only sanctioned way in, since cfg/root/win
    // themselves are never exposed — a page can't reach into settings it
    // doesn't own or call internal launcher functions.
    //
    // The other direction — a page contributing to pibble, rather than the
    // other way round — goes through one more property on the same root
    // item, read by win.customSettingsTabs (see there for details) rather
    // than written by PageContext: a `settingsTab` Component gets the page
    // its own tab in Settings, alongside General/Pages/Keybindings/
    // Flyouts, labeled after the page's own folder name (capitalized) —
    // not something the page declares itself.
    // A page gets exactly this and nothing else: enough to theme itself
    // consistently and persist its own data. Some things that used to
    // live here (close/openSettings/notify/copyToClipboard, the
    // animation-parameter set, a `ti` icon-glyph map, iconFont itself,
    // surface) are gone because they were reachable another way already
    // (the keybind closes the launcher; notify-send/Quickshell.clipboardText
    // are plain Quickshell, no wrapper needed), asked a page to reproduce
    // pibble's own visual rhythm exactly (which isn't something most pages
    // need and is cheap for the ones that do want it to just build
    // themselves off `active`), or (iconFont, surface) didn't correspond
    // to any real per-page use once the built-in icon glyph map was cut.
    // fill/fillActive/border below are the opposite case: kept (and
    // precomputed, not left as bare alpha numbers) because there's no way
    // for a page to discover or reproduce these specific values other than
    // reading this file.
    component PageContext: QtObject {
        id: pageCtx
        // `required` (must be supplied at construction, see the "Custom
        // pages" render block below) but not `readonly` — QML doesn't
        // allow both on the same property. Stays mutable after
        // construction as a result; nothing a page does should ever
        // reassign it, since getSetting/setSetting's namespacing depends
        // on it never changing after the host sets it.
        required property string pageId
        readonly property color accent: root.accent
        readonly property color fg: root.fg
        readonly property color muted: root.muted
        // the shell's text font
        readonly property string font: root.mono
        readonly property real fontScale: cfg.fontScale
        // the fill/border colors the built-in Apps/Walls/Clips grids and
        // Settings buttons round their tiles with — precomputed, not a
        // bare alpha number, since the number alone is only ever used one
        // way (Qt.alpha(accent, thatNumber)) and precomputing means a
        // future change to the actual formula (not just the number) would
        // still reach every page using these, not just ones re-derived by
        // hand. The built-ins' own radius ranges 8-19px scaled to tile
        // size, not one constant, so there's no equivalent radius property —
        // pick whatever radius suits your own tile.
        readonly property color fill: Qt.alpha(root.accent, 0.11)
        readonly property color fillActive: Qt.alpha(root.accent, 0.22)
        readonly property color border: Qt.alpha(root.accent, 0.33)
        // true from the moment this page becomes the one on screen until
        // it's navigated away from (Tab, Escape, picking another page) —
        // mirrors what every built-in pane gates its own entrance
        // animations on (see win.pane). Also written directly onto the
        // page's own root item (if it declares `active`), since a
        // binding alone can't run code — see that property's own comment
        // in the "Custom pages" render block below.
        readonly property bool active: win.pane === pageId
        readonly property bool shown: win.shown
        // One call gives an item the built-in grids' own tile-entrance
        // rhythm (see cfg.animStyle, "Transitions" in Settings > Grids):
        // pop in from a smaller/lower/transparent starting state, staggered
        // by `slot` among `cols` columns if the style calls for a stagger.
        // Everything (the animation objects, restarting it whenever this
        // page becomes active again) is owned here — a page never touches
        // a SequentialAnimation or hears about win.animFromScale/animDur/
        // etc directly, so it can't get any of that wrong. `slot`/`cols`
        // default to 0/1 (no stagger) for a page with just one tile; pass
        // them for a real grid the same way the built-ins index their own
        // (row-major, 0-based).
        function tileIn(item, slot, cols) {
            if (!item)
                return;
            const s = slot ?? 0;
            const c = cols ?? 1;
            let rec = tileRegistry.find(r => r.item === item);
            if (!rec) {
                // a Translate in transform, not item.y itself, so this
                // never fights whatever actually positions the item
                // (anchors, a Row/Column, explicit bindings, ...)
                const offset = tileOffsetFactory.createObject(item, {});
                item.transform = (item.transform ?? []).concat([offset]);
                const spring = tileSpringFactory.createObject(item, { pibbleItem: item, pibbleOffset: offset, pibbleSlot: s, pibbleCols: c });
                rec = { item, spring };
                tileRegistry.push(rec);
            } else {
                rec.spring.pibbleSlot = s;
                rec.spring.pibbleCols = c;
            }
            rec.spring.restart();
        }
        // tileIn() bookkeeping below — not part of the documented pibble
        // contract (see DOCS.md), just what tileIn() itself needs to
        // remember which items to re-spring when this page becomes active
        // again (see onActiveChanged).
        property var tileRegistry: []
        onActiveChanged: if (active)
            tileRegistry.forEach(r => r.spring.restart())
        readonly property Component tileOffsetFactory: Component {
            Translate {}
        }
        readonly property Component tileSpringFactory: Component {
            SequentialAnimation {
                id: spring
                property var pibbleItem: null
                property var pibbleOffset: null
                property int pibbleSlot: 0
                property int pibbleCols: 1
                PropertyAction { target: spring.pibbleItem; property: "opacity"; value: 0 }
                PropertyAction { target: spring.pibbleItem; property: "scale"; value: win.animFromScale }
                PropertyAction { target: spring.pibbleOffset; property: "y"; value: win.animFromY }
                PauseAnimation { duration: win.animDelay(spring.pibbleSlot, spring.pibbleCols) }
                ParallelAnimation {
                    NumberAnimation { target: spring.pibbleItem; property: "opacity"; to: 1; duration: win.animFadeDur; easing.type: Easing.OutCubic }
                    NumberAnimation { target: spring.pibbleItem; property: "scale"; to: 1; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                    NumberAnimation { target: spring.pibbleOffset; property: "y"; to: 0; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                }
            }
        }
        // per-page persistence: a page only ever sees its own namespace
        // (cfg.customPageData[pageId]), keyed by whatever string the page
        // chooses — arbitrary JSON-serializable values, same as any cfg.*
        // setting. Survives reinstalling/renaming other pages; only wiped if
        // the page itself is trashed (see trashPage()).
        function getSetting(key: string, fallback) {
            const store = (cfg.customPageData ?? {})[pageId];
            return store && key in store ? store[key] : fallback;
        }
        function setSetting(key: string, value): void {
            const all = Object.assign({}, cfg.customPageData ?? {});
            all[pageId] = Object.assign({}, all[pageId] ?? {}, { [key]: value });
            cfg.customPageData = all;
            root.saveSettings();
        }
    }

    // one physical-looking key in a keybinding chord (keybindings tab): a
    // flat "cap" over a slightly darker "base" peeking out underneath reads
    // as a keycap without needing a dedicated icon font — tabler-icons only
    // ships a matching glyph for a couple of keys (Return's corner-down-left
    // arrow being the clean one), so most labels just render as text.
    component KeyCap: Item {
        id: keycap
        property string label: ""
        // Return always gets a glyph; every other key renders as plain text.
        property string glyph: label === "Return" ? root.ti.cornerDownLeft : ""
        implicitWidth: Math.max(28, capText.implicitWidth + 16)
        implicitHeight: 26

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3
            radius: 6
            color: Qt.alpha(root.fg, 0.16)
        }
        Rectangle {
            width: parent.width
            height: parent.height - 3
            radius: 6
            color: Qt.alpha(root.accent, 0.14)
            border.width: 1
            border.color: Qt.alpha(root.accent, 0.4)
        }
        Text {
            id: capText
            anchors.centerIn: parent
            text: keycap.glyph || keycap.label
            color: root.fg
            font.family: keycap.glyph ? root.iconFont : root.mono
            font.pixelSize: root.fs(12)
        }
    }

    // "+" joiner between the caps of a multi-key chord (e.g. Shift+Tab);
    // height matches KeyCap.implicitHeight so it centers against the caps
    // in the Row they share, which doesn't reposition child y itself.
    component KeyPlus: Text {
        text: "+"
        height: 26
        verticalAlignment: Text.AlignVCenter
        color: root.muted
        font { family: root.mono; pixelSize: root.fs(12) }
    }

    // visible grid-of-tiles size picker (Grids settings tab): hovering
    // previews a cols×rows selection Excel-insert-table style, clicking
    // commits it. `target` indexes root.gridTargets for which page's cfg
    // cols/rows properties and bounds apply. The tile canvas is always laid
    // out at root.gridPickerMaxCols × gridPickerMaxRows (the largest any
    // target needs) so switching targets never resizes it — tiles outside
    // the active target's bounds just pop out, and any that come back into
    // bounds pop in, instead of the grid instantly snapping to a new shape.
    // When the walls target is showing the "windows" carousel style, each
    // bar is exactly the footprint a 1-wide × spec.maxRows-tall column of
    // tiles already occupies (same col x, same offsetY, same width) — the
    // row-0 tile of that column simply grows to cover the whole column
    // height while rows 1..maxRows-1 beneath it shrink away, so the same
    // Behaviors that already animate x/y/opacity/scale read as those tiles
    // conjoining into one bar (and splitting back apart on the way out).
    // Columns beyond wallsBarSlots, and rows past a bar's height in taller
    // targets like apps, just pop in/out exactly as they do when switching
    // targets — no separate animation path for them.
    component GridSizeTiles: Item {
        id: gp
        property string target: "apps"
        readonly property var spec: root.gridTargets[gp.target]
        readonly property bool wallsBars: gp.target === "walls" && cfg.wallpaperStyle !== "tiles"
        readonly property int curCols: cfg[gp.spec.colsProp]
        readonly property int curRows: cfg[gp.spec.rowsProp]
        readonly property int curVisible: cfg.wallsVisible
        // >0 while hovered (a preview size); 0 falls back to the committed
        // size. Reset on exit/target switch so the preview always reflects
        // the grid actually under the mouse instead of a stale hover from
        // before the mouse left or before switching pages.
        property int hoverCols: 0
        property int hoverRows: 0
        property int hoverVisible: 0
        onTargetChanged: gp.resetHover()
        onWallsBarsChanged: gp.resetHover()
        function resetHover() {
            gp.hoverCols = 0;
            gp.hoverRows = 0;
            gp.hoverVisible = 0;
        }
        readonly property int shownCols: gp.hoverCols > 0 ? gp.hoverCols : gp.curCols
        readonly property int shownRows: gp.hoverRows > 0 ? gp.hoverRows : gp.curRows
        readonly property int shownVisible: gp.hoverVisible > 0 ? gp.hoverVisible : gp.curVisible
        readonly property int tileSize: 26
        readonly property int tileGap: 6
        readonly property int step: gp.tileSize + gp.tileGap
        readonly property int gridW: root.gridPickerMaxCols * gp.tileSize + (root.gridPickerMaxCols - 1) * gp.tileGap
        readonly property int gridH: root.gridPickerMaxRows * gp.tileSize + (root.gridPickerMaxRows - 1) * gp.tileGap
        readonly property int activeW: gp.spec.maxCols * gp.tileSize + (gp.spec.maxCols - 1) * gp.tileGap
        readonly property int activeH: gp.spec.maxRows * gp.tileSize + (gp.spec.maxRows - 1) * gp.tileGap
        // the active target's grid sits centered within the fixed canvas,
        // so a 4×4 target's tiles aren't stuck in the corner of a 6×6 canvas
        readonly property int offsetX: Math.round((gp.gridW - gp.activeW) / 2)
        readonly property int offsetY: Math.round((gp.gridH - gp.activeH) / 2)

        // bar-mode selection: root.wallsBarSlots columns (0..barCenter*2),
        // always odd 3–9, symmetric around the center column. Bars use the
        // walls spec's own column offset/step, not a separate layout, so a
        // bar sits exactly where that column's tiles already sit.
        readonly property int barSlots: root.wallsBarSlots
        readonly property int barCenter: Math.floor(gp.barSlots / 2)
        readonly property int barsOffsetX: Math.round((gp.gridW - (gp.barSlots * gp.step - gp.tileGap)) / 2)
        function halfFor(n: int): int {
            return Math.floor((n - 1) / 2);
        }
        function visibleForBar(idx: int): int {
            const half = Math.max(1, Math.min(gp.halfFor(gp.barSlots), Math.abs(idx - gp.barCenter)));
            return half * 2 + 1;
        }

        width: 780
        height: gp.gridH + 14 + sizeLabel.implicitHeight

        Item {
            id: tilesWrap
            anchors.horizontalCenter: parent.horizontalCenter
            width: gp.gridW
            height: gp.gridH

            Repeater {
                model: root.gridPickerMaxCols * root.gridPickerMaxRows

                Rectangle {
                    id: tile
                    required property int index
                    readonly property int col: index % root.gridPickerMaxCols
                    readonly property int row: Math.floor(index / root.gridPickerMaxCols)
                    readonly property int barDist: Math.abs(tile.col - gp.barCenter)
                    // the tile that becomes a bar's visible body: row 0 of
                    // any in-range column, stretched down over its column
                    readonly property bool isBarBody: gp.wallsBars && tile.row === 0 && tile.col < gp.barSlots
                    // the rest of that same column (rows 1..spec.maxRows-1):
                    // these are what visibly conjoin — they slide up to the
                    // bar's top edge while shrinking away, rather than
                    // fading out in place like a tile that's simply out of
                    // bounds (rows past spec.maxRows, e.g. the apps tab's
                    // taller columns, still do exactly that)
                    readonly property bool mergingIntoBar: gp.wallsBars && tile.col < gp.barSlots
                        && tile.row > 0 && tile.row < gp.spec.maxRows
                    // whether this tile exists at all for the active target
                    // (drives the pop in/out on target switch, and — in bar
                    // mode — the rest of a bar's column shrinking away
                    // beneath the row-0 tile that grew to cover it)
                    readonly property bool inBounds: gp.wallsBars
                        ? tile.isBarBody
                        : (tile.col < gp.spec.maxCols && tile.row < gp.spec.maxRows)
                    // live hover/click preview, Excel-insert-style — falls
                    // back to the committed size when nothing is hovered
                    readonly property bool previewed: gp.wallsBars
                        ? tile.barDist <= gp.halfFor(gp.shownVisible)
                        : (tile.col < gp.shownCols && tile.row < gp.shownRows)
                    // the actually-saved size — always outlined, even while
                    // a hover preview is filling in a different size
                    readonly property bool committed: gp.wallsBars
                        ? tile.barDist <= gp.halfFor(gp.curVisible)
                        : (tile.col < gp.curCols && tile.row < gp.curRows)
                    x: gp.wallsBars ? (gp.barsOffsetX + tile.col * gp.step) : (gp.offsetX + tile.col * gp.step)
                    y: gp.offsetY + (tile.mergingIntoBar ? 0 : tile.row * gp.step)
                    width: gp.tileSize
                    height: tile.isBarBody ? gp.activeH : gp.tileSize
                    radius: 5
                    opacity: tile.inBounds ? 1 : 0
                    scale: tile.inBounds ? 1 : 0
                    color: tile.previewed ? Qt.alpha(root.accent, 0.35) : "transparent"
                    border.width: tile.committed ? 2 : 1
                    border.color: tile.committed ? root.accent : Qt.alpha(root.muted, 0.3)
                    Behavior on x { NumberAnimation { duration: win.had(240); easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: win.had(240); easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: win.had(240); easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: win.had(240); easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: win.had(90) } }
                    Behavior on color { ColorAnimation { duration: win.had(120) } }
                    Behavior on opacity { NumberAnimation { duration: win.had(180); easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: win.had(240); easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                }
            }

            MouseArea {
                x: gp.wallsBars ? gp.barsOffsetX : gp.offsetX
                y: gp.offsetY
                width: gp.wallsBars ? (gp.barSlots * gp.step - gp.tileGap) : gp.activeW
                height: gp.activeH
                hoverEnabled: true
                onPositionChanged: mouse => {
                    if (gp.wallsBars) {
                        const idx = Math.max(0, Math.min(gp.barSlots - 1, Math.round(mouse.x / gp.step)));
                        gp.hoverVisible = gp.visibleForBar(idx);
                    } else {
                        gp.hoverCols = Math.max(gp.spec.minCols, Math.min(gp.spec.maxCols, Math.floor(mouse.x / gp.step) + 1));
                        gp.hoverRows = Math.max(gp.spec.minRows, Math.min(gp.spec.maxRows, Math.floor(mouse.y / gp.step) + 1));
                    }
                }
                onExited: gp.resetHover()
                onClicked: mouse => {
                    if (gp.wallsBars) {
                        const idx = Math.max(0, Math.min(gp.barSlots - 1, Math.round(mouse.x / gp.step)));
                        cfg.wallsVisible = gp.visibleForBar(idx);
                    } else {
                        cfg[gp.spec.colsProp] = Math.max(gp.spec.minCols, Math.min(gp.spec.maxCols, Math.floor(mouse.x / gp.step) + 1));
                        cfg[gp.spec.rowsProp] = Math.max(gp.spec.minRows, Math.min(gp.spec.maxRows, Math.floor(mouse.y / gp.step) + 1));
                    }
                    root.saveSettings();
                }
            }
        }

        Text {
            id: sizeLabel
            anchors.top: tilesWrap.bottom
            anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            text: gp.wallsBars ? (gp.shownVisible + " visible") : (gp.shownCols + " × " + gp.shownRows)
            color: root.fg
            font { family: root.mono; pixelSize: root.fs(13) }
        }
    }

    // ---------- settings ----------
    FileView {
        id: settingsStore
        path: Quickshell.statePath("settings.json")
        blockLoading: true
        printErrors: false
        // pick up hand edits to settings.json live; without this the daemon
        // keeps its stale in-memory copy and silently overwrites the file on
        // its next save
        watchChanges: true
        onFileChanged: reload()
        // this can re-fire on every save (writeAdapter's own write loops
        // back through the watcher above), so the Dynamic-theme kickoff is
        // guarded to only ever fire once, on the true initial load
        onLoaded: {
            // JsonAdapter's load (both the initial parse and any reload()
            // from a hand-edit) writes object/array-typed properties in a
            // way that doesn't reliably emit their changed signal — plain
            // `cfg.pageOrder = [...]` assignments from QML do (moveFullPage
            // reacts instantly), but the load path leaves bindings that
            // depend on these (fullPageOrder, activePanes) stuck on whatever
            // they last evaluated to, typically the pre-load default. Force
            // a re-notify by reassigning a fresh shallow copy of each.
            cfg.pageOrder = cfg.pageOrder.slice();
            cfg.pages = Object.assign({}, cfg.pages);
            cfg.keybinds = Object.assign({}, cfg.keybinds);
            cfg.flyouts = Object.assign({}, cfg.flyouts);
            cfg.pibbleAlerts = Object.assign({}, cfg.pibbleAlerts);
            cfg.clockShow = Object.assign({}, cfg.clockShow);
            root.healSettings();
            if (!matugenProc.startupKicked) {
                matugenProc.startupKicked = true;
                if (cfg.theme === "matugen")
                    root.runMatugen();
            }
        }

        JsonAdapter {
            id: cfg
            property int appsCols: 4
            property int appsRows: 3
            property int wallsCols: 3
            property int wallsRows: 3
            // bars visible in the "windows" carousel: the selected center
            // plus equal wings, so always odd (healSettings clamps to 3–9)
            property int wallsVisible: 7
            property int clipsCols: 4
            property int clipsRows: 4
            property int clipsMax: 100
            property var pages: ({ clock: true, apps: true, walls: true, clips: true })
            // cycle order of the pages (drag the chips in settings to change)
            property var pageOrder: ["clock", "apps", "walls", "clips"]
            // pages added via the Pages settings row's upload picker; each
            // is { id, label, path, on } and starts unchecked. Loaded and
            // cycled alongside the built-in four once ticked on — see
            // win.fullPageOrder and the "Custom pages" Loader block
            property var uploadedPages: []
            // per-page persistent storage for custom pages, namespaced by
            // page id (see PageContext.getSetting/setSetting) — never read
            // or written to directly by pibble itself otherwise
            property var customPageData: ({})
            property string animStyle: "wave"
            // independent of animStyle: gates the settings pane's entrance
            // spring and the power-off/reboot pull-back animation, neither
            // of which is a "grid" (see win.had())
            property bool hiddenMenuAnimations: true
            // shared across the launcher and both flyouts
            property real fontScale: 1.0
            property string fontFamily: ""
            property string iconTheme: ""
            property string theme: "matugen"
            // user-editable palette for the "custom" theme; defaults match
            // the retired Mono preset so a first-time pick starts from something sane
            property string customAccent: "#cfcfcf"
            property string customFg: "#f0f0f0"
            property string customMuted: "#8a8a8a"
            // "tiles" is the grid picker; "windows" and "windows-flat" are
            // the horizontal carousel (see wallCarousel), the latter with
            // the backdrop parallax pan disabled
            property string wallpaperStyle: "tiles"
            property string wallpaperDir: "~/Pictures/wallpapers"
            // command run when a wallpaper is chosen; $WALL is the image,
            // $BLUR the blurred variant (only generated if referenced)
            property string wallCommand: root.defaultWallCommand
            // path of the last wallpaper applied through the launcher; the
            // Dynamic theme samples this directly instead of asking the
            // compositor what it's currently showing, since wallCommand is
            // freeform and may not even go through the tool we'd query
            property string currentWallpaper: ""
            property real dimOpacity: 0.4
            property string launchAnimation: "grow-top-left"
            // whether the launcher asks the compositor to blur behind it at
            // all; independent of launchAnimation (see BackgroundEffect.blurRegion)
            property bool bgBlur: true
            // gates the swipe-up/swipe-down power-off/reboot drag gesture
            // and the swipe-left/swipe-right pane/tab-cycle gesture,
            // independently; the keybind/Enter-confirm flow the power
            // gesture feeds into stays available either way
            property var gestures: ({ power: true, panes: true })
            property var keybinds: ({ cycle: "Tab", reverseCycle: "Shift+Tab", launch: "Return", exit: "Escape", settings: "Ctrl+S", power: "Ctrl+P", reboot: "Ctrl+R" })
            // flyouts (volume + notification OSDs) — independent of whether
            // other apps' notifications show
            property var flyouts: ({ volume: true, notifs: true })
            // gates notify-send calls pibble sends on its own behalf, split
            // by kind: errors (missing tools, failed commands), system
            // (copy confirmations, custom page discovery, page trashed),
            // battery (low battery warning)
            property var pibbleAlerts: ({ errors: true, system: true, battery: true })
            property real volWidth: 420
            property string volAnim: "pop"
            // volume OSD content style: pill (a level bar) or sine (equalizer)
            property string volStyle: "sine"
            // numeric volume % readout on the OSD
            property bool volShowPercent: true
            property int volTimeout: 2000
            property int notifTimeout: 5000
            // one notification at a time (queue across apps, replace within
            // an app): "bubble" = tinted circle + card, "pill" = card only
            property string notifStyle: "bubble"
            // "pop" = the bubble/card pop-in and stagger animation, "none"
            // disables all notification entry/exit animation
            property string notifAnim: "pop"
            // how many of the most recent cached notifications `pibble
            // replay` can step back through on repeated presses (see
            // notifCache below); 1-5
            property int replayCount: 1
            // clock-page weather readout (wttr.in); empty location auto-detects by IP
            property bool weatherEnabled: true
            property string weatherLocation: ""
            // clock page layout: which of date/battery/weather show; the line
            // grouping itself is fixed (see win.clockVisibleGroups)
            property var clockShow: ({ date: true, battery: true, weather: true })
        }
    }
    function saveSettings() {
        settingsStore.writeAdapter();
    }

    // ---------- notification cache (pibble replay) ----------
    // The last 5 notifications pibble has shown, most recent first, kept on
    // disk so `pibble replay` (a plain CLI invocation, no QML state of its
    // own) can ask the running daemon to re-fire one of them via IPC.
    // Capped at 5 unconditionally — cfg.replayCount only trims how many of
    // the cached 5 are reachable by stepping back through repeated presses.
    FileView {
        id: notifCacheStore
        path: Quickshell.statePath("notif-cache.json")
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: notifCache
            property var items: []
        }
    }
    // raw fields only — enough to rebuild a faithful notify-send call.
    // Anything display-derived (glyph, resolved icon/image URLs, own/app
    // labels) is deliberately left out: replaying re-sends the original
    // notification and lets the live pipeline derive all of that itself,
    // the same way it would for a first arrival. icon/image get the same
    // slot-swap classification deriveNotifView does (some senders put a
    // file path in appIcon, or route everything through image as an
    // "image://icon/NAME" pseudo-URL) but keep raw values — a bare icon
    // name or file path — since these feed notify-send's -i/-h flags
    // directly on replay, not a QML Image source.
    function cacheNotification(n): void {
        let icon = String(n.appIcon ?? "");
        let img = String(n.image ?? "");
        if (icon.startsWith("file://") || icon.startsWith("/")) {
            if (!img)
                img = icon;
            icon = "";
        }
        if (img.startsWith("image://icon/")) {
            const rest = img.slice("image://icon/".length);
            if (rest.startsWith("/"))
                img = rest;
            else {
                if (!icon)
                    icon = rest;
                img = "";
            }
        } else if (img.startsWith("file://")) {
            img = img.slice("file://".length);
        }
        const entry = {
            appName: String(n.appName ?? ""),
            appIcon: icon,
            image: img,
            summary: n.summary ?? "",
            body: n.body ?? "",
            urgency: NotificationUrgency.toString(n.urgency),
            // when the *original* notification arrived, so a later replay can
            // show "<original> - 5m ago" instead of a static "REPLAY" tag
            timestamp: Date.now()
        };
        notifCache.items = [entry].concat(notifCache.items).slice(0, 5);
        notifCacheStore.writeAdapter();
    }
    // Replays by re-sending a real notify-send call with the original
    // notification's own icon/image/urgency, rather than a separate "replay"
    // rendering path: the re-sent notification lands in
    // NotificationServer.onNotification -> flyWin.accept() exactly like any
    // live one, so it animates and dismisses identically — a genuine
    // replay, not a second UI that can drift from the first. The sender
    // identity is always the literal "REPLAY" (not the original app), so
    // repeated presses always land in flyWin's own same-app "replace
    // in-place" path — see accept()'s appKey comparisons — regardless of
    // which app each replayed notification originally came from, and so a
    // live notification from the real sender never collides with it. The
    // original sender rides along in the desktop-entry hint purely so
    // deriveNotifView can show "<original> - <n> ago" on the card; the
    // original arrival time rides along the same way in a pibble-private
    // hint (no standard notify-send hint carries this) so that "ago" reads
    // relative to when the notification actually happened, not to when it
    // was replayed.
    function fireReplay(it): void {
        const args = ["notify-send"];
        if (it.urgency)
            args.push("-u", String(it.urgency).toLowerCase());
        // it.app is a one-release fallback for cache entries written by the
        // previous (display-derived) cache format, so an on-disk cache from
        // before this change doesn't replay unattributed the first time
        const appName = it.appName || it.app || "";
        args.push("-a", "REPLAY");
        if (appName)
            args.push("-h", "string:desktop-entry:" + appName);
        if (it.timestamp)
            args.push("-h", "string:x-pibble-orig-ts:" + it.timestamp);
        if (it.appIcon)
            args.push("-i", it.appIcon);
        if (it.image)
            args.push("-h", "string:image-path:" + it.image.replace(/^file:\/\//, ""));
        args.push(it.summary ?? "", it.body ?? "");
        Quickshell.execDetached(args);
    }
    // cursor into notifCache.items (0 = most recent) that each `pibble
    // replay` press steps forward by one, so consecutive presses walk back
    // through history one notification at a time instead of bursting the
    // whole cache at once; wraps back to the most recent once it reaches
    // the deepest reachable notification. A press arriving more than
    // replaySessionTimeout after the previous one is treated as a new
    // session and also starts back over at the most recent notification
    property int replayIndex: -1
    property double replayLastFireMs: 0
    readonly property int replaySessionTimeout: 5000
    function replayNotifications(): void {
        if (!notifCache.items.length)
            return;
        const depth = Math.max(1, Math.min(5, cfg.replayCount, notifCache.items.length));
        const now = Date.now();
        replayIndex = (replayIndex < 0 || now - replayLastFireMs > replaySessionTimeout)
            ? 0 : (replayIndex + 1) % depth;
        replayLastFireMs = now;
        fireReplay(notifCache.items[replayIndex]);
    }

    // ---------- theme ----------
    // Named schemes plus a resolved one: "matugen" (labelled "Dynamic" in
    // settings) samples the current wallpaper for the launcher/volume and
    // tints each notification from its own app icon.
    readonly property var themes: [
        { id: "amber", name: "Amber", accent: "#e8a24a", fg: "#f3ede4", muted: "#8a8378" },
        { id: "frost", name: "Frost", accent: "#7ab8e0", fg: "#e6eef4", muted: "#83919c" },
        { id: "moss",  name: "Moss",  accent: "#a3c76a", fg: "#eef3e4", muted: "#8d9378" },
        { id: "rose",  name: "Rose",  accent: "#e07a9a", fg: "#f4e8ec", muted: "#9c8389" },
        { id: "custom", name: "Custom", accent: "", fg: "", muted: "" },
        { id: "matugen", name: "Dynamic", accent: "", fg: "", muted: "" }
    ]
    // filled in from matugen (current wallpaper) at startup
    property var dynTheme: ({ accent: "#e8a24a", fg: "#f3ede4", muted: "#8a8378" })
    // user-defined palette, edited via the color picker under the theme row
    readonly property var customTheme: ({ accent: cfg.customAccent, fg: cfg.customFg, muted: cfg.customMuted })
    readonly property var launcherBase: cfg.theme === "matugen" ? dynTheme
        : cfg.theme === "custom" ? customTheme
        : (themes.find(t => t.id === cfg.theme) ?? themes[0])
    readonly property var activeTheme: launcherBase
    readonly property color accent: activeTheme.accent
    readonly property color fg: activeTheme.fg
    readonly property color muted: activeTheme.muted
    // backdrop the launcher dims the screen with
    readonly property color surface: "#0a0908"
    readonly property string mono: cfg.fontFamily

    // theme is shared by the launcher and both flyouts now
    readonly property var flyTh: activeTheme
    readonly property string flyMono: mono
    // "matugen" ("Dynamic") theme: near-black card, bubble tinted from the
    // app icon; the volume level bar still follows the wallpaper palette
    readonly property bool notifIconTint: cfg.theme === "matugen"
    readonly property var notifTh: notifIconTint
        ? { accent: flyTh.accent, fg: "#f2f0ee", muted: "#908c87" }
        : flyTh
    // card surface behind both flyouts
    readonly property color flySurface: "#0c0c10"
    function flyoutOn(name: string): bool {
        return (cfg.flyouts ?? {})[name] !== false;
    }
    function alertOn(name: string): bool {
        return (cfg.pibbleAlerts ?? {})[name] !== false;
    }
    function gestureOn(name: string): bool {
        return (cfg.gestures ?? {})[name] !== false;
    }
    // icon-name → displayable URL; senders (and .desktop Icon= entries)
    // sometimes resolve the icon themselves, so paths and urls pass through
    function iconUrl(name: string): string {
        if (!name)
            return "";
        if (name.startsWith("file://"))
            return name;
        if (name.startsWith("/"))
            return "file://" + name;
        return Quickshell.iconPath(name, true);
    }
    // compact relative-time label for `pibble replay` cards ("5m ago"); not
    // used anywhere live notifications need a timestamp, so it's plain
    // one-shot text, not a ticking Timer-backed binding
    function timeAgo(ms: double): string {
        const diff = Math.max(0, Date.now() - ms);
        const mins = Math.floor(diff / 60000);
        if (mins < 1)
            return "just now";
        if (mins < 60)
            return mins + "m ago";
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return hours + "h ago";
        return Math.floor(hours / 24) + "d ago";
    }

    // notification glyph classifier, shared by the stack card and the
    // flyout bubble. Matches on the *raw* freedesktop icon name pibble
    // itself passed via notify-send -i (see notifyError and the various
    // -i-passing notify-send calls throughout), not the resolved icon
    // path: resolution depends on the active system icon theme actually
    // having that name, which isn't guaranteed, and a failed resolution
    // used to silently fall through to the generic bell below with no
    // error visible. Exact icon-name matches take priority over the
    // generic keyword/urgency fallback so a specific glyph (trash, low
    // battery, etc) never gets overridden by a coincidental "fail"/"not
    // found" in the summary text.
    function notifGlyph(iconName: string, urgency, summary: string): string {
        switch (iconName) {
        case "dialog-error": return root.ti.alertTriangle;
        case "edit-copy": return root.ti.copy;
        case "list-add": return root.ti.plus;
        case "user-trash": return root.ti.trash;
        case "battery-low": return root.ti.batteryLow;
        case "preferences-desktop-wallpaper": return root.ti.wallpaper;
        case "system-software-install": return root.ti.download;
        }
        const sl = summary.toLowerCase();
        if (urgency === NotificationUrgency.Critical || sl.includes("fail") || sl.includes("not found"))
            return root.ti.alertTriangle;
        if (sl.includes("copied"))
            return root.ti.copy;
        return root.ti.bell;
    }

    // notification object → display fields, shared by the live flyout card
    // (flyWin.snapshot) and the replay cache (cacheNotification below) so a
    // replayed notification renders with exactly the icon/image/glyph the
    // live card showed, instead of a second derivation that could drift.
    function deriveNotifView(n): var {
        let icon = root.iconUrl(String(n.appIcon ?? ""));
        let img = String(n.image ?? "");
        // the bare freedesktop icon name (e.g. "dialog-error"), kept
        // separate from icon/img above which carry whatever's actually
        // displayable (a resolved path or image provider URL) — used only
        // for notifGlyph's classification below. notify-send's -i flag
        // does *not* populate the app_icon D-Bus argument (confirmed via
        // dbus-monitor): libnotify routes it through the "image-path"
        // hint instead, which arrives here as n.image, not n.appIcon — so
        // appIcon is empty for every notify-send-style call pibble itself
        // makes, and the real name only recovers below once the
        // image://icon/ prefix is stripped off
        let iconName = String(n.appIcon ?? "");
        // some apps (e.g. niri screenshots) pass a file path in the icon
        // field: that is notification media, not an app icon
        if (icon.startsWith("file://")) {
            if (!img)
                img = icon;
            icon = "";
        }
        // notify-send-style senders arrive with everything in the image
        // slot (appIcon empty), routed through the icon provider: a
        // file path there is notification media (decode it directly so
        // the aspect probe sees real dimensions), an icon name is the
        // app icon, not media
        if (img.startsWith("image://icon/")) {
            const rest = img.slice("image://icon/".length);
            if (rest.startsWith("/"))
                img = "file://" + rest;
            else {
                if (!icon)
                    icon = img;
                if (!iconName)
                    iconName = rest;
                img = "";
            }
        }
        // some senders (e.g. Discord) omit the app name and icon but set
        // the desktop-entry hint — recover both from the entry
        const de = String(n.desktopEntry ?? "");
        let appName = String(n.appName ?? "");
        // pibble replay (see fireReplay) always sends "REPLAY" as its own
        // identity so repeated replays replace each other regardless of
        // origin; the real sender rides along in the desktop-entry hint
        // purely for display here, and the original arrival time (also a
        // hint, since notify-send has no standard one for it) becomes a
        // relative "5m ago" in place of a static "REPLAY" tag
        if (appName === "REPLAY") {
            const origTs = Number(n.hints?.["x-pibble-orig-ts"] ?? 0);
            const ago = origTs ? root.timeAgo(origTs) : "";
            appName = de ? (ago ? de + " - " + ago : de) : (ago || "REPLAY");
        }
        else if (de && (!appName || !icon)) {
            const ent = Array.from(DesktopEntries.applications.values)
                .find(e => e.id.toLowerCase() === de.toLowerCase());
            if (ent) {
                if (!appName)
                    appName = ent.name;
                if (!icon && ent.icon)
                    icon = root.iconUrl(ent.icon);
            }
            if (!appName)
                appName = de;
        }
        return {
            // n.appName is forced to "REPLAY" by fireReplay for every
            // replayed notification (see there) regardless of who
            // originally sent it, so a replay of pibble's own alert would
            // otherwise stop counting as "own" here and lose both its
            // glyph rendering and its icon tinting exemption below; the
            // desktop-entry hint still carries the true original sender
            // through a replay, so check that too
            own: n.appName === "pibble" || de === "pibble",
            glyph: root.notifGlyph(iconName, n.urgency, String(n.summary ?? "")),
            app: appName,
            key: (String(n.appName ?? "")) || de,
            summary: n.summary ?? "",
            body: n.body ?? "",
            image: img,
            icon: icon,
            timeout: n.expireTimeout
        };
    }

    // pibble's own UI glyphs (weather/battery/checks/etc, as opposed to
    // other apps' resolved icons) come from one vendored icon webfont,
    // addressed by codepoint rather than name.
    FontLoader { id: msIconFont; source: Qt.resolvedUrl("fonts/MaterialSymbolsSharp_48pt-SemiBold.ttf") }
    readonly property string iconFont: msIconFont.name

    // codepoints looked up by hand from Material Symbols' own cmap —
    // Private Use Area codepoints carry no standard meaning outside this font.
    readonly property var ti: ({
        sun: "\ue430", cloud: "\ue2bd", cloudRain: "\uf176", cloudSnow: "\ue810",
        cloudStorm: "\uebdb", snowflake: "\ued5b", bolt: "\uea0b", check: "\ue5ca",
        settings: "\ue8b8", refresh: "\ue5d5", copy: "\ue14d", bell: "\ue7f4",
        alertTriangle: "\ue002", cornerDownLeft: "\ue31b",
        wallpaper: "\ue1bc", plus: "\uf710", trash: "\ue872",
        batteryLow: "\uf251", download: "\ue171"
    })

    function fs(px: int): int {
        return Math.round(px * cfg.fontScale);
    }

    // internal errors surface as regular notifications (we are the
    // server); always the generic alert glyph (see notifGlyph) so every
    // pibble-raised error reads the same at a glance.
    // -t 0 (expire_timeout 0, "never expire" per spec — see showTimer) so
    // an actionable error can't auto-dismiss before it's been read
    function notifyError(summary: string, body: string) {
        if (!alertOn("errors"))
            return;
        Quickshell.execDetached(["notify-send", "-a", "pibble", "-i", "dialog-error", "-t", "0", summary, body]);
    }

    // the two `wl-paste --watch` invocations cliphist needs to see both text
    // and image copies; shared between the alert body and the flyout's
    // tap-to-copy action (see the "Clipboard watcher not running" case in
    // the notification flyout below) so they can never drift apart
    readonly property string clipWatcherFixCommand: "wl-paste --type text --watch cliphist store\nwl-paste --type image --watch cliphist store"
    function copyToClipboard(text: string): void {
        Quickshell.clipboardText = text;
        if (alertOn("system"))
            Quickshell.execDetached(["notify-send", "-a", "pibble", "-i", "edit-copy", "Copied to clipboard", text]);
    }

    // bundles version/build info, this run's recent log, and the latest
    // crash report for this shell (if any) into one blob for bug reports;
    // the clipboard write happens once debugInfoProc's stdout is collected
    function copyDebugInfo() {
        if (debugInfoProc.running)
            return;
        debugInfoProc.running = true;
    }

    // shown at the bottom of the general settings tab; empty when the shell
    // isn't running from a git checkout (e.g. a packaged install)
    property string pibbleCommit: ""
    Process {
        running: true
        command: ["bash", "-c", `git -C "$1" rev-parse --short HEAD 2>/dev/null`, "_", Quickshell.shellDir]
        stdout: StdioCollector {
            onStreamFinished: root.pibbleCommit = text.trim()
        }
    }

    function humanBytes(n: int): string {
        if (n < 1024)
            return n + " B";
        if (n < 1048576)
            return (n / 1024).toFixed(1) + " KiB";
        return (n / 1048576).toFixed(1) + " MiB";
    }

    // heal out-of-range / retired settings values. Hooked to the store's
    // loaded signal (not Component.onCompleted) so it also covers hot
    // reloads and hand edits picked up by the file watcher.
    function healSettings() {
        // clamp out-of-range clip rows (old list-style pane stored large
        // values; the grid renders 2–4 rows) — clamp, don't reset, so a
        // hand-edited value degrades to the nearest legal one
        if (cfg.clipsRows > 4 || cfg.clipsRows < 2) {
            cfg.clipsRows = Math.max(2, Math.min(4, cfg.clipsRows));
            saveSettings();
        }
        // the windows carousel shows a selected center bar plus equal
        // wings, so the visible count must be odd; clamp to 3–9 and
        // round even hand-edited values down
        if (cfg.wallsVisible < 3 || cfg.wallsVisible > 9 || cfg.wallsVisible % 2 === 0) {
            cfg.wallsVisible = Math.max(3, Math.min(9,
                cfg.wallsVisible % 2 === 0 ? cfg.wallsVisible - 1 : cfg.wallsVisible));
            saveSettings();
        }
        if (cfg.replayCount < 1 || cfg.replayCount > 5) {
            cfg.replayCount = Math.max(1, Math.min(5, cfg.replayCount));
            saveSettings();
        }
        // One-time migrations, keyed strictly on values only old configs
        // can contain — every branch must be a no-op on a fresh or healed
        // config, because this also runs if a load ever surfaces adapter
        // defaults (an unconditional save here once clobbered the file).
        if (cfg.theme === "dynamic") {
            cfg.theme = "matugen"; // renamed
            saveSettings();
        }
        // the retired equalizer visualizers collapse into the sine wave
        if (["mirror", "spectrum", "flicker"].includes(cfg.volStyle)) {
            cfg.volStyle = "sine";
            saveSettings();
        }
        // "flyout" was renamed "bubble"; the retired stack style folds in too
        if (cfg.notifStyle === "flyout" || cfg.notifStyle === "stack") {
            cfg.notifStyle = "bubble";
            saveSettings();
        }
        // the Mono preset was retired in favor of the custom color picker
        // (seeded with Mono's old palette); configs that had it selected
        // fall back to the default so a theme always shows as selected
        if (cfg.theme === "mono") {
            cfg.theme = "matugen";
            saveSettings();
        }
        if (!["tiles", "windows", "windows-flat"].includes(cfg.wallpaperStyle)) {
            cfg.wallpaperStyle = "tiles";
            saveSettings();
        }
        // the single "alerts" flyout checkbox split into per-category
        // pibbleAlerts (errors/system/battery)
        if (cfg.flyouts && Object.prototype.hasOwnProperty.call(cfg.flyouts, "alerts")) {
            const wasOn = cfg.flyouts.alerts !== false;
            cfg.pibbleAlerts = { errors: wasOn, system: wasOn, battery: wasOn };
            const fly = Object.assign({}, cfg.flyouts);
            delete fly.alerts;
            cfg.flyouts = fly;
            saveSettings();
        }
        // the single "gestures" checkbox split into per-category swipe
        // toggles (power: swipe up/down to arm the reboot/power-off
        // prompt; panes: swipe left/right to cycle panes/settings tabs)
        if (typeof cfg.gestures === "boolean") {
            const wasOn = cfg.gestures;
            cfg.gestures = { power: wasOn, panes: wasOn };
            saveSettings();
        }
    }
    Component.onCompleted: healSettings()

    Process {
        id: matugenProc
        // Kicked off imperatively from settingsStore.onLoaded (once, for the
        // initial run) and from applyWallpaper() (on every wallpaper pick)
        // — never via a `running: cfg.theme === "matugen"`-style binding.
        // That was tried and races: settingsStore's file load is async, so
        // cfg.currentWallpaper is still "" (the JsonAdapter's blank default)
        // when the tree is first constructed, even though cfg.theme already
        // reads "matugen" (its default too). The natural fix looked like
        // adding `&& cfg.currentWallpaper !== ""` to the binding, but that
        // still loses: once the load completes, `running` and `command`
        // both react to the same cfg.currentWallpaper change as sibling
        // bindings on this Process, and Qt doesn't guarantee `command` has
        // re-evaluated to the loaded path before `running`'s flip spawns
        // the process — so it reliably ran with an empty $WALL anyway.
        // Driving both imperatively, one statement after the other, forces
        // the ordering: by the time `running = true` executes, `command`'s
        // binding has already settled on the just-loaded value.
        property bool startupKicked: false
        property bool rerun: false
        onRunningChanged: {
            if (!running && rerun) {
                rerun = false;
                Qt.callLater(() => running = true);
            }
        }
        // samples cfg.currentWallpaper (set by applyWallpaper) rather than
        // asking the compositor what's on screen — wallCommand is a
        // freeform user command and may not even go through the tool we'd
        // query, so the picker's own record of what it applied is the only
        // source that's guaranteed to match
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            command -v matugen >/dev/null || { echo NOMATUGEN; exit 0; }
            img="$1"
            [ -n "$img" ] || exit 0
            matugen image "$img" --json hex --dry-run --prefer saturation 2>/dev/null`, "_", root.matugenSource]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "NOMATUGEN") {
                    if (cfg.theme === "matugen")
                        root.notifyError("matugen not found", "Install matugen to use the Dynamic theme.");
                    return;
                }
                // empty output is benign (awww not up yet at login, no
                // wallpaper set, or a run torn down early): keep the last
                // palette silently instead of raising a false alarm
                if (!text.trim())
                    return;
                try {
                    const c = JSON.parse(text).colors;
                    root.dynTheme = {
                        accent: c.primary.dark.color,
                        fg: c.on_surface.dark.color,
                        muted: c.outline.dark.color
                    };
                } catch (e) {
                    if (cfg.theme === "matugen")
                        root.notifyError("Matugen theme failed", "matugen returned no palette for the current wallpaper");
                }
            }
        }
    }
    // starts (or queues a rerun of) matugenProc for the current wallpaper;
    // shared by the initial-load kickoff and applyWallpaper()
    function runMatugen() {
        if (matugenProc.running)
            matugenProc.rerun = true;
        else
            matugenProc.running = true;
    }

    Process {
        id: debugInfoProc
        // matches by "Shell ID" (md5 of this shell.qml's path, same key
        // quickshell stamps into crash report.txt) rather than run id, since
        // a crash's run has already ended by the time anyone goes looking
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$PATH"
            pid="$1"
            shell_dir="$2"
            shell_id="$3"
            crashdir="$4"
            echo "pibble debug info -- $(date -Iseconds)"
            qs --version 2>/dev/null
            echo "Shell: $shell_dir"
            echo "Shell ID: $shell_id"
            commit=$(git -C "$shell_dir" rev-parse --short HEAD 2>/dev/null)
            [ -n "$commit" ] && echo "Commit: $commit"
            echo
            echo "----- recent log -----"
            qs log --pid "$pid" --no-color -t 200 2>&1
            latest=""
            for d in $(ls -dt "$crashdir"/*/ 2>/dev/null); do
                grep -q "Shell ID: $shell_id" "$d/report.txt" 2>/dev/null && { latest="$d"; break; }
            done
            if [ -n "$latest" ]; then
                echo
                echo "----- most recent crash: $latest -----"
                cat "$latest/report.txt" 2>/dev/null
            fi`, "_", "" + Quickshell.processId, Quickshell.shellDir, Quickshell.shellId,
            (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/quickshell/crashes"]
        stdout: StdioCollector {
            onStreamFinished: {
                Quickshell.clipboardText = text;
                if (root.alertOn("system"))
                    Quickshell.execDetached(["notify-send", "-a", "pibble", "-i", "edit-copy", "Copied to clipboard", text.slice(0, 4000)]);
            }
        }
    }

    // ---------- apps ----------
    // warm decode order = the home page's sort, so the icons the user sees
    // first come off the (single) QML image reader thread first
    readonly property var warmOrderApps: allApps.slice().sort((a, b) =>
        launchCount(b) - launchCount(a) || a.name.localeCompare(b.name))
    readonly property var allApps: {
        const list = Array.from(DesktopEntries.applications.values)
            .filter(e => !e.noDisplay);
        list.sort((a, b) => a.name.localeCompare(b.name));
        return list;
    }

    // Subsequence fuzzy match. Returns null when q doesn't match, else a
    // score favoring prefixes, word starts, consecutive runs, and short names.
    function fuzzyScore(lname: string, q: string): var {
        let score = 0;
        let next = 0;
        let prevMatch = -2;
        let consec = 0;
        for (let qi = 0; qi < q.length; qi++) {
            const found = lname.indexOf(q[qi], next);
            if (found < 0)
                return null;
            if (found === 0)
                score += 8;
            else if (" -_./".includes(lname[found - 1]))
                score += 6;
            if (found === prevMatch + 1) {
                consec++;
                score += 4 + consec;
            } else {
                consec = 0;
            }
            score -= found - next; // gap penalty
            prevMatch = found;
            next = found + 1;
        }
        if (lname.startsWith(q))
            score += 10;
        else if (lname.includes(q))
            score += 6;
        return score - lname.length * 0.1;
    }

    // The shell runs as a persistent daemon; the launcher window is toggled
    // over IPC: qs -p <repo> ipc call launcher toggle
    IpcHandler {
        target: "launcher"

        // `page` is "" for a plain toggle (`pibble toggle`) or a pane id for
        // `pibble toggle <page>`. Closed: opens straight onto that page.
        // Open and already showing it: closes, so re-pressing the same
        // page's keybind acts like a normal toggle. Open and showing
        // something else: switches to it and stays open — a different
        // page's keybind reads as "take me there", not "close everything".
        function toggle(page: string): void {
            const p = win.resolvePageArg(page);
            if (win.shown && !win.exiting) {
                if (p && win.pane !== p)
                    win.setPane(p);
                else
                    win.exit();
            } else {
                win.open(p);
            }
        }
        // "show" would collide with the `qs ipc show` CLI subcommand
        function open(): void {
            if (!win.shown || win.exiting)
                win.open();
        }
        function close(): void {
            if (win.shown)
                win.exit();
        }
        // `pibble replay`: steps back one more cached notification (up to
        // cfg.replayCount deep) and re-fires just that one, independent of
        // whether the launcher window itself is open
        function replay(): void {
            root.replayNotifications();
        }
    }

    // Per-app launch counts, persisted across runs. Apps launched more often
    // rank higher in search results.
    FileView {
        id: store
        path: Quickshell.statePath("launch-counts.json")
        blockLoading: true
        printErrors: false

        JsonAdapter {
            id: stats
            property var counts: ({})
        }
    }

    function launchCount(entry): int {
        return (stats.counts && stats.counts[entry.id]) || 0;
    }

    function recordLaunch(entry) {
        const c = Object.assign({}, stats.counts);
        c[entry.id] = (c[entry.id] || 0) + 1;
        stats.counts = c;
        store.writeAdapter();
    }

    // ---------- wallpapers ----------
    function expandHome(p: string): string {
        return p.startsWith("~") ? Quickshell.env("HOME") + p.slice(1) : p;
    }
    readonly property string wallDir: expandHome(cfg.wallpaperDir)

    // Single persistent, self-cleaning cache root for everything the app
    // generates (wallpaper thumbnails/blur, clip thumbnails) — separate from
    // the source directories so deleting a wallpaper or a clip scrolling
    // past clipsMax can be detected and swept on the next scan.
    readonly property string cacheRoot: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/pibble"
    readonly property string wallCacheDir: cacheRoot + "/wallpapers"

    // Each entry: path|thumb|blurred. thumb/blurred point into wallCacheDir,
    // keyed by a hash of the source path (stable across renames of unrelated
    // files, safe across multiple wallpaperDirs); <stem>blurred.<ext> next to
    // the source is still honored as a user-supplied override.
    property var wallpapers: []
    property string lastMissingDir: ""
    // matugen chokes on/slow-decodes an animated source; sample the cached
    // static thumbnail instead when the current wallpaper is a .gif (see
    // matugenProc). Falls back to the raw path before the background scan
    // has generated a thumbnail for it yet.
    readonly property string matugenSource: {
        const w = root.wallpapers.find(x => x.path === cfg.currentWallpaper);
        return (w && w.gif && w.thumb) ? w.thumb : cfg.currentWallpaper;
    }
    function rescanWallpapers() {
        wallScan.running = false;
        wallScan.running = true;
    }
    Process {
        id: wallScan
        running: true
        command: ["bash", "-c", `
            cd "$1" || { echo NODIR; exit 0; }
            cachedir="$2"
            shopt -s nullglob nocaseglob
            for f in *.png *.jpg *.jpeg *.webp *.gif; do
                case "$f" in *blurred.*) continue ;; esac
                stem="\${f%.*}" ext="\${f##*.}"
                # generated thumb/blur are always true-color (png), even for a
                # .gif source: writing a single decoded frame back out as .gif
                # would quantize it to a 256-color palette, banding badly once
                # blurred; the source itself is still played back untouched
                oext="$ext"; case "\${ext,,}" in gif) oext="png" ;; esac
                key=$(printf '%s' "$PWD/$f" | md5sum | cut -d' ' -f1)
                thumb="$PWD/$f" blur=""
                # only trust caches newer than the source image
                [ "$cachedir/thumbnails/$key.$oext" -nt "$f" ] && thumb="$cachedir/thumbnails/$key.$oext"
                [ "$cachedir/blurred/$key.$oext" -nt "$f" ] && blur="$cachedir/blurred/$key.$oext"
                [ -e "\${stem}blurred.$ext" ] && blur="$PWD/\${stem}blurred.$ext"
                printf '%s|%s|%s\\n' "$PWD/$f" "$thumb" "$blur"
            done | sort`, "_", root.wallDir, root.wallCacheDir]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "NODIR") {
                    root.wallpapers = [];
                    if (root.lastMissingDir !== root.wallDir) {
                        root.lastMissingDir = root.wallDir;
                        root.notifyError("Wallpaper folder not found", root.wallDir);
                    }
                    return;
                }
                root.lastMissingDir = "";
                const walls = text.trim().split("\n").filter(l => l).map(l => {
                    const p = l.split("|");
                    return { path: p[0], thumb: p[1], blur: p[2] || "", gif: /\.gif$/i.test(p[0]) };
                });
                root.wallpapers = walls;
                // Generate missing thumbnails (a full 5K image standing in as
                // its own thumbnail costs ~100ms to decode+upload) and blurred
                // overview variants in the background; the next scan picks
                // them up and applying never has to blur synchronously. Also
                // sweeps cache entries whose source wallpaper is gone — runs
                // every scan (not just when something's missing) so deletions
                // get cleaned up promptly.
                const wantBlur = cfg.wallCommand.includes("$BLUR");
                Quickshell.execDetached(["bash", "-c", `
                    walldir="$1" cachedir="$2" gb="$3" alerts="$4"; shift 4
                    mkdir -p "$cachedir/thumbnails" "$cachedir/blurred"
                    warned=0
                    live=""
                    for f in "$@"; do
                        b=$(basename "$f")
                        stem="\${b%.*}" ext="\${b##*.}"
                        # see the matching oext note in the scan pass above
                        oext="$ext"; case "\${ext,,}" in gif) oext="png" ;; esac
                        key=$(printf '%s' "$f" | md5sum | cut -d' ' -f1)
                        live="$live $key"
                        needthumb=0 needblur=0
                        [ "$cachedir/thumbnails/$key.$oext" -nt "$f" ] || needthumb=1
                        if [ "$gb" = "1" ]; then
                            [ "$cachedir/blurred/$key.$oext" -nt "$f" ] || [ -e "$walldir/\${stem}blurred.$ext" ] || needblur=1
                        fi
                        if [ "$needthumb" = "1" ] || [ "$needblur" = "1" ]; then
                            if ! command -v magick >/dev/null 2>&1; then
                                if [ "$warned" = "0" ] && [ "$alerts" = "1" ]; then
                                    warned=1
                                    notify-send -a pibble -i dialog-error -t 0 "magick not found" "ImageMagick's magick is used to generate wallpaper thumbnails and blurred previews - install it for sharper, faster previews."
                                fi
                            else
                                # "$f[0]": first frame only, so an animated
                                # .gif source still yields a static
                                # thumbnail/blur (only the selected/centered
                                # tile/window plays the source file itself)
                                [ "$needthumb" = "1" ] && magick "$f[0]" -resize 480x270^ -gravity center -extent 480x270 "$cachedir/thumbnails/$key.$oext"
                                [ "$needblur" = "1" ] && magick "$f[0]" -resize 1024x -blur 0x10 "$cachedir/blurred/$key.$oext"
                            fi
                        fi
                    done
                    for d in "$cachedir/thumbnails" "$cachedir/blurred"; do
                        for c in "$d"/*; do
                            [ -e "$c" ] || continue
                            k=$(basename "$c"); k="\${k%.*}"
                            case " $live " in *" $k "*) ;; *) rm -f "$c" ;; esac
                        done
                    done`, "_", root.wallDir, root.wallCacheDir, wantBlur ? "1" : "0", root.alertOn("errors") ? "1" : "0"].concat(walls.map(w => w.path)));
            }
        }
    }

    // ---------- uploaded pages (Pages settings row) ----------
    // pages added via the settings row's upload picker live here, gitignored
    // since they're user content, not shell code (see win.pageIds and the
    // "Custom pages" Loader block for how they actually render) — this is
    // also where dropping a page folder in by hand shows it up in the list.
    //
    // Every page is a top-level directory loaded from <dir>/main.qml — a
    // page can be split across as many sibling files as it wants as long
    // as they all live in its own directory. Reach them from main.qml with
    // `import "." as Local` and `Local.Foo {}` — quickshell's own qmldir
    // synthesis (see quickshell.qmlscanner in its logs) shadows the
    // plain-Qt implicit directory import an ordinary QML app would get for
    // free, so an unqualified `Foo {}` or bare `import "."` silently fails
    // to resolve ("Foo is not a type") even though the file sits right
    // there; the qualified form was verified working. A directory with no
    // main.qml is surfaced as a disabled, undeletable-by-toggle row
    // instead of being silently ignored or half-loaded — see the "broken"
    // handling below.
    //
    // counter.example/ — the shipped, tracked example — is a real
    // directory page under a *.example name, which is the convention for
    // a template that shouldn't show up as a real, toggleable row (see the
    // scan below) — copy it out from under that suffix to actually try it.
    readonly property string customPagesDir: Quickshell.shellDir + "/custom-pages"
    function rescanUploadedPages() {
        pagesScan.running = false;
        pagesScan.running = true;
    }
    Process {
        id: pagesScan
        running: true
        command: ["bash", "-c", `
            dir="$1"
            [ -d "$dir" ] || exit 0
            for d in "$dir"/*/; do
                [ -d "$d" ] || continue
                name="$(basename "$d")"
                # *.example directories are inert templates — skip
                # entirely, not even as "broken"
                case "$name" in *.example) continue ;; esac
                if [ -f "$d/main.qml" ]; then
                    printf 'D\\t%s\\n' "$name"
                else
                    printf 'X\\t%s\\n' "$name"
                fi
            done`, "_", root.customPagesDir]
        stdout: StdioCollector {
            onStreamFinished: {
                // reconciles cfg.uploadedPages against what's actually on
                // disk: entries removed outside the app (or trashed via the
                // row's own delete control) drop out, ones added outside
                // the app (or dropped in by hand) show up unchecked — the
                // same merge either way, so external edits and in-app
                // uploads/trashes are indistinguishable once this runs.
                // Each disk line is "D<tab>name" (folder page with a
                // main.qml) or "X<tab>name" (folder missing one — tracked
                // so it gets a row and a one-time notification, but never a
                // loadable/toggleable page).
                const lines = text.trim() ? text.trim().split("\n") : [];
                const found = [];
                for (const line of lines) {
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    found.push({ kind: line.slice(0, tab), name: line.slice(tab + 1) });
                }
                const foundNames = found.map(e => e.name);
                const existing = cfg.uploadedPages ?? [];
                const stillPresent = existing.filter(u => foundNames.includes(u.filename));
                const knownNames = stillPresent.map(u => u.filename);
                const added = found.filter(e => !knownNames.includes(e.name)).map(e => ({
                    id: "folder:" + e.name,
                    label: e.name,
                    filename: e.name,
                    broken: e.kind === "X",
                    path: root.customPagesDir + "/" + e.name,
                    on: false
                }));
                const merged = stillPresent.concat(added);
                if (JSON.stringify(merged) !== JSON.stringify(existing)) {
                    cfg.uploadedPages = merged;
                    // win.fullPageOrder drops any now-stale ids and appends
                    // newly-discovered ones at the end by default; newly
                    // *added* ones (not ones that were merely re-discovered
                    // after an external edit) get spliced out of there and
                    // reinserted directly under the pinned add row instead
                    // — custom pages default to the front of the list,
                    // ahead of the built-in four, not the back
                    const addedIds = added.map(u => u.id);
                    if (addedIds.length) {
                        const order = win.fullPageOrder.filter(id => !addedIds.includes(id));
                        order.splice(1, 0, ...addedIds);
                        cfg.pageOrder = order;
                    } else {
                        cfg.pageOrder = win.fullPageOrder;
                    }
                    root.saveSettings();
                    // new entries start unchecked (see `added` above) with
                    // no other indication they arrived — whether just
                    // uploaded through the row's own picker or dropped into
                    // custom-pages by hand — so nudge the user to go flip
                    // them on instead of leaving them to discover an
                    // inert-looking row on their own. Broken folders get
                    // their own message (there's nothing to "enable"), and
                    // only fire once each — same as a real page, this
                    // fires off `added`, not off however many broken rows
                    // still exist on every later rescan.
                    const goodAdded = added.filter(u => !u.broken);
                    const brokenAdded = added.filter(u => u.broken);
                    if (goodAdded.length && root.alertOn("system")) {
                        const body = goodAdded.length === 1
                            ? goodAdded[0].label + " - enable it in Settings > Pages"
                            : goodAdded.length + " new custom pages - enable them in Settings > Pages";
                        Quickshell.execDetached(["notify-send", "-a", "pibble", "-i", "list-add", "New custom page found", body]);
                    }
                    for (const u of brokenAdded)
                        root.notifyError("Custom page “" + u.label + "” is missing main.qml", "Folders in pibble/custom-pages need a main.qml entry point - see Settings > Pages.");
                }
            }
        }
    }

    // ---------- clipboard history (cliphist) ----------
    property var clips: []
    property bool cliphistAvailable: true
    // cliphist installed but nothing is feeding it (no `wl-paste --watch`
    // running to pipe clipboard changes into `cliphist store`)
    property bool clipWatcherRunning: true
    readonly property string clipThumbDir: cacheRoot + "/clips"
    // scratch file for the notification tint's icon-grab round trip (see
    // the flyout notification Canvas below)
    readonly property string tintGrabPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/pibble-tint.png"
    // re-checked (and re-notified) every time the clips pane is navigated
    // to, not just once per problem — the user wants a reminder each visit
    function checkClipAlert() {
        if (win.pane !== "clips")
            return;
        if (!cliphistAvailable)
            notifyError("cliphist not found", "Install cliphist to enable clipboard history.");
        else if (!clipWatcherRunning)
            notifyError("Clipboard watcher not running",
                "Nothing is piping clipboard changes into cliphist - clipboard history won't update. Run these (e.g. from your compositor's autostart):\n" +
                root.clipWatcherFixCommand);
    }

    Process {
        id: clipScan
        running: false // started after the intro finishes
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
            command -v cliphist >/dev/null || { echo NOCLIPHIST; exit 0; }
            pgrep -x wl-paste >/dev/null 2>&1 && echo WATCH:1 || echo WATCH:0
            cliphist list | head -n "$1" | while IFS=$'\t' read -r id preview; do
                n=$(cliphist decode "$id" 2>/dev/null | wc -c)
                printf '%s\t%s\t%s\n' "$id" "$n" "$preview"
            done`, "_", String(cfg.clipsMax)]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "NOCLIPHIST") {
                    root.cliphistAvailable = false;
                    root.checkClipAlert();
                    return;
                }
                root.cliphistAvailable = true;
                const nl = text.indexOf("\n");
                root.clipWatcherRunning = text.slice(0, nl).trim() === "WATCH:1";
                root.checkClipAlert();
                root.clips = text.slice(nl + 1).split("\n").filter(l => l.trim()).map(l => {
                    const t1 = l.indexOf("\t");
                    const t2 = l.indexOf("\t", t1 + 1);
                    const id = l.slice(0, t1);
                    const bytes = parseInt(l.slice(t1 + 1, t2)) || 0;
                    const preview = l.slice(t2 + 1);
                    const m = preview.match(/^\[\[ binary data ([0-9.]+ \w+) (\w+) (\d+x\d+)/);
                    return m
                        ? { id, bytes, image: true, size: m[1], kind: m[2], dims: m[3], preview: m[2] + " image  " + m[3] + "  " + m[1], thumb: "" }
                        : { id, bytes, image: false, preview: preview.trim() };
                });
                // Sweep cached thumbs (and on-demand full-res decodes) for
                // ids that fell out of the current clipsMax window — runs
                // every scan so the cache never grows past what's shown.
                clipPrune.command = ["bash", "-c", `
                    dir="$1"; shift
                    [ -d "$dir" ] || exit 0
                    for f in "$dir"/*.png; do
                        [ -e "$f" ] || continue
                        b=$(basename "$f" .png)
                        id="\${b%-full}"
                        case " $* " in *" $id "*) ;; *) rm -f "$f" ;; esac
                    done`, "_", root.clipThumbDir].concat(root.clips.map(c => c.id));
                clipPrune.running = true;

                const imgs = root.clips.filter(c => c.image).map(c => c.id);
                if (imgs.length) {
                    clipThumbs.command = ["bash", "-c", `
                        export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
                        dir="$1" alerts="$2"; shift 2
                        mkdir -p "$dir"
                        warned=0
                        # Downscale at generation time so the on-disk thumb is
                        # small: the QML reader thread decodes the whole PNG
                        # before sourceSize applies, so a full-res screenshot
                        # would starve the app-icon decodes queued behind it.
                        for id in "$@"; do
                            [ -s "$dir/$id.png" ] && continue
                            tmp=$(mktemp)
                            cliphist decode "$id" > "$tmp"
                            if command -v magick >/dev/null; then
                                magick "$tmp" -resize '480x640>' "$dir/$id.png" 2>/dev/null || cp "$tmp" "$dir/$id.png"
                            elif command -v convert >/dev/null; then
                                convert "$tmp" -resize '480x640>' "$dir/$id.png" 2>/dev/null || cp "$tmp" "$dir/$id.png"
                            else
                                if [ "$warned" = "0" ] && [ "$alerts" = "1" ]; then
                                    warned=1
                                    notify-send -a pibble -i dialog-error -t 0 "magick not found" "ImageMagick (magick or convert) is used to downscale clipboard image thumbnails - install one to keep memory/decode cost down for large screenshots."
                                fi
                                cp "$tmp" "$dir/$id.png"
                            fi
                            rm -f "$tmp"
                        done`, "_", root.clipThumbDir, root.alertOn("errors") ? "1" : "0"].concat(imgs);
                    clipThumbs.running = true;
                }
            }
        }
    }
    Process {
        id: clipPrune
    }
    Process {
        id: clipThumbs
        onExited: {
            root.clips = root.clips.map(c => c.image
                ? Object.assign({}, c, { thumb: root.clipThumbDir + "/" + c.id + ".png" })
                : c);
        }
    }

    property bool scansStarted: false

    // ---------- fonts ----------
    property var fontFamilies: []
    Process {
        id: fontScan
        running: false // started after the intro finishes
        command: ["bash", "-c", "fc-list :spacing=mono family | sed 's/,.*//' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: root.fontFamilies = text.split("\n").filter(l => l.trim())
        }
    }

    // ---------- icon themes ----------
    property var iconThemes: []
    Process {
        id: iconThemeScan
        running: false // started after the intro finishes
        command: ["bash", "-c", `
            for d in /usr/share/icons/* "$HOME/.icons"/* "$HOME/.local/share/icons"/*; do
                [ -f "$d/index.theme" ] || continue
                grep -q '^Directories=' "$d/index.theme" || continue
                basename "$d"
            done | sort -u`]
        stdout: StdioCollector {
            onStreamFinished: root.iconThemes = text.split("\n").filter(l => l.trim())
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---------- weather (clock page) ----------
    property string weatherText: ""
    property bool weatherOk: false
    Process {
        id: weatherFetch
        // location passed as $1, not interpolated into the script, since
        // cfg.weatherLocation is user-editable free text; PATH is widened
        // since Quickshell launches processes without a login shell's PATH,
        // which otherwise silently hides curl on some setups
        command: ["bash", "-c", `export PATH="$PATH:/usr/bin:/usr/local/bin:/bin"; curl -fs -m 5 "wttr.in/$1?format=%C+%t"`, "_", cfg.weatherLocation]
        stdout: StdioCollector {
            onStreamFinished: {
                // wttr.in's "%C+%t" format collapses to "Condition  +Temp"
                // (double space: the "+" separator plus %C's own trailing
                // padding), so normalize runs of whitespace down to one
                const t = text.trim().replace(/\s+/g, " ");
                root.weatherOk = t.length > 0 && !t.includes("Unknown location");
                root.weatherText = root.weatherOk ? t : "";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("pibble: weather fetch failed:", text.trim());
            }
        }
    }
    Timer {
        interval: 15 * 60 * 1000
        running: cfg.weatherEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            weatherFetch.running = false;
            weatherFetch.running = true;
        }
    }
    // maps the wttr.in condition text to a weather glyph
    function weatherIcon(text) {
        const t = text.toLowerCase();
        if (t.includes("thunder"))
            return root.ti.cloudStorm;
        if (t.includes("snow") || t.includes("sleet") || t.includes("ice"))
            return root.ti.snowflake;
        if (t.includes("rain") || t.includes("drizzle") || t.includes("shower"))
            return root.ti.cloudRain;
        if (t.includes("fog") || t.includes("mist") || t.includes("haze") || t.includes("overcast") || t.includes("cloud"))
            return root.ti.cloud;
        if (t.includes("clear") || t.includes("sunny"))
            return root.ti.sun;
        return "";
    }

    // ---------- battery (clock page) ----------
    readonly property var battDevice: UPower.displayDevice
    readonly property bool batteryPresent: {
        const d = root.battDevice;
        return !!d && d.ready && d.isLaptopBattery;
    }
    readonly property bool batteryCharging: root.batteryPresent && root.battDevice.state === UPowerDeviceState.Charging
    // always icon + percentage, charging or not
    readonly property string batteryText: root.batteryPresent ? Math.round(root.battDevice.percentage * 100) + "%" : ""

    // fires once per discharge dip below 5%, not once per tick; re-arms once
    // the level recovers with some headroom (plugging in, or just climbing
    // back past the boundary) so it can't flap right at the threshold
    property bool lowBatteryAlerted: false
    function checkLowBattery() {
        if (!root.batteryPresent || root.batteryCharging) {
            lowBatteryAlerted = false;
            return;
        }
        const pct = root.battDevice.percentage * 100;
        if (pct <= 5) {
            if (!lowBatteryAlerted) {
                lowBatteryAlerted = true;
                if (alertOn("battery"))
                    Quickshell.execDetached(["notify-send", "-a", "pibble", "-u", "critical",
                        "-i", "battery-low", "-t", "0", "Low battery", Math.round(pct) + "% remaining - plug in soon."]);
            }
        } else if (pct > 8) {
            lowBatteryAlerted = false;
        }
    }
    Connections {
        target: root.battDevice
        function onPercentageChanged() { root.checkLowBattery(); }
        function onStateChanged() { root.checkLowBattery(); }
    }

    PanelWindow {
        id: win

        property bool shown: false
        visible: shown

        function open(targetPane) {
            fadeOut.stop(); // reopening mid-dismiss is allowed
            resetState(targetPane);
            shown = true;
            input.forceActiveFocus();
            // fresh data per open: the clipboard and wallpaper folder change
            // between opens
            clipScan.running = false;
            clipScan.running = true;
            root.rescanWallpapers();
            root.rescanUploadedPages();
        }

        function resetState(targetPane) {
            exiting = false;
            revealStarted = false;
            reveal = 0;
            content.opacity = 0;
            warmingApps = false;
            warmingWalls = false;
            wallWarmTick = 0;
            expandedClip = null;
            cancelCapture();
            input.text = "";
            // panes keep the opacity their last entry animation ended at;
            // reset them before the pane change below, or the entrance
            // animation it triggers (see drawerIn/wallDrawerIn/customPageIn
            // etc, restarted off onPaneChanged) gets clobbered right back
            // to 0.004 by this same reset running after it — a race that's
            // invisible with a real animation duration (it keeps writing
            // opacity every frame regardless) but leaves the pane stuck
            // dim when the tile animation style is "none" and its restart
            // completes synchronously.
            drawer.opacity = 0.004;
            wallDrawer.opacity = 0.004;
            wallCarousel.opacity = 0.004;
            clipDrawer.opacity = 0.004;
            settingsPane.opacity = 0.004;
            for (let i = 0; i < customPagesRepeater.count; i++) {
                const h = customPagesRepeater.itemAt(i);
                if (h)
                    h.opacity = 0.004;
            }
            // panes replay their entrance animation off onPaneChanged (see
            // drawerIn/wallDrawerIn/etc below), which only fires on an
            // actual value change — reopening onto the same pane the
            // launcher was last closed on is otherwise a no-op assignment,
            // so the pane's opacity stays wherever the 0.004 reset above
            // leaves it, with nothing left to animate it back in. Round-trip
            // through a dead value so the assignment always fires a real
            // transition.
            // `pibble toggle <page>` passes targetPane so a closed launcher
            // opens straight onto the requested page instead of the home
            // pane; an invalid/disabled/absent target falls back to home,
            // same rule setPane() uses.
            const home = (targetPane && (targetPane === "settings" || activePanes.includes(targetPane))) ? targetPane : homePane();
            if (pane === home)
                pane = "";
            pane = home;
            paneBeforeSettings = homePane();
            settingsTab = "general";
            selected = 0;
            wallSelected = 0;
            wallCarouselStep = 0;
            clipSelected = 0;
            powerArmed = false;
            powerDragging = false;
            powerRaw = 0;
            rebootArmed = false;
            rebootDragging = false;
            rebootRaw = 0;
        }

        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "pibble-launcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // "grow" styles reveal a circle from a corner (or the center) that
        // expands to cover the screen; "fade" (below) cross-fades content
        // opacity instead. The circle itself is a client-side mask on our
        // own content (see growMask below), so it renders identically on
        // every compositor. Quantized to an int diameter so the mask/region
        // geometry always changes as one step.
        property real reveal: 0
        readonly property bool fadeMode: cfg.launchAnimation === "fade"
        // "none" skips the reveal entirely (see lad() below) — it must not
        // be treated as "grow" just because it isn't "fade".
        readonly property bool noneMode: cfg.launchAnimation === "none"
        readonly property bool growMode: !fadeMode && !noneMode
        readonly property real revW: screen ? screen.width : 0
        readonly property real revH: screen ? screen.height : 0
        readonly property var originFrac: {
            switch (cfg.launchAnimation) {
            case "grow-top-left": return [0, 0];
            case "grow-top-right": return [1, 0];
            case "grow-bottom-left": return [0, 1];
            case "grow-bottom-right": return [1, 1];
            default: return [0.5, 0.5]; // grow-center, and fade (origin unused)
            }
        }
        readonly property real originX: originFrac[0] * revW
        readonly property real originY: originFrac[1] * revH
        // radius needed to cover the farthest screen corner from the origin.
        // At reveal=1 that corner sits exactly on the circle — a
        // zero-width mathematical tangent that the mask's antialiasing/
        // threshold softening (see maskThresholdMin/maskSpreadAtMin below)
        // turns into a visibly rounded notch (all 4 corners for
        // grow-center, since they're all equidistant; just the 1 farthest
        // one otherwise). A small overshoot keeps every corner strictly
        // inside the circle instead of grazing it.
        readonly property real maxRevealRadius: 1.02 * Math.max(
            Math.hypot(originX, originY),
            Math.hypot(revW - originX, originY),
            Math.hypot(originX, revH - originY),
            Math.hypot(revW - originX, revH - originY))
        // Clamped to 1px: an empty region reads as "no region set", which the
        // protocol treats as blur-the-whole-surface — a full-screen blur flash.
        readonly property int revealDiameter: Math.max(1, Math.ceil(2 * maxRevealRadius * reveal))
        // This is a bonus on top of the client-side circle, not what draws
        // it: wherever a compositor implements ext-background-effect-v1,
        // this blurs the same area the circle already occupies. "fade" and
        // "none" have no circle, so they just get the whole surface,
        // statically, for as long as the window is open. Requesting a
        // region at all is what flips background-effect into "on request"
        // on niri, which then defaults xray on too — so with the
        // "Background blur" setting off, don't ask at all.
        BackgroundEffect.blurRegion: !cfg.bgBlur ? null : (win.growMode ? growRegion : fadeBlurRegion)
        Region {
            id: growRegion
            shape: RegionShape.Ellipse
            x: win.originX - win.revealDiameter / 2
            y: win.originY - win.revealDiameter / 2
            width: win.revealDiameter
            height: win.revealDiameter
        }
        Region {
            id: fadeBlurRegion
            width: win.revW
            height: win.revH
        }

        // ---------- pane state ----------
        // Tab cycles the enabled panes; the settings pane sits outside the
        // cycle (opened via the corner button or Ctrl+S).
        property string pane: "clock"
        // every id the Pages settings row can show: the four built-in
        // panes, any uploaded custom pages, and "__add_folder__" (the
        // add-a-page row — a real, reorderable member of this list so it
        // drags like everything else, but not a real page: win/pagesBlock's
        // pageOn/pageToggle/etc. special-case it).
        // Deliberately reads only cfg.uploadedPages, never
        // cfg.pageOrder, so its value (and object identity) stays put
        // across a pure reorder — that's what the settings row's Repeater
        // binds its model to, since rebinding a Repeater's model to a new
        // array/object each time destroys and recreates every delegate.
        // Recreating mid-drag severs the DragHandler's grab after one step,
        // and recreating on every property change (rather than genuine
        // add/remove) skips the position Behavior, so reorders — including
        // a Reset — never animate. Membership only actually changes on
        // upload/trash/disk sync, so this binding is stable the rest of
        // the time.
        readonly property var pageIds: {
            const def = ["clock", "apps", "walls", "clips"];
            // custom pages before the built-in four: this is what the
            // "missing id" top-up in fullPageOrder below falls back to
            // whenever it has to place one without a captured position
            // (see there), so the default order — before anything's ever
            // been dragged — has custom pages at the front
            return (cfg.uploadedPages ?? []).map(u => u.id).concat(def, ["__add_folder__"]);
        }
        // display order for the Pages settings row, layered on top of
        // pageIds above; also what activePanes below filters down to the
        // enabled subset for Tab's cycle order, so dragging a row here
        // reorders the cycle too. The "missing id" top-up loop below is a
        // fallback for ids this doesn't already have an opinion on (should
        // rarely trigger — pagesScan normally captures a new page's
        // position itself, splicing it in right after the add row, i.e.
        // ahead of the built-in four); if it does fire, it appends in
        // pageIds order, which is custom pages first, so still front-
        // leaning rather than landing at the very bottom.
        // "__add_folder__" is pinned to the top unconditionally —
        // stripped out of whatever cfg.pageOrder says and put back at the
        // front every time, not just defaulted there once, since it isn't
        // draggable (see the pageRow DragHandler's `enabled:
        // !pageRow.isAdd`) and nothing else should end up above it either.
        readonly property var fullPageOrder: {
            const valid = pageIds;
            const o = (Array.isArray(cfg.pageOrder) ? cfg.pageOrder : [])
                .filter(p => valid.includes(p) && p !== "__add_folder__");
            for (const v of valid)
                if (!o.includes(v) && v !== "__add_folder__")
                    o.push(v);
            o.unshift("__add_folder__");
            return o;
        }
        function moveFullPage(p: string, to: int) {
            const o = fullPageOrder.filter(x => x !== p);
            o.splice(Math.max(0, Math.min(o.length, to)), 0, p);
            cfg.pageOrder = o;
        }
        function toggleUploadedPage(id: string) {
            const uploaded = cfg.uploadedPages ?? [];
            const u = uploaded.find(x => x.id === id);
            // a broken page (folder missing main.qml — see pagesScan) has
            // nothing to load; its row exists so it can be seen and
            // trashed, not toggled on
            if (!u || u.broken)
                return;
            // keep at least one page enabled overall (built-in or custom),
            // same invariant togglePage enforces for the built-in four
            if (u.on && activePanes.length <= 1)
                return;
            cfg.uploadedPages = uploaded.map(x => x.id === id ? Object.assign({}, x, { on: !x.on }) : x);
            root.saveSettings();
        }
        // cycle order: the four built-ins (gated by cfg.pages) plus any
        // enabled custom page, in fullPageOrder's relative order — a custom
        // page's position among the Pages settings rows is exactly where it
        // sits in Tab's cycle too.
        readonly property var activePanes: {
            const pages = cfg.pages ?? {};
            const uploaded = cfg.uploadedPages ?? [];
            const list = fullPageOrder.filter(id => {
                if (id === "__add_folder__")
                    return false;
                const u = uploaded.find(x => x.id === id);
                return u ? u.on : pages[id] !== false;
            });
            return list.length ? list : ["clock"];
        }
        function homePane(): string {
            return activePanes[0];
        }
        // `pibble toggle <page>` accepts a custom page's bare filename (what
        // `pibble help` lists, e.g. "counter") as well as its real, prefixed
        // id ("folder:counter") — the prefix is internal namespacing (see
        // customPagesDir/pagesScan) that a CLI user shouldn't have to know
        // or type. Falls through unresolved for built-in ids and "settings",
        // which already match activePanes directly.
        function resolvePageArg(p: string): string {
            if (!p || activePanes.includes(p) || p === "settings")
                return p;
            const u = (cfg.uploadedPages ?? []).find(x => x.id.split(":").slice(1).join(":") === p);
            return u ? u.id : p;
        }
        // custom pages that additionally contribute a Settings tab — a
        // loaded page's root item opts in by declaring `settingsTab` (a
        // Component); see PageContext. The tab's label is derived from the
        // page's own folder name (capitalized), not something the page
        // declares itself. Reads customPageHost.pageItem (not the Repeater
        // directly) so this recomputes whenever a page loads/unloads, not
        // just when the set of uploaded pages itself changes.
        readonly property var customSettingsTabs: {
            const tabs = [];
            for (let i = 0; i < customPagesRepeater.count; i++) {
                const h = customPagesRepeater.itemAt(i);
                const it = h ? h.pageItem : null;
                if (it && "settingsTab" in it && it.settingsTab) {
                    const name = h.modelData.label;
                    tabs.push({ pageId: h.modelData.id, label: name.charAt(0).toUpperCase() + name.slice(1), component: it.settingsTab });
                }
            }
            return tabs;
        }
        readonly property bool drawerOpen: pane === "apps"

        // ---------- clock line layout ----------
        // fixed layout, not user-reorderable: battery+weather always
        // combine onto one shared line at the bottom (if either is ticked).
        // date sits directly against the clock — above it when anything
        // else is also showing (so it reads as a header line over the
        // whole block), otherwise below it (just the two of them).
        // cfg.clockShow just controls per-item visibility.
        readonly property var clockVisibleGroups: {
            const show = cfg.clockShow ?? {};
            const dateOn = show.date !== false;
            const bw = [];
            if (show.battery !== false)
                bw.push("battery");
            if (show.weather !== false)
                bw.push("weather");
            const groups = [];
            if (dateOn && bw.length) {
                groups.push(["date"]);
                groups.push(["time"]);
            } else {
                groups.push(["time"]);
                if (dateOn)
                    groups.push(["date"]);
            }
            if (bw.length)
                groups.push(bw);
            return groups;
        }
        function toggleClockItem(id: string): void {
            const show = Object.assign({ date: true, battery: true, weather: true }, cfg.clockShow ?? {});
            show[id] = show[id] === false ? true : false;
            cfg.clockShow = show;
            root.saveSettings();
        }

        function setPane(p: string) {
            input.text = "";
            cancelCapture();
            expandedClip = null;
            pane = (p === "settings" || activePanes.includes(p)) ? p : homePane();
            if (pane === "clips")
                root.checkClipAlert();
        }
        // settings remembers where it was opened from
        property string paneBeforeSettings: "clock"
        property string settingsTab: "general"
        // which page's grid the tile picker on the Grids tab is editing
        property string gridTarget: "apps"
        function toggleSettings() {
            if (pane === "settings") {
                setPane(paneBeforeSettings);
            } else {
                paneBeforeSettings = pane;
                setPane("settings");
            }
        }
        // ---------- swipe-to-power / swipe-to-reboot ----------
        // Dragging down on empty space pulls the pane content down (rubber
        // band) and reveals a ring that strokes itself closed as you drag,
        // like a swipe-to-refresh. Releasing with the ring complete (or the
        // power keybind) arms the "power off?" prompt; Enter then powers
        // off, anything else (Escape, a click, another key) lets go. Dragging
        // up does the same from the bottom edge, arming a "reboot?" prompt
        // instead — same physics, opposite sign, mirrored geometry.
        property bool powerDragging: false
        property real dragGrabY: 0
        property real powerRaw: 0 // raw downward drag distance (finger travel)
        property bool powerArmed: false
        readonly property real powerThreshold: 300
        readonly property real powerProgress: Math.min(1, powerRaw / powerThreshold)
        // content shift lags the finger with increasing resistance
        readonly property real powerPull: 170 * (1 - Math.exp(-powerRaw / 260))
        Behavior on powerRaw {
            enabled: !win.powerDragging
            NumberAnimation { duration: win.had(320); easing.type: Easing.OutCubic }
        }
        Timer {
            // a forgotten armed prompt must not lie in wait to turn the next
            // launch Return into a poweroff: let go on its own after a beat
            interval: 8000
            running: win.powerArmed && !win.powerDragging
            onTriggered: win.disarmPower()
        }
        function disarmPower() {
            powerArmed = false;
            powerRaw = 0;
        }
        // the power keybind plays the pull animation (the powerRaw Behavior
        // animates the ride down) straight into the armed pose: Enter powers
        // off, anything else lets go — same as completing the drag by hand
        function playPower() {
            powerArmed = true;
            powerRaw = powerThreshold;
        }
        function powerOff() {
            Quickshell.execDetached(["systemctl", "poweroff"]);
            exit();
        }

        property bool rebootDragging: false
        property real rebootRaw: 0 // raw upward drag distance (finger travel)
        property bool rebootArmed: false
        readonly property real rebootThreshold: 300
        readonly property real rebootProgress: Math.min(1, rebootRaw / rebootThreshold)
        readonly property real rebootPull: 170 * (1 - Math.exp(-rebootRaw / 260))
        Behavior on rebootRaw {
            enabled: !win.rebootDragging
            NumberAnimation { duration: win.had(320); easing.type: Easing.OutCubic }
        }
        Timer {
            // same forgotten-prompt safety net as power, mirrored
            interval: 8000
            running: win.rebootArmed && !win.rebootDragging
            onTriggered: win.disarmReboot()
        }
        function disarmReboot() {
            rebootArmed = false;
            rebootRaw = 0;
        }
        function playReboot() {
            rebootArmed = true;
            rebootRaw = rebootThreshold;
        }
        function rebootNow() {
            Quickshell.execDetached(["systemctl", "reboot"]);
            exit();
        }
        function cyclePane(dir: int) {
            // inside settings the cycle keybinds walk the settings tabs
            if (pane === "settings") {
                const tabs = ["general", "pages", "keybindings", "flyouts"].concat(customSettingsTabs.map(t => t.pageId));
                settingsTab = tabs[((tabs.indexOf(settingsTab) + dir) % tabs.length + tabs.length) % tabs.length];
                return;
            }
            let i = activePanes.indexOf(pane);
            if (i < 0)
                i = 0;
            setPane(activePanes[((i + dir) % activePanes.length + activePanes.length) % activePanes.length]);
        }

        // ---------- matches ----------
        property var matches: {
            const q = input.text.toLowerCase().trim();
            if (!q) {
                const all = root.allApps.slice();
                all.sort((a, b) => root.launchCount(b) - root.launchCount(a)
                    || a.name.localeCompare(b.name));
                return all;
            }
            const scored = [];
            for (const a of root.allApps) {
                const s = root.fuzzyScore(a.name.toLowerCase(), q);
                if (s !== null)
                    scored.push({ entry: a, score: s });
            }
            scored.sort((x, y) => root.launchCount(y.entry) - root.launchCount(x.entry)
                || y.score - x.score
                || x.entry.name.localeCompare(y.entry.name));
            return scored.map(x => x.entry);
        }
        property int selected: 0
        onMatchesChanged: selected = 0
        readonly property int appPageSize: cfg.appsCols * cfg.appsRows
        readonly property int appPage: appPageSize > 0 ? Math.floor(selected / appPageSize) : 0

        function wallName(wall): string {
            return wall.path.split("/").pop().replace(/\.[^.]+$/, "");
        }
        property var wallMatches: {
            // The "windows" carousel is a spatial strip, not a list: reordering
            // or dropping entries out from under it as the query changes reads
            // as chaos (tiles teleporting to unrelated slots every keystroke).
            // It keeps root.wallpapers's natural order/contents always, and
            // typing instead jumps the selection to the best match — see
            // jumpWallCarousel(), driven from input.onTextChanged.
            if (cfg.wallpaperStyle !== "tiles")
                return root.wallpapers;
            const q = input.text.toLowerCase().trim();
            if (!q)
                return root.wallpapers;
            const scored = [];
            for (const w of root.wallpapers) {
                const s = root.fuzzyScore(wallName(w).toLowerCase(), q);
                if (s !== null)
                    scored.push({ w, s });
            }
            scored.sort((x, y) => y.s - x.s || wallName(x.w).localeCompare(wallName(y.w)));
            return scored.map(x => x.w);
        }
        property int wallSelected: 0
        onWallMatchesChanged: {
            wallSelected = 0;
            wallCarouselStep = 0;
        }
        // Windows-carousel-only: true once a query has no fuzzy match at all
        // anywhere in root.wallpapers, so every tile plays its exit spring
        // (see wcCell.wall below) instead of the carousel sitting frozen on
        // stale content.
        property bool wallCarouselEmpty: false
        // Jumps the (unfiltered) windows carousel to the best fuzzy match for
        // the current query, choosing whichever wrap direction is shorter so
        // the slide always takes the short way around the ring. Called from
        // input.onTextChanged and whenever the walls pane/style is (re)entered
        // with a query already typed.
        function jumpWallCarousel() {
            const q = input.text.toLowerCase().trim();
            if (!q) {
                wallCarouselEmpty = false;
                return;
            }
            let best = -1;
            let bestScore = -Infinity;
            for (let i = 0; i < root.wallpapers.length; i++) {
                const s = root.fuzzyScore(wallName(root.wallpapers[i]).toLowerCase(), q);
                if (s !== null && s > bestScore) {
                    bestScore = s;
                    best = i;
                }
            }
            if (best < 0) {
                wallCarouselEmpty = true;
                return;
            }
            wallCarouselEmpty = false;
            const count = root.wallpapers.length;
            if (count > 0 && best !== wallSelected) {
                let delta = ((best - wallSelected) % count + count) % count;
                if (delta > count / 2)
                    delta -= count;
                wallSelected = best;
                wallCarouselStep += delta;
            }
        }
        readonly property int wallPageSize: cfg.wallsCols * cfg.wallsRows
        readonly property int wallPage: wallPageSize > 0 ? Math.floor(wallSelected / wallPageSize) : 0

        // ---------- wallpaper carousel ("windows" style) ----------
        // Unbounded step counter driving the carousel's animated position:
        // it only ever moves by ±1 per navigation (never wraps), so a
        // Behavior on wallCarouselAnim always eases in the direction the
        // user actually scrolled, even when wallSelected itself wraps
        // around the end of the list. wallSelected stays the authoritative
        // bounded index (what applyWallpaper()/activate() read).
        property int wallCarouselStep: 0
        property real wallCarouselAnim: wallCarouselStep
        Behavior on wallCarouselAnim {
            NumberAnimation { id: wallCarouselAnimAnim; duration: 420; easing.type: Easing.OutCubic }
        }
        // isCenter (Math.abs(rank) < 0.5) goes true well before the slide's
        // eased approach actually reaches rank 0 — gating gif playback on
        // isCenter alone starts the (unpanned, fixed-crop) AnimatedImage
        // mid-slide, while the still frame beside it is still panning,
        // which reads as a jump. Wait for the slide to fully stop first.
        readonly property bool wallCarouselSettled: !wallCarouselAnimAnim.running
        function moveCarousel(dir: int) {
            const count = wallMatches.length;
            if (!count)
                return;
            wallSelected = ((wallSelected + dir) % count + count) % count;
            wallCarouselStep += dir;
        }

        property var clipMatches: {
            const q = input.text.toLowerCase().trim();
            if (!q)
                return root.clips;
            const scored = [];
            for (const c of root.clips) {
                const s = root.fuzzyScore(c.preview.toLowerCase(), q);
                if (s !== null)
                    scored.push({ c, s });
            }
            scored.sort((x, y) => y.s - x.s);
            return scored.map(x => x.c);
        }
        property int clipSelected: 0
        onClipMatchesChanged: clipSelected = 0
        readonly property int clipRowsC: Math.max(2, Math.min(4, cfg.clipsRows))
        readonly property int clipPageSize: cfg.clipsCols * clipRowsC
        readonly property int clipPage: clipPageSize > 0 ? Math.floor(clipSelected / clipPageSize) : 0

        // ---------- navigation ----------
        // Horizontal: previous/next item, wrapping. Vertical: down a row
        // within the column; at the bottom of a column, hop to the top of the
        // next column (next page after the last column), and mirrored for up.
        function hMove(sel: int, count: int, dir: int): int {
            if (!count)
                return 0;
            return ((sel + dir) % count + count) % count;
        }
        // Down walks the entire column — through every page — before hopping
        // to the top of the next column; Up mirrors it.
        function vMove(sel: int, count: int, cols: int, rows: int, dir: int): int {
            if (!count)
                return 0;
            const page = cols * rows;
            const p = Math.floor(sel / page);
            const w = sel % page;
            const r = Math.floor(w / cols);
            const c = w % cols;
            const pages = Math.ceil(count / page);
            if (dir > 0) {
                // next row in this column, continuing onto the next page
                const idx = r < rows - 1 ? sel + cols : (p + 1) * page + c;
                if (idx < count)
                    return idx;
                // column exhausted: top of the next column (first page)
                const nc = c + 1;
                return (nc < cols && nc < count) ? nc : 0;
            } else {
                if (r > 0)
                    return sel - cols;
                if (p > 0)
                    return (p - 1) * page + (rows - 1) * cols + c;
                // top of the column: bottom-most cell of the previous column
                const nc = c > 0 ? c - 1 : cols - 1;
                for (let pp = pages - 1; pp >= 0; pp--) {
                    for (let rr = rows - 1; rr >= 0; rr--) {
                        const idx = pp * page + rr * cols + nc;
                        if (idx < count)
                            return idx;
                    }
                }
                return count - 1;
            }
        }
        function navigate(dx: int, dy: int) {
            if (pane === "apps") {
                const next = dy !== 0
                    ? vMove(selected, matches.length, cfg.appsCols, cfg.appsRows, dy)
                    : hMove(selected, matches.length, dx);
                // Re-stagger when the move crosses onto a new page, so the
                // tile wave replays instead of the whole grid popping at once.
                // Set it before the assignment: the entry rebinding cascade
                // that restarts springIn fires synchronously here, and it
                // reads staggering to compute the per-tile delay.
                pageStagger(appPageSize, selected, next);
                selected = next;
            } else if (pane === "walls") {
                if (cfg.wallpaperStyle !== "tiles") {
                    moveCarousel(dy !== 0 ? dy : dx);
                } else {
                    const next = dy !== 0
                        ? vMove(wallSelected, wallMatches.length, cfg.wallsCols, cfg.wallsRows, dy)
                        : hMove(wallSelected, wallMatches.length, dx);
                    pageStagger(wallPageSize, wallSelected, next);
                    wallSelected = next;
                }
            } else if (pane === "clips") {
                const next = dy !== 0
                    ? vMove(clipSelected, clipMatches.length, cfg.clipsCols, clipRowsC, dy)
                    : hMove(clipSelected, clipMatches.length, dx);
                pageStagger(clipPageSize, clipSelected, next);
                clipSelected = next;
            }
        }
        // Arm the tile stagger when a navigation moves between pages (guarding
        // the zero page-size case the page getters guard against too).
        function pageStagger(size: int, before: int, after: int) {
            if (size > 0 && Math.floor(before / size) !== Math.floor(after / size))
                beginStagger();
        }

        // ---------- actions ----------
        // Launch through gtk-launch (GLib): quickshell's own Exec parser
        // follows the desktop-entry spec strictly, where single quotes are
        // not quoting characters — entries like `Exec=kitty bash -lc '...'`
        // get split mid-quote and crash on startup. GLib parses shell-style
        // (like every GTK-based launcher), and also honors Path= and
        // DBusActivatable. Falls back to the entry's own execute() if
        // gtk-launch can't find the id.
        property var launchEntry: null
        Process {
            id: appLaunch
            onExited: exitCode => {
                if (exitCode !== 0 && win.launchEntry)
                    win.launchEntry.execute();
                win.launchEntry = null;
            }
        }
        function launch(entry) {
            if (!entry)
                return;
            root.recordLaunch(entry);
            launchEntry = entry;
            // The launched app inherits gtk-launch's stdio, i.e. this Process's
            // pipes — which close once gtk-launch exits, so chatty apps
            // (flatpaks especially) would SIGPIPE on their next log line and
            // die seconds after launch. Point stdio at /dev/null and give the
            // app its own session; setsid -w keeps gtk-launch's exit code for
            // the fallback below.
            appLaunch.command = ["bash", "-c", 'command -v gtk-launch >/dev/null || exit 42; setsid -w gtk-launch "$1" >/dev/null 2>&1', "_", entry.id];
            appLaunch.running = true;
            exit();
        }

        function applyWallpaper(wall) {
            if (!wall)
                return;
            // record what was applied so the Dynamic theme can sample this
            // exact file directly, instead of asking the compositor what's
            // currently on screen (see matugenProc)
            cfg.currentWallpaper = wall.path;
            root.saveSettings();
            root.runMatugen();
            // Runs the configurable command with $WALL and $BLUR exported.
            // The blurred variant is only ensured when the command actually
            // references $BLUR, so non-blur setups skip that work entirely.
            Quickshell.execDetached(["bash", "-c", `
                export PATH="$HOME/.local/bin:$PATH"
                WALL="$1"
                BLUR="$2"
                if [ "$5" = "1" ] && [ -z "$BLUR" ]; then
                    mkdir -p "$3/blurred"
                    b=$(basename "$1"); stem="\${b%.*}" ext="\${b##*.}"
                    # gif source blurs to png, not gif: a single decoded frame
                    # re-quantized to a 256-color gif palette bands badly
                    case "\${ext,,}" in gif) ext="png" ;; esac
                    BLUR="$3/blurred/$stem.$ext"
                    if [ ! -e "$BLUR" ]; then
                        if command -v magick >/dev/null 2>&1; then
                            magick "$WALL[0]" -resize 1024x -blur 0x10 "$BLUR"
                        elif [ "$6" = "1" ]; then
                            notify-send -a pibble -i dialog-error -t 0 "magick not found" "ImageMagick's magick is used to generate the blurred wallpaper variant referenced by \\$BLUR - install it to enable blur."
                        fi
                    fi
                fi
                export WALL BLUR
                eval "$4" || { [ "$6" = "1" ] && notify-send -a pibble -i dialog-error -t 0 "Wallpaper command failed" "$4"; }
            `, "_", wall.path, wall.blur, root.wallCacheDir, cfg.wallCommand,
                cfg.wallCommand.includes("$BLUR") ? "1" : "0", root.alertOn("errors") ? "1" : "0"]);
            exit();
        }

        // Enter on a clip copies it and expands the tile into an info card;
        // Enter again (or Escape) collapses it. The launcher stays open.
        property var expandedClip: null
        property string expandedText: ""
        property int expandedBytes: -1
        // full-resolution decode for the expand view: the grid/warm-up thumb
        // (c.thumb) is downscaled on disk to keep the background warm cheap,
        // so expanding needs its own full-res decode. Done lazily here, on
        // the interactive expand action, instead of eagerly for every clip.
        property string expandedFullPath: ""
        property point expandOrigin: Qt.point(0, 0)
        signal expandAnimStart
        signal expandAnimCollapse
        function collapseClip() {
            if (expandedClip)
                expandAnimCollapse();
        }
        function expandClip(clip) {
            if (!clip)
                return;
            expandedClip = clip;
            expandedText = "";
            expandedBytes = -1;
            expandedFullPath = "";
            // cells record expandOrigin synchronously on the change above
            Qt.callLater(() => expandAnimStart());
            // Skip the on-demand decode when the clip's native size already
            // fits the thumb cap (480x640): the thumb (built with magick's
            // "only shrink if larger" >) IS the full-res image there, so
            // decoding again would just swap the Image source to identical
            // pixels — and any source change makes QML clear the current
            // pixmap and reload async, flashing blank for no visual gain.
            const d = (clip.dims || "").split("x");
            const iw = parseInt(d[0]) || 0;
            const ih = parseInt(d[1]) || 0;
            if (clip.image && (iw > 480 || ih > 640)) {
                clipFullImg.forId = clip.id;
                clipFullImg.command = ["bash", "-c", `
                    export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
                    dir="$1"; id="$2"
                    f="$dir/$id-full.png"
                    [ -s "$f" ] || cliphist decode "$id" > "$f"`, "_", root.clipThumbDir, clip.id];
                clipFullImg.running = true;
            }
            // Fast path: decode for the details view immediately so the
            // text reveal runs together with the expand animation.
            infoClipId = clip.id;
            clipInfo.command = ["bash", "-c", `
                export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
                cliphist decode "$1" | wc -c
                [ "$2" = "txt" ] && cliphist decode "$1" | head -c 4000
                exit 0`, "_", clip.id, clip.image ? "img" : "txt"];
            clipInfo.running = true;
            // Slow path: copy (which re-stores the entry under a new id via
            // the watcher), notify, then patch the new id into the list so
            // cached thumbnails stay valid.
            clipCopy.command = ["bash", "-c", `
                export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
                if ! command -v wl-copy >/dev/null 2>&1; then
                    [ "$5" = "1" ] && notify-send -a pibble -i dialog-error -t 0 "wl-copy not found" "wl-copy (wl-clipboard) is used to place clipboard history entries back on the clipboard - install it to copy from this page."
                    exit 0
                fi
                tmp=$(mktemp)
                cliphist decode "$1" > "$tmp"
                wl-copy < "$tmp"
                # the notification body carries the full copied text (images
                # get the description passed in as $4)
                if [ "$2" = "img" ]; then
                    body="$4"
                else
                    body=$(head -c 4000 "$tmp")
                fi
                rm -f "$tmp"
                # copied images ride along as notification media (the decoded
                # entry is already cached by the thumbnail scan)
                if [ "$6" = "1" ]; then
                    if [ "$2" = "img" ] && [ -s "$3/$1.png" ]; then
                        notify-send -a pibble -i edit-copy -h "string:image-path:$3/$1.png" "Copied to clipboard" "$body"
                    else
                        notify-send -a pibble -i edit-copy "Copied to clipboard" "$body"
                    fi
                fi
                sleep 0.3
                nid=$(cliphist list | head -n 1 | cut -f1)
                echo "$nid"
                if [ "$2" = "img" ] && [ -n "$nid" ] && [ "$nid" != "$1" ]; then
                    cp "$3/$1.png" "$3/$nid.png" 2>/dev/null
                fi
                exit 0`, "_", clip.id, clip.image ? "img" : "txt", root.clipThumbDir,
                clip.preview.slice(0, 60), root.alertOn("errors") ? "1" : "0", root.alertOn("system") ? "1" : "0"];
            clipCopy.running = true;
        }
        property string infoClipId: ""
        Process {
            id: clipFullImg
            property string forId: ""
            onExited: (code) => {
                if (code === 0 && forId === win.expandedClip?.id) {
                    win.expandedFullPath = root.clipThumbDir + "/" + forId + "-full.png";
                }
            }
        }
        Process {
            id: clipInfo
            stdout: StdioCollector {
                onStreamFinished: {
                    const nl = text.indexOf("\n");
                    win.expandedBytes = parseInt(text.slice(0, nl).trim()) || 0;
                    win.expandedText = text.slice(nl + 1);
                }
            }
        }
        Process {
            id: clipCopy
            stdout: StdioCollector {
                onStreamFinished: {
                    const nid = text.trim();
                    if (nid && win.infoClipId && nid !== win.infoClipId) {
                        const idx = root.clips.findIndex(c => c.id === win.infoClipId);
                        if (idx >= 0) {
                            const c = root.clips[idx];
                            const upd = Object.assign({}, c, { id: nid });
                            if (c.image && c.thumb)
                                upd.thumb = root.clipThumbDir + "/" + nid + ".png";
                            root.clips = [upd].concat(root.clips.filter(x => x.id !== win.infoClipId));
                        }
                    }
                }
            }
        }
        readonly property var expandedInfo: {
            const c = expandedClip;
            if (!c)
                return [];
            const rows = [];
            rows.push(["type", c.image ? c.kind + " image" : "text"]);
            rows.push(["size", expandedBytes >= 0 ? root.humanBytes(expandedBytes) : (c.image ? c.size : "…")]);
            if (c.image)
                rows.push(["resolution", c.dims]);
            else if (expandedText)
                rows.push(["lines", "" + expandedText.split("\n").length + (expandedBytes > 1500 ? " (truncated)" : "")]);
            return rows;
        }

        function activate() {
            if (pane === "walls")
                applyWallpaper(wallMatches[wallSelected] ?? null);
            else if (pane === "clips") {
                if (expandedClip)
                    collapseClip();
                else
                    expandClip(clipMatches[clipSelected] ?? null);
            } else if (pane === "apps")
                launch(matches.length ? matches[selected] : null);
            else if (pane === "clock")
                setPane("apps");
        }

        // ---------- keybinds ----------
        readonly property var bindDefaults: ({ cycle: "Tab", reverseCycle: "Shift+Tab", launch: "Return", exit: "Escape", settings: "Ctrl+S", power: "Ctrl+P", reboot: "Ctrl+R" })
        // capture (Keybindings tab, click-to-record): capturingBind names the
        // action being recorded; captureHeldKeys tracks which physical keys
        // are still down so the bind only commits once every key of the
        // chord has been released (not on the initial keydown), matching a
        // real "record a shortcut" UX. captureLive always reflects the most
        // recent key event: a bare modifier (Ctrl alone) shows and can still
        // be replaced or extended by whatever's pressed next — pressing a
        // different key switches to that key, holding a modifier and then
        // pressing a real key extends it into "Ctrl+S". Release-time decides
        // whether the final value is actually a complete, saveable chord (a
        // bare modifier alone never is — see bareModifierLabels below).
        property string capturingBind: ""
        property string captureLive: ""
        property var captureHeldKeys: []
        readonly property var bareModifierLabels: ["Ctrl", "Alt", "Shift", "Super"]
        function cancelCapture() {
            capturingBind = "";
            captureLive = "";
            captureHeldKeys = [];
        }
        function modifierLabel(key: int): string {
            switch (key) {
            case Qt.Key_Control: return "Ctrl";
            case Qt.Key_Alt: return "Alt";
            case Qt.Key_Shift: return "Shift";
            case Qt.Key_Meta: return "Super";
            default: return "";
            }
        }
        function keyName(event): string {
            const special = new Map([
                [Qt.Key_Tab, "Tab"], [Qt.Key_Backtab, "Tab"],
                [Qt.Key_Return, "Return"], [Qt.Key_Enter, "Return"],
                [Qt.Key_Escape, "Escape"], [Qt.Key_Space, "Space"],
                [Qt.Key_Backspace, "Backspace"], [Qt.Key_Delete, "Delete"],
                [Qt.Key_Insert, "Insert"],
                [Qt.Key_Home, "Home"], [Qt.Key_End, "End"],
                [Qt.Key_PageUp, "PageUp"], [Qt.Key_PageDown, "PageDown"],
                [Qt.Key_Up, "Up"], [Qt.Key_Down, "Down"], [Qt.Key_Left, "Left"], [Qt.Key_Right, "Right"],
                [Qt.Key_CapsLock, "CapsLock"], [Qt.Key_NumLock, "NumLock"], [Qt.Key_ScrollLock, "ScrollLock"],
                [Qt.Key_Pause, "Pause"], [Qt.Key_Print, "Print"], [Qt.Key_Menu, "Menu"]
            ]);
            let name = special.get(event.key);
            // whether name came from the raw, layout/shift-independent key
            // code (true for everything below) rather than event.text —
            // only the text fallback already bakes Shift into the character
            let fromText = false;
            if (!name && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35)
                name = "F" + (event.key - Qt.Key_F1 + 1);
            // letters/digits from the key code, so Ctrl+letter works (its
            // event.text is a control character) and Shift+letter isn't
            // silently identical to the bare letter
            if (!name && event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
                name = String.fromCharCode(event.key);
            if (!name && event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
                name = String.fromCharCode(event.key);
            if (!name && event.text && event.text.trim() && event.text.charCodeAt(0) >= 32) {
                name = event.text.toUpperCase();
                fromText = true;
            }
            if (!name)
                return "";
            // at most one modifier prefix, so every bind is at most two keys
            let mod = "";
            if (event.modifiers & Qt.ControlModifier)
                mod = "Ctrl+";
            else if (event.modifiers & Qt.AltModifier)
                mod = "Alt+";
            else if ((event.modifiers & Qt.ShiftModifier) && !fromText)
                mod = "Shift+";
            return mod + name;
        }
        function setBind(action: string, key: string) {
            const kb = Object.assign({}, cfg.keybinds);
            kb[action] = key;
            cfg.keybinds = kb;
            root.saveSettings();
        }

        // ---------- exit / intro ----------
        property bool exiting: false
        function exit() {
            if (exiting)
                return;
            exiting = true;
            firstFrames.stop();
            fadeIn.stop();
            fadeOut.restart();
        }

        // resume from a dialog that borrowed the screen (e.g. the Pages
        // tab's upload picker): replays the entrance animation without
        // resetState()'s full reset (pane/tab/selection/rescans), so it lands
        // back exactly where the exit animation left off instead of at the
        // home pane
        function reopenAfterDialog() {
            exiting = false;
            revealStarted = false;
            reveal = 0;
            content.opacity = 0;
            shown = true;
            input.forceActiveFocus();
        }

        // set right before exit() when the close is a hand-off to one of
        // the pages upload dialogs rather than a real dismiss — "file" or
        // "folder", matching which row was tapped; fadeOut's final
        // ScriptAction opens the right one only once the exit animation
        // has fully played, instead of racing it
        property string dialogPending: ""

        ParallelAnimation {
            id: fadeIn
            onFinished: {
                // warm once per daemon run: the thumbs stay pinned by the
                // warm-up Images, so re-ticking the ~2s FrameAnimation on
                // every open just burned frames right as the user started
                // typing (visible as reveal/tile jank on quick Tab presses)
                if (!win.wallsWarmedOnce) {
                    win.wallsWarmedOnce = true;
                    win.warmingWalls = true;
                }
                // deferred one-time startup work (clip scans run per open)
                if (!root.scansStarted) {
                    root.scansStarted = true;
                    iconThemeScan.running = true;
                    fontScan.running = true;
                    if (cfg.theme !== "matugen")
                        root.runMatugen();
                }
            }
            NumberAnimation {
                target: content
                property: "opacity"
                from: 0
                to: 1
                duration: win.lad(win.fadeMode ? 320 : 450)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: win
                property: "reveal"
                from: 0
                to: 1
                // Only visible in "grow" styles — unused by "fade"/"none".
                duration: win.lad(520)
                // Starts at moderate velocity (no ease-in dead zone where the
                // dot seems stuck, no Out-style explosion), settles gently.
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.33, 0.15, 0.2, 1.0, 1.0, 1.0]
            }
        }

        SequentialAnimation {
            id: fadeOut
            ParallelAnimation {
                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 0
                    duration: win.lad(win.fadeMode ? 260 : 320)
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: win
                    property: "reveal"
                    // Only visible in "grow" styles, same as above.
                    to: 0
                    duration: win.lad(320)
                    easing.type: Easing.InQuad
                }
            }
            // hide the window; the daemon keeps running
            ScriptAction {
                script: win.shown = false
            }
            ScriptAction {
                script: {
                    if (win.dialogPending === "folder") {
                        win.dialogPending = "";
                        pagesUploadFolderDialog.open();
                    }
                }
            }
        }

        // ---------- content ----------
        Item {
            id: content
            anchors.fill: parent
            opacity: 0
            // "grow" styles: clip content itself into the growing circle
            // instead of relying on compositor blur to fake one — renders
            // identically on every compositor.
            layer.enabled: win.growMode
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: growMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 0.05
            }

            // Mask shape: same geometry as the blur-region ellipse above, so
            // the client-drawn circle and any compositor blur behind it
            // (where supported) stay in sync.
            //
            // Sized to match content's own bounds (not just the circle) so
            // MultiEffect maps mask <-> source pixel-for-pixel instead of
            // stretching a small texture across the whole surface. Kept
            // genuinely visible (not visible: false) and layered explicitly,
            // since an invisible item's layer never actually renders — a
            // huge offset is what keeps it off the real screen instead.
            Item {
                id: growMask
                visible: true
                layer.enabled: true
                x: -100000
                y: -100000
                width: content.width
                height: content.height

                Rectangle {
                    antialiasing: true
                    x: win.originX - win.revealDiameter / 2
                    y: win.originY - win.revealDiameter / 2
                    width: win.revealDiameter
                    height: win.revealDiameter
                    radius: width / 2
                    color: "white"
                }
            }

            // the swipe-to-power/reboot rubber band, shared: every pane
            // references this one instance, so the pull physics live in a
            // single place. Power pulls content down, reboot pulls it up.
            Translate {
                id: panePull
                y: win.powerPull - win.rebootPull
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(root.surface, cfg.dimOpacity)
            }

            // Background click-catcher; also the scroll-wheel path. Wheel
            // events land here from anywhere on screen: MouseAreas ignore
            // wheel unless they connect onWheel, so tile/button areas pass
            // scrolls down to this full-screen area. (A topmost sibling with
            // a WheelHandler never received the events on this layer surface,
            // so the handler lives on a MouseArea, whose delivery is proven
            // by the click path.)
            MouseArea {
                anchors.fill: parent
                property real wheelAcc: 0
                // swipe-left/right to cycle panes (or, inside settings,
                // settings tabs) — same cyclePane() the Tab/Shift+Tab
                // keybinds drive. Tracked here (rather than with a second,
                // orthogonal DragHandler alongside the power/reboot one
                // below) because PointerHandlers on this layer-shell
                // surface aren't reliably delivered events — see the
                // onWheel note above this MouseArea about the WheelHandler
                // that never fired; MouseArea's own press/move/release is
                // the path already proven to work here.
                property real pressX: 0
                property bool horizTracking: false
                onClicked: {
                    if (win.powerArmed)
                        win.disarmPower();
                    else if (win.rebootArmed)
                        win.disarmReboot();
                    else if (win.expandedClip)
                        win.collapseClip();
                    else if (win.capturingBind)
                        win.cancelCapture();
                    else
                        input.forceActiveFocus();
                }
                onPressed: mouse => {
                    pressX = mouse.x;
                    horizTracking = root.gestureOn("panes");
                }
                onReleased: mouse => {
                    if (horizTracking && Math.abs(mouse.x - pressX) > 80)
                        win.cyclePane(mouse.x - pressX < 0 ? 1 : -1);
                    horizTracking = false;
                }
                onWheel: wheel => {
                    wheelAcc += wheel.angleDelta.y;
                    while (wheelAcc >= 120) {
                        win.navigate(0, -1);
                        wheelAcc -= 120;
                    }
                    while (wheelAcc <= -120) {
                        win.navigate(0, 1);
                        wheelAcc += 120;
                    }
                }

                // swipe-to-power/reboot: a vertical drag that starts on empty
                // space (tile MouseAreas grab their own presses). Same
                // scene-coords pattern as the notification swipe: the content
                // moving under the cursor must not feed back into the drag.
                // One signed delta drives both gestures: downward feeds
                // powerRaw, upward feeds rebootRaw, the other stays at 0.
                DragHandler {
                    target: null
                    enabled: root.gestureOn("power")
                    xAxis.enabled: false
                    yAxis.enabled: true
                    onActiveChanged: {
                        if (active) {
                            win.powerDragging = true;
                            win.rebootDragging = true;
                            win.dragGrabY = centroid.scenePosition.y - win.powerRaw + win.rebootRaw;
                        } else {
                            win.powerDragging = false;
                            win.rebootDragging = false;
                            if (win.powerProgress >= 1) {
                                // hold the completed pose and wait for Enter
                                win.powerArmed = true;
                                win.powerRaw = win.powerThreshold;
                            } else {
                                win.disarmPower(); // springs back up
                            }
                            if (win.rebootProgress >= 1) {
                                win.rebootArmed = true;
                                win.rebootRaw = win.rebootThreshold;
                            } else {
                                win.disarmReboot();
                            }
                        }
                    }
                    onCentroidChanged: {
                        if (active) {
                            const delta = centroid.scenePosition.y - win.dragGrabY;
                            win.powerRaw = Math.max(0, delta);
                            win.rebootRaw = Math.max(0, -delta);
                        }
                    }
                }
            }

            // Idle state: big clock + date. The outer gate holds the clock
            // back until the blur hole is large enough to accommodate it.
            Item {
                id: clockGate
                anchors.centerIn: parent
                width: clockView.width
                height: clockView.height
                transform: panePull
                visible: win.pane === "clock"
                onVisibleChanged: if (visible) fadeUp.restart()
                // "grow" styles: fade in only once the hole (from wherever it
                // originates) has grown enough to reach and contain the
                // clock. "fade" has no hole — content's own opacity fade
                // (plus clockView's own fadeUp below) is the whole effect.
                opacity: {
                    if (win.fadeMode)
                        return 1;
                    const rc = (Math.hypot(width, height) + 60) / 2;
                    const dist = Math.hypot(win.originX - win.revW / 2, win.originY - win.revH / 2);
                    const radius = win.revealDiameter / 2;
                    return Math.max(0, Math.min(1, (radius - dist - rc * 0.8) / (rc * 0.5)));
                }

                Column {
                    id: clockView
                    anchors.centerIn: parent
                    spacing: 8
                    // a line's own opacity fade (below) changes whether the
                    // Column counts it in the layout; animate that reflow
                    // too so sibling lines slide to their new spot instead
                    // of jumping (e.g. the battery/weather line growing in
                    // once weather finishes its first fetch)
                    move: Transition {
                        NumberAnimation { property: "y"; duration: 240; easing.type: Easing.OutCubic }
                    }

                    // one line per group in win.clockVisibleGroups; the
                    // "time" line renders big only when it's alone on its
                    // line, so merging it with other items falls back to the
                    // small line-item size below
                    Repeater {
                        model: win.clockVisibleGroups

                        Row {
                            id: clockLine
                            required property var modelData
                            // membership in modelData is settings-driven and
                            // stable; runtime availability (battery present,
                            // weather fetched) only ever fades a segment in
                            // place via its own opacity below — it never adds
                            // to or removes from this Repeater's model, so
                            // Row's move transition can animate every reflow
                            // instead of anything popping
                            function isAvailable(id) {
                                return id === "time" || id === "date"
                                    || (id === "battery" && root.batteryText.length > 0)
                                    || (id === "weather" && root.weatherOk);
                            }
                            readonly property var availableIds: modelData.filter(isAvailable)
                            readonly property bool bigTime: modelData.length === 1 && modelData[0] === "time"
                            anchors.horizontalCenter: parent.horizontalCenter
                            // a segment appearing/disappearing changes this
                            // line's total width, which recenters it; smooth
                            // that recenter too so the line doesn't hop
                            // sideways while a segment fades
                            Behavior on x {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                            move: Transition {
                                NumberAnimation { property: "x"; duration: 220; easing.type: Easing.OutCubic }
                            }
                            spacing: bigTime ? 0 : 8
                            // fades the whole line in/out (e.g. weather still
                            // loading, or no battery on this machine) rather
                            // than popping it in/out of the Column; stays in
                            // the layout until nearly invisible so the fade
                            // reads as a smooth grow, not a snap
                            opacity: availableIds.length > 0 ? 1 : 0
                            visible: opacity > 0.01
                            Behavior on opacity {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }

                            Repeater {
                                // static per-line membership — see
                                // clockLine.isAvailable above
                                model: clockLine.modelData

                                Row {
                                    id: seg
                                    required property string modelData
                                    required property int index
                                    readonly property bool available: clockLine.isAvailable(modelData)
                                    readonly property bool isFirstVisible: clockLine.availableIds.length > 0 && clockLine.availableIds[0] === modelData
                                    spacing: seg.modelData === "weather" ? 8 : 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    // an unavailable segment (no battery, or
                                    // weather not fetched yet) fades out in
                                    // place instead of leaving the model, same
                                    // trick as segIcon below, one level up
                                    opacity: available ? 1 : 0
                                    visible: opacity > 0.01
                                    Behavior on opacity {
                                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                    }
                                    // segIcon/segValue fade in/out in place
                                    // rather than popping, but Row still
                                    // repositions siblings the instant that
                                    // happens; animate that reflow too so
                                    // nothing jumps while a segment fades
                                    move: Transition {
                                        NumberAnimation { property: "x"; duration: 220; easing.type: Easing.OutCubic }
                                    }

                                    Text {
                                        visible: !seg.isFirstVisible
                                        text: "·"
                                        color: root.muted
                                        anchors.verticalCenter: parent.verticalCenter
                                        font { family: root.mono; pixelSize: root.fs(14) }
                                    }
                                    Text {
                                        id: segIcon
                                        // Row has no exit transition (only "add"/"move"), so
                                        // an item mid-fade-out has to stay visible and keep
                                        // its old glyph on screen instead of just vanishing:
                                        // frozenText holds the last real icon, only updating
                                        // the instant a new one arrives, while opacity (not
                                        // "visible") tracks whether one should currently show
                                        // — dropping out of the layout only once it's faded
                                        // low enough not to be noticed
                                        readonly property string iconText: seg.modelData === "battery" ? (root.batteryCharging ? root.ti.bolt : "")
                                            : seg.modelData === "weather" ? root.weatherIcon(root.weatherText) : ""
                                        property string frozenText: iconText
                                        onIconTextChanged: if (iconText.length > 0) frozenText = iconText
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: opacity > 0.01
                                        opacity: iconText.length > 0 ? 1 : 0
                                        Behavior on opacity {
                                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                        }
                                        text: frozenText
                                        color: seg.modelData === "battery" ? root.accent : root.muted
                                        font { family: root.iconFont; pixelSize: root.fs(16) }
                                    }
                                    Text {
                                        // same freeze trick as segIcon above: hold the
                                        // last real value while the segment fades out so
                                        // the text doesn't blank before it's gone
                                        readonly property string valueText: seg.modelData === "time" ? Qt.formatDateTime(clock.date, "HH:mm")
                                            : seg.modelData === "date" ? Qt.formatDateTime(clock.date, "dddd, MMMM d")
                                            : seg.modelData === "battery" ? root.batteryText : root.weatherText
                                        property string frozenValue: valueText
                                        onValueTextChanged: if (valueText.length > 0) frozenValue = valueText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: frozenValue
                                        color: seg.modelData === "date" ? root.muted
                                            : seg.modelData === "battery" ? (root.batteryCharging ? root.accent : root.muted)
                                            : seg.modelData === "weather" ? root.muted : root.fg
                                        font {
                                            family: root.mono
                                            pixelSize: seg.modelData === "time" && clockLine.bigTime ? root.fs(120) : root.fs(seg.modelData === "date" ? 17 : 14)
                                            weight: seg.modelData === "time" && clockLine.bigTime ? Font.DemiBold : Font.Normal
                                            letterSpacing: seg.modelData === "date" ? 3 : 1
                                            capitalization: seg.modelData === "date" ? Font.AllUppercase : Font.MixedCase
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ParallelAnimation {
                        id: fadeUp
                        NumberAnimation { target: clockView; property: "opacity"; from: 0; to: 1; duration: win.ad(300); easing.type: Easing.OutCubic }
                        NumberAnimation { target: clockView; property: "anchors.verticalCenterOffset"; from: 10; to: 0; duration: win.ad(300); easing.type: Easing.OutCubic }
                    }
                }
            }

            // App drawer: paged grid of app tiles
            Item {
                id: drawer
                anchors.centerIn: parent
                width: cfg.appsCols * 174 + (cfg.appsCols - 1) * 24 + 52
                height: grid.height + 52
                transform: panePull
                opacity: 0.004
                visible: win.drawerOpen || win.warmingApps
                Connections {
                    target: win
                    function onPaneChanged() {
                        if (win.pane === "apps")
                            drawerIn.restart();
                    }
                }

                ParallelAnimation {
                    id: drawerIn
                    NumberAnimation { target: drawer; property: "opacity"; from: 0; to: 1; duration: win.ad(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: drawer; property: "scale"; from: 0.9; to: 1; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: drawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Grid {
                    id: grid
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    columns: cfg.appsCols
                    columnSpacing: 24
                    rowSpacing: 24

                    Repeater {
                        model: win.appPageSize

                        Item {
                            id: cell
                            required property int index
                            width: 174
                            height: 100

                            readonly property int appIndex: win.appPage * win.appPageSize + index
                            property var entry: win.matches[appIndex] ?? null
                            property var shownEntry: null
                            property bool filled: false
                            readonly property bool isSelected: entry !== null && win.selected === cell.appIndex

                            onEntryChanged: {
                                if (entry) {
                                    const wasFilled = filled;
                                    const isNew = !wasFilled || !shownEntry || shownEntry.id !== entry.id;
                                    shownEntry = entry;
                                    filled = true;
                                    if (isNew) {
                                        springIn.stop();
                                        springOut.stop();
                                        if (wasFilled) {
                                            // direct replacement (filter narrowed and a
                                            // different app slid into this slot): snap
                                            // straight to the resting state, no animation
                                            wrap.opacity = 1;
                                            wrap.scale = 1;
                                            wrap.y = 0;
                                        } else {
                                            springIn.restart();
                                        }
                                    }
                                } else if (filled) {
                                    // ghost: the old tile springs out in place
                                    filled = false;
                                    springIn.stop();
                                    springOut.restart();
                                }
                            }
                            // replay the wave when the drawer opens: cells
                            // were already filled while it was hidden
                            Connections {
                                target: win
                                function onPaneChanged() {
                                    if (win.pane === "apps" && cell.filled)
                                        springIn.restart();
                                }
                            }

                            Column {
                                id: wrap
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 8
                                opacity: 0

                                Item {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 76
                                    height: 76

                                    Rectangle {
                                        visible: cell.isSelected
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        radius: 23
                                        color: "transparent"
                                        border.width: 3
                                        border.color: Qt.alpha(root.accent, 0.33)
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: Qt.alpha(root.accent, cell.isSelected ? 0.22 : 0.11)
                                        border.width: 1
                                        border.color: cell.isSelected ? root.accent : Qt.alpha(root.accent, 0.33)

                                        Image {
                                            id: icon
                                            anchors.centerIn: parent
                                            width: 44
                                            height: 44
                                            sourceSize: Qt.size(88, 88)
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectFit
                                            source: root.iconUrl(cell.shownEntry ? cell.shownEntry.icon : "")
                                            visible: status === Image.Ready
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !icon.visible
                                            text: (cell.shownEntry ? cell.shownEntry.name : "").slice(0, 2).toUpperCase()
                                            color: root.accent
                                            font { family: root.mono; pixelSize: root.fs(16); weight: Font.Bold }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: cell.filled
                                            onClicked: win.launch(cell.entry)
                                        }
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(implicitWidth, 76)
                                    height: 16
                                    text: cell.shownEntry ? cell.shownEntry.name : ""
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    color: root.fg
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                            }

                            SequentialAnimation {
                                id: springIn
                                PropertyAction { target: wrap; property: "opacity"; value: 0 }
                                PropertyAction { target: wrap; property: "scale"; value: win.animFromScale }
                                PropertyAction { target: wrap; property: "y"; value: win.animFromY }
                                PauseAnimation { duration: win.animDelay(cell.index, cfg.appsCols) }
                                ParallelAnimation {
                                    NumberAnimation { target: wrap; property: "opacity"; to: 1; duration: win.animFadeDur; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: wrap; property: "scale"; to: 1; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                                    NumberAnimation { target: wrap; property: "y"; to: 0; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                                }
                            }

                            SequentialAnimation {
                                id: springOut
                                ParallelAnimation {
                                    NumberAnimation { target: wrap; property: "scale"; to: win.animOutBounce ? 1.08 : 1; duration: win.animOutBounce ? win.ad(80) : 0; easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: wrap; property: "scale"; to: win.animFromScale; duration: win.ad(win.animOutSettleDur); easing.type: win.animOutEase }
                                    NumberAnimation { target: wrap; property: "opacity"; to: 0; duration: win.ad(win.animOutSettleDur); easing.type: win.animOutEase }
                                }
                            }
                        }
                    }
                }

            }

            // Empty state: fades in only once the last exiting tile has
            // fully sprung out (win.ad(400), matching drawer's springOut)
            // instead of popping in on top of tiles still animating away;
            // snaps back to hidden the instant results reappear so it's
            // ready to fade in again next time. Centered on the pane like
            // the wallpaper/clip empty states below, not inside `drawer`
            // (whose box stays the full grid size regardless of match count).
            Text {
                id: appsNoMatches
                visible: win.pane === "apps" && opacity > 0
                anchors.centerIn: parent
                opacity: 0
                text: root.allApps.length === 0 ? "no apps found" : "no matches"
                color: root.muted
                font { family: root.mono; pixelSize: root.fs(14) }

                Connections {
                    target: win
                    function onMatchesChanged() {
                        if (win.matches.length === 0)
                            appsNoMatchesFade.restart();
                        else {
                            appsNoMatchesFade.stop();
                            appsNoMatches.opacity = 0;
                        }
                    }
                }
                SequentialAnimation {
                    id: appsNoMatchesFade
                    PauseAnimation { duration: win.ad(400) }
                    NumberAnimation { target: appsNoMatches; property: "opacity"; to: 1; duration: win.ad(220); easing.type: Easing.OutCubic }
                }
            }

            // Wallpaper selector
            Item {
                id: wallDrawer
                anchors.centerIn: parent
                width: cfg.wallsCols * 240 + (cfg.wallsCols - 1) * 24 + 52
                height: wallGrid.height + 52
                transform: panePull
                opacity: 0.004
                // during warm-up, show the pane only after all thumbnail
                // textures are uploaded, so its first frame reuses them
                visible: cfg.wallpaperStyle === "tiles"
                    && (win.pane === "walls" || (win.warmingWalls && win.wallWarmTick > root.wallpapers.length))
                Connections {
                    target: win
                    function onPaneChanged() {
                        if (win.pane === "walls" && cfg.wallpaperStyle === "tiles")
                            wallIn.restart();
                    }
                }

                ParallelAnimation {
                    id: wallIn
                    NumberAnimation { target: wallDrawer; property: "opacity"; from: 0; to: 1; duration: win.ad(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: wallDrawer; property: "scale"; from: 0.9; to: 1; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: wallDrawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Grid {
                    id: wallGrid
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    columns: cfg.wallsCols
                    columnSpacing: 24
                    rowSpacing: 24

                    Repeater {
                        model: win.wallPageSize

                        Item {
                            id: wallCell
                            required property int index
                            readonly property int wallIndex: win.wallPage * win.wallPageSize + index
                            readonly property var wall: win.wallMatches[wallIndex] ?? null
                            readonly property bool isSelected: wall !== null && win.wallSelected === wallIndex
                            width: 240
                            height: 159

                            visible: !win.warmingWalls || win.wallWarmTick > root.wallpapers.length + index + 1

                            property var shownWall: null
                            property bool filled: false
                            onWallChanged: {
                                if (wall) {
                                    const wasFilled = filled;
                                    const isNew = !wasFilled || !shownWall || shownWall.path !== wall.path;
                                    shownWall = wall;
                                    filled = true;
                                    if (isNew) {
                                        wallSpringIn.stop();
                                        wallSpringOut.stop();
                                        if (wasFilled) {
                                            // direct replacement: snap straight to the
                                            // resting state, no animation
                                            wallWrap.opacity = 1;
                                            wallWrap.scale = 1;
                                            wallWrap.y = 0;
                                        } else {
                                            wallSpringIn.restart();
                                        }
                                    }
                                } else if (filled) {
                                    filled = false;
                                    wallSpringIn.stop();
                                    wallSpringOut.restart();
                                }
                            }
                            // replay the spring when the selector opens: the
                            // cells were already filled while it was hidden
                            Connections {
                                target: win
                                function onPaneChanged() {
                                    if (win.pane === "walls" && wallCell.filled)
                                        wallSpringIn.restart();
                                }
                            }

                            Item {
                                id: wallWrap
                                width: 240
                                height: 159
                                opacity: 0

                                Rectangle {
                                    visible: wallCell.isSelected
                                    anchors.fill: thumb
                                    anchors.margins: -5
                                    radius: 19
                                    color: "transparent"
                                    border.width: 3
                                    border.color: Qt.alpha(root.accent, 0.33)
                                }
                                ClippingRectangle {
                                    id: thumb
                                    width: 240
                                    height: 135
                                    radius: 14
                                    color: Qt.alpha(root.accent, wallCell.isSelected ? 0.22 : 0.11)

                                    // Only the selected tile plays its .gif (from
                                    // the source file, not the static thumbnail);
                                    // every other tile stays a still frame so
                                    // scrolling the grid doesn't decode a movie
                                    // per cell.
                                    readonly property bool animating: wallCell.isSelected && !!wallCell.shownWall?.gif

                                    Image {
                                        anchors.fill: parent
                                        visible: !thumb.animating
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(480, 270)
                                        source: wallCell.shownWall ? "file://" + wallCell.shownWall.thumb : ""
                                    }
                                    AnimatedImage {
                                        anchors.fill: parent
                                        visible: thumb.animating
                                        playing: thumb.animating
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        source: thumb.animating ? "file://" + wallCell.shownWall.path : ""
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: wallCell.filled
                                        onClicked: win.applyWallpaper(wallCell.wall)
                                    }
                                }
                                // Stroke above the image, not a border on thumb
                                // (ClippingRectangle): the clip mask and an
                                // underlying border rasterize a pixel apart, so
                                // the image eats the bottom (and right) stroke —
                                // same image-over-border effect as the carousel's
                                // wcThumb stroke below.
                                Rectangle {
                                    anchors.fill: thumb
                                    radius: 14
                                    color: "transparent"
                                    border.width: 1
                                    border.color: wallCell.isSelected ? root.accent : Qt.alpha(root.accent, 0.33)
                                }
                                Text {
                                    anchors.top: thumb.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(implicitWidth, 220)
                                    height: 16
                                    text: wallCell.shownWall ? win.wallName(wallCell.shownWall) : ""
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    color: root.fg
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                            }

                            SequentialAnimation {
                                id: wallSpringIn
                                PropertyAction { target: wallWrap; property: "opacity"; value: 0 }
                                PropertyAction { target: wallWrap; property: "scale"; value: win.animFromScale }
                                PropertyAction { target: wallWrap; property: "y"; value: win.animFromY }
                                PauseAnimation { duration: win.animDelay(wallCell.index, cfg.wallsCols) }
                                ParallelAnimation {
                                    NumberAnimation { target: wallWrap; property: "opacity"; to: 1; duration: win.animFadeDur; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: wallWrap; property: "scale"; to: 1; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                                    NumberAnimation { target: wallWrap; property: "y"; to: 0; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                                }
                            }

                            SequentialAnimation {
                                id: wallSpringOut
                                ParallelAnimation {
                                    NumberAnimation { target: wallWrap; property: "scale"; to: win.animOutBounce ? 1.08 : 1; duration: win.animOutBounce ? win.ad(80) : 0; easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: wallWrap; property: "scale"; to: win.animFromScale; duration: win.ad(win.animOutSettleDur); easing.type: win.animOutEase }
                                    NumberAnimation { target: wallWrap; property: "opacity"; to: 0; duration: win.ad(win.animOutSettleDur); easing.type: win.animOutEase }
                                }
                            }
                        }
                    }
                }
            }

            // Wallpaper selector — "windows" style: an infinite horizontal
            // carousel of narrow parallax "windows", the selected wallpaper
            // always centered (see cfg.wallpaperStyle, win.moveCarousel()).
            Item {
                id: wallCarousel
                anchors.centerIn: parent
                // slots actually shown; delegates beyond that (up to
                // restSpan) sit pre-positioned but faded out, ready to slide
                // into view without popping in from nowhere
                readonly property int halfVisible: Math.floor((cfg.wallsVisible - 1) / 2)
                readonly property int bufferSlots: 2
                readonly property int restSpan: halfVisible + bufferSlots
                readonly property int totalSlots: 2 * restSpan + 1
                // A count change strands the Repeater's surviving delegates:
                // their absStep was imperatively relabeled by rebalance()
                // (congruent mod the *old* totalSlots), and freshly added
                // ones init assuming step 0 — so rebuild the whole
                // contiguous window around the current selection, keeping
                // wallCarouselStep congruent with wallSelected. callLater
                // lets the Repeater finish adding/removing delegates first;
                // the carousel is hidden while the settings pane is open,
                // so the relayout is never seen.
                onTotalSlotsChanged: Qt.callLater(() => {
                    win.wallCarouselStep = win.wallSelected;
                    for (let i = 0; i < wcRepeater.count; i++) {
                        const c = wcRepeater.itemAt(i);
                        if (c)
                            c.absStep = win.wallSelected + i - restSpan;
                    }
                })
                readonly property int barWidth: 205
                readonly property int barHeight: 440
                readonly property int slotSpacing: 240
                readonly property real parallaxPx: cfg.wallpaperStyle === "windows-flat" ? 0 : 75
                readonly property int captionGap: 14
                width: (2 * halfVisible + 1) * slotSpacing
                height: barHeight + captionGap + 22
                transform: panePull
                opacity: 0.004
                visible: cfg.wallpaperStyle !== "tiles" && win.pane === "walls"

                Connections {
                    target: win
                    function onPaneChanged() {
                        if (win.pane === "walls" && cfg.wallpaperStyle !== "tiles") {
                            win.jumpWallCarousel();
                            carouselIn.restart();
                        }
                    }
                }

                ParallelAnimation {
                    id: carouselIn
                    NumberAnimation { target: wallCarousel; property: "opacity"; from: 0; to: 1; duration: win.ad(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: wallCarousel; property: "scale"; from: 0.9; to: 1; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: wallCarousel; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Repeater {
                    id: wcRepeater
                    // fixed count: delegate identity (and its absStep) must
                    // stay stable across steps so the strip visibly slides
                    // instead of the content teleporting into static slots
                    model: wallCarousel.totalSlots

                    Item {
                        id: wcCell
                        required property int index
                        property int absStep: index - wallCarousel.restSpan
                        readonly property real rank: absStep - win.wallCarouselAnim
                        readonly property int count: win.wallMatches.length
                        readonly property int wallIndex: count > 0 ? ((absStep % count) + count) % count : -1
                        readonly property var wall: (wallIndex >= 0 && !win.wallCarouselEmpty) ? win.wallMatches[wallIndex] : null
                        readonly property bool isCenter: wallIndex >= 0 && wallIndex === win.wallSelected && Math.abs(rank) < 0.5
                        // drives the ring/stroke/fill selection highlight
                        // below; continuous in |rank| (not isCenter's hard
                        // cutoff) so it cross-fades with the slide instead
                        // of snapping — see wallCell's isSelected boolean
                        // toggle above for how the static tiles grid does it
                        readonly property real selFade: Math.max(0, 1 - Math.abs(rank) * 2)
                        // left-to-right visual slot, for the same wave/slide
                        // stagger the tile grids use (see win.animDelay)
                        readonly property int visSlot: Math.max(0, Math.min(wallCarousel.halfVisible * 2,
                            Math.round(rank) + wallCarousel.halfVisible))

                        // once a cell has drifted a full step past the resting
                        // buffer, relabel it to the opposite edge (±totalSlots
                        // keeps it congruent mod the ring) — by then it's
                        // faded to 0 opacity, so the relabel is invisible
                        function rebalance() {
                            while (absStep - win.wallCarouselAnim > wallCarousel.restSpan + 1)
                                absStep -= wallCarousel.totalSlots;
                            while (absStep - win.wallCarouselAnim < -(wallCarousel.restSpan + 1))
                                absStep += wallCarousel.totalSlots;
                        }
                        Connections {
                            target: win
                            function onWallCarouselAnimChanged() { wcCell.rebalance(); }
                            function onWallMatchesChanged() {
                                wcCell.absStep = wcCell.index - wallCarousel.restSpan;
                            }
                            // replay the spring when the selector opens: the
                            // cell was already filled while it was hidden, so
                            // onWallChanged alone won't fire (see wallCell's
                            // identical hook for the "tiles" style)
                            function onPaneChanged() {
                                if (win.pane === "walls" && cfg.wallpaperStyle !== "tiles" && wcCell.filled)
                                    wcSpringIn.restart();
                            }
                        }

                        x: parent.width / 2 - width / 2 + rank * wallCarousel.slotSpacing
                        y: 0
                        width: wallCarousel.barWidth
                        height: wallCarousel.barHeight
                        z: -Math.abs(rank)
                        // continuous in rank (exactly 1 at rank 0) — an
                        // isCenter branch here would snap scale mid-slide
                        // the moment rank crosses 0.5
                        scale: Math.max(0.82, 1 - Math.abs(rank) * 0.05)
                        // No wall===null cut here (unlike the plain
                        // opacity/rank cull below): a cell losing its wall
                        // (query no longer matches, list emptied) still needs
                        // to render while wcWrap's own opacity plays the exit
                        // spring — hard-cutting the parent to 0 here would
                        // hide that animation entirely. A cell that's never
                        // had a wall (count === 0) just stays invisible via
                        // wcWrap's untouched initial opacity of 0.
                        opacity: Math.max(0, Math.min(1, wallCarousel.halfVisible + 1 - Math.abs(rank)))

                        // entrance/exit spring for this window's content,
                        // replayed whenever filtering changes which wallpaper
                        // it shows — same wave/pop/fade/slide/none language
                        // (cfg.animStyle) and stagger the tile grids use
                        property var shownWall: null
                        property bool filled: false
                        onWallChanged: {
                            if (wall) {
                                const wasFilled = filled;
                                const isNew = !wasFilled || !shownWall || shownWall.path !== wall.path;
                                shownWall = wall;
                                filled = true;
                                if (isNew) {
                                    wcSpringIn.stop();
                                    wcSpringOut.stop();
                                    if (wasFilled) {
                                        // direct replacement: snap straight to the
                                        // resting state, no animation
                                        wcWrap.opacity = 1;
                                        wcWrap.scale = 1;
                                        wcWrap.y = 0;
                                    } else {
                                        wcSpringIn.restart();
                                    }
                                }
                            } else if (filled) {
                                filled = false;
                                wcSpringIn.stop();
                                wcSpringOut.restart();
                            }
                        }

                        Item {
                            id: wcWrap
                            anchors.fill: parent
                            opacity: 0

                            // selected-tile ring from the tiles grid (see
                            // wallCell above), reused here: sits behind
                            // wcThumb and is larger by the same margin, so
                            // it never overlaps the thumbnail itself, just
                            // frames it. Opacity tracks |rank| continuously
                            // (not wcCell.isCenter's hard cutoff) so it
                            // cross-fades smoothly between the outgoing and
                            // incoming centered card as the carousel slides,
                            // instead of popping on/off mid-transition.
                            // Anchored to parent (wcWrap), not wcThumb — same
                            // reason the inner stroke below is: anchoring to
                            // the ClippingRectangle sibling instead of the
                            // plain, non-clipping parent visibly jittered the
                            // ring every frame while wcCell's scale animated.
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -5
                                radius: 17
                                color: "transparent"
                                border.width: 3
                                border.color: Qt.alpha(root.accent, 0.33)
                                opacity: wcCell.selFade
                            }
                            ClippingRectangle {
                                id: wcThumb
                                anchors.fill: parent
                                radius: 12
                                color: Qt.alpha(root.accent, 0.08 + 0.08 * wcCell.selFade)

                                Image {
                                    // wider than the bar and panned opposite the
                                    // scroll direction, so each window reads as
                                    // a fixed frame onto a slowly-drifting
                                    // backdrop. The pan is driven by the cell's
                                    // rank — bounded, unlike wallCarouselAnim,
                                    // whose unbounded growth would slide the
                                    // backdrop out of the frame after a few
                                    // steps in one direction — and the image is
                                    // wide enough to cover the whole fade range
                                    // (|rank| <= halfVisible + 1; past that the
                                    // cell is fully transparent, so further
                                    // overshoot is invisible). The full-res
                                    // source (not the 480x270 tile thumbnail,
                                    // which is already cropped tight to a
                                    // landscape frame and has no spare width to
                                    // pan through) decoded at bar height keeps
                                    // the pan free of seams.
                                    width: wallCarousel.barWidth + ((wallCarousel.halfVisible + 1) * wallCarousel.parallaxPx + 20) * 2
                                    height: parent.height
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: (parent.width - width) / 2 - wcCell.rank * wallCarousel.parallaxPx
                                    // hidden once the centered gif takes over below,
                                    // so its still frame doesn't show through at
                                    // slightly different crop/pan geometry
                                    visible: !wcThumb.animating
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize: Qt.size(0, wallCarousel.barHeight)
                                    // shownWall, not wall: wall goes null the instant
                                    // the cell is filtered/emptied out, but the exit
                                    // spring below still needs something to fade —
                                    // shownWall keeps the last-rendered wallpaper
                                    // until a new one replaces it (see onWallChanged)
                                    source: wcCell.shownWall ? "file://" + wcCell.shownWall.path : ""
                                }
                                // Only the centered window plays its .gif from the
                                // source file; side windows keep the still Image
                                // above (which already shows frame 0 of a gif) so
                                // scrolling the carousel doesn't decode a movie
                                // per window.
                                readonly property bool animating: wcCell.isCenter && win.wallCarouselSettled && !!wcCell.shownWall?.gif
                                AnimatedImage {
                                    // Same (wider-than-bar) target width as the still
                                    // Image above, not just barWidth: PreserveAspectCrop
                                    // picks its scale from max(targetW/iw, targetH/ih),
                                    // so a narrower target box here would crop to a
                                    // different (larger) scale than the still frame it
                                    // replaces, producing a visible shrink/jump the
                                    // instant a centered gif starts playing.
                                    width: wallCarousel.barWidth + ((wallCarousel.halfVisible + 1) * wallCarousel.parallaxPx + 20) * 2
                                    height: parent.height
                                    anchors.centerIn: parent
                                    visible: wcThumb.animating
                                    playing: wcThumb.animating
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    source: wcThumb.animating ? "file://" + wcCell.shownWall.path : ""
                                }
                            }
                            // Stroke above the image, not a border on wcThumb:
                            // settled cells rest on half-pixel x (parent
                            // width is an odd multiple of slotSpacing) and
                            // side cells have fractional edges from the rank
                            // scale, so the clip mask and an underlying
                            // border rasterize a pixel apart — the image eats
                            // the right/bottom stroke and roughens the
                            // corners (same image-over-border effect the
                            // tiles grid's wallDrawer stroke above works
                            // around).
                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: "transparent"
                                border.width: 1
                                // same muted-to-full-accent brighten tiles
                                // mode gives the selected cell's stroke
                                border.color: Qt.alpha(root.accent, 0.33 + 0.67 * wcCell.selFade)
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: wcCell.wall !== null
                                onClicked: {
                                    if (wcCell.isCenter)
                                        win.applyWallpaper(wcCell.wall);
                                    else
                                        win.moveCarousel(Math.round(wcCell.rank));
                                }
                            }
                        }

                        SequentialAnimation {
                            id: wcSpringIn
                            PropertyAction { target: wcWrap; property: "opacity"; value: 0 }
                            PropertyAction { target: wcWrap; property: "scale"; value: win.animFromScale }
                            PropertyAction { target: wcWrap; property: "y"; value: win.animFromY }
                            PauseAnimation { duration: win.animDelay(wcCell.visSlot, wallCarousel.halfVisible * 2 + 1) }
                            ParallelAnimation {
                                NumberAnimation { target: wcWrap; property: "opacity"; to: 1; duration: win.animFadeDur; easing.type: Easing.OutCubic }
                                NumberAnimation { target: wcWrap; property: "scale"; to: 1; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                                NumberAnimation { target: wcWrap; property: "y"; to: 0; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 2.2 }
                            }
                        }
                        SequentialAnimation {
                            id: wcSpringOut
                            ParallelAnimation {
                                NumberAnimation { target: wcWrap; property: "scale"; to: win.animOutBounce ? 1.08 : 1; duration: win.animOutBounce ? win.ad(80) : 0; easing.type: Easing.OutQuad }
                            }
                            ParallelAnimation {
                                NumberAnimation { target: wcWrap; property: "scale"; to: win.animFromScale; duration: win.ad(win.animOutSettleDur); easing.type: win.animOutEase }
                                NumberAnimation { target: wcWrap; property: "opacity"; to: 0; duration: win.ad(win.animOutSettleDur); easing.type: win.animOutEase }
                            }
                        }
                    }
                }

                Text {
                    anchors.top: parent.top
                    anchors.topMargin: wallCarousel.barHeight + wallCarousel.captionGap
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, wallCarousel.width)
                    text: {
                        if (win.wallCarouselEmpty)
                            return "";
                        const w = win.wallMatches[win.wallSelected];
                        return w ? win.wallName(w) : "";
                    }
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    color: root.fg
                    font { family: root.mono; pixelSize: root.fs(13) }
                }
            }

            // Wallpaper empty state: shared between the tiles grid and the
            // windows carousel, since only one of them is ever visible. Fades
            // in only once the last exiting tile has fully sprung out
            // (win.ad(400), matching wallSpringOut/wcSpringOut) instead of
            // popping in on top of tiles still animating away.
            Text {
                id: wallsNoMatches
                visible: win.pane === "walls" && opacity > 0
                anchors.centerIn: parent
                transform: panePull
                opacity: 0
                text: root.wallpapers.length === 0 ? "no wallpapers found" : "no matches"
                color: root.muted
                font { family: root.mono; pixelSize: root.fs(14) }

                Connections {
                    target: win
                    function onWallMatchesChanged() {
                        if (win.wallMatches.length === 0)
                            wallsNoMatchesFade.restart();
                        else {
                            wallsNoMatchesFade.stop();
                            wallsNoMatches.opacity = 0;
                        }
                    }
                    // windows carousel: wallMatches never empties (it always
                    // holds the full, unfiltered list — see wallMatches
                    // above), so its "nothing matched" state is signaled
                    // separately by wallCarouselEmpty instead.
                    function onWallCarouselEmptyChanged() {
                        if (win.wallCarouselEmpty)
                            wallsNoMatchesFade.restart();
                        else {
                            wallsNoMatchesFade.stop();
                            wallsNoMatches.opacity = 0;
                        }
                    }
                }
                SequentialAnimation {
                    id: wallsNoMatchesFade
                    PauseAnimation { duration: win.ad(400) }
                    NumberAnimation { target: wallsNoMatches; property: "opacity"; to: 1; duration: win.ad(220); easing.type: Easing.OutCubic }
                }
            }

            // Clipboard history: masonry grid of variable-height tiles
            Item {
                id: clipDrawer
                anchors.centerIn: parent
                width: cfg.clipsCols * 240 + (cfg.clipsCols - 1) * 16 + 52
                height: Math.max(clipMasonry.height, 120) + 52
                // a filtered-out tile collapsing to 0 height shrinks
                // clipMasonry, which (via centerIn: parent below) would
                // otherwise snap the whole drawer's top edge down instantly;
                // animate the resize instead so it reads as a settle
                Behavior on height {
                    NumberAnimation { duration: win.ad(240); easing.type: Easing.OutCubic }
                }
                transform: panePull
                opacity: 0.004
                visible: win.pane === "clips"
                Connections {
                    target: win
                    function onPaneChanged() {
                        if (win.pane === "clips")
                            clipIn.restart();
                    }
                }

                ParallelAnimation {
                    id: clipIn
                    NumberAnimation { target: clipDrawer; property: "opacity"; from: 0; to: 1; duration: win.ad(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: clipDrawer; property: "scale"; from: 0.9; to: 1; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: clipDrawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Row {
                    id: clipMasonry
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26
                    // pinned directly rather than left implicit: even with
                    // each clipColumn's own width fixed at 240, relying on
                    // Row to sum them back up is one more layer that could
                    // drift when a column empties out, so state the total
                    // outright to match clipDrawer's own (also fixed) width
                    width: cfg.clipsCols * 240 + (cfg.clipsCols - 1) * 16
                    spacing: 16

                    Repeater {
                        model: cfg.clipsCols

                        Column {
                            id: clipColumn
                            required property int index
                            // fixed, not implicit: an empty column (fewer
                            // matches than clipsCols) would otherwise
                            // collapse to 0 width, shrinking clipMasonry and
                            // shifting the other columns sideways to stay
                            // centered in clipDrawer's fixed-width box
                            width: 240
                            spacing: 16
                            // a tile above collapsing to 0 height (see
                            // clipSpringOut.onStopped) shifts every cell
                            // below it up within the column; animate that
                            // reflow instead of letting it snap
                            move: Transition {
                                NumberAnimation { property: "y"; duration: win.ad(220); easing.type: Easing.OutCubic }
                            }

                            Repeater {
                                model: win.clipRowsC

                                Item {
                                    id: clipCell
                                    required property int index
                                    // round-robin: slot order matches the
                                    // row-major order vMove navigates
                                    readonly property int slot: index * cfg.clipsCols + clipColumn.index
                                    readonly property int clipIndex: win.clipPage * win.clipPageSize + slot
                                    readonly property var clip: win.clipMatches[clipIndex] ?? null
                                    readonly property bool isSelected: clip !== null && win.clipSelected === clipIndex

                                    property var shownClip: null
                                    property bool filled: false
                                    onClipChanged: {
                                        if (clip) {
                                            const wasFilled = filled;
                                            const isNew = !wasFilled || !shownClip || shownClip.id !== clip.id;
                                            shownClip = clip;
                                            filled = true;
                                            if (isNew) {
                                                clipSpringIn.stop();
                                                clipSpringOut.stop();
                                                if (wasFilled) {
                                                    // direct replacement: snap straight to the
                                                    // resting state, no animation
                                                    clipTile.opacity = 1;
                                                    clipTile.scale = 1;
                                                    clipTile.y = 0;
                                                } else {
                                                    clipSpringIn.restart();
                                                }
                                            }
                                        } else if (filled) {
                                            filled = false;
                                            clipSpringIn.stop();
                                            clipSpringOut.restart();
                                        }
                                    }
                                    Connections {
                                        target: win
                                        function onPaneChanged() {
                                            if (win.pane === "clips" && clipCell.filled)
                                                clipSpringIn.restart();
                                        }
                                    }

                                    // text tiles grow with content up to a square;
                                    // image tiles keep their real aspect ratio
                                    // measure the wrapped text for an exact fit:
                                    // the tile hugs the content, truncating only
                                    // once it would exceed a square
                                    Text {
                                        id: measureText
                                        visible: false
                                        width: 214
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        text: {
                                            const c = clipCell.shownClip;
                                            return c && !c.image ? c.preview : "";
                                        }
                                        font { family: root.mono; pixelSize: root.fs(13) }
                                    }
                                    readonly property real lineHpx: measureText.lineCount > 0
                                        ? measureText.paintedHeight / measureText.lineCount
                                        : root.fs(16)
                                    readonly property int tileH: {
                                        const c = shownClip;
                                        if (!c)
                                            return 0;
                                        if (c.image) {
                                            const d = (c.dims || "").split("x");
                                            const iw = parseInt(d[0]) || 16;
                                            const ih = parseInt(d[1]) || 9;
                                            return Math.max(70, Math.min(320, Math.round(240 * ih / iw)));
                                        }
                                        return Math.max(44, Math.min(240, Math.ceil(measureText.paintedHeight) + 26));
                                    }
                                    width: 240
                                    height: tileH > 0 ? tileH + 24 : 0
                                    visible: tileH > 0

                                    // expanding one clip animates the rest away
                                    opacity: win.expandedClip !== null ? 0 : 1
                                    scale: win.expandedClip !== null ? 0.85 : 1
                                    Behavior on opacity {
                                        NumberAnimation { duration: win.ad(180); easing.type: Easing.OutCubic }
                                    }
                                    Behavior on scale {
                                        NumberAnimation { duration: win.ad(220); easing.type: Easing.OutCubic }
                                    }
                                    // report the tile position so the expand
                                    // animation can grow out of it
                                    Connections {
                                        target: win
                                        function onExpandedClipChanged() {
                                            if (win.expandedClip && clipCell.isSelected) {
                                                const p = clipCell.mapToItem(clipDrawer, clipCell.width / 2, clipCell.height / 2);
                                                win.expandOrigin = Qt.point(p.x, p.y);
                                            }
                                        }
                                    }

                                    // caption line, like app/wallpaper labels
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: clipTile.y + clipCell.tileH + 6
                                        opacity: clipTile.opacity
                                        scale: clipTile.scale
                                        text: {
                                            const c = clipCell.shownClip;
                                            if (!c)
                                                return "";
                                            return c.image ? c.dims : c.bytes + " chars";
                                        }
                                        color: root.fg
                                        font { family: root.mono; pixelSize: root.fs(12) }
                                    }

                                    Rectangle {
                                        id: clipTile
                                        width: parent.width
                                        height: clipCell.tileH
                                        radius: 12
                                        opacity: 0
                                        color: Qt.alpha(root.accent, clipCell.isSelected ? 0.22 : 0.11)
                                        border.width: 1
                                        border.color: clipCell.isSelected ? root.accent : Qt.alpha(root.accent, 0.33)

                                        Rectangle {
                                            visible: clipCell.isSelected
                                            anchors.fill: parent
                                            anchors.margins: -5
                                            radius: 17
                                            color: "transparent"
                                            border.width: 3
                                            border.color: Qt.alpha(root.accent, 0.33)
                                        }

                                        ClippingRectangle {
                                            visible: clipCell.shownClip !== null && clipCell.shownClip.image === true
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            radius: 9
                                            color: "transparent"

                                            Image {
                                                anchors.fill: parent
                                                asynchronous: true
                                                fillMode: Image.PreserveAspectFit
                                                sourceSize: Qt.size(480, 640)
                                                source: {
                                                    const c = clipCell.shownClip;
                                                    return c && c.image && c.thumb ? "file://" + c.thumb : "";
                                                }
                                            }
                                        }
                                        Text {
                                            visible: clipCell.shownClip !== null && clipCell.shownClip.image !== true
                                            anchors.fill: parent
                                            anchors.margins: 13
                                            text: clipCell.shownClip ? clipCell.shownClip.preview : ""
                                            textFormat: Text.PlainText
                                            wrapMode: Text.Wrap
                                            elide: Text.ElideRight
                                            maximumLineCount: Math.max(1, Math.floor((clipCell.tileH - 26) / Math.max(1, clipCell.lineHpx)))
                                            color: root.fg
                                            font { family: root.mono; pixelSize: root.fs(13) }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: clipCell.filled && win.expandedClip === null
                                            onClicked: {
                                                win.clipSelected = clipCell.clipIndex;
                                                win.expandClip(clipCell.clip);
                                            }
                                        }
                                    }

                                    SequentialAnimation {
                                        id: clipSpringIn
                                        PropertyAction { target: clipTile; property: "opacity"; value: 0 }
                                        PropertyAction { target: clipTile; property: "scale"; value: win.animFromScale }
                                        PropertyAction { target: clipTile; property: "y"; value: win.animFromY }
                                        PauseAnimation { duration: win.animDelay(clipCell.slot, cfg.clipsCols) }
                                        ParallelAnimation {
                                            NumberAnimation { target: clipTile; property: "opacity"; to: 1; duration: win.animFadeDur; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: clipTile; property: "scale"; to: 1; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 1.6 }
                                            NumberAnimation { target: clipTile; property: "y"; to: 0; duration: win.animDur; easing.type: win.animEase; easing.overshoot: 1.6 }
                                        }
                                    }
                                    SequentialAnimation {
                                        id: clipSpringOut
                                        ParallelAnimation {
                                            NumberAnimation { target: clipTile; property: "scale"; to: win.animOutBounce ? 1.08 : 1; duration: win.animOutBounce ? win.ad(80) : 0; easing.type: Easing.OutQuad }
                                        }
                                        ParallelAnimation {
                                            NumberAnimation { target: clipTile; property: "scale"; to: win.animFromScale; duration: win.ad(win.animOutSettleDur); easing.type: win.animOutEase }
                                            NumberAnimation { target: clipTile; property: "opacity"; to: 0; duration: win.ad(win.animOutSettleDur); easing.type: win.animOutEase }
                                        }
                                        // clear shownClip once the tile is actually gone, not just
                                        // invisible: tileH (and so this cell's visible/height) is
                                        // derived from shownClip, so leaving it set would keep this
                                        // cell's slot permanently reserved in the masonry column —
                                        // stale layout space a later "no matches" state reads as
                                        // tiles still being there. Guarded by filled: a re-match
                                        // arriving mid-exit already called .stop() on us via the
                                        // isNew branch above and has its own shownClip in place, so
                                        // stopping here from that must not clobber it.
                                        onStopped: if (!clipCell.filled) clipCell.shownClip = null;
                                    }
                                }
                            }
                        }
                    }
                }

                // expanded clip: grows out of the selected tile while the
                // rest of the grid animates away (no dimming overlay)
                Item {
                    id: expandCard
                    visible: win.expandedClip !== null
                    readonly property bool isImg: win.expandedClip !== null && win.expandedClip.image === true
                    // images render at native size, capped to fit the screen
                    // (58% of width, 53% of height to leave room for the
                    // text/metadata below the image and the card's margins)
                    readonly property size imgFit: {
                        if (!isImg)
                            return Qt.size(0, 0);
                        const d = (win.expandedClip.dims || "").split("x");
                        const iw = parseInt(d[0]) || 16;
                        const ih = parseInt(d[1]) || 9;
                        const maxW = win.revW * 0.58;
                        const maxH = win.revH * 0.53;
                        const s = Math.min(1, maxW / iw, maxH / ih);
                        return Qt.size(Math.max(320, Math.round(iw * s)), Math.max(180, Math.round(ih * s)));
                    }
                    anchors.centerIn: parent
                    width: isImg ? imgFit.width + 48 : 560
                    height: expandCol.height + 44
                    // large images cover much more of the screen than text
                    // cards, so the same growth duration reads as an abrupt
                    // pop; ease it in more slowly
                    readonly property int expandDur: isImg ? 560 : 380
                    // the decoded full text arrives async and is longer than
                    // the preview; grow smoothly instead of jumping
                    Behavior on height {
                        NumberAnimation { duration: win.ad(380); easing.type: Easing.OutCubic }
                    }
                    transform: Translate { id: expandTx }

                    // swallow clicks so they don't fall through to the
                    // background (which collapses the expansion)
                    MouseArea {
                        anchors.fill: parent
                    }

                    ParallelAnimation {
                        id: expandIn
                        NumberAnimation { target: expandTx; property: "x"; to: 0; duration: win.ad(expandCard.expandDur); easing.type: Easing.OutCubic }
                        NumberAnimation { target: expandTx; property: "y"; to: 0; duration: win.ad(expandCard.expandDur); easing.type: Easing.OutCubic }
                        NumberAnimation { target: expandCard; property: "opacity"; from: 0.3; to: 1; duration: win.ad(Math.round(expandCard.expandDur * 0.58)); easing.type: Easing.OutCubic }
                        NumberAnimation { target: expandCard; property: "scale"; from: 0.35; to: 1; duration: win.ad(expandCard.expandDur); easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                    }
                    SequentialAnimation {
                        id: expandOut
                        ParallelAnimation {
                            NumberAnimation {
                                target: expandTx
                                property: "x"
                                to: win.expandOrigin.x - clipDrawer.width / 2
                                duration: win.ad(260)
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation {
                                target: expandTx
                                property: "y"
                                to: win.expandOrigin.y - clipDrawer.height / 2
                                duration: win.ad(260)
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation { target: expandCard; property: "scale"; to: 0.35; duration: win.ad(260); easing.type: Easing.InCubic }
                            NumberAnimation { target: expandCard; property: "opacity"; to: 0; duration: win.ad(260); easing.type: Easing.InCubic }
                        }
                        ScriptAction { script: win.expandedClip = null }
                    }
                    Connections {
                        target: win
                        function onExpandAnimStart() {
                            expandOut.stop();
                            expandTx.x = win.expandOrigin.x - clipDrawer.width / 2;
                            expandTx.y = win.expandOrigin.y - clipDrawer.height / 2;
                            expandIn.restart();
                        }
                        function onExpandAnimCollapse() {
                            expandIn.stop();
                            expandOut.restart();
                        }
                    }

                    Column {
                        id: expandCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 22
                        width: parent.width - 48
                        spacing: 14

                        ClippingRectangle {
                            visible: expandCard.isImg
                            width: parent.width
                            height: expandCard.imgFit.height
                            radius: 12
                            color: "transparent"

                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                sourceSize: Qt.size(win.revW, win.revH)
                                // prefer the on-demand full-res decode; the
                                // small thumb is an instant placeholder while
                                // it lands, and the fallback if decode fails
                                source: {
                                    const c = win.expandedClip;
                                    if (!c || !c.image)
                                        return "";
                                    if (win.expandedFullPath && clipFullImg.forId === c.id)
                                        return "file://" + win.expandedFullPath;
                                    return c.thumb ? "file://" + c.thumb : "";
                                }
                            }
                        }
                        // the full text reveals gradually as the container
                        // grows, instead of jumping when the decode lands
                        Item {
                            visible: win.expandedClip !== null && win.expandedClip.image !== true
                            width: parent.width
                            height: expandBody.paintedHeight
                            clip: true
                            Behavior on height {
                                NumberAnimation { duration: win.ad(380); easing.type: Easing.OutCubic }
                            }

                            Text {
                                id: expandBody
                                width: parent.width
                                text: win.expandedText || (win.expandedClip ? win.expandedClip.preview : "")
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                                maximumLineCount: 30
                                color: root.fg
                                font { family: root.mono; pixelSize: root.fs(13) }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Qt.alpha(root.accent, 0.25)
                        }

                        Repeater {
                            model: win.expandedInfo

                            Item {
                                required property var modelData
                                width: expandCol.width
                                height: root.fs(20)

                                Text {
                                    anchors.left: parent.left
                                    text: parent.modelData[0]
                                    color: root.muted
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: parent.modelData[1]
                                    color: root.fg
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                            }
                        }
                    }
                }
            }

            // Clipboard empty states: siblings of clipDrawer (not nested
            // inside it) so anchors.centerIn: parent centers on the pane
            // instead of clipDrawer's box, which stays sized to the full
            // grid regardless of clip/match count.
            Text {
                visible: win.pane === "clips" && root.clips.length === 0
                anchors.centerIn: parent
                transform: panePull
                text: "clipboard history is empty"
                color: root.muted
                font { family: root.mono; pixelSize: root.fs(14) }
            }
            // Fades in only once the last exiting tile has fully sprung out
            // (win.ad(240), matching clipSpringOut) instead of popping in on
            // top of tiles still animating away. wantShow is a plain
            // reactive binding (always correct for the *current* query) —
            // debouncedShow just delays acting on it by one clipSpringOut's
            // worth of time, via a Timer that restarts/cancels on every
            // change instead of an imperative restart()/stop() pair racing
            // against whichever keystroke's onClipMatchesChanged fires last.
            Text {
                id: clipsNoMatches
                readonly property bool wantShow: root.clips.length > 0 && win.clipMatches.length === 0
                property bool debouncedShow: false
                onWantShowChanged: {
                    if (wantShow)
                        noMatchesDelay.restart();
                    else {
                        noMatchesDelay.stop();
                        debouncedShow = false;
                    }
                }
                visible: win.pane === "clips" && opacity > 0
                anchors.centerIn: parent
                transform: panePull
                opacity: debouncedShow ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: win.ad(220); easing.type: Easing.OutCubic }
                }
                text: "no matches"
                color: root.muted
                font { family: root.mono; pixelSize: root.fs(14) }

                Timer {
                    id: noMatchesDelay
                    interval: win.ad(240)
                    onTriggered: clipsNoMatches.debouncedShow = true
                }
            }

            // Custom pages: one host per enabled upload (see
            // root.customPagesDir), each Loader-ing the user's own .qml file
            // as its content. Bound to cfg.uploadedPages directly (not
            // win.fullPageOrder) for the same delegate-stability reason
            // pagesBlock's Repeater is — membership only changes on
            // upload/trash/disk sync, never on a pure reorder. Kept alive
            // (active whenever the page itself is switched on) rather than
            // lazy-loaded to the current pane, so a page's own state
            // (timers, scroll position, whatever it wants to hold onto)
            // survives Tab-cycling away and back, same as the volume OSD.
            Repeater {
                id: customPagesRepeater
                model: cfg.uploadedPages ?? []

                Item {
                    id: customPageHost
                    required property var modelData
                    anchors.centerIn: parent
                    width: pageLoader.item && pageLoader.item.width > 0 ? pageLoader.item.width : 420
                    height: pageLoader.item && pageLoader.item.height > 0 ? pageLoader.item.height : 320
                    transform: panePull
                    opacity: 0.004
                    visible: modelData.on && win.pane === modelData.id

                    // fresh context per page, not shared — see PageContext
                    readonly property var ctx: PageContext {
                        pageId: customPageHost.modelData.id
                    }
                    // exposed so win.customSettingsTabs (a plain computed
                    // property, not something Loader-internal) can react to
                    // this page loading/unloading without reaching into the
                    // Repeater's delegates itself
                    readonly property var pageItem: pageLoader.item

                    function syncActive() {
                        if (pageLoader.item && "active" in pageLoader.item)
                            pageLoader.item.active = win.pane === modelData.id;
                    }

                    Connections {
                        target: win
                        function onPaneChanged() {
                            if (win.pane === customPageHost.modelData.id)
                                customPageIn.restart();
                            customPageHost.syncActive();
                        }
                    }

                    ParallelAnimation {
                        id: customPageIn
                        NumberAnimation { target: customPageHost; property: "opacity"; from: 0; to: 1; duration: win.ad(200); easing.type: Easing.OutCubic }
                        NumberAnimation { target: customPageHost; property: "scale"; from: 0.9; to: 1; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                        NumberAnimation { target: customPageHost; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.ad(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    }

                    Loader {
                        id: pageLoader
                        anchors.centerIn: parent
                        // modelData.on can only be true for a real (non-
                        // broken) entry — see win.toggleUploadedPage — but
                        // this is also a settings.json value, hand-editable
                        // like any other, so the broken check is repeated
                        // here rather than trusted from there
                        active: customPageHost.modelData.on && !customPageHost.modelData.broken
                        // every page's entry point is <dir>/main.qml (see
                        // pagesScan and the customPagesDir comment for how
                        // it reaches its own sibling files — nothing else
                        // needed here, this Loader doesn't care how many
                        // files the page is split across)
                        source: active ? Qt.resolvedUrl(customPageHost.modelData.path + "/main.qml") : ""
                        onLoaded: {
                            if ("pibble" in item)
                                item.pibble = customPageHost.ctx;
                            customPageHost.syncActive();
                        }
                        // a page that fails to parse/instantiate just never
                        // shows (the real QML error lands in the terminal/
                        // journal like any other, per CLAUDE.md's "no
                        // compiler" note) — this only tells the user which
                        // one so they know where to look
                        onStatusChanged: {
                            if (status === Loader.Error)
                                root.notifyError("Custom page failed to load", customPageHost.modelData.label);
                        }
                    }
                }
            }

            // Settings pane
            Item {
                id: settingsPane
                // built-ins first, then one slot per custom page that opts
                // into a settings tab (see win.customSettingsTabs) — in
                // whatever order those pages themselves loaded in
                readonly property var tabOrder: ["general", "pages", "keybindings", "flyouts"].concat(win.customSettingsTabs.map(t => t.pageId))
                // customPagesRepeater's model is cfg.uploadedPages itself,
                // reassigned wholesale (a fresh array) on every toggle/
                // upload/trash/rescan — since it's a plain JS-array model,
                // that recreates every delegate, not just the one that
                // changed. For the split of a frame that a custom tab's
                // host is mid-recreate, win.customSettingsTabs (which reads
                // pageItem off those delegates) loses that tab, so
                // rawTabIdx briefly goes -1. Snapping tabIdx to 0 in that
                // window used to yank every filmstrip pane (see the
                // `Behavior on x` below and the built-in tabs' copies) over
                // to tab 0 and spring it back once the tab reappears — the
                // "settings flies across the screen" glitch. Holding the
                // last good index instead means the recreate is invisible:
                // nothing here moves until there's a real index to move to.
                readonly property int rawTabIdx: tabOrder.indexOf(win.settingsTab)
                property int tabIdx: 0
                onRawTabIdxChanged: if (rawTabIdx >= 0)
                    tabIdx = rawTabIdx
                anchors.centerIn: parent
                width: 860
                height: 26 + settingsHeader.height + 18 + tabViewport.height + 26
                transform: panePull
                opacity: 0.004
                visible: win.pane === "settings"
                Connections {
                    target: win
                    function onPaneChanged() {
                        if (win.pane === "settings")
                            settingsIn.restart();
                    }
                }
                ParallelAnimation {
                    id: settingsIn
                    NumberAnimation { target: settingsPane; property: "opacity"; from: 0; to: 1; duration: win.had(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: settingsPane; property: "scale"; from: 0.9; to: 1; duration: win.had(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { target: settingsPane; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: win.had(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                // header: title + underlined tab links, left-aligned
                Item {
                    id: settingsHeader
                    width: 780
                    height: 58
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 26

                    Text {
                        text: "SETTINGS"
                        color: root.muted
                        font { family: root.mono; pixelSize: root.fs(13); letterSpacing: 3 }
                    }
                    Row {
                        anchors.bottom: parent.bottom
                        spacing: 26

                        Repeater {
                            model: [
                                { id: "general", label: "General" },
                                { id: "pages", label: "Pages" },
                                { id: "keybindings", label: "Keybindings" },
                                { id: "flyouts", label: "Flyouts" }
                            ].concat(win.customSettingsTabs.map(t => ({ id: t.pageId, label: t.label })))

                            Item {
                                id: settingsTabItem
                                required property var modelData
                                readonly property bool active: win.settingsTab === modelData.id
                                width: settingsTabText.implicitWidth
                                height: 24

                                Text {
                                    id: settingsTabText
                                    text: settingsTabItem.modelData.label
                                    color: settingsTabItem.active ? root.fg : root.muted
                                    font { family: root.mono; pixelSize: root.fs(14) }
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 2
                                    radius: 1
                                    color: root.accent
                                    opacity: settingsTabItem.active ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: win.had(150); easing.type: Easing.OutCubic }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: win.settingsTab = settingsTabItem.modelData.id
                                }
                            }
                        }
                    }
                }

                // pages slide horizontally when switching tabs, all
                // top-aligned so shorter pages stay level
                Item {
                    id: tabViewport
                    clip: true
                    width: 820
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: settingsHeader.bottom
                    anchors.topMargin: 18
                    // constant height (tallest page): switching tabs never
                    // moves the pane, shorter pages stay top-aligned
                    height: Math.max(genCol.height, settingsCol.height, keybindCol.height, flyCol.height, customTabsMaxHeight)
                    // tallest of any custom tab's content column, recomputed
                    // whenever one loads/resizes — 0 (a no-op in the Math.max
                    // above) when there are none
                    readonly property real customTabsMaxHeight: {
                        let m = 0;
                        for (let i = 0; i < customTabsRepeater.count; i++) {
                            const c = customTabsRepeater.itemAt(i);
                            if (c)
                                m = Math.max(m, c.height);
                        }
                        return m;
                    }

                // general tab: settings shared by the launcher and both flyouts
                Column {
                    id: genCol
                    x: 20 + (0 - settingsPane.tabIdx) * 840
                    Behavior on x {
                        NumberAnimation { duration: win.had(420); easing.type: Easing.OutCubic }
                    }
                    spacing: 14

                    SettingRow { key: "launchAnimation"; label: "Launch animation"; valueWidth: 190 }
                    SettingRow { key: "hiddenMenuAnimations"; label: "Hidden menu animations"; sub: "settings pane and power-off/reboot prompts" }
                    SettingRow { key: "fontFamily"; label: "Font"; valueWidth: 190 }
                    SettingRow { key: "fontScale"; label: "Font size" }
                    ThemeRow {}
                    CustomColorRow {}

                    // bundles version/build info, this run's recent log, and
                    // the latest crash report (if any) for pasting into a
                    // bug report; right-aligned with the same margin as
                    // SReset elsewhere, even though this row has no reset
                    Item {
                        width: 780
                        height: 40

                        SLabel {
                            anchors.left: parent.left
                            text: "Copy debug info"
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            width: debugBtnRow.implicitWidth + 28
                            height: 34
                            radius: 10
                            color: Qt.alpha(root.accent, debugBtnArea.containsMouse ? 0.25 : 0.11)
                            border.width: 1
                            border.color: Qt.alpha(root.accent, 0.33)

                            Row {
                                id: debugBtnRow
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: root.ti.copy
                                    color: root.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                    font { family: root.iconFont; pixelSize: root.fs(16) }
                                }
                                Text {
                                    text: "Copy"
                                    color: root.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                    font { family: root.mono; pixelSize: root.fs(15); weight: Font.Bold }
                                }
                            }
                            MouseArea {
                                id: debugBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.copyDebugInfo()
                            }
                        }
                    }

                    // closes out the tab with a divider and the repo's
                    // commit, centered underneath; extra breathing room above
                    // and below the divider itself, beyond the Column's
                    // normal row spacing
                    Item {
                        width: 780
                        height: 10 + 1 + 10 + versionText.implicitHeight

                        Rectangle {
                            y: 10
                            width: parent.width
                            height: 1
                            color: Qt.alpha(root.muted, 0.25)
                        }
                        Text {
                            id: versionText
                            anchors.top: parent.top
                            anchors.topMargin: 10 + 1 + 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.pibbleCommit !== ""
                            text: root.pibbleCommit
                            color: root.muted
                            font { family: root.mono; pixelSize: root.fs(11) }

                            property int clicks: 0
                            property bool revealed: false

                            Behavior on opacity {
                                NumberAnimation { duration: 420; easing.type: Easing.InOutQuad }
                            }
                            Timer {
                                id: clickWindow
                                interval: 500
                                onTriggered: versionText.clicks = 0
                            }
                            Timer {
                                id: versionReveal
                                interval: 420
                                onTriggered: {
                                    versionText.text = "I vibe coded this using a microphone.";
                                    versionText.opacity = 1;
                                    revealTimeout.start();
                                }
                            }
                            Timer {
                                id: revealTimeout
                                interval: 3000
                                onTriggered: {
                                    versionText.opacity = 0;
                                    versionHide.start();
                                }
                            }
                            Timer {
                                id: versionHide
                                interval: 420
                                onTriggered: {
                                    versionText.text = root.pibbleCommit;
                                    versionText.opacity = 1;
                                    versionText.revealed = false;
                                    versionText.clicks = 0;
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                onClicked: {
                                    if (versionText.revealed)
                                        return;
                                    versionText.clicks++;
                                    clickWindow.restart();
                                    if (versionText.clicks >= 3) {
                                        versionText.revealed = true;
                                        versionText.opacity = 0;
                                        versionReveal.start();
                                    }
                                }
                            }
                        }
                    }
                }

                // flyouts tab: volume + notification OSDs
                Column {
                    id: flyCol
                    x: 20 + (3 - settingsPane.tabIdx) * 840
                    Behavior on x {
                        NumberAnimation { duration: win.had(420); easing.type: Easing.OutCubic }
                    }
                    spacing: 14

                    // default valueWidth throughout (the values are short), so
                    // the ‹ › buttons line up column-tight like the launcher
                    // tab; only the font row needs a wide value
                    // enabled flyouts (unloading notifications releases the
                    // org.freedesktop.Notifications DBus name for other daemons)
                    Item {
                        width: 780
                        height: 34

                        SLabel {
                            anchors.left: parent.left
                            text: "Flyouts"
                        }
                        SReset {
                            key: "flyouts"
                            anchors.right: parent.right
                        }
                        ChipRow {
                            anchors.right: parent.right
                            anchors.rightMargin: 34 + 32
                            anchors.verticalCenter: parent.verticalCenter
                            items: [
                                { id: "volume", label: "volume" },
                                { id: "notifs", label: "notifications" }
                            ]
                            isOn: root.flyoutOn
                            toggle: win.toggleFlyout
                        }
                    }

                    SettingRow { key: "volStyle"; label: "Volume style" }
                    SettingRow { key: "volWidth"; label: "Volume size" }
                    SettingRow { key: "volAnim"; label: "Volume animation" }
                    SettingRow { key: "volPercent"; label: "Volume percent" }
                    SettingRow { key: "volTimeout"; label: "Volume timeout" }

                    // pibble's own notify-send calls (missing tools, failed
                    // commands, copy confirmations, low battery), independent
                    // of the "notifications" flyout above which only gates
                    // other apps' notifications
                    Item {
                        width: 780
                        height: 34

                        SLabel {
                            anchors.left: parent.left
                            text: "Pibble alerts"
                        }
                        SReset {
                            key: "pibbleAlerts"
                            anchors.right: parent.right
                        }
                        ChipRow {
                            anchors.right: parent.right
                            anchors.rightMargin: 34 + 32
                            anchors.verticalCenter: parent.verticalCenter
                            items: [
                                { id: "errors", label: "errors" },
                                { id: "system", label: "system" },
                                { id: "battery", label: "battery" }
                            ]
                            isOn: root.alertOn
                            toggle: win.toggleAlert
                        }
                    }
                    SettingRow { key: "notifStyle"; label: "Notification style" }
                    SettingRow { key: "notifAnim"; label: "Notification animation" }
                    SettingRow { key: "notifTimeout"; label: "Notification timeout" }
                    SettingRow { key: "replayCount"; label: "Replay count"; sub: "how many recent notifications `pibble replay` can step back through" }
                }

                Column {
                    id: settingsCol
                    x: 20 + (1 - settingsPane.tabIdx) * 840
                    Behavior on x {
                        NumberAnimation { duration: win.had(420); easing.type: Easing.OutCubic }
                    }
                    spacing: 14

                    // enabled pages: click the box to toggle, drag a row up/down
                    // to reorder the cycle (topmost is the home pane). Vertical
                    // list rather than a horizontal chip row so it can hold an
                    // arbitrary number of uploaded pages (see below) without
                    // running out of width — grows with the page count up to
                    // 6 rows (including the "add a page" row), then scrolls.
                    Item {
                        id: pagesBlock
                        width: 780
                        height: 34 + 8 + pagesFlick.height + 2 + pagesSub.implicitHeight
                        readonly property int rowH: 32
                        // small left inset applied to every row's content
                        // (both the checkbox/label and the revealed delete
                        // box) so nothing ever sits flush against pagesFlick's
                        // own clip edge — a border drawn exactly on that
                        // boundary gets its outer half-pixel clipped away
                        readonly property real rowInset: 2

                        // drag state lives here (not per-row) so the edge-scroll
                        // timer can keep the dragged row glued to the pointer
                        // purely by nudging contentY
                        property string draggedId: ""
                        property real pointerViewportY: 0
                        property real dragGrabOffset: 0
                        property int edgeDir: 0
                        // which uploaded row (if any) currently has its
                        // swipe-to-trash control revealed; opening one closes
                        // any other that was already open
                        property string revealedId: ""
                        // which uploaded row (if any) is mid dismiss-animation
                        // after a confirmed trash, before the file is actually
                        // moved — see trashPage()
                        property string removingId: ""

                        // rubber-bands value past [min,max] instead of hard
                        // clamping, so dragging the reveal past fully-open
                        // (or back past fully-closed) still tracks the
                        // pointer but with resistance that grows the further
                        // past the limit it goes, asymptoting toward min-damp/
                        // max+damp rather than ever truly reaching it — only
                        // used while Hidden menu animations is on (see
                        // swipeDrag.onCentroidChanged); off, the reveal is
                        // hard-clamped instead, with no left-swipe at all
                        function rubberBand(value, min, max, damp) {
                            if (value < min) {
                                const over = min - value;
                                return min - damp * (1 - 1 / (over / damp + 1));
                            }
                            if (value > max) {
                                const over = value - max;
                                return max + damp * (1 - 1 / (over / damp + 1));
                            }
                            return value;
                        }

                        function dragReorderCheck() {
                            if (!draggedId)
                                return;
                            const contentLocalY = pointerViewportY - dragGrabOffset + pagesFlick.contentY;
                            const idx = Math.max(0, Math.min(win.fullPageOrder.length - 1, Math.round(contentLocalY / rowH)));
                            if (idx !== win.fullPageOrder.indexOf(draggedId))
                                win.moveFullPage(draggedId, idx);
                        }
                        readonly property var defLabels: ({ clock: "Clock", apps: "Apps", walls: "Walls", clips: "Clips" })
                        function pageLabel(id) {
                            if (id === "__add_folder__")
                                return "Add a page…";
                            if (defLabels[id])
                                return defLabels[id];
                            const u = (cfg.uploadedPages ?? []).find(p => p.id === id);
                            if (!u)
                                return id;
                            const label = u.label.charAt(0).toUpperCase() + u.label.slice(1);
                            return u.broken ? label + " - missing main.qml" : label;
                        }
                        function pageOn(id) {
                            if (defLabels[id])
                                return (cfg.pages ?? {})[id] !== false;
                            const u = (cfg.uploadedPages ?? []).find(p => p.id === id);
                            return !!(u && u.on);
                        }
                        function pageBroken(id) {
                            const u = (cfg.uploadedPages ?? []).find(p => p.id === id);
                            return !!(u && u.broken);
                        }
                        function pageToggle(id) {
                            if (defLabels[id])
                                win.togglePage(id);
                            else
                                win.toggleUploadedPage(id);
                        }
                        // moves an uploaded page's file to the trash (not a
                        // hard delete — gio trash/trash-put when available,
                        // otherwise a same-directory rename as a last
                        // resort); the row itself drops out on the rescan
                        // this kicks off, same path as noticing the file
                        // vanished from an outside edit
                        function trashPage(id) {
                            const u = (cfg.uploadedPages ?? []).find(p => p.id === id);
                            if (!u)
                                return;
                            pagesTrash.trashedLabel = u.label;
                            pagesTrash.command = ["bash", "-c", `
                                p="$1"
                                if command -v gio >/dev/null 2>&1; then gio trash -- "$p"
                                elif command -v trash-put >/dev/null 2>&1; then trash-put -- "$p"
                                else mv -- "$p" "$p.trashed"
                                fi`, "_", u.path];
                            pagesTrash.running = true;
                        }

                        Item {
                            id: pagesHeader
                            width: parent.width
                            height: 34

                            SLabel {
                                anchors.left: parent.left
                                text: "Pages"
                            }
                            SReset {
                                key: "pages"
                                anchors.right: parent.right
                            }
                        }

                        // copies the folder picked via the "add a page" row
                        // into pibble/custom-pages (gitignored, since it's
                        // user content, not shell code) and rescans — the
                        // row shows up unchecked once the scan picks the
                        // new folder up, the same path an outside drag-
                        // and-drop into that folder would take. Kept under
                        // its own name (not stamped with a timestamp)
                        // unless that name's already taken, in which case
                        // it gets the usual "name (2)" treatment instead of
                        // picking a new name every time.
                        FolderDialog {
                            id: pagesUploadFolderDialog
                            title: "Select a page folder (needs a main.qml inside)"
                            onAccepted: {
                                // strip a trailing slash (if any) before
                                // splitting, or base would come out as
                                // "mywidget/" instead of "mywidget"
                                const src = String(selectedFolder).replace("file://", "").replace(/\/$/, "");
                                const base = src.slice(src.lastIndexOf("/") + 1);
                                pagesUploadFolderCopy.command = ["bash", "-c", `
                                    dir="$1"; src="$2"; base="$3"
                                    mkdir -p "$dir"
                                    dest="$dir/$base"
                                    n=2
                                    while [ -e "$dest" ]; do
                                        dest="$dir/$base ($n)"
                                        n=$((n + 1))
                                    done
                                    cp -r -- "$src" "$dest"`, "_", root.customPagesDir, src, base];
                                pagesUploadFolderCopy.running = true;
                                win.reopenAfterDialog();
                            }
                            onRejected: {
                                win.reopenAfterDialog();
                            }
                        }
                        Process {
                            id: pagesUploadFolderCopy
                            onExited: exitCode => {
                                if (exitCode === 0)
                                    root.rescanUploadedPages();
                            }
                        }
                        Process {
                            id: pagesTrash
                            property string trashedLabel: ""
                            onExited: exitCode => {
                                // on failure this un-hides the row (it slides
                                // back in via the same removing Behaviors)
                                // instead of leaving it stuck invisible
                                const removedId = pagesBlock.removingId;
                                pagesBlock.removingId = "";
                                if (exitCode !== 0)
                                    return;
                                if (pagesBlock.revealedId === removedId)
                                    pagesBlock.revealedId = "";
                                if (removedId && (cfg.customPageData ?? {})[removedId] !== undefined) {
                                    const all = Object.assign({}, cfg.customPageData);
                                    delete all[removedId];
                                    cfg.customPageData = all;
                                }
                                root.rescanUploadedPages();
                                if (root.alertOn("system"))
                                    Quickshell.execDetached(["notify-send", "-a", "pibble", "-i", "user-trash", "Page moved to trash", trashedLabel]);
                            }
                        }
                        // picks up files dropped into/removed from the test
                        // folder by hand while this tab is open, not just on
                        // the next launcher open
                        Timer {
                            interval: 1500
                            repeat: true
                            running: win.shown && win.pane === "settings" && win.settingsTab === "pages"
                            onTriggered: root.rescanUploadedPages()
                        }

                        // stops short of 780 — the same 24px+8px gap the
                        // header's SReset sits in above — so the scroll
                        // track lands to the left of it instead of hugging
                        // the column's outer edge like the reset icon does.
                        // The list itself is narrower still, leaving room
                        // for the scroll-track gutter on its own right.
                        // Qt's hit-test culling skips a whole subtree when
                        // the point is outside an ancestor's rect, so the
                        // track needs to stay within this wrapper's bounds
                        // to receive a press at all
                        Item {
                            id: pagesListWrap
                            anchors.top: pagesHeader.bottom
                            anchors.topMargin: 8
                            width: 780 - 24 - 8
                            height: pagesFlick.height

                            Flickable {
                                id: pagesFlick
                                width: parent.width - 18
                                // "__add_folder__" is a real member of
                                // fullPageOrder (see win.pageIds), so its
                                // row is already included in the count
                                height: pagesBlock.rowH * Math.min(win.fullPageOrder.length, 6)
                                Behavior on height {
                                    NumberAnimation { duration: win.had(180); easing.type: Easing.OutCubic }
                                }
                                clip: true
                                contentWidth: width
                                contentHeight: pagesRows.height
                                boundsBehavior: Flickable.StopAtBounds

                                Item {
                                    id: pagesRows
                                    width: 780
                                    height: win.fullPageOrder.length * pagesBlock.rowH

                                    // model is win.pageIds, not win.fullPageOrder:
                                    // pageIds only changes on genuine add/remove,
                                    // so a plain reorder never touches the
                                    // Repeater's model and never destroys/
                                    // recreates delegates — see the comment on
                                    // win.pageIds for why that matters (a
                                    // recreated delegate mid-drag loses its
                                    // DragHandler's grab, and a recreated one on
                                    // Reset has no Behavior to animate from)
                                    Repeater {
                                        model: win.pageIds

                                        Item {
                                            id: pageRow
                                            required property string modelData
                                            readonly property int ord: win.fullPageOrder.indexOf(modelData)
                                            readonly property bool isReal: !!pagesBlock.defLabels[modelData]
                                            readonly property bool isAdd: modelData === "__add_folder__"
                                            readonly property bool isUploaded: !isReal && !isAdd
                                            width: 780
                                            height: pagesBlock.rowH - 4

                                            property bool held: false
                                            property real slotY: ord * pagesBlock.rowH
                                            property real dragOff: held ? (pagesBlock.pointerViewportY - pagesBlock.dragGrabOffset + pagesFlick.contentY - slotY) : 0
                                            Behavior on slotY {
                                                enabled: !pageRow.held
                                                NumberAnimation { duration: win.had(220); easing.type: Easing.OutCubic }
                                            }
                                            Behavior on dragOff {
                                                enabled: !pageRow.held
                                                NumberAnimation { duration: win.had(220); easing.type: Easing.OutCubic }
                                            }
                                            y: slotY + dragOff
                                            z: held ? 2 : 0
                                            scale: held ? 1.02 : 1
                                            Behavior on scale {
                                                NumberAnimation { duration: win.had(140); easing.type: Easing.OutCubic }
                                            }

                                            // dismiss animation once a trash is
                                            // confirmed: slides the whole row
                                            // (including its revealed delete
                                            // box) out to the left and fades
                                            // it, with the actual file-move
                                            // (and the model update that
                                            // destroys this delegate) held off
                                            // until it's finished — see the
                                            // delete TapHandler below and
                                            // pageRemoveDelay
                                            readonly property bool removing: pagesBlock.removingId === modelData
                                            property real removeOffset: removing ? -width : 0
                                            Behavior on removeOffset {
                                                NumberAnimation { duration: win.had(220); easing.type: Easing.InCubic }
                                            }
                                            opacity: removing ? 0 : 1
                                            Behavior on opacity {
                                                NumberAnimation { duration: win.had(220); easing.type: Easing.InCubic }
                                            }
                                            x: removeOffset

                                            // horizontal reveal for the uploaded-row
                                            // swipe-to-trash gesture (see pageFront's
                                            // swipeDrag below); closes itself whenever
                                            // a different row becomes the open one
                                            property real revealX: 0
                                            // one tickbox-width slot (18) plus the
                                            // same 8px gap pageContent's Row uses
                                            // between the tickbox and label
                                            readonly property real revealWidth: 26
                                            // enabled is toggled imperatively from
                                            // swipeDrag (not bound to !swipeDrag.active):
                                            // that binding races the same handler's own
                                            // revealX write on release — both react to
                                            // the same activeChanged signal, and there's
                                            // no guarantee the enabled binding resolves
                                            // before the write reaches this Behavior, so
                                            // the rebound was sometimes snapping instead
                                            // of animating. An explicit imperative set,
                                            // strictly before the write, always wins the
                                            // race because it's sequenced in code order
                                            // OutBack (a touch of overshoot on settle)
                                            // when animations are on, matching the
                                            // rubber-banded drag above; plain OutCubic
                                            // when they're off, since win.had() zeroes
                                            // the duration anyway and there's nothing
                                            // to overshoot from at that point
                                            Behavior on revealX {
                                                id: revealXBehavior
                                                enabled: false
                                                NumberAnimation {
                                                    duration: win.had(220)
                                                    easing.type: cfg.hiddenMenuAnimations ? Easing.OutBack : Easing.OutCubic
                                                    easing.overshoot: 1.5
                                                }
                                            }
                                            Connections {
                                                target: pagesBlock
                                                function onRevealedIdChanged() {
                                                    if (pagesBlock.revealedId !== pageRow.modelData) {
                                                        pageRow.revealX = 0;
                                                        pageDelete.confirming = false;
                                                    }
                                                }
                                            }

                                            // vertical reorder drag, covering the whole
                                            // row; pageFront below carries an orthogonal
                                            // horizontal-only DragHandler for the swipe
                                            // gesture — xAxis/yAxis being disabled on
                                            // one each is what lets a mostly-vertical vs.
                                            // mostly-horizontal drag resolve to the right
                                            // one without the two fighting over the grab
                                            DragHandler {
                                                // the add row is pinned to the
                                                // top (see win.fullPageOrder) and
                                                // can't be reordered
                                                enabled: !pageRow.isAdd
                                                target: null
                                                xAxis.enabled: false
                                                onActiveChanged: {
                                                    if (active) {
                                                        const viewportY = pageRow.mapToItem(pagesFlick, 0, centroid.position.y).y;
                                                        pageRow.held = true;
                                                        pagesBlock.pointerViewportY = viewportY;
                                                        pagesBlock.dragGrabOffset = viewportY - (pageRow.slotY - pagesFlick.contentY);
                                                        pagesBlock.draggedId = pageRow.modelData;
                                                        pagesFlick.interactive = false;
                                                    } else {
                                                        pageRow.held = false;
                                                        pagesBlock.draggedId = "";
                                                        pagesBlock.edgeDir = 0;
                                                        pagesFlick.interactive = true;
                                                        root.saveSettings();
                                                    }
                                                }
                                                onCentroidChanged: {
                                                    if (!active)
                                                        return;
                                                    const viewportY = pageRow.mapToItem(pagesFlick, 0, centroid.position.y).y;
                                                    pagesBlock.pointerViewportY = viewportY;
                                                    const edge = 28;
                                                    if (viewportY < edge)
                                                        pagesBlock.edgeDir = -1;
                                                    else if (viewportY > pagesFlick.height - edge)
                                                        pagesBlock.edgeDir = 1;
                                                    else
                                                        pagesBlock.edgeDir = 0;
                                                    pagesBlock.dragReorderCheck();
                                                }
                                            }

                                            // trash button — no background needed to hide
                                            // it: it sits just past the row's left edge,
                                            // outside pagesFlick's clip rect, and slides
                                            // into view as pageFront (below) moves right in
                                            // lockstep (both driven by the same revealX).
                                            // Same footprint as pageBox (18x18, flush
                                            // against the row's left edge once fully
                                            // revealed) so revealing it reads as a real
                                            // tickbox-sized slot pushing the row's content
                                            // over, not a floating overlay. Tap once to
                                            // arm (turns red), tap again to actually trash
                                            // — only reachable once revealed, so
                                            // swipe-then-tap-tap is the full confirmation
                                            Item {
                                                id: pageDelete
                                                visible: pageRow.isUploaded
                                                x: pageRow.revealX - pageRow.revealWidth + pagesBlock.rowInset
                                                y: 0
                                                width: pageRow.revealWidth
                                                height: parent.height
                                                property bool confirming: false

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 18
                                                    height: 18
                                                    radius: 4
                                                    color: pageDelete.confirming ? Qt.alpha("#e5484d", 0.85) : Qt.alpha(root.muted, 0.2)
                                                    border.width: 1
                                                    border.color: pageDelete.confirming ? "#e5484d" : Qt.alpha(root.muted, 0.6)
                                                    Behavior on color {
                                                        ColorAnimation { duration: win.had(140) }
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "×"
                                                        color: pageDelete.confirming ? "#141210" : root.muted
                                                        font { family: root.mono; pixelSize: 14 }
                                                    }
                                                }
                                                Timer {
                                                    id: pageDeleteRevert
                                                    interval: 2500
                                                    onTriggered: pageDelete.confirming = false
                                                }
                                                // fires once the slide-left/fade dismiss
                                                // (pageRow.removing, above) has finished;
                                                // only then does the file actually move,
                                                // so the row is already invisible by the
                                                // time the model update destroys it
                                                Timer {
                                                    id: pageRemoveDelay
                                                    interval: 220
                                                    onTriggered: pagesBlock.trashPage(pageRow.modelData)
                                                }
                                                TapHandler {
                                                    enabled: pageRow.revealX > pageRow.revealWidth - 1
                                                    onTapped: {
                                                        if (pageDelete.confirming) {
                                                            // leaves revealX/revealedId alone —
                                                            // the row slides away exactly as
                                                            // last seen (still revealed, still
                                                            // red) rather than snapping closed
                                                            // first
                                                            pagesBlock.removingId = pageRow.modelData;
                                                            pageRemoveDelay.restart();
                                                        } else {
                                                            pageDelete.confirming = true;
                                                            pageDeleteRevert.restart();
                                                        }
                                                    }
                                                }
                                            }

                                            // front layer: checkbox/label (or the add
                                            // affordance) — slides right on a swipe to
                                            // expose pageDelete above. width/height
                                            // are plain bindings rather than
                                            // anchors.fill: an item can't have both an
                                            // anchored (left+right) and an explicitly
                                            // bound x — whichever is (re)assigned last
                                            // wins, and the two silently fight for
                                            // control of x on every relayout
                                            Item {
                                                id: pageFront
                                                width: pageRow.width
                                                height: pageRow.height
                                                x: pageRow.revealX + pagesBlock.rowInset
                                                z: 1

                                                Row {
                                                    id: pageContent
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 8

                                                    Rectangle {
                                                        id: pageBox
                                                        readonly property bool broken: pagesBlock.pageBroken(pageRow.modelData)
                                                        visible: !pageRow.isAdd
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 18
                                                        height: 18
                                                        radius: 4
                                                        color: pagesBlock.pageOn(pageRow.modelData) ? Qt.alpha(root.accent, 0.85) : "transparent"
                                                        border.width: 1
                                                        border.color: broken ? Qt.alpha(root.muted, 0.6) : (pagesBlock.pageOn(pageRow.modelData) ? root.accent : Qt.alpha(root.muted, 0.6))

                                                        Text {
                                                            anchors.centerIn: parent
                                                            visible: pagesBlock.pageOn(pageRow.modelData) || pageBox.broken
                                                            text: pageBox.broken ? root.ti.alertTriangle : root.ti.check
                                                            color: pageBox.broken ? Qt.alpha(root.muted, 0.9) : "#141210"
                                                            font { family: root.iconFont; pixelSize: 13 }
                                                        }
                                                        // disabled while revealed (a tap there
                                                        // closes the swipe instead) or when the
                                                        // page is broken — there's nothing to
                                                        // toggle on, only to trash
                                                        TapHandler {
                                                            enabled: pageRow.revealX < 1 && !pageBox.broken
                                                            onTapped: pagesBlock.pageToggle(pageRow.modelData)
                                                        }
                                                    }
                                                    Rectangle {
                                                        visible: pageRow.isAdd
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 18
                                                        height: 18
                                                        radius: 4
                                                        color: "transparent"
                                                        border.width: 1
                                                        border.color: Qt.alpha(root.accent, 0.6)

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "+"
                                                            color: root.accent
                                                            font { family: root.mono; pixelSize: 13 }
                                                        }
                                                    }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: pagesBlock.pageLabel(pageRow.modelData)
                                                        color: pageRow.isAdd ? root.accent : (pagesBlock.pageOn(pageRow.modelData) ? root.fg : root.muted)
                                                        font { family: root.mono; pixelSize: root.fs(13) }
                                                    }
                                                }

                                                TapHandler {
                                                    enabled: pageRow.isAdd
                                                    onTapped: {
                                                        win.dialogPending = "folder";
                                                        win.exit();
                                                    }
                                                }
                                                // tapping the revealed front layer
                                                // anywhere else just closes it again
                                                TapHandler {
                                                    enabled: pageRow.isUploaded && pageRow.revealX > 1
                                                    onTapped: {
                                                        pageRow.revealX = 0;
                                                        pageDelete.confirming = false;
                                                        pagesBlock.revealedId = "";
                                                    }
                                                }

                                                DragHandler {
                                                    id: swipeDrag
                                                    target: null
                                                    yAxis.enabled: false
                                                    enabled: pageRow.isUploaded
                                                    property real grabX: 0
                                                    onActiveChanged: {
                                                        if (active) {
                                                            revealXBehavior.enabled = false;
                                                            grabX = centroid.scenePosition.x - pageRow.revealX;
                                                            pagesBlock.revealedId = pageRow.modelData;
                                                        } else {
                                                            revealXBehavior.enabled = true;
                                                            pageRow.revealX = pageRow.revealX > pageRow.revealWidth / 2 ? pageRow.revealWidth : 0;
                                                            if (pageRow.revealX === 0) {
                                                                pagesBlock.revealedId = "";
                                                                pageDelete.confirming = false;
                                                            }
                                                        }
                                                    }
                                                    onCentroidChanged: {
                                                        if (!active)
                                                            return;
                                                        // rubber-banded when animations are on
                                                        // (dragging past either end still tracks
                                                        // the finger, with resistance); hard-
                                                        // clamped when they're off — no leftward
                                                        // swipe, no resistance past either end
                                                        pageRow.revealX = cfg.hiddenMenuAnimations
                                                            ? pagesBlock.rubberBand(centroid.scenePosition.x - grabX, 0, pageRow.revealWidth, 90)
                                                            : Math.max(0, Math.min(pageRow.revealWidth, centroid.scenePosition.x - grabX));
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // dragging a row past the viewport edge scrolls the
                            // list in that direction
                            Timer {
                                interval: 16
                                repeat: true
                                running: pagesBlock.edgeDir !== 0 && pagesBlock.draggedId !== ""
                                onTriggered: {
                                    const maxY = Math.max(0, pagesFlick.contentHeight - pagesFlick.height);
                                    pagesFlick.contentY = Math.max(0, Math.min(maxY, pagesFlick.contentY + pagesBlock.edgeDir * 14));
                                    pagesBlock.dragReorderCheck();
                                }
                            }

                            // this layer-shell surface never delivers wheel
                            // events to a WheelHandler (see the background
                            // click-catcher's identical note above), and a
                            // plain Flickable's own wheel handling relies on
                            // one — acceptedButtons: NoButton lets presses/
                            // drags fall through to the rows underneath while
                            // still catching the wheel. contentY is animated
                            // rather than set outright (a standalone
                            // NumberAnimation, not a Behavior — a Behavior on
                            // contentY would also apply to, and fight, native
                            // touch/drag flicking): with only a handful of
                            // rows one notch can easily cover the whole
                            // scroll range, and an instant jump there reads
                            // as broken where a quick animated slide doesn't
                            MouseArea {
                                anchors.fill: pagesFlick
                                acceptedButtons: Qt.NoButton
                                onWheel: wheel => {
                                    const maxY = Math.max(0, pagesFlick.contentHeight - pagesFlick.height);
                                    const target = Math.max(0, Math.min(maxY, pagesFlick.contentY - (wheel.angleDelta.y / 120) * pagesBlock.rowH * 3));
                                    pagesWheelScroll.to = target;
                                    pagesWheelScroll.restart();
                                }
                            }
                            NumberAnimation {
                                id: pagesWheelScroll
                                target: pagesFlick
                                property: "contentY"
                                duration: 100
                                easing.type: Easing.OutCubic
                            }

                            // hand-rolled scroll indicator: a MouseArea with
                            // preventStealing (rather than a DragHandler) is
                            // what reliably beats the swipe-to-power
                            // catcher's own DragHandler for the drag grab.
                            // Width matches the 18px gap pagesListWrap leaves
                            // to the right of pagesFlick exactly, so it can't
                            // extend leftward over row content
                            Item {
                                id: pagesScrollHit
                                anchors.right: parent.right
                                anchors.top: pagesFlick.top
                                anchors.bottom: pagesFlick.bottom
                                width: 18
                                readonly property bool shouldShow: pagesFlick.contentHeight > pagesFlick.height

                                Rectangle {
                                    id: pagesScrollTrack
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 6
                                    // grows/shrinks in vertically, from the
                                    // center out, as the list crosses the
                                    // row-count that needs scrolling, rather
                                    // than popping in/out
                                    height: pagesScrollHit.shouldShow ? parent.height : 0
                                    Behavior on height {
                                        NumberAnimation { duration: win.had(180); easing.type: Easing.OutCubic }
                                    }
                                    radius: 3
                                    color: Qt.alpha(root.muted, 0.15)

                                    Rectangle {
                                        id: pagesScrollThumb
                                        width: parent.width
                                        radius: 3
                                        color: Qt.alpha(root.accent, pagesScrollArea.pressed ? 0.85 : 0.6)
                                        // floored so it stays grabbable once the
                                        // list is long enough that the honest
                                        // proportional size would be a sliver —
                                        // no ceiling, since capping the top end
                                        // would misrepresent how much is
                                        // visible (e.g. 6 of 7 rows shown should
                                        // read as a thumb spanning ~85% of the
                                        // track, not a stub). Also capped to the
                                        // track's own (animating) height, so the
                                        // floor doesn't leave the thumb poking
                                        // out past a track that's mid-shrink or
                                        // fully collapsed
                                        height: Math.min(pagesScrollTrack.height, Math.max(12, pagesFlick.visibleArea.heightRatio * pagesScrollTrack.height))
                                        // yPosition alone assumes the thumb is
                                        // exactly heightRatio*trackHeight tall
                                        // (yPosition + heightRatio caps at 1,
                                        // landing y+height on the track's
                                        // bottom edge); once height is floored
                                        // instead, that no longer reaches the
                                        // bottom, so rescale yPosition's own
                                        // range ([0, 1-heightRatio]) to
                                        // [0, 1] first
                                        y: {
                                            const range = 1 - pagesFlick.visibleArea.heightRatio;
                                            const progress = range > 0 ? pagesFlick.visibleArea.yPosition / range : 0;
                                            return progress * (pagesScrollTrack.height - height);
                                        }
                                    }
                                }

                                MouseArea {
                                    id: pagesScrollArea
                                    anchors.fill: parent
                                    enabled: pagesScrollHit.shouldShow
                                    preventStealing: true
                                    property real pressY: 0
                                    property real pressThumbY: 0
                                    onPressed: mouse => {
                                        pressY = mouse.y;
                                        pressThumbY = pagesScrollThumb.y;
                                    }
                                    onPositionChanged: mouse => {
                                        if (!pressed)
                                            return;
                                        const usable = Math.max(1, pagesScrollTrack.height - pagesScrollThumb.height);
                                        const newY = Math.max(0, Math.min(usable, pressThumbY + (mouse.y - pressY)));
                                        const maxContentY = Math.max(0, pagesFlick.contentHeight - pagesFlick.height);
                                        pagesFlick.contentY = (newY / usable) * maxContentY;
                                    }
                                }
                            }
                        }

                        SSub {
                            id: pagesSub
                            anchors.top: pagesListWrap.bottom
                            anchors.topMargin: 2
                            text: "drag to reorder · swipe right to delete · folders with a main.qml placed in pibble/custom-pages appear here"
                        }
                    }

                    SettingRow { key: "dimOpacity"; label: "Background opacity" }

                    SettingRow { key: "bgBlur"; label: "Background blur"; sub: "only supported by compositors that implement the ext-background-effect-v1 protocol" }

                    // clock-page layout: three stationary tickboxes (date,
                    // battery, weather). The grouping itself is fixed, not
                    // user-arranged: the clock always sits on its own line up
                    // top, date (if ticked) directly under it, and battery +
                    // weather (if either is ticked) always share one line at
                    // the bottom.
                    Item {
                        width: 780
                        height: 34

                        SLabel {
                            anchors.left: parent.left
                            text: "Clock"
                        }
                        SReset {
                            key: "clock"
                            anchors.right: parent.right
                        }
                        Item {
                            id: clockArea
                            anchors.right: parent.right
                            anchors.rightMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            // fixed 100px pitch between tickboxes
                            readonly property int slotW: 100
                            width: slotW * 3 - 8
                            height: 28

                            Repeater {
                                model: ["date", "battery", "weather"]

                                Item {
                                    id: clockChip
                                    required property var modelData
                                    required property int index
                                    readonly property bool on: (cfg.clockShow ?? {})[modelData] !== false
                                    x: index * clockArea.slotW
                                    width: clockArea.slotW - 8
                                    height: 28

                                    Rectangle {
                                        id: clockCheckbox
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        height: 18
                                        radius: 4
                                        color: clockChip.on ? Qt.alpha(root.accent, 0.85) : "transparent"
                                        border.width: 1
                                        border.color: clockChip.on ? root.accent : Qt.alpha(root.muted, 0.6)

                                        Text {
                                            anchors.centerIn: parent
                                            visible: clockChip.on
                                            text: root.ti.check
                                            color: "#141210"
                                            font { family: root.iconFont; pixelSize: 13 }
                                        }
                                    }
                                    Text {
                                        id: clockLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: clockCheckbox.right
                                        anchors.leftMargin: 6
                                        text: clockChip.modelData
                                        color: clockChip.on ? root.fg : root.muted
                                        font { family: root.mono; pixelSize: root.fs(12) }
                                    }

                                    TapHandler {
                                        onTapped: win.toggleClockItem(clockChip.modelData)
                                    }
                                }
                            }
                        }
                    }

                    // grid size: one visible tile grid, switchable between the
                    // three pages that have a configurable grid size
                    Item {
                        width: 780
                        height: 34

                        SLabel {
                            anchors.left: parent.left
                            text: "Grid size"
                        }
                        SReset {
                            key: root.gridTargets[win.gridTarget].resetKey
                            anchors.right: parent.right
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 34 + 32
                            spacing: 24
                            height: parent.height

                            Repeater {
                                model: ["apps", "walls", "clips"]

                                Item {
                                    id: gridTargetChip
                                    required property string modelData
                                    readonly property bool active: win.gridTarget === modelData
                                    width: gridTargetText.implicitWidth
                                    height: parent.height

                                    Text {
                                        id: gridTargetText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.gridTargets[gridTargetChip.modelData].label
                                        color: gridTargetChip.active ? root.fg : root.muted
                                        font { family: root.mono; pixelSize: root.fs(13) }
                                    }
                                    Rectangle {
                                        anchors.top: gridTargetText.bottom
                                        anchors.topMargin: 4
                                        width: parent.width
                                        height: 2
                                        radius: 1
                                        color: root.accent
                                        opacity: gridTargetChip.active ? 1 : 0
                                        Behavior on opacity {
                                            NumberAnimation { duration: win.had(150); easing.type: Easing.OutCubic }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: win.gridTarget = gridTargetChip.modelData
                                    }
                                }
                            }
                        }
                    }

                    GridSizeTiles {
                        target: win.gridTarget
                    }

                    SettingRow { key: "animStyle"; label: "Grid animation" }

                    SettingRow { key: "iconTheme"; label: "App icon theme"; sub: "applies on next launch"; valueWidth: 190 }

                    SettingRow { key: "wallpaperStyle"; label: "Wallpaper style"; valueWidth: 190 }

                    // wallpaper path
                    Item {
                        width: 780
                        height: 38

                        SLabel {
                            anchors.left: parent.left
                            text: "Wallpaper path"
                        }
                        SReset {
                            key: "wallpaperDir"
                            anchors.right: parent.right
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            width: 420
                            height: 34
                            radius: 8
                            color: Qt.alpha(root.accent, pathInput.activeFocus ? 0.16 : 0.08)
                            border.width: 1
                            border.color: pathInput.activeFocus ? root.accent : Qt.alpha(root.accent, 0.33)

                            Text {
                                anchors.fill: parent
                                anchors.margins: 8
                                verticalAlignment: Text.AlignVCenter
                                visible: pathInput.text.length === 0
                                text: "~/Pictures/wallpapers"
                                color: root.muted
                                font { family: root.mono; pixelSize: root.fs(13) }
                            }
                            TextInput {
                                id: pathInput
                                anchors.fill: parent
                                anchors.margins: 8
                                verticalAlignment: TextInput.AlignVCenter
                                text: cfg.wallpaperDir
                                color: root.fg
                                clip: true
                                font { family: root.mono; pixelSize: root.fs(13) }
                                onEditingFinished: {
                                    if (text !== cfg.wallpaperDir) {
                                        cfg.wallpaperDir = text;
                                        root.saveSettings();
                                        root.rescanWallpapers();
                                    }
                                    input.forceActiveFocus();
                                }
                                Keys.onEscapePressed: input.forceActiveFocus()
                                Connections {
                                    target: cfg
                                    function onWallpaperDirChanged() {
                                        pathInput.text = cfg.wallpaperDir;
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

                    // wallpaper command ($WALL = image, $BLUR = blurred variant)
                    Item {
                        width: 780
                        height: 38 + 2 + wallCmdSub.implicitHeight

                        Item {
                        id: wallCmdMain
                        width: parent.width
                        height: 38

                        SLabel {
                            anchors.left: parent.left
                            text: "Wallpaper command"
                        }
                        SReset {
                            key: "wallCommand"
                            anchors.right: parent.right
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            width: 506
                            height: 34
                            radius: 8
                            color: Qt.alpha(root.accent, cmdInput.activeFocus ? 0.16 : 0.08)
                            border.width: 1
                            border.color: cmdInput.activeFocus ? root.accent : Qt.alpha(root.accent, 0.33)

                            Text {
                                anchors.fill: parent
                                anchors.margins: 8
                                verticalAlignment: Text.AlignVCenter
                                visible: cmdInput.text.length === 0
                                text: root.defaultWallCommand
                                color: root.muted
                                elide: Text.ElideRight
                                font { family: root.mono; pixelSize: root.fs(12) }
                            }
                            TextInput {
                                id: cmdInput
                                anchors.fill: parent
                                anchors.margins: 8
                                verticalAlignment: TextInput.AlignVCenter
                                text: cfg.wallCommand
                                color: root.fg
                                clip: true
                                font { family: root.mono; pixelSize: root.fs(12) }
                                onEditingFinished: {
                                    if (text !== cfg.wallCommand) {
                                        cfg.wallCommand = text;
                                        root.saveSettings();
                                    }
                                    input.forceActiveFocus();
                                }
                                Keys.onEscapePressed: input.forceActiveFocus()
                                Connections {
                                    target: cfg
                                    function onWallCommandChanged() {
                                        cmdInput.text = cfg.wallCommand;
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

                        SSub {
                            id: wallCmdSub
                            anchors.top: wallCmdMain.bottom
                            anchors.topMargin: 2
                            text: "$WALL = selected image, $BLUR = blurred variant (auto-generated)"
                        }
                    }

                    SettingRow { key: "clipsMax"; label: "Clipboard entries" }

                }

                // keybindings tab
                Column {
                    id: keybindCol
                    x: 20 + (2 - settingsPane.tabIdx) * 840
                    Behavior on x {
                        NumberAnimation { duration: win.had(420); easing.type: Easing.OutCubic }
                    }
                    spacing: 14

                    // shared width for every chord box, fixed to the longest
                    // possible two-key chord (one modifier + the longest
                    // recognised key name) rather than derived from whatever
                    // binds happen to be set — so the box is wide enough for
                    // anything keyName() can produce and never resizes when
                    // a row starts/stops capturing or a bind changes length.
                    readonly property real uniformBoxWidth: Math.max(captureMetrics.implicitWidth, maxChordMetrics.implicitWidth)
                    Text {
                        id: captureMetrics
                        visible: false
                        text: "press a key…"
                        font { family: root.mono; pixelSize: root.fs(13) }
                    }
                    Row {
                        id: maxChordMetrics
                        visible: false
                        spacing: 4
                        KeyCap { label: "Shift" }
                        KeyPlus {}
                        KeyCap { label: "ScrollLock" }
                    }

                    Repeater {
                        id: bindRepeater
                        model: [
                            { action: "cycle", label: "Cycle pages" },
                            { action: "reverseCycle", label: "Cycle pages (reverse)" },
                            { action: "launch", label: "Launch / apply" },
                            { action: "settings", label: "Settings" },
                            { action: "power", label: "Power off prompt" },
                            { action: "reboot", label: "Reboot prompt" },
                            { action: "exit", label: "Exit / back" }
                        ]

                        Item {
                            id: bindRow
                            required property var modelData
                            width: 780
                            height: 34

                            SLabel {
                                anchors.left: parent.left
                                text: bindRow.modelData.label
                            }
                            SReset {
                                key: "bind:" + bindRow.modelData.action
                                anchors.right: parent.right
                            }
                            Rectangle {
                                id: bindBox
                                readonly property bool capturing: win.capturingBind === bindRow.modelData.action
                                readonly property string bindStr: cfg.keybinds[bindRow.modelData.action] ?? win.bindDefaults[bindRow.modelData.action] ?? ""
                                readonly property var keyTokens: bindStr.split("+")
                                // while capturing, render whatever's currently held (via
                                // win.captureLive) in the same KeyCap style as the settled
                                // chip, instead of dropping to plain text — only the
                                // "nothing held yet" moment has no keys to render, so that's
                                // the one case still showing a plain hint
                                readonly property var displayTokens: capturing ? (win.captureLive ? win.captureLive.split("+") : []) : keyTokens
                                anchors.right: parent.right
                                anchors.rightMargin: 34
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(110, keybindCol.uniformBoxWidth + 32)
                                height: 34
                                radius: 8
                                color: Qt.alpha(root.accent, capturing ? 0.3 : 0.11)
                                border.width: 1
                                border.color: capturing ? root.accent : Qt.alpha(root.accent, 0.33)

                                Text {
                                    anchors.centerIn: parent
                                    visible: bindBox.displayTokens.length === 0
                                    text: "press a key…"
                                    color: root.fg
                                    font { family: root.mono; pixelSize: root.fs(13) }
                                }
                                Row {
                                    id: capRow
                                    anchors.centerIn: parent
                                    visible: bindBox.displayTokens.length > 0
                                    spacing: 4
                                    Repeater {
                                        model: bindBox.displayTokens
                                        Row {
                                            id: pairRow
                                            required property string modelData
                                            required property int index
                                            spacing: 4
                                            KeyCap {
                                                label: pairRow.modelData
                                            }
                                            KeyPlus {
                                                visible: pairRow.index < bindBox.displayTokens.length - 1
                                            }
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        win.capturingBind = bindRow.modelData.action;
                                        input.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: 780
                        height: 34 + gestureSub.implicitHeight + 2

                        Item {
                            id: gestureMain
                            width: parent.width
                            height: 34

                            SLabel {
                                anchors.left: parent.left
                                text: "Gestures"
                            }
                            SReset {
                                key: "gestures"
                                anchors.right: parent.right
                            }
                            ChipRow {
                                anchors.right: parent.right
                                anchors.rightMargin: 34 + 32
                                anchors.verticalCenter: parent.verticalCenter
                                items: [
                                    { id: "power", label: "power/reboot" },
                                    { id: "panes", label: "pages" }
                                ]
                                isOn: root.gestureOn
                                toggle: win.toggleGesture
                            }
                        }
                        SSub {
                            id: gestureSub
                            anchors.top: gestureMain.bottom
                            anchors.topMargin: 2
                            text: "power/reboot: swipe up/down to arm the prompt · pages: swipe left/right to cycle panes/settings tabs"
                        }
                    }
                }

                // one slide per custom page that contributes a settings
                // tab (see win.customSettingsTabs) — same filmstrip as the
                // four built-in columns above, just at whatever index
                // settingsPane.tabOrder placed this page's id at
                Repeater {
                    id: customTabsRepeater
                    model: win.customSettingsTabs

                    Column {
                        id: customTabCol
                        required property var modelData
                        readonly property int slideIdx: settingsPane.tabOrder.indexOf(modelData.pageId)
                        x: 20 + (slideIdx - settingsPane.tabIdx) * 840
                        // a freshly-appearing tab's slideIdx starts at -1 for
                        // one tick — win.customSettingsTabs (which this
                        // Repeater's model is) picks up the page's newly-
                        // loaded settingsTab a moment before
                        // settingsPane.tabOrder, which derives from it, has
                        // recomputed to include this pageId — so x's first
                        // real value briefly parks off-screen left before
                        // jumping to its actual off-screen-right slot once
                        // slideIdx corrects. With the Behavior live for that
                        // correction, it animates the whole ~4200px hop,
                        // sweeping straight through the visible viewport
                        // (the "page content flying across the screen" bug).
                        // Qt.callLater defers arming the Behavior past that
                        // initial settle, so only genuine later tab switches
                        // (settingsPane.tabIdx changing, not this one-time
                        // slideIdx correction) animate.
                        property bool animateX: false
                        Component.onCompleted: Qt.callLater(() => customTabCol.animateX = true)
                        Behavior on x {
                            enabled: customTabCol.animateX
                            NumberAnimation { duration: win.had(420); easing.type: Easing.OutCubic }
                        }
                        spacing: 14

                        // the page's own Component — declared inside its
                        // file, so it resolves `pibble`/getSetting/etc via
                        // that file's own scope, same as any other child of
                        // its root item would
                        Loader {
                            sourceComponent: customTabCol.modelData.component
                        }
                    }
                }
                } // tabViewport

                // topmost within the settings pane: clicking a tab link, an
                // SBtn/SReset, a different chord box, or empty padding while
                // a bind is being recorded should cancel that recording —
                // but the click must still reach whatever it landed on (the
                // tab switch, the button press, etc), so this observes the
                // press and lets it fall through instead of consuming it.
                MouseArea {
                    anchors.fill: parent
                    propagateComposedEvents: true
                    onPressed: mouse => {
                        if (win.capturingBind)
                            win.cancelCapture();
                        mouse.accepted = false;
                    }
                }
            }

            // Swipe-to-power/reboot pull indicator: extra dim over the whole
            // screen, and a small ring that rides ahead of the pulled
            // content (down from the top for power, up from the bottom for
            // reboot), stroking itself closed as the drag progresses. On
            // completion a confirmation prompt fades in; Enter confirms.
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.5 * Math.max(win.powerProgress, win.rebootProgress)
            }
            Item {
                id: powerRing
                visible: win.powerRaw > 1
                anchors.horizontalCenter: parent.horizontalCenter
                // the -200 rides in with the pull so the ring still enters
                // from the top edge, just landing higher than the stock spot
                y: -height + win.powerPull * 2.6 - 200 * win.powerProgress
                width: 36
                height: 36
                opacity: Math.min(1, win.powerRaw / 80)

                Canvas {
                    id: ringCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const cx = width / 2, cy = height / 2, r = 10;
                        // p drives the sweep growth and stops at 1 — past
                        // the arm threshold the shape (and its gaps) is
                        // done growing. Instead, overshoot dragging spins
                        // the whole completed assembly (tail, head, dash)
                        // rigidly together, capped with the same
                        // diminishing-returns curve as powerPull, so the
                        // gaps around the dash stay fixed instead of
                        // stretching apart
                        const p = Math.min(1, win.powerRaw / win.powerThreshold);
                        const maxOvershoot = 0.4;
                        const excess = Math.max(0, win.powerRaw - win.powerThreshold);
                        const rot = maxOvershoot * (1 - Math.exp(-excess / 260)) * Math.PI * 2;
                        // a fixed dash marks 12 o'clock the whole time; the
                        // ring never closes onto it — both ends pull away
                        // from the dash as the drag progresses, landing with
                        // an equal gap to either side of it once complete
                        const finalGap = 1.1;
                        const tail = -Math.PI / 2 + (finalGap / 2) * p + rot;
                        const head = tail + (Math.PI * 2 - finalGap) * p;
                        ctx.lineWidth = 3.3;
                        ctx.lineCap = "butt";
                        ctx.strokeStyle = root.accent;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, tail, head, false);
                        ctx.stroke();

                        // the dash itself: perpendicular to the ring (i.e.
                        // radial), leading a constant finalGap/2 ahead of
                        // the head — so it rides along with the head,
                        // landing exactly at 12 o'clock once the head
                        // completes its sweep. Held back until the drag is
                        // two thirds of the way through, then grows from a
                        // sliver
                        if (p > 2 / 3) {
                            const dashAngle = head + finalGap / 2;
                            const dx = Math.cos(dashAngle), dy = Math.sin(dashAngle);
                            const dcx = cx + (r - 2) * dx, dcy = cy + (r - 2) * dy;
                            const halfLen = (0.05 + 4.55 * (p - 2 / 3) / (1 / 3));
                            ctx.beginPath();
                            ctx.moveTo(dcx - dx * halfLen, dcy - dy * halfLen);
                            ctx.lineTo(dcx + dx * halfLen, dcy + dy * halfLen);
                            ctx.stroke();
                        }
                    }
                }
                Connections {
                    target: win
                    // powerRaw (not powerProgress, which clamps at 1)
                    // drives the paint so dragging past the threshold keeps
                    // repainting the overshoot spin
                    function onPowerRawChanged() {
                        ringCanvas.requestPaint();
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: powerRing.y + powerRing.height + 12
                text: "power off?"
                color: root.fg
                // start the fade as the ring nears closed: the pull easing
                // crawls through its last few percent, so waiting for exactly
                // 1.0 reads as a long pause after the circle looks complete
                opacity: win.powerProgress >= 0.85 ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: win.had(160); easing.type: Easing.OutCubic }
                }
                font { family: root.mono; pixelSize: root.fs(18); letterSpacing: 2 }
            }

            // reboot ring: mirror of powerRing, riding up from the bottom
            // edge instead of down from the top.
            Item {
                id: rebootRing
                visible: win.rebootRaw > 1
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -height + win.rebootPull * 2.6 - 200 * win.rebootProgress
                width: 36
                height: 36
                opacity: Math.min(1, win.rebootRaw / 80)

                Canvas {
                    id: rebootRingCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const cx = width / 2, cy = height / 2, r = 10;
                        // unlike powerRing, this one never lets the arc
                        // close: past maxArc of a full turn the tail chases
                        // the head at the same rate instead of staying
                        // pinned at the top, so the gap holds steady and the
                        // ring reads as a snake that can't catch its tail.
                        // headFrac keeps advancing past the arm threshold
                        // instead of freezing there, but the extra spin is
                        // capped with the same diminishing-returns curve as
                        // rebootPull, so it matches the drag's own
                        // overshoot limits rather than spinning forever
                        const maxArc = 0.82;
                        const maxOvershoot = 0.4;
                        const excess = Math.max(0, win.rebootRaw - win.rebootThreshold);
                        const headFrac = Math.min(1, win.rebootRaw / win.rebootThreshold)
                            + maxOvershoot * (1 - Math.exp(-excess / 260));
                        const tailFrac = Math.max(0, headFrac - maxArc);
                        const start = -Math.PI / 2 + Math.PI * 2 * tailFrac;
                        const end = -Math.PI / 2 + Math.PI * 2 * headFrac;
                        ctx.lineWidth = 3.3;
                        ctx.lineCap = "butt";
                        ctx.strokeStyle = root.accent;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, start, end, false);
                        ctx.stroke();

                        // leading arrowhead, oriented along the direction of travel
                        if (headFrac > 0.02) {
                            const hx = cx + r * Math.cos(end);
                            const hy = cy + r * Math.sin(end);
                            const tangent = end + Math.PI / 2;
                            const nx = Math.cos(tangent + Math.PI / 2);
                            const ny = Math.sin(tangent + Math.PI / 2);
                            // grows over the course of the drag, from a
                            // small nub to the full arrowhead — capped so
                            // it doesn't keep bloating during overshoot
                            const arrowScale = 0.3 + 0.7 * Math.min(1, headFrac);
                            const tipX = hx + Math.cos(tangent) * 4.5 * arrowScale;
                            const tipY = hy + Math.sin(tangent) * 4.5 * arrowScale;
                            const backX = hx - Math.cos(tangent) * 3 * arrowScale;
                            const backY = hy - Math.sin(tangent) * 3 * arrowScale;
                            ctx.beginPath();
                            ctx.moveTo(tipX, tipY);
                            ctx.lineTo(backX + nx * 5 * arrowScale, backY + ny * 5 * arrowScale);
                            ctx.lineTo(backX - nx * 5 * arrowScale, backY - ny * 5 * arrowScale);
                            ctx.closePath();
                            ctx.fillStyle = root.accent;
                            ctx.fill();
                        }
                    }
                }
                Connections {
                    target: win
                    // rebootRaw (not rebootProgress, which clamps at 1)
                    // drives the paint so dragging past the threshold keeps
                    // repainting the overshoot spin
                    function onRebootRawChanged() {
                        rebootRingCanvas.requestPaint();
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                // trails above the ring by the same gap powerText trails
                // below powerRing, mirrored around the bottom edge
                anchors.bottomMargin: win.rebootPull * 2.6 - 200 * win.rebootProgress + 12
                text: "reboot?"
                color: root.fg
                opacity: win.rebootProgress >= 0.85 ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: win.had(160); easing.type: Easing.OutCubic }
                }
                font { family: root.mono; pixelSize: root.fs(18); letterSpacing: 2 }
            }

            // Corner settings button: pops up when hovering the bottom-right
            // corner, or while the settings pane is open
            MouseArea {
                id: settingsHover
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 260
                height: 180
                hoverEnabled: true
                readonly property bool revealed: containsMouse || win.pane === "settings"

                Rectangle {
                    id: cornerBtn
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 32
                    width: 56
                    height: 56
                    radius: 28
                    antialiasing: true
                    color: Qt.alpha(root.accent, cornerBtnArea.containsMouse ? 0.2 : 0.11)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.33)
                    opacity: settingsHover.revealed ? 1 : 0
                    scale: settingsHover.revealed ? 1 : 0.5
                    Behavior on opacity {
                        NumberAnimation { duration: win.had(160); easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: win.had(260); easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.ti.settings
                        color: root.fg
                        font { family: root.iconFont; pixelSize: root.fs(22) }
                    }
                    MouseArea {
                        id: cornerBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: win.toggleSettings()
                    }
                }
            }

        }

        function cycleIconTheme(dir: int) {
            const list = [""].concat(root.iconThemes);
            let i = list.indexOf(cfg.iconTheme);
            if (i < 0)
                i = 0;
            cfg.iconTheme = list[((i + dir) % list.length + list.length) % list.length];
        }

        function settingValue(key: string): string {
            switch (key) {
            case "clipsMax": return "" + cfg.clipsMax;
            case "animStyle": return cfg.animStyle;
            case "fontScale": return Math.round(cfg.fontScale * 100) + "%";
            case "dimOpacity": return Math.round(cfg.dimOpacity * 100) + "%";
            case "launchAnimation": return cfg.launchAnimation;
            case "bgBlur": return cfg.bgBlur ? "on" : "off";
            case "hiddenMenuAnimations": return cfg.hiddenMenuAnimations ? "on" : "off";
            case "fontFamily": return cfg.fontFamily || "system default";
            case "iconTheme": return cfg.iconTheme || "system default";
            case "volWidth": return cfg.volWidth + " px";
            case "volAnim": return cfg.volAnim;
            case "volStyle": return cfg.volStyle === "sine" ? "sine wave" : cfg.volStyle;
            case "volPercent": return cfg.volShowPercent ? "on" : "off";
            case "volTimeout": return (cfg.volTimeout / 1000).toFixed(0) + " s";
            case "notifTimeout": return (cfg.notifTimeout / 1000).toFixed(0) + " s";
            case "replayCount": return "" + cfg.replayCount;
            case "notifStyle": return cfg.notifStyle;
            case "notifAnim": return cfg.notifAnim;
            case "wallpaperStyle": return cfg.wallpaperStyle === "windows-flat" ? "windows no parallax" : cfg.wallpaperStyle;
            }
            return "";
        }
        readonly property var launchAnimChoices: ["grow-center", "grow-top-left", "grow-top-right", "grow-bottom-left", "grow-bottom-right", "fade", "none"]
        function cycleChoice(cur: string, list, dir: int): string {
            let i = list.indexOf(cur);
            if (i < 0)
                i = 0;
            return list[((i + dir) % list.length + list.length) % list.length];
        }
        function adjustSetting(key: string, dir: int) {
            switch (key) {
            case "clipsMax":
                cfg.clipsMax = Math.max(20, Math.min(200, cfg.clipsMax + dir * 20));
                clipScan.running = false;
                clipScan.running = true;
                break;
            case "animStyle": {
                const styles = ["wave", "pop", "fade", "slide", "none"];
                let i = styles.indexOf(cfg.animStyle);
                if (i < 0)
                    i = 0;
                cfg.animStyle = styles[((i + dir) % styles.length + styles.length) % styles.length];
                break;
            }
            case "fontScale":
                cfg.fontScale = Math.max(0.7, Math.min(1.6, Math.round((cfg.fontScale + dir * 0.1) * 100) / 100));
                break;
            case "dimOpacity":
                cfg.dimOpacity = Math.max(0, Math.min(1, Math.round((cfg.dimOpacity + dir * 0.05) * 100) / 100));
                break;
            case "launchAnimation": {
                let i = launchAnimChoices.indexOf(cfg.launchAnimation);
                if (i < 0)
                    i = 0;
                cfg.launchAnimation = launchAnimChoices[((i + dir) % launchAnimChoices.length + launchAnimChoices.length) % launchAnimChoices.length];
                break;
            }
            case "bgBlur":
                cfg.bgBlur = !cfg.bgBlur;
                break;
            case "hiddenMenuAnimations":
                cfg.hiddenMenuAnimations = !cfg.hiddenMenuAnimations;
                break;
            case "fontFamily": {
                const list = [""].concat(root.fontFamilies);
                let i = list.indexOf(cfg.fontFamily);
                if (i < 0)
                    i = 0;
                cfg.fontFamily = list[((i + dir) % list.length + list.length) % list.length];
                break;
            }
            case "iconTheme":
                cycleIconTheme(dir);
                break;
            case "volWidth":
                cfg.volWidth = Math.max(240, Math.min(560, cfg.volWidth + dir * 20));
                break;
            case "volAnim":
                cfg.volAnim = cycleChoice(cfg.volAnim, ["slide", "fade", "pop", "none"], dir);
                break;
            case "volStyle":
                cfg.volStyle = cycleChoice(cfg.volStyle, ["pill", "sine"], dir);
                break;
            case "volPercent":
                cfg.volShowPercent = !cfg.volShowPercent;
                break;
            case "volTimeout":
                cfg.volTimeout = Math.max(1000, Math.min(10000, cfg.volTimeout + dir * 1000));
                break;
            case "notifTimeout":
                cfg.notifTimeout = Math.max(1000, Math.min(15000, cfg.notifTimeout + dir * 1000));
                break;
            case "replayCount":
                cfg.replayCount = Math.max(1, Math.min(5, cfg.replayCount + dir));
                break;
            case "notifStyle":
                cfg.notifStyle = cycleChoice(cfg.notifStyle, ["bubble", "pill"], dir);
                break;
            case "notifAnim":
                cfg.notifAnim = cycleChoice(cfg.notifAnim, ["pop", "none"], dir);
                break;
            case "wallpaperStyle":
                cfg.wallpaperStyle = cycleChoice(cfg.wallpaperStyle, ["tiles", "windows", "windows-flat"], dir);
                break;
            }
            root.saveSettings();
        }

        function toggleFlyout(f: string) {
            const fly = Object.assign({ volume: true, notifs: true }, cfg.flyouts);
            fly[f] = fly[f] === false;
            cfg.flyouts = fly;
            root.saveSettings();
        }

        function toggleAlert(a: string) {
            const al = Object.assign({ errors: true, system: true, battery: true }, cfg.pibbleAlerts);
            al[a] = al[a] === false;
            cfg.pibbleAlerts = al;
            root.saveSettings();
        }

        function toggleGesture(g: string) {
            const ges = Object.assign({ power: true, panes: true }, cfg.gestures);
            ges[g] = ges[g] === false;
            cfg.gestures = ges;
            root.saveSettings();
        }

        function togglePage(p: string) {
            const pages = Object.assign({ clock: true, apps: true, walls: true, clips: true }, cfg.pages);
            // keep at least one page enabled overall (built-in or custom)
            if (pages[p] !== false && activePanes.length <= 1)
                return;
            pages[p] = pages[p] === false;
            cfg.pages = pages;
            root.saveSettings();
            if (!activePanes.includes(pane) && pane !== "settings")
                setPane(homePane());
        }

        function resetSetting(key: string) {
            switch (key) {
            case "pages":
                // uploaded pages aren't touched — only their order resets,
                // which drops them to the end and the add row back to the
                // top (see win.fullPageOrder)
                cfg.pages = ({ clock: true, apps: true, walls: true, clips: true });
                cfg.pageOrder = ["clock", "apps", "walls", "clips"];
                break;
            case "clock":
                cfg.clockShow = ({ date: true, battery: true, weather: true });
                break;
            case "appsGrid": cfg.appsCols = 4; cfg.appsRows = 3; break;
            case "wallsGrid": cfg.wallsCols = 3; cfg.wallsRows = 3; cfg.wallsVisible = 7; break;
            case "clipsGrid": cfg.clipsCols = 4; cfg.clipsRows = 4; break;
            case "clipsMax":
                cfg.clipsMax = 100;
                clipScan.running = false;
                clipScan.running = true;
                break;
            case "animStyle": cfg.animStyle = "wave"; break;
            case "fontScale": cfg.fontScale = 1.0; break;
            case "dimOpacity": cfg.dimOpacity = 0.4; break;
            case "launchAnimation": cfg.launchAnimation = "grow-top-left"; break;
            case "bgBlur": cfg.bgBlur = true; break;
            case "hiddenMenuAnimations": cfg.hiddenMenuAnimations = true; break;
            case "gestures": cfg.gestures = ({ power: true, panes: true }); break;
            case "fontFamily": cfg.fontFamily = ""; break;
            case "iconTheme": cfg.iconTheme = ""; break;
            case "theme": cfg.theme = "matugen"; break;
            case "customColors":
                // the retired Mono preset's palette
                cfg.customAccent = "#cfcfcf";
                cfg.customFg = "#f0f0f0";
                cfg.customMuted = "#8a8a8a";
                break;
            case "wallpaperDir":
                cfg.wallpaperDir = "~/Pictures/wallpapers";
                root.rescanWallpapers();
                break;
            case "wallCommand": cfg.wallCommand = root.defaultWallCommand; break;
            case "volWidth": cfg.volWidth = 420; break;
            case "flyouts": cfg.flyouts = ({ volume: true, notifs: true }); break;
            case "pibbleAlerts": cfg.pibbleAlerts = ({ errors: true, system: true, battery: true }); break;
            case "volAnim": cfg.volAnim = "pop"; break;
            case "volStyle": cfg.volStyle = "sine"; break;
            case "volPercent": cfg.volShowPercent = true; break;
            case "volTimeout": cfg.volTimeout = 2000; break;
            case "notifTimeout": cfg.notifTimeout = 5000; break;
            case "replayCount": cfg.replayCount = 1; break;
            case "notifStyle": cfg.notifStyle = "bubble"; break;
            case "notifAnim": cfg.notifAnim = "pop"; break;
            case "wallpaperStyle": cfg.wallpaperStyle = "tiles"; break;
            default:
                if (key.startsWith("bind:")) {
                    const a = key.slice(5);
                    setBind(a, bindDefaults[a] ?? "");
                    return; // setBind saves
                }
            }
            root.saveSettings();
        }

        // Hidden input that captures all typing, mirroring the design's off-screen <input>
        TextInput {
            id: input
            width: 1
            height: 1
            opacity: 0
            focus: true

            // typing from the clock jumps straight into the app search
            onTextChanged: {
                if (text.length > 0 && win.pane === "clock" && win.activePanes.includes("apps"))
                    win.pane = "apps";
                if (win.pane === "walls" && cfg.wallpaperStyle !== "tiles")
                    win.jumpWallCarousel();
            }

            Keys.onPressed: event => {
                // keybind capture (settings): record which keys are down and
                // the latest chord name they spell, but don't save yet — the
                // bind only commits once every held key is released, so a
                // chord like Ctrl+S can be pressed as a whole instead of
                // firing the instant Ctrl (or S) lands.
                if (win.capturingBind) {
                    event.accepted = true;
                    if (event.isAutoRepeat)
                        return;
                    if (!win.captureHeldKeys.includes(event.key))
                        win.captureHeldKeys = win.captureHeldKeys.concat([event.key]);
                    // always take the newest key event: pressing a different
                    // key switches to it outright (A then Ctrl shows "Ctrl",
                    // not "A"), and a bare modifier can still be extended by
                    // whatever's pressed next into a real chord ("Ctrl" then
                    // "S" becomes "Ctrl+S"). A stray unrecognized key leaves
                    // the display as-is rather than blanking it.
                    const ks = win.keyName(event);
                    win.captureLive = ks || win.modifierLabel(event.key) || win.captureLive;
                    return;
                }
                const ks = win.keyName(event);
                const kb = cfg.keybinds;
                // armed power prompt: Enter powers off, anything else lets go
                if (win.powerArmed) {
                    event.accepted = true;
                    // a bare modifier press is not a decision either way
                    if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta].includes(event.key))
                        return;
                    // compare the unmodified key: Ctrl still held from the
                    // Ctrl+P arm must not turn the confirm into "Ctrl+Return"
                    const bare = ks.replace(/^(?:Ctrl\+|Alt\+|Shift\+)+/, "");
                    if (bare === (kb.launch ?? "Return"))
                        win.powerOff();
                    else
                        win.disarmPower();
                    return;
                }
                // armed reboot prompt: same confirm/cancel dance as power
                if (win.rebootArmed) {
                    event.accepted = true;
                    if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta].includes(event.key))
                        return;
                    const bare = ks.replace(/^(?:Ctrl\+|Alt\+|Shift\+)+/, "");
                    if (bare === (kb.launch ?? "Return"))
                        win.rebootNow();
                    else
                        win.disarmReboot();
                    return;
                }
                if (ks === (kb.exit ?? "Escape")) {
                    // layered: expanded clip -> settings -> whole app
                    if (win.expandedClip)
                        win.collapseClip();
                    else if (win.pane === "settings")
                        win.setPane(win.paneBeforeSettings);
                    else
                        win.exit();
                    event.accepted = true;
                } else if (ks === (kb.settings ?? "Ctrl+S")) {
                    win.toggleSettings();
                    event.accepted = true;
                } else if (ks === (kb.power ?? "Ctrl+P")) {
                    win.playPower();
                    event.accepted = true;
                } else if (ks === (kb.reboot ?? "Ctrl+R")) {
                    win.playReboot();
                    event.accepted = true;
                } else if (ks === (kb.reverseCycle ?? "Shift+Tab")) {
                    win.cyclePane(-1);
                    event.accepted = true;
                } else if (ks === (kb.cycle ?? "Tab")) {
                    win.cyclePane(1);
                    event.accepted = true;
                } else if (ks === (kb.launch ?? "Return")) {
                    win.activate();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    win.navigate(1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    win.navigate(-1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    win.navigate(0, 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    win.navigate(0, -1);
                    event.accepted = true;
                }
            }

            Keys.onReleased: event => {
                // keybind capture: commit the last chord seen while keys
                // were down, but only once every key of it has come back up
                // — releasing the modifier first (or the main key first)
                // both land here, so either release order works.
                if (win.capturingBind) {
                    event.accepted = true;
                    if (event.isAutoRepeat)
                        return;
                    win.captureHeldKeys = win.captureHeldKeys.filter(k => k !== event.key);
                    if (win.captureHeldKeys.length === 0) {
                        // a bare modifier alone (nothing ever extended it
                        // into a real chord) isn't saveable
                        if (win.captureLive && !win.bareModifierLabels.includes(win.captureLive))
                            win.setBind(win.capturingBind, win.captureLive);
                        win.cancelCapture();
                    }
                }
            }
        }

        // Start the reveal only after the mapped window has actually rendered
        // a couple of frames. Animations are wall-clock based, so starting at
        // map time means first-frame latency eats the start of the animation
        // and the hole pops in already partly grown.
        property bool revealStarted: false
        // While warming, the drawer / wallpaper pane / image preloaders are
        // rendered at near-zero opacity so their scene graph nodes and
        // textures are built up front instead of stuttering the first open.
        // Apps warm before the reveal (typing can happen immediately); the
        // heavier wallpaper thumbnails warm after the reveal finishes.
        property bool warmingApps: false
        property bool warmingWalls: false
        property bool warmedOnce: false
        property bool wallsWarmedOnce: false
        FrameAnimation {
            id: firstFrames
            onTriggered: {
                // caches survive between opens; warm only the first time
                if (win.warmedOnce) {
                    fadeIn.restart();
                    stop();
                    return;
                }
                if (currentFrame === 1) {
                    win.warmingApps = true;
                } else if (currentFrame >= 3) {
                    win.warmingApps = false;
                    win.warmedOnce = true;
                    fadeIn.restart();
                    stop();
                }
            }
        }
        // Spread the wallpaper warm-up over one thumbnail per frame: doing
        // all uploads in a single frame caused a ~110ms hitch right as the
        // reveal ended, mid-spring when the user had typed early.
        property int wallWarmTick: 0
        FrameAnimation {
            running: win.warmingWalls
            onTriggered: {
                win.wallWarmTick = currentFrame;
                // thumbnails first (one per frame), then the pane's cells
                // (one per frame — each ClippingRectangle is an offscreen
                // render target and costs a chunk of frame time to create)
                if (currentFrame > root.wallpapers.length + win.wallPageSize + 4)
                    win.warmingWalls = false;
            }
        }

        // ---------- tile entry animation styles ----------
        // wave: staggered spring cascade (default). pop: all tiles spring at
        // once. fade: soft staggered fade. slide: rows slide up. none: instant.
        readonly property string animStyle: cfg.animStyle
        readonly property real animFromScale: animStyle === "wave" || animStyle === "pop" ? 0.4 : 1
        readonly property int animFromY: animStyle === "slide" ? 46 : animStyle === "fade" ? 6 : animStyle === "none" ? 0 : 14
        readonly property int animDur: animStyle === "fade" ? 220 : animStyle === "slide" ? 320 : animStyle === "none" ? 0 : 400
        readonly property int animFadeDur: animStyle === "none" ? 0 : 180
        readonly property int animEase: animStyle === "wave" || animStyle === "pop" ? Easing.OutBack : Easing.OutCubic
        // Exit mirrors entrance: tiles spring back out toward the same
        // from-state (animFromScale/animFromY) they sprang in from, so
        // "wave"/"pop" (bounce) read as the reverse of their entrance
        // instead of all sharing one bounce-then-shrink shape.
        readonly property bool animOutBounce: animStyle === "wave" || animStyle === "pop"
        readonly property int animOutSettleDur: animStyle === "fade" ? 180 : animStyle === "slide" ? 260 : 320
        readonly property int animOutEase: animOutBounce ? Easing.InQuad : Easing.InCubic
        // "none" (tile animation) zeroes tile/pane-entrance durations only —
        // the launch reveal has its own independent "none" (see lad below),
        // so picking one doesn't silently also flatten the other.
        function ad(ms: int): int {
            return animStyle === "none" ? 0 : ms;
        }
        // Launch-animation duration helper: zeroed only by launchAnimation
        // === "none", never by the tile animation setting above.
        function lad(ms: int): int {
            return win.noneMode ? 0 : ms;
        }
        // Hidden-menu-animation duration helper: zeroed only by
        // cfg.hiddenMenuAnimations, never by the tile animation setting —
        // the settings pane and power/reboot prompts aren't grids.
        function had(ms: int): int {
            return cfg.hiddenMenuAnimations ? ms : 0;
        }
        function animDelay(slot: int, cols: int): int {
            if (!staggering)
                return 0;
            switch (animStyle) {
            case "wave": return slot * 35;
            case "slide": return Math.floor(slot / cols) * 60;
            }
            return 0;
        }

        // Tile stagger applies when a pane opens, not on every keystroke —
        // re-staggering while filtering makes tiles blink out and pause.
        property bool staggering: false
        Timer {
            id: staggerTimer
            interval: 600
            onTriggered: win.staggering = false
        }
        function beginStagger() {
            staggering = true;
            staggerTimer.restart();
        }
        onPaneChanged: {
            if (pane !== "clock")
                beginStagger();
        }
        function startReveal() {
            if (revealStarted || !backingWindowVisible)
                return;
            revealStarted = true;
            // With the launch animation off there is no reveal to protect
            // from the warm-up frames: show everything on the very first
            // frame. (firstFrames still runs for cache warming; the
            // zero-duration fadeIn it triggers just re-sets these same
            // values.) Gated on noneMode, not the grid tile animStyle —
            // fadeIn's duration comes from win.lad()/noneMode, so checking
            // animStyle here let a "none" grid style with a real launch
            // animation snap reveal/opacity to 1 for a frame and then have
            // fadeIn yank them back to 0 to animate in, flickering.
            if (noneMode) {
                reveal = 1;
                content.opacity = 1;
            }
            firstFrames.reset();
            firstFrames.start();
        }
        onBackingWindowVisibleChanged: startReveal()

        // Pre-decode app icons and wallpaper thumbnails while idle, so the
        // drawer's first appearance doesn't stall on cold image loads. The
        // sources/sourceSizes match the visible tiles exactly for cache hits.
        Item {
            visible: win.warmingApps
            opacity: 0.004
            Repeater {
                model: root.warmOrderApps
                Image {
                    required property var modelData
                    width: 1
                    height: 1
                    asynchronous: true
                    sourceSize: Qt.size(88, 88)
                    source: root.iconUrl(modelData.icon)
                }
            }
        }
        // clipboard image thumbnails, decoded as the scan lands and pinned
        // so clip page flips hit the pixmap cache instead of re-decoding.
        // The thumbs are downscaled on disk at generation time (see
        // clipThumbs), so these decodes are cheap and no longer starve the
        // app-icon decodes sharing the single QML image reader thread.
        //
        // Safeguard: on the cold first open, hold the clip decodes until the
        // app icons have warmed (warmedOnce), then release them one per frame
        // (clipWarmTick) so a batch of thumbs still can't burst the reader
        // thread ahead of the icons. Once warmed, the gate stays open and
        // clips decode freely as their thumbs land — the icons are cached by
        // then, so there is nothing left to starve. clipWarmTick is not reset
        // per open for the same reason.
        property int clipWarmTick: 0
        FrameAnimation {
            running: win.warmedOnce && win.clipWarmTick <= root.clips.length
            onTriggered: win.clipWarmTick = currentFrame
        }
        Item {
            visible: false
            Repeater {
                model: root.clips
                Image {
                    required property int index
                    required property var modelData
                    width: 1
                    height: 1
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(480, 640)
                    source: win.warmedOnce && win.clipWarmTick > index
                            && modelData.image === true && modelData.thumb
                            ? "file://" + modelData.thumb : ""
                }
            }
        }
        Item {
            visible: win.warmingWalls
            opacity: 0.004
            Repeater {
                model: root.wallpapers
                Image {
                    required property int index
                    required property var modelData
                    width: 1
                    height: 1
                    visible: win.wallWarmTick > index
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(480, 270)
                    source: "file://" + modelData.thumb
                }
            }
        }

        Component.onCompleted: {
            input.forceActiveFocus();
            startReveal();
        }
    }

    // Warm the app-icon pixmap cache the moment the daemon starts, so the
    // very first launcher open renders icons immediately instead of briefly
    // showing the two-letter fallback while the SVGs decode (QML decodes
    // images on a single reader thread, so ~100 theme SVGs take a second or
    // two — pay that at session start, not at first open). A tiny transparent
    // overlay surface is enough to drive the image provider and populate the
    // process-global cache; it unloads once the cache is warm (the in-window
    // warm-up Item keeps every pixmap referenced after that, so the cache
    // never evicts them).
    property bool bootWarmIcons: true
    Timer { interval: 30000; running: true; onTriggered: root.bootWarmIcons = false }
    LazyLoader {
        active: root.bootWarmIcons
        PanelWindow {
            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "pibble-warmup"
            mask: Region {} // click-through, takes no input

            Item {
                anchors.fill: parent
                Repeater {
                    model: root.warmOrderApps
                    Image {
                        required property var modelData
                        width: 1
                        height: 1
                        asynchronous: true
                        sourceSize: Qt.size(88, 88)
                        source: root.iconUrl(modelData.icon)
                    }
                }
            }
        }
    }

    // ================= OSDs (persistent) =================
    // Both flyouts are persistent windows of fixed size; the cards animate
    // inside them. Cards are always fully opaque (root.flySurface, no
    // border), so unlike the launcher's reveal these windows request no
    // BackgroundEffect.blurRegion at all — there'd be nothing behind an
    // opaque card for it to show.

    // ---------- volume OSD: pill sliding up from the bottom edge ----------
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool sinkMuted: sink && sink.audio ? sink.audio.muted : false

    // ignore the initial property churn while pipewire connects
    property bool volReady: false
    Timer {
        interval: 2000
        running: true
        onTriggered: root.volReady = true
    }
    onVolChanged: if (volReady) volOsd.ping()
    onSinkMutedChanged: if (volReady) volOsd.ping()

    Scope {
        id: volOsd
        property bool show: false
        property bool leaving: false
        property bool entered: false
        function ping() {
            if (!root.flyoutOn("volume"))
                return;
            leaving = false;
            if (!show) {
                show = true;
                // entered flips a tick later so the first frame renders the
                // hidden pose and the entry actually animates
                entered = false;
                Qt.callLater(() => entered = true);
            }
            volHide.restart();
        }
        Timer {
            id: volHide
            interval: cfg.volTimeout
            onTriggered: volOsd.leaving = true
        }
        // Fallback unmap. Normally the window unmaps the instant the exit
        // animation reports the card gone (see volCard's watchers), which
        // avoids a lingering blurred remnant after the pill has left; this
        // just guarantees teardown if no frame reports it.
        Timer {
            interval: 500
            running: volOsd.leaving
            onTriggered: volOsd.finishHide()
        }
        function finishHide() {
            show = false;
            leaving = false;
        }

        // Always loaded, only mapped while showing: mapping a pre-built
        // window costs a frame or two, unlike the full rebuild a LazyLoader
        // pays, so rapid volume changes never lag. The card moves inside the
        // fixed window; layer margins never animate (margin changes need a
        // compositor round trip per step and stutter).
        PanelWindow {
            id: volWin
            readonly property string mode: cfg.volAnim
            readonly property bool eq: cfg.volStyle !== "pill"
            visible: volOsd.show || volOsd.leaving
            anchors.bottom: true
            implicitWidth: cfg.volWidth + 8
            implicitHeight: 280
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "pibble-volume"
            // the OSD never takes input
            mask: Region {}

            // ~90ms animation tick drives the equalizer bar motion, only
            // while the OSD is on screen (pill needs no tick)
            property int tick: 0
            Timer {
                interval: 90
                running: volWin.eq && (volOsd.show || volOsd.leaving)
                repeat: true
                onTriggered: volWin.tick++
            }
            readonly property bool pct: cfg.volShowPercent
            // Half-height (px) of one sine-wave bar (mirrored above/below the
            // centre). The volume factor dominates (the wobble is a narrow
            // band on top) and the amplitude spans most of the card, so a
            // volume change reads clearly as taller/shorter bars.
            function volBarHalf(i: int, n: int): int {
                const eff = root.sinkMuted ? 0 : root.vol * 100;
                if (eff <= 0)
                    return 2; // 4px floor
                // square-root response: steep below ~50% so quiet-range
                // volume steps read clearly, flattening toward full volume
                const v = Math.sqrt(Math.min(1, eff / 100));
                const wobble = 0.78 + 0.22 * Math.sin(tick * 0.35 + i * 0.85 + 2);
                return Math.round(Math.max(4, v * 84 * wobble) / 2);
            }

            Rectangle {
                id: volCard
                readonly property bool on: volOsd.show && !volOsd.leaving && volOsd.entered
                x: (parent.width - width) / 2
                width: cfg.volWidth
                // equalizer variants need a taller card than the pill
                height: volWin.eq ? 108 : 56
                radius: volWin.eq ? 18 : 28
                // rests 90px above the screen bottom; the slide exit drops it
                // past the window (= screen) bottom edge. Bounce is built in:
                // the exit overshoot lands off-screen, so only the entry
                // shows it.
                readonly property real restY: parent.height - height - 90
                y: volWin.mode === "slide" ? (on ? restY : parent.height) : restY
                Behavior on y {
                    NumberAnimation {
                        duration: volWin.mode === "slide" ? 340 : 0
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }
                // the sine bars render straight on the wallpaper; the pill
                // style keeps a card behind the level bar so it reads as a
                // pill rather than a bare line
                color: volWin.eq ? "transparent" : root.flySurface
                antialiasing: true
                opacity: volWin.mode === "slide" ? 1 : (on ? 1 : 0)
                scale: volWin.mode === "pop" ? (on ? 1 : 0.8) : 1
                // unmap the window the instant the card has left, so no
                // blurred remnant lingers between the anim ending and the
                // fallback timer (fixes the "small square" on non-slide exits)
                onOpacityChanged: if (volOsd.leaving && opacity <= 0.02) volOsd.finishHide()
                onYChanged: if (volOsd.leaving && volWin.mode === "slide" && y >= parent.height - 2) volOsd.finishHide()
                Behavior on opacity {
                    NumberAnimation { duration: volWin.mode === "none" ? 0 : 200; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: volWin.mode === "none" ? 0 : 240; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                }

                // optional numeric readout on the right edge; the bar/eq
                // content shifts left to make room. Fixed width so the layout
                // doesn't jitter as the digit count changes.
                Text {
                    id: volPct
                    visible: volWin.pct
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.flyFs(42)
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.vol * 100) + "%"
                    color: root.sinkMuted ? root.flyTh.muted : root.flyTh.fg
                    font { family: root.flyMono; pixelSize: root.flyFs(15); weight: Font.DemiBold }
                }
                readonly property real pctSpace: volWin.pct ? volPct.width + 16 : 0

                // "pill" style: a plain level bar
                Item {
                    visible: !volWin.eq
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: -volCard.pctSpace / 2
                    width: parent.width - 60 - volCard.pctSpace
                    height: 8

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: Qt.alpha(root.flyTh.accent, 0.15)
                    }
                    Rectangle {
                        width: parent.width * Math.min(1, root.vol)
                        height: parent.height
                        radius: 4
                        color: root.sinkMuted ? Qt.alpha(root.flyTh.muted, 0.8) : root.flyTh.accent
                        Behavior on width {
                            NumberAnimation { duration: 70; easing.type: Easing.OutCubic }
                        }
                    }
                }

                // sine-wave visualizer:
                // fixed-width bars (the design's 6px) mirrored above and below
                // a horizontal centre axis, following the flyout accent colour
                // (neutral when muted / 0). The card width sets how many bars
                // fit — resizing adds/removes bars at the design's ~26px pitch
                // instead of stretching them — and the row still spans edge to
                // edge like the pill's bar. No per-bar height Behaviors: the
                // ~90ms tick already paces the motion, and animating the bars
                // at 60fps kept the compositor re-blurring the backdrop every
                // frame, which showed up as input lag.
                Row {
                    id: eqRow
                    visible: volWin.eq
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: -volCard.pctSpace / 2
                    readonly property real avail: volCard.width - 48 - volCard.pctSpace
                    readonly property real barW: 6
                    // bar pitch (px between bar centres) is fixed: dense
                    // enough to read as a waveform at any card width
                    readonly property real pitch: 14
                    readonly property int nBars: Math.max(2, Math.floor((avail + pitch - barW) / pitch))
                    spacing: nBars > 1 ? (avail - barW * nBars) / (nBars - 1) : 0

                    Repeater {
                        model: eqRow.nBars
                        Item {
                            id: eqBar
                            required property int index
                            width: eqRow.barW
                            height: 60
                            readonly property real half: volWin.volBarHalf(index, eqRow.nBars)
                            readonly property color barColor: (root.sinkMuted || root.vol <= 0)
                                ? root.flyTh.muted : root.flyTh.accent

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.verticalCenter
                                width: eqRow.barW
                                radius: 3
                                height: eqBar.half
                                color: eqBar.barColor
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.verticalCenter
                                width: eqRow.barW
                                radius: 3
                                height: eqBar.half
                                color: eqBar.barColor
                                opacity: 0.55
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- notification flyouts ----------
    function flyFs(px: int): int {
        return Math.round(px * cfg.fontScale);
    }

    // Own org.freedesktop.Notifications only while the flyout is enabled;
    // unloading releases the name for another daemon to claim.
    LazyLoader {
        active: root.flyoutOn("notifs")

        NotificationServer {
            bodySupported: true
            imageSupported: true
            onNotification: n => {
                n.tracked = true;
                // notifications pibble replay fires itself must not become
                // replayable history, or replaying repeatedly would keep
                // pushing the same notification back to the front
                if (n.appName !== "REPLAY")
                    root.cacheNotification(n);
                flyNotifLoader.item?.accept(n);
            }
        }
    }

    // ---------- notification flyout (notifStyle "bubble" / "pill") ----------
    // One notification at a time. "bubble": an app-tinted circle pops in
    // below the top-right corner, pulses with an expanding ring, then a
    // compact card staggers its lines in to the left of it. "pill" is the
    // same card without the circle, tucked into the corner directly. Same-app arrivals replace the
    // visible card (it slides out and the new one fires next; if the card
    // hasn't appeared yet the content just swaps in place); other apps queue
    // and fire after the current one dismisses. The tint colour is the
    // dominant colour of the app icon (Canvas pixel average, cached per
    // icon), falling back to the flyout theme accent.
    LazyLoader {
        id: flyNotifLoader
        active: root.flyoutOn("notifs")

        PanelWindow {
            id: flyWin
            // hidden -> appear (circle pops in) -> pulse (overshoot + ring) ->
            // show (card staggers in, timeout runs) -> dismiss (lines stagger
            // out, card slides, circle shrinks) -> hidden
            property string phase: "hidden"
            // "pill" skips every bubble beat: no circle, no pulse phase, the
            // card claims the corner the circle vacated
            readonly property bool bubble: cfg.notifStyle !== "pill"
            property var current: null
            // snapshot of the notification's content: keeps the card intact
            // through the exit animation even if the sender closes the object
            property var view: ({ own: false, glyph: "", app: "", key: "", summary: "", body: "", image: "", icon: "", timeout: 0 })
            property var queue: []
            property int exitDir: 0
            // this dismissal keeps the bubble up until the card is gone
            property bool lingerOut: false
            // "simple" | "thumb" | "rich"; frozen when the card fires so a late
            // image probe can't reshape the visible card
            property string variant: "simple"
            property color nColor: root.notifTh.accent
            property var tintCache: ({})
            Behavior on nColor {
                ColorAnimation { duration: 220 }
            }

            visible: phase !== "hidden"
            anchors.top: true
            anchors.right: true
            // fixed size: everything animates inside (see the OSD architecture
            // note); sized for the widest card at max font scale plus ring bloom
            // and a fully expanded body
            implicitWidth: 720
            implicitHeight: 640
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "pibble-notifications"

            function accept(n) {
                // sender may retract a queued notification before it fires
                n.closed.connect(() => flyWin.unqueue(n));
                // fire straight away only when nothing is up AND nothing is
                // waiting (during the inter-notification gap the phase is hidden
                // but the queue must keep its order)
                if (phase === "hidden" && queue.length === 0) {
                    fire(n);
                    return;
                }
                // never hold two notifications of one app: replace in the queue
                for (let i = 0; i < queue.length; i++) {
                    if (appKey(queue[i]) === appKey(n)) {
                        const old = queue[i];
                        queue[i] = n;
                        old.expire();
                        return;
                    }
                }
                if (phase !== "hidden" && view.key === appKey(n)) {
                    if (phase === "appear" || phase === "pulse") {
                        // card isn't up yet: swap the content in place
                        const old = current;
                        snapshot(n);
                        if (old)
                            old.expire();
                        return;
                    }
                    // on screen: slide the current card out now, fire this next
                    queue.unshift(n);
                    if (phase === "show")
                        dismiss(0);
                    return; // already dismissing: it fires on finalize
                }
                if (queue.length >= 6)
                    queue.shift().expire();
                queue.push(n);
            }
            function unqueue(n) {
                const i = queue.indexOf(n);
                if (i >= 0)
                    queue.splice(i, 1);
            }
            // identity for replace-within-app: the name when given, else the
            // desktop-entry hint (Discord and friends send no appName)
            function appKey(n): string {
                return String(n.appName ?? "") || String(n.desktopEntry ?? "");
            }
            function snapshot(n) {
                current = n;
                view = root.deriveNotifView(n);
                imgProbe.source = view.image;
                // errors and low battery always read as red, regardless of
                // theme/tint, so severity is visible at a glance
                if (view.glyph === root.ti.alertTriangle || view.glyph === root.ti.batteryLow) {
                    nColor = "#e0524f";
                    return;
                }
                // "default" theme tints from the app icon (else the media
                // image); pinned themes use their accent everywhere
                const src = (root.notifIconTint && !view.own) ? (view.icon || view.image) : "";
                if (!src)
                    nColor = root.notifTh.accent;
                else if (tintCache[src] !== undefined)
                    nColor = tintCache[src];
                else {
                    nColor = root.notifTh.accent;
                    tint.src = src; // updates nColor when extracted
                }
            }
            function fire(n) {
                snapshot(n);
                exitDir = 0;
                phase = "appear";
                phaseTimer.restart();
            }
            // dir: swipe direction (-1 rubber-bands back before the drift),
            // 0 for timeout/bubble click/sender-close; all exit drifting right
            function dismiss(dir: int) {
                if (phase === "hidden" || phase === "dismiss")
                    return;
                exitDir = dir;
                phase = "dismiss";
                phaseTimer.restart();
            }
            function finalize() {
                const c = current;
                current = null;
                if (c)
                    c.expire();
                phase = "hidden";
                if (queue.length > 0)
                    gapTimer.restart();
            }
            function computeVariant(): string {
                if (!view.image)
                    return "simple";
                // wide images (16:10 and up: screenshots, photos) read best as a
                // full strip; squarer ones (avatars, album art) as a thumbnail
                if (imgProbe.status === Image.Ready && imgProbe.implicitHeight > 0
                    && imgProbe.implicitWidth / imgProbe.implicitHeight >= 1.6)
                    return "rich";
                return "thumb";
            }

            onPhaseChanged: {
                iconIn.stop();
                iconPop.stop();
                iconSettle.stop();
                iconOut.stop();
                iconOutDelay.stop();
                stagInAnim.stop();
                stagOutAnim.stop();
                wipeAnim.stop();
                switch (phase) {
                case "appear":
                    ringAnim.stop();
                    // pill: no circle to choreograph
                    // entry pose, applied instantly (inst gates the Behaviors)
                    fcard.inst = true;
                    fcard.stagIn = 0;
                    fcard.stagOut = 0;
                    fcard.imgWipe = 0;
                    fcard.cardO = 0;
                    fcard.cardYS = 0.92;
                    fcard.swipeX = 0;
                    fcard.expanded = false;
                    fcard.inst = false;
                    ring.scale = 1;
                    ring.opacity = 0;
                    if (flyWin.bubble)
                        iconIn.restart();
                    break;
                case "pulse":
                    iconPop.restart();
                    ringAnim.restart();
                    break;
                case "show":
                    variant = computeVariant();
                    if (flyWin.bubble)
                        iconSettle.restart();
                    fcard.cardO = 1;
                    fcard.cardYS = 1;
                    stagInAnim.restart();
                    wipeAnim.restart();
                    break;
                case "dismiss":
                    stagOutAnim.restart();
                    // hold the bubble until the card has fully left
                    flyWin.lingerOut = flyWin.bubble && fcard.cardO > 0;
                    if (flyWin.bubble) {
                        if (flyWin.lingerOut)
                            iconOutDelay.restart();
                        else
                            iconOut.restart();
                    }
                    // every dismissal fades with a gentle rightward drift; a
                    // left swipe rubber-bands back through rest to reach it
                    if (fcard.cardO > 0)
                        fcard.swipeX = (exitDir < 0 ? 0 : fcard.swipeX) + 18;
                    fcard.cardO = 0;
                    break;
                }
            }

            Timer {
                id: phaseTimer
                interval: cfg.notifAnim === "none" ? 0
                    : flyWin.phase === "appear" ? (flyWin.bubble ? 430 : 60)
                    : flyWin.phase === "pulse" ? 210
                    : flyWin.lingerOut ? 640 : 340
                onTriggered: {
                    switch (flyWin.phase) {
                    case "appear":
                        if (flyWin.bubble) {
                            flyWin.phase = "pulse";
                            phaseTimer.restart();
                        } else {
                            flyWin.phase = "show"; // showTimer takes over
                        }
                        break;
                    case "pulse":
                        flyWin.phase = "show"; // showTimer takes over
                        break;
                    case "dismiss":
                        flyWin.finalize();
                        break;
                    }
                }
            }
            Timer {
                id: showTimer
                // a sender timeout of exactly 0 means "never expire" (spec): the
                // notification stays until clicked or swiped away
                interval: flyWin.view.timeout > 0 ? flyWin.view.timeout : cfg.notifTimeout
                running: flyWin.phase === "show" && !cardHover.hovered && flyWin.view.timeout !== 0
                onTriggered: flyWin.dismiss(0)
            }
            Timer {
                // small beat between one notification leaving and the next firing
                id: gapTimer
                interval: 160
                onTriggered: {
                    if (flyWin.queue.length > 0 && flyWin.phase === "hidden")
                        flyWin.fire(flyWin.queue.shift());
                }
            }
            // sender closed the on-screen notification — animate out
            Connections {
                target: flyWin.current
                ignoreUnknownSignals: true
                function onClosed() {
                    flyWin.current = null;
                    flyWin.dismiss(0);
                }
            }

            // aspect-ratio probe for the notification image; the icon-circle
            // phases (~630ms) cover the async load before the card needs it
            Image {
                id: imgProbe
                visible: false
                asynchronous: true
                // ratio-only probe: cap one dimension (ratio is preserved
                // when only one is set) so a 4K screenshot isn't decoded at
                // native size just to read its aspect
                sourceSize.width: 160
                // a big image can outlast the icon phases; when the probe lands
                // while the card is up, re-classify once so a wide screenshot
                // isn't stuck cropped into the thumbnail circle
                onStatusChanged: {
                    if (status === Image.Ready && flyWin.phase === "show")
                        flyWin.variant = flyWin.computeVariant();
                }
            }
            // dominant-colour extraction: the icon is decoded at 26x26 (fast,
            // off the GUI thread regardless of the source's native size),
            // grabbed to a real file, then drawn into the canvas and
            // averaged, weighted by saturation and alpha, skipping
            // near-white/black pixels; the result is normalised into a band
            // that reads on the dark card.
            // Canvas.drawImage() can't sample a live Image item's texture
            // directly (reads back all-zero pixels even once Ready), and
            // Canvas.loadImage() never resolves the "itemgrabber:" URL that
            // Item.grabToImage() hands back (onImageLoaded never fires for
            // it) — but a real file:// path loads and draws fine, so the
            // grab is saved to disk and reloaded from there. Grabbing the
            // already 26x26-decoded item keeps this cheap even when a
            // full-size screenshot arrives as notification media (loading
            // it at native resolution via Canvas.loadImage directly stalled
            // the whole shell).
            Image {
                id: tintSrc
                x: -60
                y: 0
                width: 26
                height: 26
                asynchronous: true
                sourceSize: Qt.size(26, 26)
                source: tint.src
                onStatusChanged: {
                    if (status === Image.Ready) {
                        tintSrc.grabToImage(result => {
                            if (result.saveToFile(root.tintGrabPath)) {
                                tint.grabUrl = "file://" + root.tintGrabPath;
                                tint.loadImage(tint.grabUrl);
                            }
                        });
                    }
                }
            }
            Canvas {
                id: tint
                property string src: ""
                property string grabUrl: ""
                x: -60
                y: 0
                width: 26
                height: 26
                renderStrategy: Canvas.Immediate
                renderTarget: Canvas.Image
                onImageLoaded: {
                    if (grabUrl && isImageLoaded(grabUrl))
                        requestPaint();
                }
                onPaint: {
                    if (!src || !grabUrl || !isImageLoaded(grabUrl))
                        return;
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.drawImage(grabUrl, 0, 0, width, height);
                    const d = ctx.getImageData(0, 0, width, height).data;
                    let r = 0, g = 0, b = 0, w = 0;
                    for (let i = 0; i < d.length; i += 4) {
                        const a = d[i + 3] / 255;
                        if (a < 0.4)
                            continue;
                        const mx = Math.max(d[i], d[i + 1], d[i + 2]);
                        const mn = Math.min(d[i], d[i + 1], d[i + 2]);
                        const lum = (mx + mn) / 510;
                        if (lum > 0.95 || lum < 0.06)
                            continue;
                        const sat = mx > 0 ? (mx - mn) / mx : 0;
                        const wt = a * (0.1 + sat * sat);
                        r += d[i] * wt;
                        g += d[i + 1] * wt;
                        b += d[i + 2] * wt;
                        w += wt;
                    }
                    let c = root.notifTh.accent;
                    if (w > 3) {
                        c = Qt.rgba(r / w / 255, g / w / 255, b / w / 255, 1);
                        // pull into a visible band; leave true greys grey
                        c = (c.hslHue < 0 || c.hslSaturation < 0.12)
                            ? Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, Math.min(0.75, Math.max(0.5, c.hslLightness)), 1)
                            : Qt.hsla(c.hslHue, Math.max(c.hslSaturation, 0.5), Math.min(0.68, Math.max(0.45, c.hslLightness)), 1);
                    }
                    flyWin.tintCache[src] = c;
                    if (src === flyWin.view.icon || src === flyWin.view.image)
                        flyWin.nColor = c;
                    unloadImage(grabUrl);
                    grabUrl = "";
                    src = ""; // also clears tintSrc.source
                }
            }

            // input only over the card and bubble while they are interactive
            mask: Region {
                x: fcard.x
                y: fcard.y
                width: flyWin.phase === "show" ? fcard.width : 0
                height: fcard.height
                regions: [
                    Region {
                        x: fIcon.x
                        y: fIcon.y
                        width: flyWin.bubble && flyWin.phase === "show" ? fIcon.width : 0
                        height: fIcon.height
                    }
                ]
            }
            // ── icon circle ──
            Item {
                id: fIcon
                visible: flyWin.bubble
                x: flyWin.width - width - 26
                y: 24
                width: 52
                height: 52
                scale: 0
                opacity: 0
                // grow-on-hover rides a transform so the phase animations own
                // `scale`; independent of the card's (separate handlers)
                readonly property bool hov: bubbleHover.hovered && flyWin.phase === "show"
                property real hoverS: hov ? 1.08 : 1
                Behavior on hoverS {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                transform: Scale {
                    origin.x: fIcon.width / 2
                    origin.y: fIcon.height / 2
                    xScale: fIcon.hoverS
                    yScale: fIcon.hoverS
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(flyWin.nColor, 1.18) }
                        GradientStop { position: 1; color: Qt.darker(flyWin.nColor, 1.22) }
                    }

                }
                Rectangle {
                    id: ring
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: "transparent"
                    border.width: 2
                    border.color: flyWin.nColor
                    opacity: 0
                }
                Image {
                    id: circleIcon
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    sourceSize: Qt.size(56, 56)
                    asynchronous: true
                    source: flyWin.view.own ? "" : flyWin.view.icon
                    visible: String(source) !== ""
                }
                // no app icon (own or not — e.g. niri's screenshot
                // notification carries only an image, no icon): fall back
                // to the icon font's glyph (root.ti.bell by default, see
                // notifGlyph) instead of a fixed drawing
                readonly property color inkC: "#f2f0ee"
                Text {
                    anchors.centerIn: parent
                    visible: !circleIcon.visible
                    text: flyWin.view.glyph
                    color: fIcon.inkC
                    font { family: root.iconFont; pixelSize: root.flyFs(24) }
                }
                HoverHandler {
                    id: bubbleHover
                }
                // clicking the bubble dismisses the notification
                MouseArea {
                    anchors.fill: parent
                    enabled: flyWin.phase === "show"
                    onClicked: flyWin.dismiss(0)
                }
            }

            // icon keyframes ported from the reference CSS; all durations
            // collapse to 0 when notifAnim is "none" so the bubble/card land
            // on their final pose instantly instead of animating in/out
            readonly property bool noAnim: cfg.notifAnim === "none"
            SequentialAnimation {
                id: iconIn
                ParallelAnimation {
                    NumberAnimation { target: fIcon; property: "opacity"; to: 1; duration: flyWin.noAnim ? 0 : 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: fIcon; property: "scale"; to: 1.18; duration: flyWin.noAnim ? 0 : 300; easing.type: Easing.OutCubic }
                }
                NumberAnimation { target: fIcon; property: "scale"; to: 0.95; duration: flyWin.noAnim ? 0 : 100; easing.type: Easing.InOutQuad }
                NumberAnimation { target: fIcon; property: "scale"; to: 1; duration: flyWin.noAnim ? 0 : 100; easing.type: Easing.InOutQuad }
            }
            SequentialAnimation {
                id: iconPop
                NumberAnimation { target: fIcon; property: "scale"; to: 1.32; duration: flyWin.noAnim ? 0 : 170; easing.type: Easing.OutCubic }
                NumberAnimation { target: fIcon; property: "scale"; to: 1.1; duration: flyWin.noAnim ? 0 : 120; easing.type: Easing.InOutQuad }
                NumberAnimation { target: fIcon; property: "scale"; to: 1.18; duration: flyWin.noAnim ? 0 : 95; easing.type: Easing.InOutQuad }
                NumberAnimation { target: fIcon; property: "scale"; to: 1.1; duration: flyWin.noAnim ? 0 : 95; easing.type: Easing.InOutQuad }
            }
            NumberAnimation {
                id: iconSettle
                target: fIcon
                property: "scale"
                to: 1.1
                duration: flyWin.noAnim ? 0 : 300
                easing.type: Easing.InOutQuad
            }
            ParallelAnimation {
                id: iconOut
                NumberAnimation { target: fIcon; property: "scale"; to: 0; duration: flyWin.noAnim ? 0 : 260; easing.type: Easing.InBack }
                NumberAnimation { target: fIcon; property: "opacity"; to: 0; duration: flyWin.noAnim ? 0 : 260; easing.type: Easing.InCubic }
            }
            Timer {
                // bubble hold on dismiss: fires the icon exit once the card's
                // slide/fade (~300ms) has finished
                id: iconOutDelay
                interval: flyWin.noAnim ? 0 : 300
                onTriggered: iconOut.restart()
            }
            ParallelAnimation {
                id: ringAnim
                NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.4; duration: flyWin.noAnim ? 0 : 600; easing.type: Easing.OutCubic }
                NumberAnimation { target: ring; property: "opacity"; from: 0.65; to: 0; duration: flyWin.noAnim ? 0 : 600; easing.type: Easing.OutCubic }
            }
            // shared clocks for the per-line staggers (ms timelines; each line
            // derives its own eased window from them in lp/lq below)
            NumberAnimation { id: stagInAnim; target: fcard; property: "stagIn"; from: 0; to: 650; duration: flyWin.noAnim ? 0 : 650 }
            NumberAnimation { id: stagOutAnim; target: fcard; property: "stagOut"; from: 0; to: 300; duration: flyWin.noAnim ? 0 : 300 }
            SequentialAnimation {
                id: wipeAnim
                PauseAnimation { duration: flyWin.noAnim ? 0 : 100 }
                NumberAnimation { target: fcard; property: "imgWipe"; from: 0; to: 1; duration: flyWin.noAnim ? 0 : 500; easing.type: Easing.OutQuint }
            }

            // ── card ──
            Rectangle {
                id: fcard
                property real stagIn: 0
                property real stagOut: 0
                property real imgWipe: 0
                property real cardO: 0
                property real cardYS: 0.92
                property real swipeX: 0
                property real grabX: 0
                property bool dragging: false
                property bool inst: false
                // click-to-expand for a body longer than the collapsed clip
                property bool expanded: false
                // whether a tap can reveal more (drives the chevron + ellipses)
                readonly property bool expandable: bodyClip.truncated || subWrap.truncated

                // per-line enter/exit progress: 380ms windows offset 90ms apart
                // in (quint-out), 180ms offset 40ms apart out (quad-in)
                function lp(i: int): real {
                    const p = Math.max(0, Math.min(1, (stagIn - i * 90) / 380));
                    return 1 - Math.pow(1 - p, 4);
                }
                function lq(i: int): real {
                    const q = Math.max(0, Math.min(1, (stagOut - i * 40) / 180));
                    return q * q;
                }
                function lineO(i: int): real {
                    return lp(i) * (1 - lq(i));
                }
                function lineY(i: int): real {
                    return 10 * (1 - lp(i)) - 6 * lq(i);
                }

                readonly property bool rich: flyWin.variant === "rich"
                readonly property bool thumb: flyWin.variant === "thumb"
                readonly property int lBase: rich ? 1 : 0
                readonly property real stripH: rich ? root.flyFs(104) : 0
                // a short single-line body renders as a sub line; anything longer
                // becomes a divided body block (they are mutually exclusive)
                readonly property bool bodyAsSub: flyWin.view.body !== "" && flyWin.view.body.length <= 60
                    && flyWin.view.body.indexOf("\n") < 0

                // natural content width clamped to a compact range; rich is fixed
                readonly property real natW: 12 + (thumb ? 50 : 0) + 34 + Math.max(
                    appRow.implicitWidth,
                    headText.implicitWidth,
                    subWrap.visible ? subText.implicitWidth : 0,
                    bodyBlock.visible ? bodyText2.implicitWidth : 0)
                width: rich ? root.flyFs(336)
                    : Math.min(root.flyFs(344), Math.max(root.flyFs(210), Math.ceil(natW)))
                height: stripH + contentBox.height + 22
                radius: 16
                antialiasing: true
                color: root.flySurface
                visible: flyWin.phase === "show" || flyWin.phase === "dismiss"
                opacity: cardO
                // grow-on-hover, independent of the bubble's (separate handlers)
                readonly property bool hov: cardHover.hovered && flyWin.phase === "show"
                property real hoverS: hov ? 1.025 : 1
                Behavior on hoverS {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                transform: [
                    Scale {
                        origin.x: fcard.width / 2
                        origin.y: fcard.height / 2
                        yScale: fcard.cardYS
                    },
                    Scale {
                        // top-pinned: a center origin tracks the animated height
                        // during expand and creeps the card upward
                        origin.x: fcard.width / 2
                        origin.y: 0
                        xScale: fcard.hoverS
                        yScale: fcard.hoverS
                    }
                ]

                // bubble: the card hangs left of the circle, its top at the
                // circle's vertical centre. pill: no circle, so the card
                // tucks into the corner the circle would have occupied.
                readonly property real restX: flyWin.bubble
                    ? fIcon.x - 10 - width
                    : flyWin.width - width - 26
                x: restX + swipeX
                y: flyWin.bubble ? fIcon.y + fIcon.height / 2 : 24
                Behavior on swipeX {
                    enabled: !fcard.inst && !fcard.dragging
                    NumberAnimation {
                        duration: flyWin.noAnim ? 0 : 300
                        easing.type: flyWin.phase === "dismiss" ? Easing.OutCubic : Easing.OutBack
                        easing.overshoot: 1.15
                    }
                }
                Behavior on cardO {
                    enabled: !fcard.inst
                    NumberAnimation {
                        duration: flyWin.noAnim ? 0 : (flyWin.phase === "dismiss" ? 260 : 320)
                        easing.type: flyWin.phase === "dismiss" ? Easing.InCubic : Easing.OutCubic
                    }
                }
                Behavior on cardYS {
                    enabled: !fcard.inst
                    NumberAnimation { duration: flyWin.noAnim ? 0 : 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                }

                // rich media strip: left-to-right wipe reveal. The inner clipper
                // overshoots the strip height so its bottom rounding falls below
                // the image (top corners round, bottom edge square).
                Item {
                    visible: fcard.rich
                    x: 0
                    y: 0
                    width: Math.round(fcard.width * fcard.imgWipe)
                    height: fcard.stripH
                    clip: true
                    opacity: 1 - fcard.lq(0)

                    // plain (unmasked) placeholder tint behind the image; kept
                    // separate from the ClippingRectangle below so its fill
                    // never bleeds into the offscreen mask's corner antialiasing
                    Rectangle {
                        width: fcard.width
                        height: fcard.stripH + 16
                        radius: 16
                        color: Qt.alpha(flyWin.nColor, 0.2)
                    }

                    ClippingRectangle {
                        width: fcard.width
                        height: fcard.stripH + 16
                        radius: 16
                        color: "transparent"

                        Image {
                            width: fcard.width
                            height: fcard.stripH
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            // decode at ~2x display width, not native size
                            sourceSize.width: 700
                            source: fcard.rich ? flyWin.view.image : ""
                        }
                    }
                }

                Row {
                    id: contentBox
                    x: 12
                    y: fcard.stripH + 11
                    width: fcard.width - 12 - 34
                    spacing: 10

                    ClippingRectangle {
                        visible: fcard.thumb
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 40
                        radius: 20
                        color: Qt.alpha(flyWin.nColor, 0.25)
                        border.width: 2
                        border.color: Qt.alpha(flyWin.nColor, 0.4)
                        opacity: fcard.lineO(0)
                        transform: Translate { y: fcard.lineY(0) }

                        Image {
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(80, 80)
                            source: fcard.thumb ? flyWin.view.image : ""
                        }
                    }

                    Column {
                        width: parent.width - (fcard.thumb ? 50 : 0)
                        spacing: 3

                        Row {
                            id: appRow
                            spacing: 5
                            opacity: fcard.lineO(fcard.lBase)
                            transform: Translate { y: fcard.lineY(fcard.lBase) }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: 2.5
                                antialiasing: true
                                color: flyWin.nColor
                            }
                            Text {
                                text: flyWin.view.app || "notification"
                                textFormat: Text.PlainText
                                color: root.notifTh.muted
                                font { family: root.flyMono; pixelSize: root.flyFs(10); letterSpacing: 2; capitalization: Font.AllUppercase }
                            }
                        }
                        Text {
                            id: headText
                            visible: text.length > 0
                            width: parent.width
                            text: flyWin.view.summary
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: root.notifTh.fg
                            font { family: root.flyMono; pixelSize: root.flyFs(13); weight: Font.DemiBold }
                            opacity: fcard.lineO(fcard.lBase + 1)
                            transform: Translate { y: fcard.lineY(fcard.lBase + 1) }
                        }
                        // short body: an elided single line that, when it doesn't
                        // fit, expands to the full wrapped text on tap (the elided
                        // and wrapped copies crossfade inside an animated clip)
                        Item {
                            id: subWrap
                            visible: fcard.bodyAsSub
                            width: parent.width
                            readonly property bool truncated: fcard.bodyAsSub && subText.truncated
                            height: visible ? (fcard.expanded && truncated ? subFull.paintedHeight : subText.implicitHeight) : 0
                            clip: true
                            opacity: fcard.lineO(fcard.lBase + 2)
                            transform: Translate { y: fcard.lineY(fcard.lBase + 2) }
                            Behavior on height {
                                enabled: flyWin.phase === "show"
                                NumberAnimation { duration: 340; easing.type: Easing.InOutCubic }
                            }

                            Text {
                                id: subText
                                width: parent.width
                                text: fcard.bodyAsSub ? flyWin.view.body : ""
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                color: root.notifTh.muted
                                font { family: root.flyMono; pixelSize: root.flyFs(11) }
                                opacity: fcard.expanded && subWrap.truncated ? 0 : 1
                                Behavior on opacity {
                                    NumberAnimation { duration: 180 }
                                }
                            }
                            Text {
                                id: subFull
                                width: parent.width
                                text: subText.text
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                color: root.notifTh.muted
                                font { family: root.flyMono; pixelSize: root.flyFs(11) }
                                opacity: 1 - subText.opacity
                                visible: opacity > 0
                            }
                        }
                        Column {
                            id: bodyBlock
                            visible: flyWin.view.body !== "" && !fcard.bodyAsSub
                            width: parent.width
                            topPadding: 5
                            spacing: 6
                            opacity: fcard.lineO(fcard.lBase + 2)
                            transform: Translate { y: fcard.lineY(fcard.lBase + 2) }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Qt.alpha(root.notifTh.fg, 0.09)
                            }
                            // body clips to 3 lines; tapping the card animates
                            // the clip open (text is fully laid out throughout,
                            // so the reveal is a smooth height change)
                            Item {
                                id: bodyClip
                                width: parent.width
                                clip: true
                                readonly property real lineH: bodyText2.lineCount > 0 ? bodyText2.paintedHeight / bodyText2.lineCount : root.flyFs(15)
                                readonly property real collapsedH: Math.min(bodyText2.paintedHeight, Math.ceil(lineH * 3))
                                readonly property bool truncated: bodyText2.paintedHeight > collapsedH + 1
                                height: fcard.expanded ? bodyText2.paintedHeight : collapsedH
                                Behavior on height {
                                    enabled: flyWin.phase === "show"
                                    NumberAnimation { duration: 340; easing.type: Easing.InOutCubic }
                                }

                                Text {
                                    id: bodyText2
                                    width: parent.width
                                    text: bodyBlock.visible ? flyWin.view.body : ""
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 24
                                    textFormat: Text.PlainText
                                    color: root.notifTh.muted
                                    font { family: root.flyMono; pixelSize: root.flyFs(11) }
                                }
                                // ellipses over the clipped last line; gone once
                                // expanded (card-coloured backing masks the text)
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    width: bodyEll.implicitWidth + 10
                                    height: bodyEll.implicitHeight
                                    color: fcard.color
                                    opacity: bodyClip.truncated && !fcard.expanded ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: 180 }
                                    }
                                    Text {
                                        id: bodyEll
                                        anchors.right: parent.right
                                        text: "…"
                                        color: root.notifTh.muted
                                        font { family: root.flyMono; pixelSize: root.flyFs(11) }
                                    }
                                }
                            }

                            // the watcher-not-running alert's only actionable
                            // content is the setup commands in its body — a
                            // real button, not tap-to-copy-and-vanish, so
                            // expanding it behaves like any other
                            // notification and copying is a deliberate,
                            // separate step (fires the usual "Copied to
                            // clipboard" toast, replacing this one, same as
                            // any other same-app follow-up notification)
                            Rectangle {
                                id: watcherCopyBtn
                                visible: fcard.expanded && flyWin.view.own && flyWin.view.summary === "Clipboard watcher not running"
                                width: watcherCopyText.implicitWidth + 24
                                height: 28
                                radius: 8
                                color: Qt.alpha(root.notifTh.accent, watcherCopyHover.hovered ? 0.28 : 0.16)
                                border.width: 1
                                border.color: Qt.alpha(root.notifTh.accent, 0.5)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    id: watcherCopyText
                                    anchors.centerIn: parent
                                    text: "Copy setup commands"
                                    color: root.notifTh.fg
                                    font { family: root.flyMono; pixelSize: root.flyFs(12) }
                                }
                                HoverHandler { id: watcherCopyHover }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.copyToClipboard(root.clipWatcherFixCommand)
                                }
                            }
                        }
                    }
                }

                // expand-state chevron: fades in only while the card is hovered
                // and there is more to show. Drawn on a Canvas so up and down
                // share exact ink bounds (glyphs sit at different heights in the
                // em box and visually jumped); flipping direction morphs the
                // arms through a flat line into the opposite point.
                Item {
                    id: chev
                    z: 5
                    // pinned to the card's top-right corner (over the media
                    // strip when there is one), inset to match the app-row
                    // dot's padding on the opposite side
                    x: fcard.width - width - 12
                    y: 12
                    width: 14
                    height: 14
                    // 1 = pointing down (can expand), -1 = pointing up
                    property real morph: fcard.expanded ? -1 : 1
                    Behavior on morph {
                        enabled: flyWin.phase === "show" && !fcard.inst
                        NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
                    }
                    opacity: (fcard.expandable || fcard.expanded) && cardHover.hovered && flyWin.phase === "show" ? 0.9 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    Canvas {
                        anchors.fill: parent
                        renderStrategy: Canvas.Immediate
                        renderTarget: Canvas.Image
                        property color col: root.notifTh.muted
                        property real m: chev.morph
                        onColChanged: requestPaint()
                        onMChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = String(col);
                            ctx.lineWidth = 1.6;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.beginPath();
                            ctx.moveTo(3.5, 7.25 - 1.75 * m);
                            ctx.lineTo(7, 7.25 + 1.75 * m);
                            ctx.lineTo(10.5, 7.25 - 1.75 * m);
                            ctx.stroke();
                        }
                    }
                }
                HoverHandler {
                    id: cardHover
                }
                // swipe-dismiss: DragHandler measures in scene coordinates,
                // so the card moving under the cursor doesn't feed the drag
                DragHandler {
                    id: fdrag
                    enabled: flyWin.phase === "show"
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    onActiveChanged: {
                        if (active) {
                            fcard.dragging = true;
                            fcard.grabX = centroid.scenePosition.x - fcard.swipeX;
                        } else {
                            fcard.dragging = false;
                            if (flyWin.phase === "show") {
                                if (fcard.swipeX > 60)
                                    flyWin.dismiss(1);
                                else if (fcard.swipeX < -60)
                                    flyWin.dismiss(-1);
                                else
                                    fcard.swipeX = 0; // springs home
                            }
                        }
                    }
                    onCentroidChanged: {
                        if (active) {
                            const raw = centroid.scenePosition.x - fcard.grabX;
                            // either direction dismisses; both share the same
                            // light asymptotic drag (cap ~140px) so the card
                            // feels equally weighted left and right
                            fcard.swipeX = 140 * raw / (140 + Math.abs(raw));
                        }
                    }
                }
                TapHandler {
                    // a tap (not a drag) expands the clipped body — same as
                    // any other long notification, including the "watcher
                    // not running" alert (its copy button, in the expanded
                    // body, is a nested MouseArea so it grabs the press
                    // before this handler sees it as a plain expand/collapse)
                    onTapped: {
                        if (fcard.expandable || fcard.expanded)
                            fcard.expanded = !fcard.expanded;
                    }
                }
            }
        }
    }
}
