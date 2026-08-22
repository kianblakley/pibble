pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/config"

// User-supplied extra pages, discovered from pibble/custom-pages - gitignored,
// since they're user content rather than shell code. Reconciles what's on disk
// against Settings.uploadedPages, so a folder dropped in by hand and one added
// through the Pages settings row's picker are indistinguishable once this runs.
//
// Every page is a top-level directory loaded from <dir>/main.qml - a page can
// be split across as many sibling files as it wants as long as they all live in
// its own directory. Reach them from main.qml with `import "." as Local` and
// `Local.Foo {}` - quickshell's own qmldir synthesis (see quickshell.qmlscanner
// in its logs) shadows the plain-Qt implicit directory import an ordinary QML
// app would get for free, so an unqualified `Foo {}` or bare `import "."`
// silently fails to resolve ("Foo is not a type") even though the file sits
// right there; the qualified form was verified working. A directory with no
// main.qml is surfaced as a disabled, undeletable-by-toggle row instead of
// being silently ignored or half-loaded - see the "broken" handling below.
//
// counter.example/ - the shipped, tracked example - is a real directory page
// under a *.example name, which is the convention for a template that shouldn't
// show up as a real, toggleable row (see the scan below); copy it out from
// under that suffix to actually try it.
Singleton {
    id: root

    readonly property string dir: Quickshell.shellDir + "/custom-pages"

    // Raised once a scan has reconciled Settings.uploadedPages against disk,
    // carrying the ids that are newly present. LauncherState listens and folds
    // them into the page order - kept as a signal so this service never has to
    // import the launcher it feeds.
    signal discovered(var addedIds)

    // `enableNew` is what the Pages tab's own picker passes: a page the user
    // just went and chose arrives switched on, where one dropped into
    // custom-pages behind pibble's back still arrives unchecked. Sticky until
    // a scan actually completes rather than cleared by the next rescan, since
    // the Pages tab rescans on a timer while it's open and would otherwise
    // wipe the intent (and cancel the in-flight scan) a moment after the copy
    // set it.
    property bool enableAdded: false
    function rescan(enableNew: bool): void {
        if (enableNew)
            enableAdded = true;
        scan.running = false;
        scan.running = true;
    }
    Process {
        id: scan
        running: true
        command: ["bash", "-c", `
            dir="$1"
            [ -d "$dir" ] || exit 0
            for d in "$dir"/*/; do
                [ -d "$d" ] || continue
                name="$(basename "$d")"
                # *.example directories are inert templates - skip
                # entirely, not even as "broken"
                case "$name" in *.example) continue ;; esac
                if [ -f "$d/main.qml" ]; then
                    printf 'D\\t%s\\n' "$name"
                else
                    printf 'X\\t%s\\n' "$name"
                fi
            done`, "_", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                // reconciles Settings.uploadedPages against what's actually on
                // disk: entries removed outside the app (or trashed via the
                // row's own delete control) drop out, ones added outside
                // the app (or dropped in by hand) show up unchecked - the
                // same merge either way, so external edits and in-app
                // uploads/trashes are indistinguishable once this runs.
                // Each disk line is "D<tab>name" (folder page with a
                // main.qml) or "X<tab>name" (folder missing one - tracked
                // so it gets a row and a one-time notification, but never a
                // loadable/toggleable page).
                const lines = text.trim() ? text.trim().split("\n") : [];
                const found = [];
                for (const line of lines) {
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    found.push({ kind: line.slice(0, tab), name: line.slice(tab + 1) });
                }
                const foundNames = found.map(e => e.name);
                const existing = Settings.uploadedPages ?? [];
                const stillPresent = existing.filter(u => foundNames.includes(u.filename));
                const knownNames = stillPresent.map(u => u.filename);
                const enableNew = root.enableAdded;
                root.enableAdded = false;
                const added = found.filter(e => !knownNames.includes(e.name)).map(e => ({
                    id: "folder:" + e.name,
                    label: e.name,
                    filename: e.name,
                    broken: e.kind === "X",
                    path: root.dir + "/" + e.name,
                    // a broken folder has nothing to load, so it stays off
                    // however it arrived - same rule toggleUploadedPage keeps
                    on: enableNew && e.kind !== "X"
                }));
                const merged = stillPresent.concat(added);
                // a page trashed through its own row clears its saved
                // customPageData (see PageList's pagesTrash); a folder
                // deleted outside the app is only ever noticed here, so
                // drop its data here too - external edits and in-app
                // trashes are supposed to be indistinguishable, and a
                // stale entry would otherwise be inherited by whatever
                // future page lands under the same folder name. Separate
                // from the merged-diff below so entries orphaned before
                // this cleanup existed still get swept.
                const data = Settings.customPageData ?? {};
                const stale = Object.keys(data).filter(id => !merged.some(u => u.id === id));
                if (stale.length) {
                    const all = Object.assign({}, data);
                    for (const id of stale)
                        delete all[id];
                    Settings.customPageData = all;
                    Settings.save();
                }
                if (JSON.stringify(merged) !== JSON.stringify(existing)) {
                    Settings.uploadedPages = merged;
                    // Page *order* belongs to LauncherState, which is what
                    // derives it (and pins the add row to the top); this
                    // service only reports which ids are newly on disk and
                    // lets it decide where they land. Emitted even when
                    // nothing was added, so a page that vanished still gets
                    // dropped out of the stored order.
                    root.discovered(added.map(u => u.id));
                    Settings.save();
                    // new entries start unchecked (see `added` above) with
                    // no other indication they arrived - whether just
                    // uploaded through the row's own picker or dropped into
                    // custom-pages by hand - so nudge the user to go flip
                    // them on instead of leaving them to discover an
                    // inert-looking row on their own. Broken folders get
                    // their own message (there's nothing to "enable"), and
                    // only fire once each - same as a real page, this
                    // fires off `added`, not off however many broken rows
                    // still exist on every later rescan.
                    // only the ones that arrived unchecked: a page the picker
                    // just switched on has nothing left to go and enable
                    const goodAdded = added.filter(u => !u.broken && !u.on);
                    const brokenAdded = added.filter(u => u.broken);
                    if (goodAdded.length && Settings.alertEnabled("actions")) {
                        const body = goodAdded.length === 1
                            ? goodAdded[0].label + " - enable it in Settings > Pages"
                            : goodAdded.length + " new custom pages - enable them in Settings > Pages";
                        Quickshell.execDetached(["notify-send", "-a", "pibble", "-i", "list-add", Strings.tr("New custom page found"), body]);
                    }
                    for (const u of brokenAdded)
                        Notifier.error(Strings.trf("Custom page “%1” is missing main.qml", u.label), Strings.tr("Folders in pibble/custom-pages need a main.qml entry point - see Settings > Pages."));
                }
            }
        }
    }
}
