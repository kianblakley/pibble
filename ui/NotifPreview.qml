import QtQuick
import "root:/config"
import "root:/services"

// A notification arriving, in the order the flyout actually arrives in: the
// bubble alone first (NotificationFlyout's "appear" phase runs iconIn and
// nothing else), and only once it has settled does the card fade up behind it
// and fill in line by line ("show", which starts cardO/cardYS and stagInAnim
// together). Sequencing them was the whole point of the split there, and a
// preview that ran them at once got the one thing about it that is visible
// wrong.
//
// Every keyframe below is the flyout's own, slowed; "off" collapses each of
// them to 0 there and here alike, so the pair simply lands.
AnimPreview {
    id: root

    readonly property bool noAnim: Settings.notifAnim === "none"
    replayOn: Settings.notifAnim

    // the card's per-line enter progress, on the flyout's own 650ms clock:
    // 380ms windows offset 90ms apart, quint-out
    property real stag: 650
    function lineO(i: int): real {
        const p = Math.max(0, Math.min(1, (root.stag - i * 90) / 380));
        return 1 - Math.pow(1 - p, 4);
    }

    Rectangle {
        id: card
        property real squash: 1
        // the card hangs left of the circle with its top at the circle's
        // vertical centre, exactly as the flyout's does
        x: bubble.x - root.u(4) - width
        y: bubble.y + bubble.height / 2
        width: root.u(68)
        height: root.u(26)
        radius: Theme.radius(root.u(6))
        color: Qt.alpha(Theme.muted, 0.22)
        transform: Scale {
            origin.x: card.width / 2
            origin.y: card.height / 2
            yScale: card.squash
        }

        // the app line, the summary and a line of body - laid out by hand
        // rather than in a Column, since each rides its own bit of the stagger
        // up into place
        Repeater {
            model: [30, 50, 22]

            Rectangle {
                required property int index
                required property int modelData
                x: root.u(6)
                y: root.u(5 + index * 7 + 4 * (1 - root.lineO(index)))
                width: root.u(modelData)
                height: root.u(3)
                radius: Theme.radius(root.u(1.5))
                color: index === 0 ? Qt.alpha(Theme.accent, 0.85) : Qt.alpha(Theme.muted, 0.6)
                opacity: root.lineO(index)
            }
        }
    }
    // declared after the card so the bubble sits over its corner, as it does
    // on screen
    Rectangle {
        id: bubble
        x: root.stageWidth - width - root.u(6)
        y: root.u(6)
        width: root.u(16)
        height: root.u(16)
        radius: Theme.radius(root.u(8))
        antialiasing: true
        color: Theme.accent
    }

    onStarted: notifIn.restart()
    SequentialAnimation {
        id: notifIn

        // ── the flyout's "appear" phase: the bubble, on its own ──
        PropertyAction { target: card; property: "opacity"; value: 0 }
        PropertyAction { target: card; property: "squash"; value: 0.92 }
        PropertyAction { target: root; property: "stag"; value: 0 }
        PropertyAction { target: bubble; property: "opacity"; value: 0 }
        PropertyAction { target: bubble; property: "scale"; value: 0 }
        ParallelAnimation {
            NumberAnimation { target: bubble; property: "opacity"; to: 1; duration: root.noAnim ? 0 : root.slow(220); easing.type: Easing.OutCubic }
            NumberAnimation { target: bubble; property: "scale"; to: 1.18; duration: root.noAnim ? 0 : root.slow(300); easing.type: Easing.OutCubic }
        }
        NumberAnimation { target: bubble; property: "scale"; to: 0.95; duration: root.noAnim ? 0 : root.slow(100); easing.type: Easing.InOutQuad }
        NumberAnimation { target: bubble; property: "scale"; to: 1; duration: root.noAnim ? 0 : root.slow(100); easing.type: Easing.InOutQuad }

        // ── "show": the card, and the lines inside it ──
        ParallelAnimation {
            NumberAnimation { target: card; property: "opacity"; to: 1; duration: root.noAnim ? 0 : root.slow(320); easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "squash"; to: 1; duration: root.noAnim ? 0 : root.slow(320); easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            NumberAnimation { target: root; property: "stag"; to: 650; duration: root.noAnim ? 0 : root.slow(650) }
        }
    }
}
