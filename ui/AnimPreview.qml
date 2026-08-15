import QtQuick
import "root:/services"

// The little stage every row on the Animations tab draws its preview into,
// centred under the row it belongs to exactly as the tile picker's canvas sits
// under its own (see GridSizePicker). Nothing frames it - a box drawn around a
// picture of a box read as part of the picture - so what the user sees is
// whatever the preview itself draws into a 16:9 stage.
//
// A preview *rests* on the pose its animation settles at and replays on demand:
// when the value it demonstrates changes (`replayOn`), when the pointer crosses
// it, and when the tab comes on screen. Nothing loops - six boxes moving
// forever, one beside each setting, would be unreadable and would keep the
// compositor redrawing a pane the user is trying to read.
//
// Previews hang explicit animations off `started` rather than toggling a
// "shown" flag, because every one of them spells out its own `from`: a replay
// lands on the start pose in the frame it is asked for, with no hidden frame to
// sequence first, and the settled pose is simply where the last run left off.
Item {
    id: root

    // Whatever this preview demonstrates - assign the setting it reads, and any
    // change to it replays the run. Stepping the value is the moment a preview
    // is most worth seeing, and it costs the caller one binding.
    property var replayOn: null
    // Stagger for the whole-tab replay below, so the column arrives as a
    // cascade rather than as six boxes twitching in lockstep.
    property int playDelay: 0
    signal started

    // Whether this preview is a screen, i.e. whether its stage clips. True for
    // everything that animates something onto a display; false for the one that
    // *is* the thing it stands for (the tile grid).
    property bool screen: true

    // The picture's design size, and how much larger than that it is actually
    // drawn. Every length a preview lays out goes through u() - so a bigger
    // unit grows the whole picture rather than handing a 100x56 box margins -
    // and everything one draws is geometry or text, both of which the scene
    // graph rasterises at whatever size they end up (nothing here is scaled
    // through a texture, which is also why the one Canvas in the set sizes
    // itself through u() instead of being transformed).
    //
    // The tab sets the unit, once, for all of them: it sizes its previews to
    // whatever height it has left over - see AnimationsTab.previewUnit.
    property real baseWidth: 100
    property real baseHeight: 56
    property real unit: 1
    function u(px: real): real {
        return px * root.unit;
    }
    // Font sizes take the same scaling but have to land on whole pixels, and
    // go through Theme.fontSize on top of it so the user's type scale still
    // applies.
    function uf(px: int): int {
        return Theme.fontSize(Math.round(px * root.unit));
    }

    default property alias contents: stage.data
    readonly property real stageWidth: stage.width
    readonly property real stageHeight: stage.height

    // How much slower a preview runs than the thing it stands for: half speed,
    // one figure for the whole set. The real animations are tuned to be *felt*
    // while the user is on their way somewhere else; here they are the subject,
    // and at full speed a 220ms pop is over before the eye that went looking
    // for it has arrived. Applied to every duration a preview takes from the
    // real code, never to the real code itself - and 0 stays 0, so an "off"
    // style still lands instantly.
    property real slowdown: 2
    function slow(ms: int): int {
        return Math.round(ms * root.slowdown);
    }

    // Whether this preview may run at all: its own visibility (the settings
    // pane is only mapped while that pane is showing), and the tab's - which
    // the filmstrip expresses by sliding inactive tabs sideways behind a clip
    // at full opacity, so nothing else here would know the box can't be seen.
    // Same ancestor-declared switch the text scramble uses, read the same way:
    // every ancestor is visited so this stays subscribed to all of them (see
    // ScrambleText's ancestorSuppressed).
    readonly property bool active: {
        let on = root.visible;
        for (let item = root.parent; item; item = item.parent) {
            if (item.previewsActive === false)
                on = false;
        }
        return on;
    }
    onActiveChanged: if (root.active)
        root.play(root.playDelay)
    onReplayOnChanged: root.play(0)

    function play(delay: int): void {
        if (!root.active)
            return;
        if (delay <= 0) {
            root.started();
            return;
        }
        delayTimer.interval = delay;
        delayTimer.restart();
    }
    Timer {
        id: delayTimer
        onTriggered: root.started()
    }

    // How much of the top of the stage the preview's resting pose leaves empty,
    // in design px like every other length here. A stage is a screen and some
    // of them draw a card sitting in the middle of it, so the box a preview
    // occupies and the picture inside it start in different places - and down a
    // column of six, aligning the boxes leaves the pictures at six different
    // distances from the stepper they answer to. The item is pulled up by its
    // own inset instead, so what lines up is the ink.
    property real contentTop: 0

    width: root.u(root.baseWidth)
    height: root.u(root.baseHeight)
    anchors.horizontalCenter: parent.horizontalCenter
    y: -root.u(root.contentTop)

    Item {
        id: stage
        anchors.fill: parent
        clip: root.screen
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.play(0)
        onClicked: root.play(0)
    }
}
