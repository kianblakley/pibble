import QtQuick
import "root:/config"
import "root:/services"
import "root:/ui"

// The apps pane: a paged grid of app tiles ranked by launch frequency and
// filtered by the shared query, plus the empty state that replaces it.
Item {
    id: root

    anchors.fill: parent

    // Called on every launcher open. A pane keeps whatever opacity its last
    // entrance animation ended at, so it has to be put back *before* the pane
    // change that restarts that animation - otherwise the restart is clobbered
    // right back to 0.004 by a reset running after it. Invisible with a real
    // duration (the animation keeps writing opacity every frame regardless) but
    // it leaves the pane stuck dim when the tile style is "none" and the
    // restart completes synchronously.
    function resetEntrance(): void {
        drawer.opacity = 0.004;
    }

    Item {
        id: drawer
        anchors.centerIn: parent
        // extra top/bottom room for the optional query label and page dots,
        // reserved only when each is on so a disabled one leaves no gap
        readonly property int queryH: Settings.pageIndicatorEnabled("query") ? 32 : 0
        readonly property int dotsH: Settings.pageIndicatorEnabled("dots") ? 20 : 0
        width: Settings.appsCols * 174 + (Settings.appsCols - 1) * 24 + 52
        height: grid.height + 52 + drawer.queryH + drawer.dotsH
        // Its own instance of the shared power/reboot rubber band: one
        // Translate per pane, all bound to the same pull, so no pane has to
        // reach across the tree for a sibling's transform.
        transform: Translate {
            y: LauncherState.powerPull - LauncherState.rebootPull
        }
        opacity: 0.004
        visible: LauncherState.drawerOpen || LauncherState.warmingApps
        Connections {
            target: LauncherState
            function onPaneChanged() {
                if (LauncherState.pane === "apps")
                    drawerEnter.restart();
            }
        }

        ParallelAnimation {
            id: drawerEnter
            NumberAnimation { target: drawer; property: "opacity"; from: 0; to: 1; duration: Anim.tile(200); easing.type: Easing.OutCubic }
            NumberAnimation { target: drawer; property: "scale"; from: 0.9; to: 1; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
            NumberAnimation { target: drawer; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        }

        PageQueryLabel {
            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            queryText: LauncherState.query
        }

        Grid {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 26 + drawer.queryH
            columns: Settings.appsCols
            columnSpacing: 24
            rowSpacing: 24

            Repeater {
                model: LauncherState.appPageSize

                Item {
                    id: cell
                    required property int index
                    width: 174
                    height: 100

                    readonly property int appIndex: LauncherState.appPage * LauncherState.appPageSize + index
                    property var entry: LauncherState.matches[appIndex] ?? null
                    property var shownEntry: null
                    property bool filled: false
                    readonly property bool isSelected: entry !== null && LauncherState.selected === cell.appIndex

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
                            filled = false;
                            springIn.stop();
                            if (LauncherState.pane === "apps") {
                                // ghost: the old tile springs out in place
                                springOut.restart();
                            } else {
                                // Filtered while the pane is off-screen. Typing
                                // from the clock sets the query and only *then*
                                // switches pane (see input.onTextChanged), so
                                // every non-match is ghosted one statement
                                // before the drawer becomes visible - playing
                                // the exit here would run it in full view,
                                // flashing the whole unfiltered page in and back
                                // out on top of the entrance. Drop straight to
                                // hidden instead; there's nothing to animate.
                                springOut.stop();
                                wrap.opacity = 0;
                            }
                        }
                    }
                    // replay the wave when the drawer opens: cells
                    // were already filled while it was hidden
                    Connections {
                        target: LauncherState
                        function onPaneChanged() {
                            if (LauncherState.pane === "apps" && cell.filled)
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
                                border.color: Qt.alpha(Theme.accent, 0.33)
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: Qt.alpha(Theme.accent, cell.isSelected ? 0.22 : 0.11)
                                border.width: 1
                                border.color: cell.isSelected ? Theme.accent : Qt.alpha(Theme.accent, 0.33)

                                Image {
                                    id: icon
                                    anchors.centerIn: parent
                                    width: 44
                                    height: 44
                                    sourceSize: Qt.size(88, 88)
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    source: Icons.url(cell.shownEntry ? cell.shownEntry.icon : "")
                                    visible: status === Image.Ready
                                }
                                ScrambleText {
                                    anchors.centerIn: parent
                                    visible: !icon.visible
                                    content: (cell.shownEntry ? cell.shownEntry.name : "").slice(0, 2).toUpperCase()
                                    // a slot taking a different app - a page
                                    // turn, or the filter narrowing - never
                                    // moves the tile, so the text resolving
                                    // again is the whole of the transition
                                    replayOnChange: true
                                    replayStagger: Anim.stagger(cell.index, Settings.appsCols, 60)
                                    color: Theme.accent
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(16); weight: Font.Bold }
                                }
                                // TapHandler (not a plain MouseArea) so a
                                // completed swipe below doesn't also
                                // register as a click - same tap-vs-drag
                                // split the wallpaper carousel's the carousel's cell uses
                                TapHandler {
                                    enabled: cell.filled
                                    onTapped: {
                                        if (Settings.singleClickActivate || cell.isSelected)
                                            LauncherState.launchRequested(cell.entry);
                                        else
                                            LauncherState.selected = cell.appIndex;
                                    }
                                }
                                // lets a pane-cycle/page swipe start with the
                                // finger/cursor right on the icon, instead of
                                // only working over the gaps between tiles -
                                // same DragHandler-alongside-TapHandler split
                                // the carousel's cell uses for the carousel, just forwarding
                                // into the shared dominant-axis dispatch
                                // instead of a carousel-specific flick
                                DragHandler {
                                    target: null
                                    enabled: cell.filled && Settings.gesturesEnabled() && !LauncherState.promptOpen
                                    property real grabX: 0
                                    property real grabY: 0
                                    onActiveChanged: {
                                        if (active) {
                                            grabX = centroid.scenePosition.x;
                                            grabY = centroid.scenePosition.y;
                                        } else {
                                            LauncherState.gestureRelease(centroid.scenePosition.x - grabX, centroid.scenePosition.y - grabY);
                                        }
                                    }
                                }
                            }
                        }

                        ScrambleText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            // restWidth, not implicitWidth: the caption keeps
                            // the width of the app's real name while it's
                            // still noise, so it doesn't breathe wider and
                            // narrower under a centered tile mid-scramble
                            width: Math.min(restWidth, 76)
                            height: 16
                            content: cell.shownEntry ? cell.shownEntry.name : ""
                            // see the initials label above
                            replayOnChange: true
                            replayStagger: Anim.stagger(cell.index, Settings.appsCols, 60)
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.fg
                            font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                        }
                    }

                    SequentialAnimation {
                        id: springIn
                        PropertyAction { target: wrap; property: "opacity"; value: 0 }
                        PropertyAction { target: wrap; property: "scale"; value: Anim.fromScale }
                        PropertyAction { target: wrap; property: "y"; value: Anim.fromY }
                        PauseAnimation { duration: Anim.stagger(cell.index, Settings.appsCols, 60) }
                        ParallelAnimation {
                            NumberAnimation { target: wrap; property: "opacity"; to: 1; duration: Anim.fadeDuration; easing.type: Easing.OutCubic }
                            NumberAnimation { target: wrap; property: "scale"; to: 1; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
                            NumberAnimation { target: wrap; property: "y"; to: 0; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
                        }
                    }

                    SequentialAnimation {
                        id: springOut
                        ParallelAnimation {
                            NumberAnimation { target: wrap; property: "scale"; to: Anim.outBounce ? 1.08 : 1; duration: Anim.outBounce ? Anim.tile(80) : 0; easing.type: Easing.OutQuad }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: wrap; property: "scale"; to: Anim.fromScale; duration: Anim.tile(Anim.outDuration); easing.type: Anim.outEasing }
                            NumberAnimation { target: wrap; property: "opacity"; to: 0; duration: Anim.tile(Anim.outDuration); easing.type: Anim.outEasing }
                        }
                    }
                }
            }
        }

        PageDots {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            pageCount: LauncherState.appPageSize > 0
                ? Math.ceil(LauncherState.matches.length / LauncherState.appPageSize) : 0
            currentPage: LauncherState.appPage
        }

    }

    // Empty state: fades in only once the last exiting tile has
    // fully sprung out (Anim.tile(400), matching drawer's springOut)
    // instead of popping in on top of tiles still animating away;
    // snaps back to hidden the instant results reappear so it's
    // ready to fade in again next time. Centered on the pane like
    // the wallpaper/clip empty states below, not inside `drawer`
    // (whose box stays the full grid size regardless of match count).
    ScrambleText {
        id: emptyLabel
        visible: LauncherState.pane === "apps" && opacity > 0
        anchors.centerIn: parent
        opacity: 0
        content: Apps.all.length === 0 ? "no apps found" : "no matches"
        // pinned to the resting string's box, so a centered label (as every
        // one out here is) doesn't shuffle sideways on every reroll, or up and
        // down with the line height of whichever font carries a symbol
        width: restWidth
        height: restHeight
        color: Theme.muted
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }

        Connections {
            target: LauncherState
            function onMatchesChanged() {
                if (LauncherState.matches.length === 0)
                    emptyFade.restart();
                else {
                    emptyFade.stop();
                    emptyLabel.opacity = 0;
                }
            }
        }
        SequentialAnimation {
            id: emptyFade
            PauseAnimation { duration: Anim.tile(400) }
            NumberAnimation { target: emptyLabel; property: "opacity"; to: 1; duration: Anim.tile(220); easing.type: Easing.OutCubic }
        }
    }
}
