import QtQuick
import "root:/config"
import "root:/services"

// visible grid-of-tiles size picker (Grids settings tab): hovering
// previews a cols×rows selection Excel-insert-table style, clicking
// commits it. `target` indexes SettingsSchema.gridTargets for which page's Settings
// cols/rows properties and bounds apply. The tile canvas is always laid
// out at SettingsSchema.pickerMaxCols × gridPickerMaxRows (the largest any
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
Item {
    id: root

    property string target: "apps"
    readonly property var spec: SettingsSchema.gridTargets[root.target]
    readonly property bool wallsBars: root.target === "walls" && Settings.wallpaperStyle !== "grid"
    readonly property int curCols: Settings[root.spec.colsProp]
    readonly property int curRows: Settings[root.spec.rowsProp]
    readonly property int curVisible: Settings.wallsVisible
    // >0 while hovered (a preview size); 0 falls back to the committed
    // size. Reset on exit/target switch so the preview always reflects
    // the grid actually under the mouse instead of a stale hover from
    // before the mouse left or before switching pages.
    property int hoverCols: 0
    property int hoverRows: 0
    property int hoverVisible: 0
    onTargetChanged: root.resetHover()
    onWallsBarsChanged: root.resetHover()
    function resetHover() {
        root.hoverCols = 0;
        root.hoverRows = 0;
        root.hoverVisible = 0;
    }
    readonly property int shownCols: root.hoverCols > 0 ? root.hoverCols : root.curCols
    readonly property int shownRows: root.hoverRows > 0 ? root.hoverRows : root.curRows
    readonly property int shownVisible: root.hoverVisible > 0 ? root.hoverVisible : root.curVisible
    readonly property int tileSize: 26
    readonly property int tileGap: 6
    readonly property int step: root.tileSize + root.tileGap
    readonly property int gridW: SettingsSchema.pickerMaxCols * root.tileSize + (SettingsSchema.pickerMaxCols - 1) * root.tileGap
    readonly property int gridH: SettingsSchema.pickerMaxRows * root.tileSize + (SettingsSchema.pickerMaxRows - 1) * root.tileGap
    readonly property int activeW: root.spec.maxCols * root.tileSize + (root.spec.maxCols - 1) * root.tileGap
    readonly property int activeH: root.spec.maxRows * root.tileSize + (root.spec.maxRows - 1) * root.tileGap
    // the active target's grid sits centered within the fixed canvas,
    // so a 4×4 target's tiles aren't stuck in the corner of a 6×6 canvas
    readonly property int offsetX: Math.round((root.gridW - root.activeW) / 2)
    readonly property int offsetY: Math.round((root.gridH - root.activeH) / 2)

    // bar-mode selection: SettingsSchema.carouselBarSlots columns (0..barCenter*2),
    // always odd 3–9, symmetric around the center column. Bars use the
    // walls spec's own column offset/step, not a separate layout, so a
    // bar sits exactly where that column's tiles already sit.
    readonly property int barSlots: SettingsSchema.carouselBarSlots
    readonly property int barCenter: Math.floor(root.barSlots / 2)
    readonly property int barsOffsetX: Math.round((root.gridW - (root.barSlots * root.step - root.tileGap)) / 2)
    function halfFor(n: int): int {
        return Math.floor((n - 1) / 2);
    }
    function visibleForBar(idx: int): int {
        const half = Math.max(1, Math.min(root.halfFor(root.barSlots), Math.abs(idx - root.barCenter)));
        return half * 2 + 1;
    }

    width: 780
    height: root.gridH + 14 + sizeLabel.implicitHeight

    Item {
        id: canvas
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.gridW
        height: root.gridH

        Repeater {
            model: SettingsSchema.pickerMaxCols * SettingsSchema.pickerMaxRows

            Rectangle {
                id: tile
                required property int index
                readonly property int col: index % SettingsSchema.pickerMaxCols
                readonly property int row: Math.floor(index / SettingsSchema.pickerMaxCols)
                readonly property int barDist: Math.abs(tile.col - root.barCenter)
                // the tile that becomes a bar's visible body: row 0 of
                // any in-range column, stretched down over its column
                readonly property bool isBarBody: root.wallsBars && tile.row === 0 && tile.col < root.barSlots
                // the rest of that same column (rows 1..spec.maxRows-1):
                // these are what visibly conjoin — they slide up to the
                // bar's top edge while shrinking away, rather than
                // fading out in place like a tile that's simply out of
                // bounds (rows past spec.maxRows, e.g. the apps tab's
                // taller columns, still do exactly that)
                readonly property bool mergingIntoBar: root.wallsBars && tile.col < root.barSlots
                    && tile.row > 0 && tile.row < root.spec.maxRows
                // whether this tile exists at all for the active target
                // (drives the pop in/out on target switch, and — in bar
                // mode — the rest of a bar's column shrinking away
                // beneath the row-0 tile that grew to cover it)
                readonly property bool inBounds: root.wallsBars
                    ? tile.isBarBody
                    : (tile.col < root.spec.maxCols && tile.row < root.spec.maxRows)
                // live hover/click preview, Excel-insert-style — falls
                // back to the committed size when nothing is hovered
                readonly property bool previewed: root.wallsBars
                    ? tile.barDist <= root.halfFor(root.shownVisible)
                    : (tile.col < root.shownCols && tile.row < root.shownRows)
                // the actually-saved size — always outlined, even while
                // a hover preview is filling in a different size
                readonly property bool committed: root.wallsBars
                    ? tile.barDist <= root.halfFor(root.curVisible)
                    : (tile.col < root.curCols && tile.row < root.curRows)
                x: root.wallsBars ? (root.barsOffsetX + tile.col * root.step) : (root.offsetX + tile.col * root.step)
                y: root.offsetY + (tile.mergingIntoBar ? 0 : tile.row * root.step)
                width: root.tileSize
                height: tile.isBarBody ? root.activeH : root.tileSize
                radius: 5
                opacity: tile.inBounds ? 1 : 0
                scale: tile.inBounds ? 1 : 0
                color: tile.previewed ? Qt.alpha(Theme.accent, 0.35) : "transparent"
                border.width: tile.committed ? 2 : 1
                border.color: tile.committed ? Theme.accent : Qt.alpha(Theme.muted, 0.3)
                Behavior on x { NumberAnimation { duration: Anim.menu(240); easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Anim.menu(240); easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: Anim.menu(240); easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: Anim.menu(240); easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: Anim.menu(90) } }
                Behavior on color { ColorAnimation { duration: Anim.menu(120) } }
                Behavior on opacity { NumberAnimation { duration: Anim.menu(180); easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: Anim.menu(240); easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
            }
        }

        MouseArea {
            x: root.wallsBars ? root.barsOffsetX : root.offsetX
            y: root.offsetY
            width: root.wallsBars ? (root.barSlots * root.step - root.tileGap) : root.activeW
            height: root.activeH
            hoverEnabled: true
            onPositionChanged: mouse => {
                if (root.wallsBars) {
                    const idx = Math.max(0, Math.min(root.barSlots - 1, Math.round(mouse.x / root.step)));
                    root.hoverVisible = root.visibleForBar(idx);
                } else {
                    root.hoverCols = Math.max(root.spec.minCols, Math.min(root.spec.maxCols, Math.floor(mouse.x / root.step) + 1));
                    root.hoverRows = Math.max(root.spec.minRows, Math.min(root.spec.maxRows, Math.floor(mouse.y / root.step) + 1));
                }
            }
            onExited: root.resetHover()
            onClicked: mouse => {
                if (root.wallsBars) {
                    const idx = Math.max(0, Math.min(root.barSlots - 1, Math.round(mouse.x / root.step)));
                    Settings.wallsVisible = root.visibleForBar(idx);
                } else {
                    Settings[root.spec.colsProp] = Math.max(root.spec.minCols, Math.min(root.spec.maxCols, Math.floor(mouse.x / root.step) + 1));
                    Settings[root.spec.rowsProp] = Math.max(root.spec.minRows, Math.min(root.spec.maxRows, Math.floor(mouse.y / root.step) + 1));
                }
                Settings.save();
            }
        }
    }

    Text {
        id: sizeLabel
        anchors.top: canvas.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.wallsBars ? (root.shownVisible + " visible") : (root.shownCols + " × " + root.shownRows)
        color: Theme.fg
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
    }
}
