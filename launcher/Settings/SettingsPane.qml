import QtQuick
import "root:/config"
import "root:/launcher"
import "root:/services"
import "root:/ui"

// The settings pane: a header of tab links over a horizontal filmstrip of
// tab columns. Every tab is laid out at once and slid sideways rather than
// loaded on demand, so switching tabs never reflows the pane.
Item {
    id: root

    // Called on every launcher open. A pane keeps whatever opacity its last
    // entrance animation ended at, so it has to be put back *before* the pane
    // change that restarts that animation - otherwise the restart is clobbered
    // right back to 0.004 by a reset running after it. Invisible with a real
    // duration (the animation keeps writing opacity every frame regardless) but
    // it leaves the pane stuck dim when the tile style is "none" and the
    // restart completes synchronously.
    function resetEntrance(): void {
        root.opacity = 0.004;
    }

    // This pane has a motion switch of its own (every duration in here goes
    // through Anim.menu), and it governs the scramble too: a pane the user has
    // asked to appear instantly has no entrance for the text to resolve
    // alongside. Read by every ScrambleText in the pane, header and tabs
    // alike - see ui/ScrambleText.qml, and the tabs' own copy of this for the
    // filmstrip half of it.
    readonly property bool scrambleSuppressed: !Settings.hiddenMenuAnimations
    // ...and which of the Animations tab's per-surface scramble switches every
    // label under here answers to. Declared once for the whole subtree rather
    // than threaded through every control in it - same ancestor walk
    // scrambleSuppressed above uses (see ui/ScrambleText.qml).
    readonly property string scrambleSection: "settings"

    // built-ins first, then one slot per custom page that opts
    // into a settings tab (see LauncherState.customSettingsTabs) - in
    // whatever order those pages themselves loaded in
    readonly property var tabOrder: ["general", "pages", "animations", "keybindings", "flyouts"].concat(LauncherState.customSettingsTabs.map(t => t.pageId))
    // LauncherWindow's customPages Repeater's model is Settings.uploadedPages itself,
    // reassigned wholesale (a fresh array) on every toggle/
    // upload/trash/rescan - since it's a plain JS-array model,
    // that recreates every delegate, not just the one that
    // changed. For the split of a frame that a custom tab's
    // host is mid-recreate, LauncherState.customSettingsTabs (which reads
    // pageItem off those delegates) loses that tab, so
    // resolvedTabIndex briefly goes -1. Snapping tabIndex to 0 in that
    // window used to yank every filmstrip pane (see the
    // `Behavior on x` below and the built-in tabs' copies) over
    // to tab 0 and spring it back once the tab reappears - the
    // "settings flies across the screen" glitch. Holding the
    // last good index instead means the recreate is invisible:
    // nothing here moves until there's a real index to move to.
    readonly property int resolvedTabIndex: tabOrder.indexOf(LauncherState.settingsTab)
    property int tabIndex: 0
    onResolvedTabIndexChanged: if (resolvedTabIndex >= 0)
        tabIndex = resolvedTabIndex
    anchors.centerIn: parent
    width: 860
    height: 26 + header.height + 18 + tabViewport.height + 26
    transform: Translate {
        y: LauncherState.powerPull - LauncherState.rebootPull
    }
    opacity: 0.004
    visible: LauncherState.pane === "settings"
    Connections {
        target: LauncherState
        function onPaneChanged() {
            if (LauncherState.pane === "settings")
                enterAnim.restart();
        }
    }
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Anim.menu(200); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; from: 0.9; to: 1; duration: Anim.menu(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        NumberAnimation { target: root; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: Anim.menu(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
    }

    // header: title + underlined tab links, left-aligned
    Item {
        id: header
        width: 780
        height: 58
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 26

        // custom pages' tabs come and go as they're toggled in
        // Settings > Pages, but LauncherState.customSettingsTabs updates by
        // wholesale reassignment (see its own comment) and a plain
        // Repeater has no enter/exit transition for that - so tab
        // entries are staged here instead: a new id gets one fade-in
        // pass, a dropped id is kept around (fading out) until
        // staleTabSweep sweeps it for real. Built-in tabs are always
        // present and never animate.
        property var stagedTabs: [
            { id: "general", label: "General", custom: false, phase: "in" },
            { id: "pages", label: "Pages", custom: false, phase: "in" },
            { id: "animations", label: "Animations", custom: false, phase: "in" },
            { id: "keybindings", label: "Navigation", custom: false, phase: "in" },
            { id: "flyouts", label: "Flyouts", custom: false, phase: "in" }
        ]
        function reconcileTabs() {
            const desired = LauncherState.customSettingsTabs;
            const desiredLabel = {};
            for (const t of desired)
                desiredLabel[t.pageId] = t.label;
            const seen = {};
            const next = [];
            for (const t of stagedTabs) {
                if (!t.custom) {
                    next.push(t);
                    continue;
                }
                seen[t.id] = true;
                if (t.id in desiredLabel)
                    next.push({ id: t.id, label: desiredLabel[t.id], custom: true, phase: "in" });
                else if (t.phase === "exiting")
                    next.push(t);
                else {
                    next.push({ id: t.id, label: t.label, custom: true, phase: "exiting" });
                    staleTabSweep.restart();
                }
            }
            for (const t of desired) {
                if (!seen[t.pageId])
                    next.push({ id: t.pageId, label: t.label, custom: true, phase: "entering" });
            }
            stagedTabs = next;
            Qt.callLater(header.settleScroll);
        }
        Component.onCompleted: reconcileTabs()
        Connections {
            target: LauncherState
            function onCustomSettingsTabsChanged() { header.reconcileTabs(); }
        }
        // generous over tabFadeOut's duration so a tab that just
        // started exiting is guaranteed to have finished fading
        Timer {
            id: staleTabSweep
            interval: Anim.menu(260)
            onTriggered: {
                const next = header.stagedTabs.filter(t => t.phase !== "exiting");
                if (next.length !== header.stagedTabs.length)
                    header.stagedTabs = next;
            }
        }

        // index of the tab currently pinned to tabViewport's left edge -
        // tabRow slides behind the fixed clip as this changes (see its
        // `Behavior on x`) rather than the viewport itself moving, so
        // scrollIndex is always exactly on a tab boundary and the
        // leftmost visible tab is never partially cut off
        property int scrollIndex: 0
        readonly property real windowX: {
            const it = tabRepeater.itemAt(scrollIndex);
            return it ? it.x : 0;
        }
        readonly property bool canScrollLeft: scrollIndex > 0
        readonly property bool canScrollRight: tabRow.width - windowX > tabRowViewport.width
        // one tab at a time, never a whole page - the arrow reveals
        // exactly the next/previous tab rather than jumping by however
        // many happen to fit
        function scrollBy(delta: int): void {
            const next = scrollIndex + delta;
            if (next < 0 || next >= stagedTabs.length)
                return;
            if (delta > 0 && !canScrollRight)
                return;
            scrollIndex = next;
        }
        // clamps scrollIndex back into range after stagedTabs changes
        // shrink it (a custom tab toggled off) or shift widths (a
        // relabel), then makes sure the active tab is still on screen -
        // jumping it to become the new leftmost tab if not, which by
        // definition always fits
        function settleScroll() {
            if (!stagedTabs.length) {
                scrollIndex = 0;
                return;
            }
            if (scrollIndex >= stagedTabs.length)
                scrollIndex = stagedTabs.length - 1;
            while (scrollIndex > 0) {
                const it = tabRepeater.itemAt(scrollIndex);
                if (!it) {
                    Qt.callLater(header.settleScroll);
                    return;
                }
                if (tabRow.width - it.x > tabRowViewport.width)
                    break;
                scrollIndex -= 1;
            }
            header.ensureActiveTabVisible();
        }
        // keyboard tab-cycling (LauncherState.cyclePane) can land on a
        // custom tab that's scrolled out of view - clicking the arrows
        // never touches this (see their onPressed), only a selection
        // change arriving some other way does
        function ensureActiveTabVisible() {
            const idx = stagedTabs.findIndex(t => t.id === LauncherState.settingsTab);
            if (idx < 0)
                return;
            if (idx < scrollIndex) {
                scrollIndex = idx;
                return;
            }
            const it = tabRepeater.itemAt(idx);
            if (!it) {
                Qt.callLater(header.ensureActiveTabVisible);
                return;
            }
            if (it.x + it.width - windowX > tabRowViewport.width)
                scrollIndex = idx;
        }
        Connections {
            target: LauncherState
            function onSettingsTabChanged() { header.ensureActiveTabVisible(); }
        }

        ScrambleText {
            content: "SETTINGS"
            color: Theme.muted
            font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13); letterSpacing: 3 }
        }

        Item {
            id: tabRowArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 24

            Item {
                id: tabRowViewport
                clip: true
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                // inset by rightArrow's own 24px box plus an 8px gap
                // (the same spacing SettingRow uses between its own
                // controls) so a clipped tab label stops short of the
                // arrow with real breathing room, not flush against it
                width: parent.width - 24 - 8

                Row {
                    id: tabRow
                    x: -header.windowX
                    spacing: 26
                    // the fixed clip stays put and the tabs slide behind
                    // it instead, so paging reads as the tabs moving
                    // rather than the window jumping
                    Behavior on x {
                        NumberAnimation { duration: Anim.menu(280); easing.type: Easing.OutCubic }
                    }

                    Repeater {
                        id: tabRepeater
                        model: header.stagedTabs

                        Item {
                            id: tabLink
                            required property var modelData
                            required property int index
                            readonly property bool active: LauncherState.settingsTab === modelData.id
                            // the resting label's width: the links sit in a
                            // Row and carry an underline the width of the
                            // link, both of which would shuffle sideways if
                            // this tracked the noise
                            width: tabLinkText.restWidth
                            height: 24
                            opacity: modelData.phase === "entering" ? 0 : 1

                            Component.onCompleted: {
                                if (modelData.phase === "entering")
                                    tabFadeIn.start();
                                else if (modelData.phase === "exiting")
                                    tabFadeOut.start();
                            }
                            NumberAnimation {
                                id: tabFadeIn
                                target: tabLink
                                property: "opacity"
                                to: 1
                                duration: Anim.menu(220)
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                id: tabFadeOut
                                target: tabLink
                                property: "opacity"
                                to: 0
                                duration: Anim.menu(220)
                                easing.type: Easing.OutCubic
                            }

                            ScrambleText {
                                id: tabLinkText
                                content: tabLink.modelData.label
                                // the links all arrive on one line with the
                                // pane behind them, so nothing else would
                                // stagger them across it (see ClockPage)
                                scrambleDelay: tabLink.index * 45
                                color: tabLink.active ? Theme.fg : Theme.muted
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(14) }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 2
                                radius: Theme.radius(1)
                                color: Theme.accent
                                opacity: tabLink.active ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: Anim.menu(150); easing.type: Easing.OutCubic }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: LauncherState.settingsTab = tabLink.modelData.id
                            }
                        }
                    }
                }
            }

            // same 24x24 box + centered-glyph convention as
            // ui/ResetButton.qml (just without its background), so the
            // glyph's own optical center lands exactly where every
            // ResetButton's does rather than flush against the row's
            // literal edge. Sits outside tabRowViewport entirely, in
            // the margin header leaves against the pane's own edge,
            // rather than overlapping the clipped tabs - so the
            // leftmost tab is always flush left against the viewport's
            // own edge with nothing reserved for this to fade in over
            Item {
                id: leftArrow
                anchors.right: tabRowViewport.left
                anchors.verticalCenter: tabRowViewport.verticalCenter
                width: 24
                height: 24
                opacity: header.canScrollLeft ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation { duration: Anim.menu(180); easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    // Icons.family's glyph sits lower in its em-box
                    // than Theme.fontFamily's does at the same
                    // pixelSize, so centering both boxes on the same
                    // line still reads as the icon sitting low against
                    // the label text next to it
                    anchors.verticalCenterOffset: -2
                    text: Icons.chevronLeft
                    color: leftArrowHover.containsMouse ? Theme.fg : Theme.muted
                    font { family: Icons.family; pixelSize: Theme.fontSize(13) }
                }
                MouseArea {
                    id: leftArrowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: header.canScrollLeft
                    onClicked: header.scrollBy(-1)
                }
            }
            // right edge flush with parent.right, exactly matching
            // where a SettingRow's own ResetButton sits (ResetButton's
            // parent Row is anchored the same way against its 780-wide
            // row) - and tabRowViewport is inset by this box's own
            // width, so a cut-off tab label never renders underneath it
            Item {
                id: rightArrow
                anchors.right: parent.right
                anchors.verticalCenter: tabRowViewport.verticalCenter
                width: 24
                height: 24
                opacity: header.canScrollRight ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation { duration: Anim.menu(180); easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -2
                    text: Icons.chevronRight
                    color: rightArrowHover.containsMouse ? Theme.fg : Theme.muted
                    font { family: Icons.family; pixelSize: Theme.fontSize(13) }
                }
                MouseArea {
                    id: rightArrowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: header.canScrollRight
                    onClicked: header.scrollBy(1)
                }
            }
        }
    }

    Item {
        id: tabViewport
        clip: true
        width: 820
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: header.bottom
        anchors.topMargin: 18
        // constant height (tallest page): switching tabs never
        // moves the pane, shorter pages stay top-aligned
        height: Math.max(generalTab.height, pagesTab.height, animationsTab.height, navigationTab.height, flyoutsTab.height, customTabsMaxHeight)
        // tallest of any custom tab's content column, recomputed
        // whenever one loads/resizes - 0 (a no-op in the Math.max
        // above) when there are none
        readonly property real customTabsMaxHeight: {
            let m = 0;
            for (let i = 0; i < customTabs.count; i++) {
                const c = customTabs.itemAt(i);
                if (c)
                    m = Math.max(m, c.height);
            }
            return m;
        }


        GeneralTab {
            id: generalTab
            slideIndex: 0
            activeIndex: root.tabIndex
        }
        PagesTab {
            id: pagesTab
            slideIndex: 1
            activeIndex: root.tabIndex
        }
        AnimationsTab {
            id: animationsTab
            slideIndex: 2
            activeIndex: root.tabIndex
        }
        NavigationTab {
            id: navigationTab
            slideIndex: 3
            activeIndex: root.tabIndex
        }
        FlyoutsTab {
            id: flyoutsTab
            slideIndex: 4
            activeIndex: root.tabIndex
        }

        Repeater {
            id: customTabs
            model: LauncherState.customSettingsTabs

            Column {
                id: customTab
                required property var modelData
                readonly property int slideIndex: root.tabOrder.indexOf(modelData.pageId)
                // see the built-in tabs' copy of this
                readonly property bool scrambleSuppressed: customTab.slideIndex !== root.tabIndex
                x: 20 + (slideIndex - root.tabIndex) * 840
                // a freshly-appearing tab's slideIndex starts at -1 for
                // one tick - LauncherState.customSettingsTabs (which this
                // Repeater's model is) picks up the page's newly-
                // loaded settingsTab a moment before
                // root.tabOrder, which derives from it, has
                // recomputed to include this pageId - so x's first
                // real value briefly parks off-screen left before
                // jumping to its actual off-screen-right slot once
                // slideIndex corrects. With the Behavior live for that
                // correction, it animates the whole ~4200px hop,
                // sweeping straight through the visible viewport
                // (the "page content flying across the screen" bug).
                // Qt.callLater defers arming the Behavior past that
                // initial settle, so only genuine later tab switches
                // (root.tabIndex changing, not this one-time
                // slideIndex correction) animate.
                property bool animateX: false
                Component.onCompleted: Qt.callLater(() => customTab.animateX = true)
                Behavior on x {
                    enabled: customTab.animateX
                    NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
                }
                spacing: 14

                // the page's own Component - declared inside its
                // file, so it resolves `pibble`/getSetting/etc via
                // that file's own scope, same as any other child of
                // its root item would
                Loader {
                    sourceComponent: customTab.modelData.component
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        onPressed: mouse => {
            if (LauncherState.capturingBind)
                LauncherState.cancelCapture();
            mouse.accepted = false;
        }
    }
}
