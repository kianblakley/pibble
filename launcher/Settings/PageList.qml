import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "root:/config"
import "root:/launcher"
import "root:/services"
import "root:/ui"

// The Pages settings row: which panes exist, in what order, and the controls
// for adding and trashing custom ones.
//
// Click a row's box to toggle it, drag a row up or down to reorder the cycle
// (topmost is the home pane), swipe an uploaded row right to reveal its delete
// control. A vertical list rather than a horizontal chip row so it can hold an
// arbitrary number of uploaded pages without running out of width — it grows
// with the page count up to six rows, then scrolls.
Item {
    id: root

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
        const idx = Math.max(0, Math.min(LauncherState.orderedPages.length - 1, Math.round(contentLocalY / rowH)));
        if (idx !== LauncherState.orderedPages.indexOf(draggedId))
            LauncherState.movePage(draggedId, idx);
    }
    readonly property var defLabels: ({ clock: "Clock", apps: "Apps", walls: "Wallpapers", clips: "Clipboard" })
    function pageLabel(id) {
        if (id === "__add_folder__")
            return "Add a page…";
        if (defLabels[id])
            return defLabels[id];
        const u = (Settings.uploadedPages ?? []).find(p => p.id === id);
        if (!u)
            return id;
        const label = u.label.charAt(0).toUpperCase() + u.label.slice(1);
        return u.broken ? label + " - missing main.qml" : label;
    }
    function pageOn(id) {
        if (defLabels[id])
            return (Settings.pages ?? {})[id] !== false;
        const u = (Settings.uploadedPages ?? []).find(p => p.id === id);
        return !!(u && u.on);
    }
    function pageBroken(id) {
        const u = (Settings.uploadedPages ?? []).find(p => p.id === id);
        return !!(u && u.broken);
    }
    function pageToggle(id) {
        if (defLabels[id])
            LauncherState.togglePage(id);
        else
            LauncherState.toggleUploadedPage(id);
    }
    // moves an uploaded page's file to the trash (not a
    // hard delete — gio trash/trash-put when available,
    // otherwise a same-directory rename as a last
    // resort); the row itself drops out on the rescan
    // this kicks off, same path as noticing the file
    // vanished from an outside edit
    function trashPage(id) {
        const u = (Settings.uploadedPages ?? []).find(p => p.id === id);
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

        SettingLabel {
            anchors.left: parent.left
            text: "Pages"
        }
        ResetButton {
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
    Connections {
        target: LauncherState
        function onUploadDialogRequested(): void {
            folderDialog.open();
        }
    }

    FolderDialog {
        id: folderDialog
        title: "Select a page folder (needs a main.qml inside)"
        onAccepted: {
            // strip a trailing slash (if any) before
            // splitting, or base would come out as
            // "mywidget/" instead of "mywidget"
            const src = String(selectedFolder).replace("file://", "").replace(/\/$/, "");
            const base = src.slice(src.lastIndexOf("/") + 1);
            folderCopy.command = ["bash", "-c", `
                dir="$1"; src="$2"; base="$3"
                mkdir -p "$dir"
                dest="$dir/$base"
                n=2
                while [ -e "$dest" ]; do
                    dest="$dir/$base ($n)"
                    n=$((n + 1))
                done
                cp -r -- "$src" "$dest"`, "_", CustomPages.dir, src, base];
            folderCopy.running = true;
            LauncherState.reopenAfterDialog();
        }
        onRejected: {
            LauncherState.reopenAfterDialog();
        }
    }
    Process {
        id: folderCopy
        onExited: exitCode => {
            if (exitCode === 0)
                CustomPages.rescan();
        }
    }
    Process {
        id: pagesTrash
        property string trashedLabel: ""
        onExited: exitCode => {
            // on failure this un-hides the row (it slides
            // back in via the same removing Behaviors)
            // instead of leaving it stuck invisible
            const removedId = root.removingId;
            root.removingId = "";
            if (exitCode !== 0)
                return;
            if (root.revealedId === removedId)
                root.revealedId = "";
            if (removedId && (Settings.customPageData ?? {})[removedId] !== undefined) {
                const all = Object.assign({}, Settings.customPageData);
                delete all[removedId];
                Settings.customPageData = all;
            }
            CustomPages.rescan();
            if (Settings.alertEnabled("actions"))
                Quickshell.execDetached(["notify-send", "-a", "pibble", "-i", "user-trash", "Page moved to trash", trashedLabel]);
        }
    }
    // picks up files dropped into/removed from the test
    // folder by hand while this tab is open, not just on
    // the next launcher open
    Timer {
        interval: 1500
        repeat: true
        running: LauncherState.shown && LauncherState.pane === "settings" && LauncherState.settingsTab === "pages"
        onTriggered: CustomPages.rescan()
    }

    // stops short of 780 — the same 24px+8px gap the
    // header's ResetButton sits in above — so the scroll
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
            // LauncherState.orderedPages (see LauncherState.pageIds), so its
            // row is already included in the count
            height: root.rowH * Math.min(LauncherState.orderedPages.length, 6)
            Behavior on height {
                NumberAnimation { duration: Anim.menu(180); easing.type: Easing.OutCubic }
            }
            clip: true
            contentWidth: width
            contentHeight: pagesRows.height
            boundsBehavior: Flickable.StopAtBounds

            Item {
                id: pagesRows
                width: 780
                height: LauncherState.orderedPages.length * root.rowH

                // model is LauncherState.pageIds, not LauncherState.orderedPages:
                // pageIds only changes on genuine add/remove,
                // so a plain reorder never touches the
                // Repeater's model and never destroys/
                // recreates delegates — see the comment on
                // LauncherState.pageIds for why that matters (a
                // recreated delegate mid-drag loses its
                // DragHandler's grab, and a recreated one on
                // Reset has no Behavior to animate from)
                Repeater {
                    model: LauncherState.pageIds

                    Item {
                        id: pageRow
                        required property string modelData
                        readonly property int ord: LauncherState.orderedPages.indexOf(modelData)
                        readonly property bool isReal: !!root.defLabels[modelData]
                        readonly property bool isAdd: modelData === "__add_folder__"
                        readonly property bool isUploaded: !isReal && !isAdd
                        width: 780
                        height: root.rowH - 4

                        property bool held: false
                        property real slotY: ord * root.rowH
                        property real dragOff: held ? (root.pointerViewportY - root.dragGrabOffset + pagesFlick.contentY - slotY) : 0
                        Behavior on slotY {
                            enabled: !pageRow.held
                            NumberAnimation { duration: Anim.menu(220); easing.type: Easing.OutCubic }
                        }
                        Behavior on dragOff {
                            enabled: !pageRow.held
                            NumberAnimation { duration: Anim.menu(220); easing.type: Easing.OutCubic }
                        }
                        y: slotY + dragOff
                        z: held ? 2 : 0
                        scale: held ? 1.02 : 1
                        Behavior on scale {
                            NumberAnimation { duration: Anim.menu(140); easing.type: Easing.OutCubic }
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
                        readonly property bool removing: root.removingId === modelData
                        property real removeOffset: removing ? -width : 0
                        Behavior on removeOffset {
                            NumberAnimation { duration: Anim.menu(220); easing.type: Easing.InCubic }
                        }
                        opacity: removing ? 0 : 1
                        Behavior on opacity {
                            NumberAnimation { duration: Anim.menu(220); easing.type: Easing.InCubic }
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
                        // when they're off, since Anim.menu() zeroes
                        // the duration anyway and there's nothing
                        // to overshoot from at that point
                        Behavior on revealX {
                            id: revealXBehavior
                            enabled: false
                            NumberAnimation {
                                duration: Anim.menu(220)
                                easing.type: Settings.hiddenMenuAnimations ? Easing.OutBack : Easing.OutCubic
                                easing.overshoot: 1.5
                            }
                        }
                        Connections {
                            target: root
                            function onRevealedIdChanged() {
                                if (root.revealedId !== pageRow.modelData) {
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
                            // top (see LauncherState.orderedPages) and
                            // can't be reordered
                            enabled: !pageRow.isAdd
                            target: null
                            xAxis.enabled: false
                            onActiveChanged: {
                                if (active) {
                                    const viewportY = pageRow.mapToItem(pagesFlick, 0, centroid.position.y).y;
                                    pageRow.held = true;
                                    root.pointerViewportY = viewportY;
                                    root.dragGrabOffset = viewportY - (pageRow.slotY - pagesFlick.contentY);
                                    root.draggedId = pageRow.modelData;
                                    pagesFlick.interactive = false;
                                } else {
                                    pageRow.held = false;
                                    root.draggedId = "";
                                    root.edgeDir = 0;
                                    pagesFlick.interactive = true;
                                    Settings.save();
                                }
                            }
                            onCentroidChanged: {
                                if (!active)
                                    return;
                                const viewportY = pageRow.mapToItem(pagesFlick, 0, centroid.position.y).y;
                                root.pointerViewportY = viewportY;
                                const edge = 28;
                                if (viewportY < edge)
                                    root.edgeDir = -1;
                                else if (viewportY > pagesFlick.height - edge)
                                    root.edgeDir = 1;
                                else
                                    root.edgeDir = 0;
                                root.dragReorderCheck();
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
                            x: pageRow.revealX - pageRow.revealWidth + root.rowInset
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
                                color: pageDelete.confirming ? Qt.alpha("#e5484d", 0.85) : Qt.alpha(Theme.muted, 0.2)
                                border.width: 1
                                border.color: pageDelete.confirming ? "#e5484d" : Qt.alpha(Theme.muted, 0.6)
                                Behavior on color {
                                    ColorAnimation { duration: Anim.menu(140) }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: pageDelete.confirming ? "#141210" : Theme.muted
                                    font { family: Theme.fontFamily; pixelSize: 14 }
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
                                onTriggered: root.trashPage(pageRow.modelData)
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
                                        root.removingId = pageRow.modelData;
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
                            x: pageRow.revealX + root.rowInset
                            z: 1

                            Row {
                                id: pageContent
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Rectangle {
                                    id: pageBox
                                    readonly property bool broken: root.pageBroken(pageRow.modelData)
                                    visible: !pageRow.isAdd
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    height: 18
                                    radius: 4
                                    color: root.pageOn(pageRow.modelData) ? Qt.alpha(Theme.accent, 0.85) : "transparent"
                                    border.width: 1
                                    border.color: broken ? Qt.alpha(Theme.muted, 0.6) : (root.pageOn(pageRow.modelData) ? Theme.accent : Qt.alpha(Theme.muted, 0.6))

                                    Text {
                                        anchors.centerIn: parent
                                        visible: root.pageOn(pageRow.modelData) || pageBox.broken
                                        text: pageBox.broken ? Icons.alertTriangle : Icons.check
                                        color: pageBox.broken ? Qt.alpha(Theme.muted, 0.9) : "#141210"
                                        font { family: Icons.family; pixelSize: 13 }
                                    }
                                    // disabled while revealed (a tap there
                                    // closes the swipe instead) or when the
                                    // page is broken — there's nothing to
                                    // toggle on, only to trash
                                    TapHandler {
                                        enabled: pageRow.revealX < 1 && !pageBox.broken
                                        onTapped: root.pageToggle(pageRow.modelData)
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
                                    border.color: Qt.alpha(Theme.accent, 0.6)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "+"
                                        color: Theme.accent
                                        font { family: Theme.fontFamily; pixelSize: 13 }
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.pageLabel(pageRow.modelData)
                                    color: pageRow.isAdd ? Theme.accent : (root.pageOn(pageRow.modelData) ? Theme.fg : Theme.muted)
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                                }
                            }

                            TapHandler {
                                enabled: pageRow.isAdd
                                onTapped: {
                                    LauncherState.dialogPending = "folder";
                                    LauncherState.exit();
                                }
                            }
                            // tapping the revealed front layer
                            // anywhere else just closes it again
                            TapHandler {
                                enabled: pageRow.isUploaded && pageRow.revealX > 1
                                onTapped: {
                                    pageRow.revealX = 0;
                                    pageDelete.confirming = false;
                                    root.revealedId = "";
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
                                        root.revealedId = pageRow.modelData;
                                    } else {
                                        revealXBehavior.enabled = true;
                                        pageRow.revealX = pageRow.revealX > pageRow.revealWidth / 2 ? pageRow.revealWidth : 0;
                                        if (pageRow.revealX === 0) {
                                            root.revealedId = "";
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
                                    pageRow.revealX = Settings.hiddenMenuAnimations
                                        ? root.rubberBand(centroid.scenePosition.x - grabX, 0, pageRow.revealWidth, 90)
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
            running: root.edgeDir !== 0 && root.draggedId !== ""
            onTriggered: {
                const maxY = Math.max(0, pagesFlick.contentHeight - pagesFlick.height);
                pagesFlick.contentY = Math.max(0, Math.min(maxY, pagesFlick.contentY + root.edgeDir * 14));
                root.dragReorderCheck();
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
                const target = Math.max(0, Math.min(maxY, pagesFlick.contentY - (wheel.angleDelta.y / 120) * root.rowH * 3));
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
                    NumberAnimation { duration: Anim.menu(180); easing.type: Easing.OutCubic }
                }
                radius: 3
                color: Qt.alpha(Theme.muted, 0.15)

                Rectangle {
                    id: pagesScrollThumb
                    width: parent.width
                    radius: 3
                    color: Qt.alpha(Theme.accent, pagesScrollArea.pressed ? 0.85 : 0.6)
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

    SettingHint {
        id: pagesSub
        anchors.top: pagesListWrap.bottom
        anchors.topMargin: 2
        text: "drag to reorder · swipe right to delete · folders with a main.qml placed in pibble/custom-pages appear here"
    }
}
