import QtQuick
import "root:/config"
import "root:/services"

// A pane's worth of tiles arriving, which is what this style actually governs -
// so the preview is tiles, drawn exactly as the grid-size picker draws a
// selected one, rather than a screen with tiles on it. Each plays AppsPage's
// springIn (see it) with the same from-state, duration, easing and stagger
// offset, slowed so a "bloom" cascade reads as a cascade.
//
// Three across and two down rather than a square: "slide" moves a whole row at
// a time and "cascade" runs along one, and neither reads as itself on a grid
// with as many rows as it has columns.
//
// Anim.staggerOffset, not Anim.stagger: the offsets themselves, with no
// staggering window over them - nothing here is a page turn, so that window is
// never armed and stagger() would hand back 0 for every tile.
AnimPreview {
    id: root

    replayOn: Settings.animStyle
    screen: false

    readonly property int cols: 3
    readonly property int rows: 2
    readonly property int tileSize: 24
    readonly property int gap: 6
    baseWidth: root.cols * root.tileSize + (root.cols - 1) * root.gap
    baseHeight: root.rows * root.tileSize + (root.rows - 1) * root.gap

    Repeater {
        model: root.cols * root.rows

        Item {
            id: cell
            required property int index
            x: root.u((index % root.cols) * (root.tileSize + root.gap))
            y: root.u(Math.floor(index / root.cols) * (root.tileSize + root.gap))
            width: root.u(root.tileSize)
            height: root.u(root.tileSize)

            Rectangle {
                id: wrap
                width: parent.width
                height: parent.height
                radius: Theme.radius(root.u(5))
                color: Qt.alpha(Theme.accent, 0.35)
                border.width: 1
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
