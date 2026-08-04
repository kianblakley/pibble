pragma Singleton
import QtQuick
import Quickshell
import "root:/config"

// The installed-application list behind the apps grid, its launch-frequency
// ranking, and the fuzzy matcher the apps and wallpaper panes share.
Singleton {
    id: root

    readonly property var all: {
        const list = Array.from(DesktopEntries.applications.values).filter(e => !e.noDisplay);
        list.sort((a, b) => a.name.localeCompare(b.name));
        return list;
    }

    // warm decode order = the home page's sort, so the icons the user sees
    // first come off the (single) QML image reader thread first
    readonly property var warmOrder: root.all.slice().sort((a, b) => root.launchCount(b) - root.launchCount(a) || a.name.localeCompare(b.name))

    function launchCount(entry): int {
        return (LaunchCounts.counts && LaunchCounts.counts[entry.id]) || 0;
    }

    function recordLaunch(entry): void {
        const next = Object.assign({}, LaunchCounts.counts);
        next[entry.id] = (next[entry.id] || 0) + 1;
        LaunchCounts.counts = next;
        LaunchCounts.save();
    }

    // Splits query on whitespace and requires every term to match somewhere in
    // haystack independently (order doesn't matter) — the same "AND of terms"
    // approach used by fzf, Sublime's Goto Anything, and VS Code's Quick Open,
    // so "code visual" or "studio code" both find "Visual Studio Code" even
    // though the words appear in a different order than typed. Falls straight
    // through to termScore for the common single-word case, leaving that
    // behavior unchanged.
    function fuzzyScore(haystack: string, query: string): var {
        const terms = query.split(/\s+/).filter(t => t.length > 0);
        if (terms.length <= 1)
            return root.termScore(haystack, query);
        let total = 0;
        for (const term of terms) {
            const score = root.termScore(haystack, term);
            if (score === null)
                return null;
            total += score;
        }
        return total;
    }

    // fzf-style subsequence match for a single term: query's characters must
    // appear in haystack in order (not necessarily contiguous), scored with
    // bonuses for prefix/word-start hits and consecutive runs, penalized for
    // gaps and overall length — the same shape of algorithm fzf, Sublime's Goto
    // Anything, and VS Code's Quick Open use. Chosen specifically because
    // subsequence matching is monotonic in the query: matching q+c as a
    // subsequence requires matching q as a subsequence first, so typing an
    // extra character can only narrow the result set, never grow it — unlike
    // bigram/edit-distance approaches, where an unrelated shared fragment can
    // cause a longer query to match something a shorter one didn't.
    function termScore(haystack: string, query: string): var {
        let score = 0;
        let next = 0;
        let prevMatch = -2;
        let consecutive = 0;
        for (let i = 0; i < query.length; i++) {
            const found = haystack.indexOf(query[i], next);
            if (found < 0)
                return null;
            if (found === 0)
                score += 8;
            else if (" -_./".includes(haystack[found - 1]))
                score += 6;
            if (found === prevMatch + 1) {
                consecutive++;
                score += 4 + consecutive;
            } else {
                consecutive = 0;
            }
            score -= found - next; // gap penalty
            prevMatch = found;
            next = found + 1;
        }
        if (haystack.startsWith(query))
            score += 10;
        else if (haystack.includes(query))
            score += 6;
        return score - haystack.length * 0.1;
    }

    // Apps in launch-frequency order, filtered by the current query. Empty
    // query keeps the whole list.
    function search(query: string): var {
        const q = query.toLowerCase().trim();
        if (!q) {
            const all = root.all.slice();
            all.sort((a, b) => root.launchCount(b) - root.launchCount(a) || a.name.localeCompare(b.name));
            return all;
        }
        const scored = [];
        for (const app of root.all) {
            const score = root.fuzzyScore(app.name.toLowerCase(), q);
            if (score !== null)
                scored.push({
                    entry: app,
                    score
                });
        }
        scored.sort((x, y) => root.launchCount(y.entry) - root.launchCount(x.entry) || y.score - x.score || x.entry.name.localeCompare(y.entry.name));
        return scored.map(x => x.entry);
    }
}
