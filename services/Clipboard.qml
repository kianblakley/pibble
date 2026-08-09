pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/config"

// Clipboard history via cliphist: the scan behind the clips pane, the
// thumbnail cache for image entries, and the full-text search the pane filters
// with.
Singleton {
    id: root

    property var entries: []
    // raw stdout of the scan `entries` was last built from; see where it's compared
    property string lastScanText: ""
    property bool available: true
    // cliphist installed but nothing is feeding it (no `wl-paste --watch`
    // running to pipe clipboard changes into `cliphist store`)
    property bool watcherRunning: true
    readonly property string thumbDir: SystemInfo.cacheRoot + "/clips"
    // Re-runs on every launcher open, since the clipboard changes between
    // them. Restarting rather than starting: a scan still in flight from a
    // previous open would otherwise land after this one and show stale entries.
    function rescan(): void {
        scan.running = false;
        scan.running = true;
    }

    // Set by LauncherState to whether the clips pane is the one on screen.
    // Injected rather than read back out of the launcher so this service stays
    // a leaf that the launcher depends on, not the other way round.
    property bool paneVisible: false

    // Raised (and re-raised) every time the clips pane is navigated to, and
    // again whenever a scan lands while it's open - not just once per problem,
    // since the user wants a reminder each visit. Silent while the pane isn't
    // showing: a scan runs on every launcher open regardless of pane.
    function checkAlert(): void {
        if (!root.paneVisible)
            return;
        if (!root.available)
            Notifier.missingDependency("cliphist not found", "Install cliphist to enable clipboard history.");
        else if (!root.watcherRunning)
            Notifier.error("Clipboard watcher not running", "Nothing is piping clipboard changes into cliphist - clipboard history won't update. Run these (e.g. from your compositor's autostart):\n" + Notifier.clipWatcherFixCommand);
    }

    Process {
        id: scan
        command: ["bash", "-c", `
            export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
            command -v cliphist >/dev/null || { echo NOCLIPHIST; exit 0; }
            pgrep -x wl-paste >/dev/null 2>&1 && echo WATCH:1 || echo WATCH:0
            cliphist list | head -n "$1" | while IFS=$'\t' read -r id preview; do
                n=$(cliphist decode "$id" 2>/dev/null | wc -c)
                full=""
                cached=0
                case "$preview" in
                    # a thumb already on disk is reported here so the entry
                    # can carry its path straight out of the scan: a rescan
                    # (one runs on every launcher open) would otherwise hand
                    # every image tile an empty thumb until the thumbnail
                    # pass exits, blanking thumbnails that were already
                    # showing a frame earlier
                    '[[ binary data'*) [ -s "$2/$id.png" ] && cached=1 ;;
                    *)
                        # full text for search, capped well past any
                        # realistic clip so scanning ~200 of these stays
                        # cheap; backslashes, tabs and newlines are escaped
                        # (reversed by unescapeClipField) since they'd
                        # otherwise corrupt this tab/newline-delimited
                        # record format
                        content=$(cliphist decode "$id" 2>/dev/null | head -c 20000)
                        full=\${content//\\/\\\\}
                        full=\${full//$'\t'/\\t}
                        full=\${full//$'\n'/\\n}
                        ;;
                esac
                printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$n" "$cached" "$full" "$preview"
            done`, "_", String(Settings.clipsMax), root.thumbDir]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "NOCLIPHIST") {
                    root.available = false;
                    root.checkAlert();
                    return;
                }
                root.available = true;
                const nl = text.indexOf("\n");
                root.watcherRunning = text.slice(0, nl).trim() === "WATCH:1";
                root.checkAlert();
                // Same reason Wallpapers guards its own list: reassigning this
                // rebuilds every clip tile's delegate and re-uploads its thumb,
                // and a scan runs on every launcher open whether or not the
                // clipboard moved. Identical scan output means an identical
                // model, so the existing array (and its live delegates) stands.
                const scanned = text.slice(nl + 1).split("\n").filter(l => l.trim()).map(l => {
                    const t1 = l.indexOf("\t");
                    const t2 = l.indexOf("\t", t1 + 1);
                    const t3 = l.indexOf("\t", t2 + 1);
                    const t4 = l.indexOf("\t", t3 + 1);
                    const id = l.slice(0, t1);
                    const bytes = parseInt(l.slice(t1 + 1, t2)) || 0;
                    const cached = l.slice(t2 + 1, t3) === "1";
                    const fullEsc = l.slice(t3 + 1, t4);
                    const preview = l.slice(t4 + 1);
                    const m = preview.match(/^\[\[ binary data ([0-9.]+ \w+) (\w+) (\d+x\d+)/);
                    return m
                        ? { id, bytes, image: true, size: m[1], kind: m[2], dims: m[3], preview: m[2] + " image  " + m[3] + "  " + m[1], thumb: cached ? root.thumbDir + "/" + id + ".png" : "" }
                        : { id, bytes, image: false, preview: preview.trim(), full: root.unescapeField(fullEsc) };
                });
                if (text !== root.lastScanText) {
                    root.lastScanText = text;
                    root.entries = scanned;
                }
                // Sweep cached thumbs (and on-demand full-res decodes) for
                // ids that fell out of the current clipsMax window - runs
                // every scan so the cache never grows past what's shown.
                prune.command = ["bash", "-c", `
                    dir="$1"; shift
                    [ -d "$dir" ] || exit 0
                    for f in "$dir"/*.png; do
                        [ -e "$f" ] || continue
                        b=$(basename "$f" .png)
                        id="\${b%-full}"
                        case " $* " in *" $id "*) ;; *) rm -f "$f" ;; esac
                    done`, "_", root.thumbDir].concat(root.entries.map(c => c.id));
                prune.running = true;

                // only the ones the scan didn't already find a thumb for:
                // with every image cached this skips the pass (and the
                // entries rewrite in its onExited) entirely
                const imgs = root.entries.filter(c => c.image && !c.thumb).map(c => c.id);
                if (imgs.length) {
                    thumbnails.command = ["bash", "-c", `
                        export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
                        dir="$1" alerts="$2"; shift 2
                        mkdir -p "$dir"
                        warned=0
                        # Downscale at generation time so the on-disk thumb is
                        # small: the QML reader thread decodes the whole PNG
                        # before sourceSize applies, so a full-res screenshot
                        # would starve the app-icon decodes queued behind it.
                        for id in "$@"; do
                            [ -s "$dir/$id.png" ] && continue
                            tmp=$(mktemp)
                            cliphist decode "$id" > "$tmp"
                            if command -v magick >/dev/null; then
                                magick "$tmp" -resize '480x640>' "$dir/$id.png" 2>/dev/null || cp "$tmp" "$dir/$id.png"
                            elif command -v convert >/dev/null; then
                                convert "$tmp" -resize '480x640>' "$dir/$id.png" 2>/dev/null || cp "$tmp" "$dir/$id.png"
                            else
                                if [ "$warned" = "0" ] && [ "$alerts" = "1" ]; then
                                    warned=1
                                    notify-send -a pibble -i system-software-install "magick not found" "ImageMagick (magick or convert) is used to downscale clipboard image thumbnails - install one to keep memory/decode cost down for large screenshots."
                                fi
                                cp "$tmp" "$dir/$id.png"
                            fi
                            rm -f "$tmp"
                        done`, "_", root.thumbDir, Settings.alertEnabled("missingDeps") ? "1" : "0"].concat(imgs);
                    thumbnails.running = true;
                }
            }
        }
    }
    Process {
        id: prune
    }
    Process {
        id: thumbnails
        onExited: {
            root.entries = root.entries.map(c => c.image
                ? Object.assign({}, c, { thumb: root.thumbDir + "/" + c.id + ".png" })
                : c);
        }
    }

    // ---------- clipboard full-text search ----------
    // Clip content is free text, not a short identifier, so the fzf-style
    // subsequence match above (fuzzyScore) is a poor fit: applied to a
    // whole clip body (can run thousands of characters) rather than a
    // short name, "characters somewhere in order" stops being a meaningful
    // filter - almost anything matches - and the scattered hits it does
    // produce have no coherent span to highlight. Clips instead get plain
    // literal substring matching per space-separated term (case
    // insensitive, AND across terms) - simple and predictable: if you can
    // see it in the text, it matches.

    // AND-matches every term as a literal substring somewhere in `text`
    // (every occurrence is collected, not just the first), then slides a
    // window over the merged, position-sorted hits to find the tightest
    // span that still covers every term at least once - the classic
    // two-pointer "minimum window substring" technique. Without this, a
    // multi-word query would either have to appear as one exact contiguous
    // phrase (too strict - "database migration" wouldn't find "migration
    // of the database") or fall back to just highlighting each term's
    // first occurrence wherever it happens to be, even if that's two
    // unrelated corners of a long clip. The window instead finds where the
    // terms actually cluster together, and that span anchors both the
    // preview snippet and the highlight ranges.
    function searchMatch(text: string, terms: var): var {
        const lower = text.toLowerCase();
        const perTerm = [];
        for (let ti = 0; ti < terms.length; ti++) {
            const term = terms[ti];
            const hits = [];
            let from = 0;
            let idx;
            while ((idx = lower.indexOf(term, from)) !== -1) {
                hits.push({ start: idx, end: idx + term.length, ti });
                from = idx + 1;
            }
            if (hits.length === 0)
                return null; // this term matched nothing - no AND match
            perTerm.push(hits);
        }

        const flat = [].concat(...perTerm).sort((a, b) => a.start - b.start);
        const need = terms.length;
        const have = new Array(need).fill(0);
        let filled = 0;
        let lo = 0;
        let best = null;
        for (let hi = 0; hi < flat.length; hi++) {
            if (have[flat[hi].ti]++ === 0)
                filled++;
            while (filled === need) {
                const width = flat[hi].end - flat[lo].start;
                if (!best || width < best.width)
                    best = { lo, hi, width, start: flat[lo].start, end: flat[hi].end };
                if (--have[flat[lo].ti] === 0)
                    filled--;
                lo++;
            }
        }
        if (!best)
            return null;

        const winHits = flat.slice(best.lo, best.hi + 1).sort((a, b) => a.start - b.start);
        const hi = [];
        for (const h of winHits) {
            const last = hi[hi.length - 1];
            if (last && h.start <= last.end)
                last.end = Math.max(last.end, h.end);
            else
                hi.push({ start: h.start, end: h.end });
        }

        const score = winHits.length * 4 - best.width * 0.05 - best.start * 0.01;
        return { score, anchor: { start: best.start, end: best.end }, hi };
    }

    // builds the tile's preview text around the matched span: the anchor
    // window plus padding on each side. Deliberately doesn't snap to word
    // boundaries - the offset bookkeeping that'd require isn't worth it for
    // a compact preview, and cutting mid-word at the edges of a snippet is
    // a well-worn convention (search-result snippets do the same).
    function snippet(text: string, match: var, radius: int): var {
        const start = Math.max(0, match.anchor.start - radius);
        const end = Math.min(text.length, match.anchor.end + radius);
        const prefix = start > 0 ? "… " : "";
        const suffix = end < text.length ? " …" : "";
        const shift = prefix.length - start;
        const hi = match.hi
            .map(h => ({ start: h.start + shift, end: h.end + shift }))
            .filter(h => h.start >= 0 && h.end <= prefix.length + (end - start));
        return { text: prefix + text.slice(start, end) + suffix, hi };
    }

    // solid #rrggbb blend of a toward b (t=0 -> a, t=1 -> b). Qt's rich-text
    // CSS subset doesn't reliably support the rgba()/alpha-channel color
    // syntax, so translucency for the highlight background below is faked
    // by blending toward the panel's dark surface color instead of an
    // actual alpha channel - this always renders as a flat, well-supported
    // #rrggbb value.

    // Text clips are matched word-by-word against their full decoded text (see
    // searchMatch) rather than the character-subsequence match apps use, since
    // that's what makes highlightable spans possible; image clips have no real
    // text to search, so they keep matching against their synthetic "png image
    // 1920x1080 ..." label the old way. Matched clips are shallow-cloned with
    // highlightText/highlightSpans attached (rather than wrapped) so every
    // other lookup elsewhere keeps working against plain clip fields unchanged.
    function search(query: string): var {
        const raw = query.trim();
        if (!raw)
            return root.entries;
        const lowered = raw.toLowerCase();
        const terms = lowered.split(/\s+/).filter(t => t.length > 0);
        const scored = [];
        for (const clip of root.entries) {
            if (clip.image) {
                const score = Apps.fuzzyScore(clip.preview.toLowerCase(), lowered);
                if (score !== null)
                    scored.push({
                        clip,
                        score
                    });
                continue;
            }
            const text = clip.full || clip.preview;
            const match = root.searchMatch(text, terms);
            if (match === null)
                continue;
            const snip = root.snippet(text, match, 90);
            scored.push({
                clip: Object.assign({}, clip, {
                    highlightText: snip.text,
                    highlightSpans: snip.hi
                }),
                score: match.score
            });
        }
        scored.sort((x, y) => y.score - x.score);
        return scored.map(x => x.clip);
    }

    // renders a snippet with its matched spans wrapped in a highlighter-
    // style background box, escaping everything else. Spans are assumed
    // sorted/non-overlapping, which is how clipSearchMatch/clipSnippet
    // produce them. Text color is left alone - only the background marks
    // the match, so the highlight reads as a marker over the text rather
    // than recoloring it.
    function highlightMarkup(text: string, hi: var): string {
        let out = "";
        let pos = 0;
        const bg = Format.mixColor(Theme.surface, Theme.accent, 0.8);
        for (const h of hi) {
            if (h.start > pos)
                out += Format.escapeHtml(text.slice(pos, h.start));
            out += `<span style="background-color:${bg}">${Format.escapeHtml(text.slice(h.start, h.end))}</span>`;
            pos = h.end;
        }
        out += Format.escapeHtml(text.slice(pos));
        return out;
    }

    // reverses the \\ \t \n escaping scan applies (in bash) to a clip's
    // full-text field before folding it into the tab/newline delimited
    // scan output - see scan's command
    function unescapeField(s: string): string {
        let out = "";
        for (let i = 0; i < s.length; i++) {
            const c = s[i];
            if (c === "\\" && i + 1 < s.length) {
                const n = s[++i];
                if (n === "n")
                    out += "\n";
                else if (n === "t")
                    out += "\t";
                else if (n === "\\")
                    out += "\\";
                else
                    out += n;
            } else {
                out += c;
            }
        }
        return out;
    }
}
