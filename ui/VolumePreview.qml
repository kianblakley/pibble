import QtQuick
import "root:/config"
import "root:/services"

// The volume OSD arriving on screen: the same three shapes VolumeOsd's card
// takes - a slide up from the screen edge (bounced), a fade, or a pop - at the
// same easings and at its durations slowed down, on a pill standing in for the
// card.
//
// The OSD's own content (pill bar or equalizer) is the volStyle setting's
// business, over on the Flyouts tab; this is only how the card gets there, so
// it always draws the level bar.
AnimPreview {
    id: root

    readonly property string mode: Settings.volAnim
    replayOn: root.mode
    // one short move, over in a fraction of what the sequenced previews take -
    // at the shared figure the whole thing is finished before the eye that went
    // looking for it has arrived
    slowdown: 3.6
    Rectangle {
        id: card
        // centred in the stage rather than down on its edge as the real OSD
        // is: the tile is a stand-in for a screen, not a screen, and a card
        // sitting on its bottom edge read as a card falling out of the tile
        readonly property real restY: (root.stageHeight - height) / 2
        x: (root.stageWidth - width) / 2
        y: card.restY
        width: root.u(76)
        height: root.u(16)
        radius: Theme.radius(root.u(8))
        color: Qt.alpha(Theme.muted, 0.22)

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.u(9)
            anchors.right: parent.right
            anchors.rightMargin: root.u(9)
            height: root.u(4)
            radius: Theme.radius(root.u(2))
            color: Qt.alpha(Theme.accent, 0.22)

            Rectangle {
                width: parent.width * 0.62
                height: parent.height
                radius: parent.radius
                color: Theme.accent
            }
        }
    }

    onStarted: volIn.restart()
    ParallelAnimation {
        id: volIn
        // "slide" rides up from below the screen's own bottom edge, which is
        // where the real card's exit drops it past - so the OutBack overshoot
        // only ever shows on the way in, same as it does on screen
        NumberAnimation {
            target: card
            property: "y"
            from: root.mode === "slide" ? root.stageHeight : card.restY
            to: card.restY
            duration: root.mode === "slide" ? root.slow(340) : 0
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
        NumberAnimation {
            target: card
            property: "opacity"
            from: root.mode === "slide" ? 1 : 0
            to: 1
            duration: root.mode === "none" ? 0 : root.slow(200)
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: card
            property: "scale"
            from: root.mode === "pop" ? 0.8 : 1
            to: 1
            duration: root.mode === "none" ? 0 : root.slow(240)
            easing.type: Easing.OutBack
            easing.overshoot: 1.6
        }
    }
}
