import QtQuick
import "root:/config"
import "root:/launcher"
import "root:/services"

// ---------- custom page contract ----------
// One of these is created per enabled custom page (see the "Custom
// pages" render block below) and handed to the loaded file's root item
// as `pibble`, if it declares that property — every member here is
// optional to use. Properties are live bindings (theme/anim-style
// changes propagate the same as they do to any built-in pane); the
// functions are the only sanctioned way in, since Settings/root/win
// themselves are never exposed — a page can't reach into settings it
// doesn't own or call internal launcher functions.
//
// The other direction — a page contributing to pibble, rather than the
// other way round — goes through one more property on the same root
// item, read by LauncherState.customSettingsTabs (see there for details) rather
// than written by PageContext: a `settingsTab` Component gets the page
// its own tab in Settings, alongside General/Pages/Keybindings/
// Flyouts, labeled after the page's own folder name (capitalized) —
// not something the page declares itself.
// A page gets exactly this and nothing else: enough to theme itself
// consistently and persist its own data. Some things that used to
// live here (close/openSettings/notify/copyToClipboard, the
// animation-parameter set, a `ti` icon-glyph map, iconFont itself,
// surface) are gone because they were reachable another way already
// (the keybind closes the launcher; notify-send/Quickshell.clipboardText
// are plain Quickshell, no wrapper needed), asked a page to reproduce
// pibble's own visual rhythm exactly (which isn't something most pages
// need and is cheap for the ones that do want it to just build
// themselves off `active`), or (iconFont, surface) didn't correspond
// to any real per-page use once the built-in icon glyph map was cut.
// fill/fillActive/border below are the opposite case: kept (and
// precomputed, not left as bare alpha numbers) because there's no way
// for a page to discover or reproduce these specific values other than
// reading this file.
QtObject {
    id: root

    // `required` (must be supplied at construction, see the "Custom
    // pages" render block below) but not `readonly` — QML doesn't
    // allow both on the same property. Stays mutable after
    // construction as a result; nothing a page does should ever
    // reassign it, since getSetting/setSetting's namespacing depends
    // on it never changing after the host sets it.
    required property string pageId
    readonly property color accent: Theme.accent
    readonly property color fg: Theme.fg
    readonly property color muted: Theme.muted
    // the shell's text font
    readonly property string font: Theme.fontFamily
    readonly property real fontScale: Settings.fontScale
    // the fill/border colors the built-in Apps/Walls/Clips grids and
    // Settings buttons round their tiles with — precomputed, not a
    // bare alpha number, since the number alone is only ever used one
    // way (Qt.alpha(accent, thatNumber)) and precomputing means a
    // future change to the actual formula (not just the number) would
    // still reach every page using these, not just ones re-derived by
    // hand. The built-ins' own radius ranges 8-19px scaled to tile
    // size, not one constant, so there's no equivalent radius property —
    // pick whatever radius suits your own tile.
    readonly property color fill: Qt.alpha(Theme.accent, 0.11)
    readonly property color fillActive: Qt.alpha(Theme.accent, 0.22)
    readonly property color border: Qt.alpha(Theme.accent, 0.33)
    // true from the moment this page becomes the one on screen until
    // it's navigated away from (Tab, Escape, picking another page) —
    // mirrors what every built-in pane gates its own entrance
    // animations on (see LauncherState.pane). Also written directly onto the
    // page's own root item (if it declares `active`), since a
    // binding alone can't run code — see that property's own comment
    // in the "Custom pages" render block below.
    readonly property bool active: LauncherState.pane === pageId
    readonly property bool shown: LauncherState.shown
    // Live text from pibble's own hidden search field (see win's
    // TextInput, id: input) — the same source the built-in Apps/Walls/
    // Clips grids filter their own `matches` off. Read-only: a page
    // can watch what the user's typing to filter its own content the
    // same way the built-ins do, without ever taking keyboard focus
    // itself. Cleared on every pane switch and launcher (re)open (see
    // LauncherState.setPane/resetState), same as it is for the built-ins.
    readonly property string searchText: LauncherState.query
    // Hands keyboard focus back to pibble's hidden search field. Only
    // needed if this page put its own focusable item (a TextInput,
    // typically) in front of it — LauncherState.input is otherwise always
    // focused, which is what lets Tab/Escape/etc keep working from any
    // page and lets searchText above stay live. A page that grabs
    // focus (e.g. a TextInput's own MouseArea/TapHandler calling
    // forceActiveFocus()) and never calls this back can leave the
    // user stuck: pibble's own keybinds (Escape included) are handled
    // inside LauncherState.input's Keys.onPressed, which only fires while it's
    // focused. Call this from whatever signals "done editing" for your
    // field — typically Keys.onEscapePressed, same as the Settings
    // pane's own text fields do internally.
    function releaseFocus(): void {
        LauncherState.focusInput();
    }
    // One call gives an item the built-in grids' own tile-entrance
    // rhythm (see Settings.animStyle, "Transitions" in Settings > Grids):
    // pop in from a smaller/lower/transparent starting state, staggered
    // by `slot` among `cols` columns if the style calls for a stagger.
    // Everything (the animation objects, restarting it whenever this
    // page becomes active again) is owned here — a page never touches
    // a SequentialAnimation or hears about Anim.fromScale/animDur/
    // etc directly, so it can't get any of that wrong. `slot`/`cols`
    // default to 0/1 (no stagger) for a page with just one tile; pass
    // them for a real grid the same way the built-ins index their own
    // (row-major, 0-based).
    function tileIn(item, slot, cols) {
        if (!item)
            return;
        const s = slot ?? 0;
        const c = cols ?? 1;
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
    // tileIn() bookkeeping below — not part of the documented pibble
    // contract (see DOCS.md), just what tileIn() itself needs to
    // remember which items to re-spring when this page becomes active
    // again (see onActiveChanged).
    property var tileRegistry: []
    onActiveChanged: if (active)
        tileRegistry.forEach(r => r.spring.restart())
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
    // per-page persistence: a page only ever sees its own namespace
    // (Settings.customPageData[pageId]), keyed by whatever string the page
    // chooses — arbitrary JSON-serializable values, same as any Settings.*
    // setting. Survives reinstalling/renaming other pages; only wiped if
    // the page itself is trashed (see trashPage()).
    function getSetting(key: string, fallback) {
        const store = (Settings.customPageData ?? {})[pageId];
        return store && key in store ? store[key] : fallback;
    }
    function setSetting(key: string, value): void {
        const all = Object.assign({}, Settings.customPageData ?? {});
        all[pageId] = Object.assign({}, all[pageId] ?? {}, { [key]: value });
        Settings.customPageData = all;
        Settings.save();
    }
}
