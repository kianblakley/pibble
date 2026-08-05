pragma Singleton
import QtQuick
import Quickshell
import "root:/config"

// Motion vocabulary for the whole shell, in one place so a tile in the apps
// grid, a bar in the wallpaper carousel and a custom page's own tiles all move
// alike.
//
// Three independent "off" switches, deliberately not folded into one: the tile
// style (Settings.animStyle === "none") zeroes grid and pane entrances, the
// launch style (Settings.launchAnimation === "none") zeroes the open/close
// reveal, and Settings.hiddenMenuAnimations zeroes the settings pane and the
// power/reboot prompts. Picking one never silently flattens another.
Singleton {
    id: root

    // bloom: staggered spring cascade (default). pop: all tiles spring at once.
    // fade: soft fade, all at once. cascade: fade's soft fade, but staggered
    // like bloom. slide: rows slide up. none: instant.
    readonly property string style: Settings.animStyle

    readonly property real fromScale: root.style === "bloom" || root.style === "pop" ? 0.4 : 1
    readonly property int fromY: root.style === "slide" ? 46 : (root.style === "fade" || root.style === "cascade") ? 6 : root.style === "none" ? 0 : 14
    readonly property int duration: (root.style === "fade" || root.style === "cascade") ? 220 : root.style === "slide" ? 320 : root.style === "none" ? 0 : 400
    readonly property int fadeDuration: root.style === "none" ? 0 : 180
    readonly property int easing: root.style === "bloom" || root.style === "pop" ? Easing.OutBack : Easing.OutCubic

    // Exit mirrors entrance: tiles spring back out toward the same from-state
    // (fromScale/fromY) they sprang in from, so "bloom"/"pop" (bounce) read as
    // the reverse of their entrance instead of all sharing one
    // bounce-then-shrink shape.
    readonly property bool outBounce: root.style === "bloom" || root.style === "pop"
    readonly property int outDuration: (root.style === "fade" || root.style === "cascade") ? 180 : root.style === "slide" ? 260 : 320
    readonly property int outEasing: root.outBounce ? Easing.InQuad : Easing.InCubic

    // Grid/pane entrance duration: zeroed by the tile style alone.
    function tile(ms: int): int {
        return root.style === "none" ? 0 : ms;
    }
    // Launcher open/close reveal duration: zeroed by the launch style alone.
    function launch(ms: int): int {
        return Settings.launchAnimation === "none" ? 0 : ms;
    }
    // Settings pane and power/reboot prompt duration: zeroed by
    // Settings.hiddenMenuAnimations alone — neither is a grid.
    function menu(ms: int): int {
        return Settings.hiddenMenuAnimations ? ms : 0;
    }

    function stagger(slot: int, cols: int, slideStep: int): int {
        if (!root.staggering)
            return 0;
        switch (root.style) {
        case "bloom":
        case "cascade":
            return slot * 35;
        case "slide":
            return Math.floor(slot / cols) * slideStep;
        }
        return 0;
    }

    // Tile stagger applies when a pane opens or a grid page turns, not on every
    // keystroke — re-staggering while filtering makes tiles blink out and pause.
    property bool staggering: false
    function beginStagger(): void {
        root.staggering = true;
        staggerWindow.restart();
    }
    // Arm the stagger when a navigation moves between pages (guarding the zero
    // page-size case the page getters guard against too).
    function staggerIfPageChanged(pageSize: int, before: int, after: int): void {
        if (pageSize > 0 && Math.floor(before / pageSize) !== Math.floor(after / pageSize))
            root.beginStagger();
    }

    Timer {
        id: staggerWindow
        interval: 600
        onTriggered: root.staggering = false
    }
}
