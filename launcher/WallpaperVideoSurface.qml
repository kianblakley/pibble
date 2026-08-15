import QtQuick
import "root:/config"
import "root:/services"

// The only way anything reaches WallpaperVideoPool, and the reason QtMultimedia
// stays an optional dependency.
//
// Naming the pool as a type would have Qt resolve its `import QtMultimedia`
// while compiling *this* document, and a module that isn't installed fails the
// document that imports it plus everything up the chain - so a machine without
// qtmultimedia lost the whole shell rather than just live previews. A Loader
// takes the path at runtime instead, where a missing module is a warning and a
// null item. Nothing else may instantiate the pool directly.
//
// Every property below is the pool's own, forwarded unchanged; see it for what
// each one means.
Item {
    id: root

    property string current: ""
    property bool live: false
    property real surfaceX: 0
    property real surfaceY: 0
    property real surfaceWidth: root.width
    property real surfaceHeight: root.height
    property bool warming: false

    // A failed load is the one place a missing *module* is knowable - the
    // pool's own MediaPlayer errors can't report it, since with no module there
    // is no player to raise them - but it is knowable far too early to say so.
    // Two things hold the alert back until a preview is actually wanted:
    //
    //   - a dependency this optional is only worth reporting once it costs
    //     something. A folder with no video in it, or previews switched off,
    //     loses nothing by the module being absent.
    //   - nothing raised while this is being constructed is deliverable at all.
    //     pibble is its own notification server (NotificationFlyout owns it),
    //     and it claims org.freedesktop.Notifications as the shell builds, so a
    //     notify-send from here races that registration and lands nowhere.
    //     Wallpapers.list is filled by a scan process, so waiting on it clears
    //     the whole of startup rather than betting on an ordering.
    readonly property bool wantsVideo: Settings.wallpaperLive && Wallpapers.list.some(w => w.video)
    onWantsVideoChanged: root.reportIfUnavailable()
    function reportIfUnavailable(): void {
        if (root.wantsVideo && pool.status === Loader.Error)
            Notifier.mediaModuleMissing();
    }

    Loader {
        id: pool
        anchors.fill: parent
        source: "WallpaperVideoPool.qml"
        onStatusChanged: root.reportIfUnavailable()
    }

    // Pushed through Binding rather than declared on the pool: a Loader can't
    // carry its item's properties, and the item doesn't exist until the module
    // has resolved (and never, if it doesn't). A Binding onto a null target is
    // a no-op that applies itself if the target turns up.
    Binding { target: pool.item; property: "current"; value: root.current }
    Binding { target: pool.item; property: "live"; value: root.live }
    Binding { target: pool.item; property: "surfaceX"; value: root.surfaceX }
    Binding { target: pool.item; property: "surfaceY"; value: root.surfaceY }
    Binding { target: pool.item; property: "surfaceWidth"; value: root.surfaceWidth }
    Binding { target: pool.item; property: "surfaceHeight"; value: root.surfaceHeight }
    Binding { target: pool.item; property: "warming"; value: root.warming }
}
