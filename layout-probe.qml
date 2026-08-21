// Headless layout check for the settings pane. Not part of the shell - nothing
// imports it and `qs -p .` never loads it. Run it through ./layout-probe.
//
// It builds the real settings tabs, in a real Quickshell engine with the real
// fonts, and measures what comes out - without mapping a single surface, so
// none of it appears on screen. That is the point: the alternative is
// restarting the daemon and toggling the launcher over whatever the user is
// doing, and a language sweep is eight of those.
//
// What it reports, per tab:
//   ELIDE    a label wider than the box it was given, i.e. text cut off
//   OVERLAP  two blocks painting over each other
//   TOOCLOSE two blocks not overlapping but with no gap left between them
//   OVERFLOW a block outside the 780px column
//
// PIBBLE_PROBE_DUMP=<tab name> additionally prints every block that tab lays
// out with its rect, which is how you find out what a finding collided with.
//
// It cannot see anything that isn't text - a swatch, a tick box, a preview -
// so a clean run is "no label is truncated or sitting on another label", not
// "the pane is beautiful". Look at it for that.
//
// Two things about measuring with no window, both of which decide the shape of
// this file. A positioner lays its children out once at creation and after
// that only on polish, and polish is driven by a window - so everything has to
// be *final before the tabs are built*, and nothing may be re-measured after.
// Hence:
//
//   - the language is set first, then the tabs are created (by activating the
//     Loaders below), then measured. Built first and relabelled after, every
//     Row would still be holding its English positions.
//   - Metrics is touched first too. Its widths come from hidden Text items
//     whose implicitWidth settles a beat after they are created, and a Row
//     built while that is still in flight keeps the stale gap.
import QtQuick
import Quickshell
import "root:/config"
import "root:/launcher/Settings"
import "root:/services"
import "root:/ui"

