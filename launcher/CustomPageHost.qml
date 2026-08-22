import QtQuick
import "root:/services"
import "root:/ui"

// One host per enabled custom page, Loader-ing the user's own main.qml as
// its content and handing it a PageContext.
//
// Kept alive (active whenever the page itself is switched on) rather than
// lazy-loaded to the current pane, so a page's own state - timers, scroll
// position, whatever it wants to hold onto - survives Tab-cycling away and
// back, same as the volume OSD.
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

    required property var modelData

    // Raised once the page's own root item exists, so LauncherWindow can
    // refresh the set of pages contributing a Settings tab.
    signal loaded
    anchors.centerIn: parent
    width: loader.item && loader.item.width > 0 ? loader.item.width : 420
    height: loader.item && loader.item.height > 0 ? loader.item.height : 320
    transform: Translate {
        y: LauncherState.powerPull - LauncherState.rebootPull
    }
    opacity: 0.004
    visible: modelData.on && LauncherState.pane === modelData.id

    // fresh context per page, not shared - see PageContext
    readonly property var ctx: PageContext {
        pageId: root.modelData.id
    }
    // exposed so LauncherState.customSettingsTabs (a plain computed
    // property, not something Loader-internal) can react to
    // this page loading/unloading without reaching into the
    // Repeater's delegates itself
    readonly property var pageItem: loader.item

    Connections {
        target: LauncherState
        function onPaneChanged() {
            if (LauncherState.pane === root.modelData.id)
                enterAnim.restart();
        }
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Anim.tile(200); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; from: 0.9; to: 1; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
        NumberAnimation { target: root; property: "anchors.verticalCenterOffset"; from: 40; to: 0; duration: Anim.tile(500); easing.type: Easing.OutBack; easing.overshoot: 1.8 }
    }

    Loader {
        id: loader
        anchors.centerIn: parent
        // modelData.on can only be true for a real (non-
        // broken) entry - see LauncherState.toggleUploadedPage - but
        // this is also a settings.json value, hand-editable
        // like any other, so the broken check is repeated
        // here rather than trusted from there
        active: root.modelData.on && !root.modelData.broken
        // setSource with initial properties rather than a `source:` binding
        // plus an assignment in onLoaded: this way `pibble` is already set
        // when the page's own bindings first evaluate, so a page never sees
        // it null and needs no guards (the whole contract leans on that -
        // see PageContext). The initial properties survive the Loader
        // sitting inactive, and a page that doesn't declare `pibble` still
        // loads, with a one-line "non-existent property" warning. Set once
        // rather than re-derived: the path can't change under this delegate,
        // since any edit to uploadedPages rebuilds the Repeater outright.
        //
        // Every page's entry point is <dir>/main.qml (see CustomPages' scan
        // and the CustomPages.dir comment for how it reaches its own sibling
        // files - this Loader doesn't care how many files the page is split
        // across).
        Component.onCompleted: loader.setSource(Qt.resolvedUrl(root.modelData.path + "/main.qml"), { pibble: root.ctx })
        onLoaded: root.loaded()
        // a page that fails to parse/instantiate just never
        // shows (there's no compile step, so the real QML
        // error only lands in the terminal/journal like any
        // other) - this only tells the user which one so
        // they know where to look
        onStatusChanged: {
            if (status === Loader.Error)
                Notifier.error(Strings.tr("Custom page failed to load"), root.modelData.label);
        }
    }
}
