import QtQuick
import QtQuick.Effects
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
    //
    // A preview opts out by simply not calling this on its durations, which is
    // what the settings one does: it is the only one showing three motions in a
    // row, and halved it ran long enough that a user stepping the row next to
    // it was waiting on a box that had stopped saying anything new.
    property real slowdown: 2
    function slow(ms: int): int {
        return Math.round(ms * root.slowdown);
    }

    // The stage's own corner radius, for a preview whose picture *is* the
    // screen rather than a card standing on one (the launch reveal, the power
    // prompt): those fill the stage edge to edge, and square corners read as
    // unfinished beside the rounded cards the rest of the set draws. 0 - the
    // default - leaves the stage square and costs nothing.
    //
    // A clip can't do this (a clip is always the item's rect, and the launch
    // reveal is a circle that runs out past the corners), so a stage that asks
    // for it is rendered to a layer and masked to a rounded rect - the same
    // mask the launcher's own reveal uses, at 100x56 instead of full screen.
    property real stageRadius: 0
    // Kept genuinely visible and parked off-screen rather than `visible: false`:
    // an invisible item's layer never renders (see LauncherWindow's growMask,
    // which this copies).
    Item {
        id: stageMask
        visible: true
        layer.enabled: root.stageRadius > 0
        x: -100000
        y: -100000
        width: stage.width
        height: stage.height

        Rectangle {
            anchors.fill: parent
            antialiasing: true
            radius: root.stageRadius
            color: "white"
        }
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

    width: root.u(root.baseWidth)
    height: root.u(root.baseHeight)
    anchors.horizontalCenter: parent.horizontalCenter

    Item {
        id: stage
        anchors.fill: parent
        clip: root.screen
        layer.enabled: root.stageRadius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: stageMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.05
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.play(0)
        onClicked: root.play(0)
    }
}