ShellRoot {
    id: probe

    readonly property string outPath: Quickshell.env("PIBBLE_PROBE_OUT") || "/tmp/pibble-layout-probe.txt"
    readonly property string lang: Quickshell.env("PIBBLE_PROBE_LANG") || "en"
    // the column every tab lays out into (see any tab's `width: 780` rows)
    readonly property real column: 780

    property var report: []
    function note(s: string): void {
        probe.report.push(s);
    }

    // Whether this item paints text the user could actually see: a Text (duck
    // typed, since ScrambleText is one and so is a bare Text) that isn't empty
    // and isn't hidden by itself or by anything above it.
    function isShownText(item: var, root: var): bool {
        if (item.contentWidth === undefined || item.text === undefined || String(item.text).trim().length === 0)
            return false;
        // TextInput/TextEdit hold the user's own string, scroll inside a clip
        // and are routinely wider than their box on purpose - none of which is
        // a layout question about pibble's own labels
        if (item.cursorPosition !== undefined)
            return false;
        for (let i = item; i && i !== root.parent; i = i.parent) {
            if (i.visible === false || i.opacity < 0.01)
                return false;
        }
        return true;
    }
    // The animation previews are miniature mock-ups of other parts of the
    // shell - a fake notification card, a fake grid - drawn at a fraction of
    // scale. Their "labels" are decoration and routinely sit on top of each
    // other by design, so the whole subtree is skipped. Duck typed on the two
    // properties every AnimPreview takes.
    function isPreview(item: var): bool {
        return item.playDelay !== undefined && item.baseWidth !== undefined;
    }

    // A ChipRow delegate: a tick box and its word, laid out as one unit. Taken
    // whole rather than descended into, because the box is half of what the
    // chip occupies and it is not text - a hint running into the box rather
    // than into the word is exactly the collision this probe exists to catch,
    // and a text-only sweep cannot see it. Duck typed on the two properties
    // the delegate declares.
    function isChip(item: var): bool {
        return item.on !== undefined && item.label !== undefined;
    }

    function collect(item: var, root: var, out: var): void {
        if (probe.isPreview(item))
            return;
        if (probe.isChip(item) && probe.isShownText(item.children[1], root)) {
            const c = item.mapToItem(root, 0, 0);
            out.push({
                text: "☐ " + item.label,
                x: c.x,
                y: c.y,
                w: item.width,
                h: item.height,
                icon: false,
                // measured against the label's own box, not the chip's: the
                // chip is the tick box plus the word, and only the word elides
                cw: probe.naturalWidth(item.children[1]),
                boxW: item.children[1].width,
                clipped: probe.naturalWidth(item.children[1]) > item.children[1].width + 0.5,
                elides: true
            });
            return;
        }
        if (probe.isShownText(item, root)) {
            const p = item.mapToItem(root, 0, 0);
            out.push({
                text: String(item.text),
                x: p.x,
                y: p.y,
                w: item.width,
                h: item.height,
                // a glyph from the icon font: its box is drawn around it by
                // whatever holds it (a stepper's 28px button, a 24px reset),
                // so it is context for a finding but never itself one
                icon: String(item.font.family) === String(Icons.family),
                // a Text laid out into less width than its string needs: with
                // an elide set that is a truncation, without one it is a label
                // painting straight past its own box
                cw: probe.naturalWidth(item),
                boxW: item.width,
                clipped: probe.naturalWidth(item) > item.width + 0.5,
                elides: item.elide !== undefined && item.elide !== Text.ElideNone
            });
        }
        for (let i = 0; i < item.children.length; i++)
            probe.collect(item.children[i], root, out);
    }

    // How wide this label's whole string wants to be. Not contentWidth on its
    // own: once a Text elides, contentWidth is the width of the *elided*
    // string, which is by definition no wider than the box - so the one
    // measurement that would reveal a truncation is the one Qt stops
    // reporting the moment there is one. ScrambleText knows its resting width
    // (it measures the string separately, for the noise), and the two together
    // catch both failures: a string too long for its cap, and a box sized a
    // hair under what Qt actually lays the string out to.
    function naturalWidth(item: var): real {
        return Math.max(item.restWidth === undefined ? 0 : item.restWidth, item.contentWidth);
    }

    function describe(it: var): string {
        return `"${it.text}" [${it.x.toFixed(0)}..${(it.x + it.w).toFixed(0)}]`;
    }

    function check(name: string, root: var): void {
        const items = [];
        probe.collect(root, root, items);
        for (const it of items) {
            if (it.icon)
                continue;
            if (it.clipped)
                probe.note(`  ELIDE    ${name}: "${it.text}" wants ${it.cw.toFixed(1)}px, has ${it.boxW.toFixed(1)}px${it.elides ? "" : " (no elide - it paints past its box)"}`);
            if (it.x < -0.5 || it.x + it.w > probe.column + 0.5)
                probe.note(`  OVERFLOW ${name}: ${probe.describe(it)} outside 0..${probe.column}`);
        }
        // Two blocks sharing a line. Overlapping is the obvious failure, but
        // merely touching is one too: these are two separate controls and the
        // pane reads them as one run of text the moment the gap closes. The
        // clearance below is a little under the 8px gap SettingRow keeps
        // between its own controls, so a row that is merely tight doesn't
        // report while one that has actually run out of room does.
        const clearance = 6;
        for (let a = 0; a < items.length; a++) {
            for (let b = a + 1; b < items.length; b++) {
                const p = items[a], q = items[b];
                if (p.icon && q.icon)
                    continue;
                // vertically apart: different rows, nothing to say
                if (p.y + p.h <= q.y + 1 || q.y + q.h <= p.y + 1)
                    continue;
                const gap = p.x < q.x ? q.x - (p.x + p.w) : p.x - (q.x + q.w);
                if (gap >= clearance)
                    continue;
                const first = p.x < q.x ? p : q;
                const second = p.x < q.x ? q : p;
                probe.note(`  ${gap < 0 ? "OVERLAP " : "TOOCLOSE"} ${name}: ${probe.describe(first)} and ${probe.describe(second)} - ${gap.toFixed(0)}px apart`);
            }
        }
    }

    Item {
        id: stage
        width: probe.column

        // inactive until the language is set - see the note at the top of the
        // file for why the order matters
        Loader {
            id: generalTab
            active: false
            sourceComponent: GeneralTab {
                slideIndex: 0
                activeIndex: 0
            }
        }
        Loader {
            id: pagesTab
            active: false
            sourceComponent: PagesTab {
                slideIndex: 0
                activeIndex: 0
            }
        }
        Loader {
            id: animationsTab
            active: false
            sourceComponent: AnimationsTab {
                slideIndex: 0
                activeIndex: 0
            }
        }
        Loader {
            id: navigationTab
            active: false
            sourceComponent: NavigationTab {
                slideIndex: 0
                activeIndex: 0
            }
        }
        Loader {
            id: flyoutsTab
            active: false
            sourceComponent: FlyoutsTab {
                slideIndex: 0
                activeIndex: 0
            }
        }

        Component.onCompleted: {
            // In memory only - never Settings.save() - so a probe run leaves
            // the user's settings.json exactly as it found it.
            Settings.language = probe.lang;
            // instantiates Metrics and lets its hidden measuring Texts settle
            // before any Row is built against them
            const warm = Metrics.shortValueWidth + Metrics.keybindBoxWidth;
            Qt.callLater(stage.build);
        }
        function build(): void {
            const tabs = {
                General: generalTab,
                Pages: pagesTab,
                Animations: animationsTab,
                Navigation: navigationTab,
                Flyouts: flyoutsTab
            };
            for (const name of Object.keys(tabs))
                tabs[name].active = true;
            probe.note(`[${probe.lang}] ${Strings.nameOf(probe.lang)}`);
            for (const name of Object.keys(tabs))
                probe.check(name, tabs[name].item);
            // PIBBLE_PROBE_DUMP=<tab> prints every block that tab lays out,
            // with its rect - for working out *why* a finding is a finding, or
            // what the room next to it actually is
            const dump = Quickshell.env("PIBBLE_PROBE_DUMP");
            if (tabs[dump]) {
                const all = [];
                probe.collect(tabs[dump].item, tabs[dump].item, all);
                for (const it of all)
                    probe.note(`  DUMP     ${dump}: ${it.x.toFixed(0)},${it.y.toFixed(0)} ${it.w.toFixed(1)}x${it.h.toFixed(0)} wants ${it.cw.toFixed(1)} "${it.text}"`);
            }
            if (probe.report.length === 1)
                probe.note("  clean");
            Quickshell.execDetached(["sh", "-c", `printf '%s\n' "$1" >> "$2"`, "_", probe.report.join("\n"), probe.outPath]);
            Quickshell.execDetached(["sh", "-c", "sleep 0.2; kill " + Quickshell.processId]);
        }
    }
}
