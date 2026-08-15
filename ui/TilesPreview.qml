import QtQuick
import "root:/config"
import "root:/services"

// A pane's worth of tiles arriving, which is what this style actually governs -
// so the preview is tiles, drawn exactly as the grid-size picker draws a
// selected one, rather than a screen with tiles on it. Each plays AppsPage's
// springIn (see it) with the same from-state, duration, easing and stagger
// offset, slowed so a "bloom" cascade reads as a cascade.
//
// Four across and two down rather than a square: "slide" moves a whole row at
// a time and "cascade" runs along one, and neither reads as itself on a grid
// with as many rows as it has columns.
//
// The one preview that doesn't take the tab's size unit: these are the grid
// picker's tiles, at the picker's own size and spacing, and a pane's tiles
// drawn larger than the picker's would read as a different control rather than
// the same one. It is a fixed block in the tab's height budget instead - see
// AnimationsTab.previewUnit.
//
// Anim.staggerOffset, not Anim.stagger: the offsets themselves, with no
// staggering window over them - nothing here is a page turn, so that window is
// never armed and stagger() would hand back 0 for every tile.
AnimPreview {
    id: root

    replayOn: Settings.animStyle
    screen: false

    readonly property int cols: 4
    readonly property int rows: 2
    // GridSizePicker's own figures - see its tileSize/tileGap
    readonly property int tileSize: 26
    readonly property int gap: 6
    baseWidth: root.cols * root.tileSize + (root.cols - 1) * root.gap
    baseHeight: root.rows * root.tileSize + (root.rows - 1) * root.gap

    Repeater {
        model: root.cols * root.rows

        Item {
            id: cell
            required property int index
            x: (index % root.cols) * (root.tileSize + root.gap)
            y: Math.floor(index / root.cols) * (root.tileSize + root.gap)
            width: root.tileSize
            height: root.tileSize

            Rectangle {
                id: wrap
                width: parent.width
                height: parent.height
                radius: Theme.radius(5)
                color: Qt.alpha(Theme.accent, 0.35)
                // a committed picker tile's own border, not a hovered one's
                border.width: 2
                border.color: Theme.accent
            }

            // AppsPage's springIn, tile for tile - including the 60px slide
            // step its own grid uses, which is what puts a whole row on one
            // beat under the "slide" style
            SequentialAnimation {
                id: springIn
                PropertyAction { target: wrap; property: "opacity"; value: 0 }
                PropertyAction { target: wrap; property: "scale"; value: Anim.fromScale }
                PropertyAction { target: wrap; property: "y"; value: Anim.fromY }
                PauseAnimation { duration: root.slow(Anim.staggerOffset(cell.index, root.cols, 60)) }
                ParallelAnimation {
                    NumberAnimation { target: wrap; property: "opacity"; to: 1; duration: root.slow(Anim.fadeDuration); easing.type: Easing.OutCubic }
                    NumberAnimation { target: wrap; property: "scale"; to: 1; duration: root.slow(Anim.duration); easing.type: Anim.easing; easing.overshoot: 2.2 }
                    NumberAnimation { target: wrap; property: "y"; to: 0; duration: root.slow(Anim.duration); easing.type: Anim.easing; easing.overshoot: 2.2 }
                }
            }
            Connections {
                target: root
                function onStarted(): void {
                    springIn.restart();
                }
            }
        }
    }
}
