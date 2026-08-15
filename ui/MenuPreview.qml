import QtQuick
import "root:/config"
import "root:/services"

// This pane's own two motions, in the order a user meets them: the settings
// pane springing up onto the screen (SettingsPane's enterAnim), and then the
// tab filmstrip sliding sideways when they pick a different tab - which is the
// other half of what this row switches off, and the half that has nothing to do
// with opening. Both run through Anim.menu(), so setting the row to "off"
// flattens the preview at the same moment it flattens the pane.
//
// The drop is the one number not taken as-is: the pane rises 40px into a
// ~700px-tall window, which over a 54px screen would be a pixel and a half.
// Scaled to the screen instead, so the spring is legible at this size.
AnimPreview {
    id: root

    replayOn: Settings.hiddenMenuAnimations
    // the tab links are the highest ink the pane draws - see contentTop
    contentTop: 8

    // Every duration below is Anim.menu()'s own - exactly as the pane runs
    // it - taken through slow() like every other preview's. The pause between
    // the two moves is this preview's own: the pane arriving and the filmstrip
    // stepping are separate motions, and run back to back they read as one
    // long slide.

    property real drop: 0
    // which tab is showing, 0-based - the filmstrip's whole position
    property real tabPos: root.tabs - 1
    readonly property int tabs: 2

    Item {
        id: pane
        anchors.fill: parent
        // the entrance's rise. On the pane, not on the preview: the tile
        // outline is the screen the pane arrives on, and screens don't move.
        transform: Translate {
            y: root.drop
        }

        // tab links across the top, with the underline riding to whichever is
        // showing, exactly as the pane's header does
        Repeater {
            model: root.tabs

            Rectangle {
                required property int index
                x: root.u(8 + index * 22)
                y: root.u(8)
                width: root.u(16)
                height: root.u(3)
                radius: Theme.radius(root.u(1.5))
                color: Qt.alpha(Theme.muted, 0.6)
            }
        }
        Rectangle {
            x: root.u(8 + root.tabPos * 22)
            y: root.u(14)
            width: root.u(16)
            height: root.u(2)
            radius: Theme.radius(root.u(1))
            color: Theme.accent
        }

        // the filmstrip: every tab laid out at once, slid sideways behind the
        // screen's clip rather than loaded on demand - the pane's own trick
        Item {
            id: film
            x: -root.tabPos * root.stageWidth
            y: root.u(22)
            width: root.stageWidth * root.tabs
            height: root.u(26)

            Repeater {
                model: root.tabs * 3

                Item {
                    required property int index
                    x: Math.floor(index / 3) * root.stageWidth + root.u(8)
                    y: (index % 3) * root.u(8)
                    width: root.stageWidth - root.u(16)
                    height: root.u(3)

                    Rectangle {
                        width: root.u(30)
                        height: parent.height
                        radius: Theme.radius(root.u(1.5))
                        color: Qt.alpha(Theme.muted, 0.6)
                    }
                    Rectangle {
                        anchors.right: parent.right
                        width: root.u(18)
                        height: parent.height
                        radius: Theme.radius(root.u(1.5))
                        color: Qt.alpha(Theme.accent, 0.55)
                    }
                }
            }
        }
    }

    onStarted: menuIn.restart()
    SequentialAnimation {
        id: menuIn
        PropertyAction { target: root; property: "tabPos"; value: 0 }
        ParallelAnimation {
            NumberAnimation { target: pane; property: "opacity"; from: 0; to: 1; duration: root.slow(Anim.menu(200)); easing.type: Easing.OutCubic }
            NumberAnimation { target: pane; property: "scale"; from: 0.9; to: 1; duration: root.slow(Anim.menu(500)); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
            NumberAnimation { target: root; property: "drop"; from: root.u(10); to: 0; duration: root.slow(Anim.menu(500)); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        }
        // long enough that the entrance has visibly finished before the tab
        // change starts - two motions in one box only read as two if nothing
        // overlaps them
        PauseAnimation { duration: root.slow(Anim.menu(260)) }
        NumberAnimation {
            target: root
            property: "tabPos"
            to: root.tabs - 1
            duration: root.slow(Anim.menu(420))
            easing.type: Easing.OutCubic
        }
    }
}
