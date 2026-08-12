import QtQuick
import "root:/config"
import "root:/launcher"
import "root:/services"

// ---------- custom page contract ----------
// pibble hands one of these to every custom page's root item, as a
// `pibble` property, if the page declares one. Every member below is
// optional - use whichever ones you want.
//
// Why this exists: a page can't otherwise know things only the launcher
// keeps track of - which pane is showing, what's being typed, where
// keyboard focus is - or reproduce the launcher's own tile-pop-in
// animation and colors by hand. This is that missing piece.
//
// It's not a sandbox. A page can `import "root:/config"` or
// `"root:/services"` and reach shell internals directly if it really
// wants to - nothing stops it. The difference is that only the members
// below are promised to keep working after a pibble update; anything
// reached by importing shell internals directly can break silently
// (there's no compile step, so a broken reference just shows up as a
// runtime warning, not a build error).
//
// No icon glyphs here - pibble's own icon codepoints (which glyph means
// what) are an internal detail of how pibble draws itself, not
// something a page should depend on. A page that wants icons uses
// `iconFont` below (pibble's own vendored font, already loaded) or
// loads its own font, then finds the codepoints it needs by opening
// that font in a codepoint viewer like FontForge - see
// calendar.example's chevron buttons for a worked example.
//
// A page sizes itself: pibble just centers a window around whatever
// width/height the page reports (420x320 if it reports none) - nothing
// clips, so a page that's too big just overlaps.
//
// Pages can also hand something back to pibble, the other direction:
// a `settingsTab` Component property on the same root item gives the
// page its own tab in Settings, labeled after the page's folder name.
QtObject {
    id: root

    readonly property color accent: Theme.accent
    readonly property color textColor: Theme.fg
    readonly property color secondaryTextColor: Theme.muted
    // the shell's text font
    readonly property string font: Theme.fontFamily
    // Family name of pibble's own icon font. It's already loaded once by
    // pibble itself, so using this instead of your own FontLoader saves
    // loading the same file twice. No codepoints, though - see the header
    // comment above for why you have to find those yourself.
    readonly property string iconFont: Icons.family
    // The multiplier behind Settings > General > "Font size" - not a ready-
    // made pixel size. Turn it into one yourself: Math.round(px * fontScale).
    // Use it for anything you want to grow/shrink with that setting, not
    // just text - padding, tile size, whatever.
    readonly property real fontScale: Settings.fontScale
    // Three shades of the accent color, pre-mixed to the same numbers the
    // built-in tile grids (Apps/Walls/Clips) use, so your own tiles match:
    // tileBg = idle background, tileBgActive = a stronger version for
    // hover/selected/highlighted, tileBorder = the outline color. Pick
    // whatever corner-radius suits your tile - the built-ins vary theirs too.
    readonly property color tileBg: Qt.alpha(Theme.accent, 0.11)
    readonly property color tileBgActive: Qt.alpha(Theme.accent, 0.22)
    readonly property color tileBorder: Qt.alpha(Theme.accent, 0.33)
    // True while this page is the one on screen, false the moment you tab
    // or escape away from it. If you just want to read it, use it straight
    // from pibble. If you want to run code when it changes, mirror it onto
    // your own root item first, the same way launcherOpen is used below:
    //   readonly property bool pageActive: pibble ? pibble.pageActive : false
    //   onPageActiveChanged: ...
    // That works with no extra setup, because QML fires onPageActiveChanged
    // for your own property regardless of whether its value came from a
    // binding or a direct assignment.
    readonly property bool pageActive: LauncherState.pane === pageId
    // True while the launcher itself is open at all, not just your page.
    readonly property bool launcherOpen: LauncherState.shown
    // Whatever the user's currently typed into pibble's hidden search box.
    // Read-only - watch it to filter your own content, the same way the
    // built-in Apps/Walls/Clips grids filter theirs. It clears itself every
    // time the launcher opens or the pane changes, so you don't have to.
    readonly property string searchText: LauncherState.query
    // Gives keyboard focus back to pibble's hidden search box. Only call
    // this if your page grabbed focus itself (e.g. put its own TextInput in
    // front and called forceActiveFocus() on it) - pibble's own keybinds,
    // Escape included, only work while its search box has focus, so a page
    // that takes focus and never gives it back can leave the user stuck.
    // Call this from whatever means "done editing" in your field - usually
    // Keys.onEscapePressed.
    function releaseFocus(): void {
        LauncherState.focusInput();
    }
    // Makes an item pop in with the same little spring animation the built-in
    // grids use: starts smaller/lower/invisible, then eases into place. Call
    // it once per item, any time you want it to (re)play - pibble owns the
    // animation itself, so you never have to touch one directly. `slot`/
    // `cols` stagger several items one after another (which position, out of
    // how many columns) - leave them out for a single tile with no stagger.
    function tileIn(item, slot, cols) {
        if (!item)
            return;
        const s = slot ?? 0;
        const c = cols ?? 1;
        pruneTiles();
        let rec = tileRegistry.find(r => r.item === item);
        if (!rec) {
            // a Translate in transform, not item.y itself, so this
            // never fights whatever actually positions the item
            // (anchors, a Row/Column, explicit bindings, ...)
            const offset = tileOffsetFactory.createObject(item, {});
            item.transform = (item.transform ?? []).concat([offset]);
            const spring = tileSpringFactory.createObject(item, { pibbleItem: item, pibbleOffset: offset, pibbleSlot: s, pibbleCols: c });
            rec = { item, spring };
            tileRegistry.push(rec);
        } else {
            rec.spring.pibbleSlot = s;
            rec.spring.pibbleCols = c;
        }
        rec.spring.restart();
    }
    // Internal only - not something a page is meant to read. It's how
    // getSetting/setSetting/pageActive know which page they're talking
    // about, set once by CustomPageHost when it creates this object. It
    // can't be `readonly` (something outside has to set it), but nothing
    // should change it after that.
    required property string pageId
    // Internal bookkeeping for tileIn() - remembers which items to
    // re-spring the next time this page becomes active again.
    property var tileRegistry: []
    // If a page's tile Repeater changes size, old delegates get destroyed
    // and new ones take their place - so this list can end up pointing at
    // items that no longer exist. Checking `r.item` alone doesn't catch
    // that (a destroyed item still reads as truthy), so use Qt.isQtObject
    // instead, and always prune before looping over the list - touching a
    // destroyed item throws, which would cut the loop short.
    function pruneTiles(): void {
        tileRegistry = tileRegistry.filter(r => Qt.isQtObject(r.item));
    }
    onPageActiveChanged: {
        if (!pageActive)
            return;
        pruneTiles();
        tileRegistry.forEach(r => r.spring.restart());
    }
    readonly property Component tileOffsetFactory: Component {
        Translate {}
    }
    readonly property Component tileSpringFactory: Component {
        SequentialAnimation {
            id: spring
            property var pibbleItem: null
            property var pibbleOffset: null
            property int pibbleSlot: 0
            property int pibbleCols: 1
            PropertyAction { target: spring.pibbleItem; property: "opacity"; value: 0 }
            PropertyAction { target: spring.pibbleItem; property: "scale"; value: Anim.fromScale }
            PropertyAction { target: spring.pibbleOffset; property: "y"; value: Anim.fromY }
            PauseAnimation { duration: Anim.stagger(spring.pibbleSlot, spring.pibbleCols, 60) }
            ParallelAnimation {
                NumberAnimation { target: spring.pibbleItem; property: "opacity"; to: 1; duration: Anim.fadeDuration; easing.type: Easing.OutCubic }
                NumberAnimation { target: spring.pibbleItem; property: "scale"; to: 1; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
                NumberAnimation { target: spring.pibbleOffset; property: "y"; to: 0; duration: Anim.duration; easing.type: Anim.easing; easing.overshoot: 2.2 }
            }
        }
    }
    // A page's own little save file - key/value, whatever JSON-serializable
    // value you want. Every page gets its own separate namespace, so two
    // pages can both use the key "count" without clashing. Cleared only if
    // this page itself gets trashed.
    function setSetting(key: string, value): void {
        const all = Object.assign({}, Settings.customPageData ?? {});
        all[pageId] = Object.assign({}, all[pageId] ?? {}, { [key]: value });
        Settings.customPageData = all;
        Settings.save();
    }
    function getSetting(key: string, fallback) {
        const store = (Settings.customPageData ?? {})[pageId];
        return store && key in store ? store[key] : fallback;
    }
}
