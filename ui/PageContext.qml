import QtQuick
import "root:/config"
import "root:/launcher"
import "root:/services"

// ---------- custom page contract ----------
// pibble hands one of these to every custom page's root item as a `pibble`
// property. Declare the property and it's yours:
//
//   Item {
//       id: root
//       property var pibble
//   }
//
// It's passed as an initial property while the page is created, *before*
// any of the page's own bindings first evaluate - so from where a page
// sits it is never null: no `pibble ?` guards, and Component.onCompleted
// can use it freely. A page that doesn't declare the property still loads
// (one warning line in the journal); it just can't see any of this. Every
// member below is optional - use whichever ones you want.
//
// Why this exists: a page can't otherwise know things only the launcher
// keeps track of - which pane is showing, what's being typed, where
// keyboard focus is - or reproduce the launcher's own entrance animation
// and colors by hand. This is that missing piece. The animation half of
// the contract is a type of its own, PageTile (ui/PageTile.qml): reach it
// with `import "root:/ui" as Pibble` and wrap anything tile-shaped in a
// `Pibble.PageTile` to give it the same pop-in the built-in grids play.
//
// It's not a sandbox. A page can `import "root:/config"` or
// `"root:/services"` and reach shell internals directly if it really
// wants to - nothing stops it. The difference is that only the members
// below, plus PageTile, are promised to keep working after a pibble
// update; anything reached by importing shell internals directly can
// break silently (there's no compile step, so a broken reference just
// shows up as a runtime warning, not a build error).
//
// A page sizes itself: pibble just centers a window around whatever
// width/height the page reports (420x320 if it reports none) - nothing
// clips, so a page that's too big just overlaps.
//
// Pages can also hand something back to pibble, the other direction: a
// `settingsTab` Component property on the same root item gives the page
// its own tab in Settings, labeled after the page's folder name. The
// Component is declared inside the page's own file, so everything in it
// reaches `pibble` and the rest of the page through ordinary QML scope.
QtObject {
    id: root

    readonly property color accentColor: Theme.accent
    readonly property color textColor: Theme.fg
    readonly property color mutedTextColor: Theme.muted
    // the shell's text font
    readonly property string font: Theme.fontFamily
    // A pixel size that tracks Settings > General > "Font size": px(14) is
    // 14 at scale 1, and grows and shrinks with the setting. Use it for
    // text, and for anything else that should follow along - padding, tile
    // size, whatever.
    function px(size: real): int {
        return Math.round(size * Settings.fontScale);
    }
    // The raw multiplier behind px(), for math px() can't express. Most
    // pages only ever need px().
    readonly property real fontScale: Settings.fontScale
    // Corner rounding, filtered through Settings > General > "Rounded
    // corners": hands back the radius you pass while that's on, and 0 while
    // it's off. Bind your corners through it - `radius: pibble.radius(8)` -
    // and your page squares itself alongside the rest of the shell instead
    // of being the one thing left rounded.
    function radius(px) {
        return Theme.radius(px ?? 0);
    }
    // Three shades of the accent color, pre-mixed to the same numbers the
    // built-in tile grids (Apps/Walls/Clips) use, so your own tiles match:
    // tileColor = idle background, activeTileColor = a stronger version for
    // hover/selected/highlighted, borderColor = the outline color. Pick
    // whatever corner-radius suits your tile - the built-ins vary theirs
    // too - and put it through radius() above so it honors the
    // rounded-corners setting.
    readonly property color tileColor: Qt.alpha(Theme.accent, 0.11)
    readonly property color activeTileColor: Qt.alpha(Theme.accent, 0.22)
    readonly property color borderColor: Qt.alpha(Theme.accent, 0.33)
    // A glyph from pibble's own icon font, by name - draw it in `iconFont`:
    //   Text { text: pibble.icon("check"); font.family: pibble.iconFont }
    // Only the names in the table below are promised (pibble is free to
    // redraw what a name maps to - the names are what's stable), and an
    // unknown name hands back "" so a typo renders as nothing rather than
    // tofu. For any icon beyond these, `iconFont` is already loaded: find
    // the codepoint you need by opening the font (fonts/) in a codepoint
    // viewer like FontForge, or load a font of your own.
    function icon(name: string): string {
        return root.iconTable[name] ?? "";
    }
    // the catalogue icon() answers from - kept as a plain table so the
    // valid names can be read straight off it
    readonly property var iconTable: ({
        "chevron-left": Icons.chevronLeft,
        "chevron-right": Icons.chevronRight,
        "arrow-left": Icons.arrowLeft,
        "arrow-right": Icons.arrowRight,
        "arrow-up": Icons.arrowUp,
        "arrow-down": Icons.arrowDown,
        "check": Icons.check,
        "plus": Icons.plus,
        "trash": Icons.trash,
        "settings": Icons.settings,
        "refresh": Icons.refresh,
        "copy": Icons.copy,
        "bell": Icons.bell,
        "warning": Icons.alertTriangle
    })
    // Family name of pibble's own icon font, for drawing icon()'s glyphs
    // (or any codepoint you dug up yourself). Already loaded once by pibble,
    // so using this instead of your own FontLoader saves loading the same
    // file twice.
    readonly property string iconFont: Icons.family
    // True while this page is the one on screen, false the moment you tab
    // or escape away from it. If you just want to read it, use it straight
    // from pibble. If you want to run code when it changes, mirror it onto
    // your own root item first, the same way launcherOpen is used below:
    //   readonly property bool pageActive: pibble.pageActive
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
    readonly property string textInput: LauncherState.query
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
    // Hands back `source` as it looks partway through the scramble pibble's
    // own labels play as a page opens, so your text resolves alongside
    // them. Use it *in a binding*, never as a one-time assignment - it
    // reads the shared clock behind the effect, so the binding re-runs
    // itself for the length of the run and settles on the real string:
    //   Text { text: pibble.scramble(modelData.name, index, 3) }
    // `slot`/`cols` stagger several labels one after another, exactly as
    // PageTile's do - leave them out for a single label. A label sitting
    // *on* a PageTile should use that tile's scrambled() instead, which is
    // this with the tile's own slot/cols already filled in, so the label
    // and the tile land together.
    //
    // Binding through this *is* the opt-in: custom pages have no chip under
    // Settings > Animations > "Text scramble" - only the labels you bind
    // here take part, so asking is consenting (see Anim.scrambleAllowed).
    // The run still rides the user's tile style: "none" under Settings >
    // Animations > "Tile animations" leaves the entrance undecorated, and
    // this hands back `source` untouched then - as it does whenever nothing
    // is running - so it's always safe to bind through.
    function scramble(source, slot, cols) {
        const text = source ?? "";
        if (!Anim.scrambleActive || !root.pageActive)
            return text;
        const s = slot ?? 0;
        // staggerOffset, not stagger: this is re-read every frame of the run,
        // and stagger()'s window closing partway through would drop the offset
        // to 0 under everything still waiting on it (see Anim).
        //
        // Measured from this run's start rather than the clock's: the clock
        // carries on across a run that begins while it is still going (a page
        // opened right behind another), where a raw elapsed would hand a page
        // arriving on the second run text that had already resolved on the
        // first.
        return Anim.scrambled(text, Anim.scrambleElapsed - Anim.scrambleRunStarted - Anim.staggerOffset(s, cols ?? 1, 60), (Anim.scrambleRun << 8) ^ (s * 31 + text.length), 0);
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
    // Reading through a binding is live: the binding re-runs whenever any
    // page saves, so a property bound through this follows setSetting() -
    // and hand-edits of settings.json picked up by the file watcher - on
    // its own.
    function getSetting(key: string, fallback) {
        const store = (Settings.customPageData ?? {})[pageId];
        return store && key in store ? store[key] : fallback;
    }
    // Internal only - not something a page is meant to read. It's how
    // getSetting/setSetting/pageActive know which page they're talking
    // about, set once by CustomPageHost when it creates this object. It
    // can't be `readonly` (something outside has to set it), but nothing
    // should change it after that.
    required property string pageId
}
