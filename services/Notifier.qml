pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "root:/config"

// Everything about notifications *as pibble sees them*: the alerts pibble
// raises on its own behalf, the shared derivation the flyout and the replay
// cache both render from, and `pibble replay` itself.
//
// pibble is its own notification server, so its alerts are ordinary
// notify-send calls that arrive back through NotificationServer like any other
// app's - there is no separate internal path that could drift from the real one.
Singleton {
    id: root

    // ---------- outgoing alerts ----------

    // Internal errors. Always the generic alert glyph (see glyphFor) so every
    // pibble-raised error reads the same at a glance. Auto-dismisses like any
    // other pibble alert, on the flyout's normal Settings.notifTimeout (no -t
    // override - expire_timeout -1, "let the server/flyout decide").
    function error(summary: string, body: string): void {
        if (!Settings.alertEnabled("errors"))
            return;
        Quickshell.execDetached(["notify-send", "-a", "pibble", "-i", "dialog-error", summary, body]);
    }

    // A required external tool isn't installed - distinct from error() (both
    // gated separately in Settings and rendered with a different glyph/color,
    // see glyphFor and NotificationFlyout.snapshot) since a missing dependency
    // is an environment gap, not something pibble itself failed at.
    function missingDependency(summary: string, body: string): void {
        if (!Settings.alertEnabled("missingDeps"))
            return;
        Quickshell.execDetached(["notify-send", "-a", "pibble", "-i", "system-software-install", summary, body]);
    }

    // A thing the user did took effect (copied, trashed, wallpaper applied,
    // page discovered). `icon` is a freedesktop name; `imagePath`, when given,
    // rides along as notification media so the card can show a real thumbnail.
    function action(icon: string, summary: string, body: string, imagePath: string): void {
        if (!Settings.alertEnabled("actions"))
            return;
        const args = ["notify-send", "-a", "pibble", "-i", icon];
        if (imagePath)
            args.push("-h", "string:image-path:" + imagePath);
        args.push(summary, body);
        Quickshell.execDetached(args);
    }

    // The QtMultimedia QML module itself isn't installed, so no video wallpaper
    // can be previewed at all. Fires from WallpaperVideoSurface's Loader, which
    // is the only place this is knowable: with no module there is no
    // MediaPlayer to raise the error below.
    property bool warnedMediaModule: false
    function mediaModuleMissing(): void {
        if (root.warnedMediaModule)
            return;
        root.warnedMediaModule = true;
        root.missingDependency(Strings.tr("QtMultimedia not found"), Strings.tr("QtMultimedia is used for live wallpaper previews - install it (e.g. qt6-qtmultimedia) to enable them. Everything else works without it."));
    }

    // Fires from a video wallpaper's MediaPlayer.onErrorOccurred (grid tile and
    // carousel preview both wire into this) rather than a startup probe: the
    // module can import fine with no working *backend* installed (its plugins
    // are a separate runtime dependency) - playback only actually fails once a
    // MediaPlayer tries to open a file. Distinct from the "ffmpeg not found"
    // alert in Wallpapers, which is about the ffmpeg CLI used to generate
    // thumbnails/blur - this one is QtMultimedia's own playback backend,
    // missing/broken independent of whether that CLI is installed.
    //
    // `backendFault` is classified by the caller rather than here, off
    // MediaPlayer's own error enum: reading that enum needs an `import
    // QtMultimedia`, and a singleton every other singleton pulls in is the one
    // place that import must never appear (see WallpaperVideoSurface). It
    // separates "nothing can play" from "this file can't play" - reporting a
    // codec QtMultimedia won't take, or a file it can't read, as a missing
    // dependency sends people installing a package they already have.
    //
    // Once-per-session, not once-per-tile, since every video tile would
    // otherwise re-report the same cause.
    property bool warnedMediaBackend: false
    function mediaPlaybackFailure(backendFault: bool, detail: string): void {
        if (root.warnedMediaBackend)
            return;
        root.warnedMediaBackend = true;
        if (backendFault)
            root.missingDependency(Strings.tr("Video wallpaper playback failed"), Strings.trf("QtMultimedia has no working playback backend (%1) - install your distro's Qt6 multimedia backend package, e.g. qt6-multimedia-ffmpeg.", detail));
        else
            root.error(Strings.tr("Video wallpaper preview failed"), detail);
    }

    // the two `wl-paste --watch` invocations cliphist needs to see both text
    // and image copies; shared between the alert body and the flyout's
    // tap-to-copy action (see the "Clipboard watcher not running" case in
    // NotificationFlyout) so they can never drift apart
    readonly property string clipWatcherFixCommand: "wl-paste --type text --watch cliphist store\nwl-paste --type image --watch cliphist store"

    function copyToClipboard(text: string): void {
        Quickshell.clipboardText = text;
        root.action("edit-copy", Strings.tr("Copied to clipboard"), text, "");
    }

    // ---------- incoming: classification ----------

    // Notification glyph classifier, shared by the flyout bubble and the replay
    // cache. Matches on the *raw* freedesktop icon name pibble itself passed via
    // notify-send -i (see error/missingDependency/action above), not the resolved
    // icon path: resolution depends on the active system icon theme actually
    // having that name, which isn't guaranteed, and a failed resolution used to
    // silently fall through to the generic bell below with no error visible.
    // Exact icon-name matches take priority over the generic keyword/urgency
    // fallback so a specific glyph (trash, low battery, etc) never gets
    // overridden by a coincidental "fail"/"not found" in the summary text.
    function glyphFor(iconName: string, urgency, summary: string): string {
        switch (iconName) {
        case "dialog-error":
            return Icons.alertTriangle;
        case "edit-copy":
            return Icons.copy;
        case "list-add":
            return Icons.plus;
        case "user-trash":
            return Icons.trash;
        case "battery-low":
            return Icons.batteryLow;
        case "preferences-desktop-wallpaper":
            return Icons.wallpaperSlideshow;
        case "system-software-install":
            return Icons.deployedCodeAlert;
        }
        const lower = summary.toLowerCase();
        if (urgency === NotificationUrgency.Critical || lower.includes("fail") || lower.includes("not found"))
            return Icons.alertTriangle;
        if (lower.includes("copied"))
            return Icons.copy;
        // wallpaper-changed rides a real thumbnail in image-path (see
        // LauncherWindow.commitWallpaper), which clobbers -i's icon name the
        // same way an image clip's "Copied to clipboard" does above - same
        // keyword fallback instead of the exact-name switch case
        if (lower.includes("wallpaper"))
            return Icons.wallpaperSlideshow;
        return Icons.bell;
    }

    // Whether this is one of pibble's own error/missing-dependency alerts, the
    // two categories that must never collapse into one card: a missing tool and
    // the failure it causes are separate things to go and fix, and the flyout
    // only ever holds one notification per sender - so without this every
    // pibble alert would expire the one before it and the user would see
    // whichever landed last. Matches the raw icon name pibble passed to
    // notify-send, recovering it from the image slot the same way viewOf does
    // (libnotify routes -i through the image-path hint, not app_icon).
    function ownAlert(n): bool {
        if (String(n.appName ?? "") !== "pibble")
            return false;
        const raw = String(n.appIcon ?? "") || String(n.image ?? "").replace("image://icon/", "");
        return raw === "dialog-error" || raw === "system-software-install";
    }

    // Identity for the flyout's replace-within-app rule (see
    // NotificationFlyout.accept): the sender's name when given, else the
    // desktop-entry hint (Discord and friends send no appName). The alerts
    // above get a per-notification key instead, so they can never match each
    // other and queue like separate apps do. Lives here rather than in the
    // flyout because viewOf's `key` has to derive identically - the flyout
    // compares the two.
    function keyOf(n): string {
        if (root.ownAlert(n))
            return "pibble-alert:" + n.id;
        return String(n.appName ?? "") || String(n.desktopEntry ?? "");
    }

    // Notification object → display fields, shared by the live flyout card and
    // the replay cache below, so a replayed notification renders with exactly
    // the icon/image/glyph the live card showed instead of a second derivation
    // that could drift.
    function viewOf(n): var {
        let icon = Icons.url(String(n.appIcon ?? ""));
        let image = String(n.image ?? "");
        // The bare freedesktop icon name (e.g. "dialog-error"), kept separate
        // from icon/image above which carry whatever's actually displayable (a
        // resolved path or image provider URL) - used only for glyphFor's
        // classification below. notify-send's -i flag does *not* populate the
        // app_icon D-Bus argument (confirmed via dbus-monitor): libnotify routes
        // it through the "image-path" hint instead, which arrives here as
        // n.image, not n.appIcon - so appIcon is empty for every
        // notify-send-style call pibble itself makes, and the real name only
        // recovers below once the image://icon/ prefix is stripped off.
        let iconName = String(n.appIcon ?? "");
        // some apps (e.g. niri screenshots) pass a file path in the icon field:
        // that is notification media, not an app icon
        if (icon.startsWith("file://")) {
            if (!image)
                image = icon;
            icon = "";
        }
        // notify-send-style senders arrive with everything in the image slot
        // (appIcon empty), routed through the icon provider: a file path there
        // is notification media (decode it directly so the aspect probe sees
        // real dimensions), an icon name is the app icon, not media
        if (image.startsWith("image://icon/")) {
            const rest = image.slice("image://icon/".length);
            if (rest.startsWith("/"))
                image = "file://" + rest;
            else {
                if (!icon)
                    icon = image;
                if (!iconName)
                    iconName = rest;
                image = "";
            }
        }
        // some senders (e.g. Discord) omit the app name and icon but set the
        // desktop-entry hint - recover both from the entry
        const entryId = String(n.desktopEntry ?? "");
        let appName = String(n.appName ?? "");
        let kept = null;
        // pibble replay (see Notifier.fireReplay) always sends "REPLAY" as its own
        // identity so repeated replays replace each other regardless of origin;
        // the real sender rides along in the desktop-entry hint purely for
        // display here, and the original arrival time (also a hint, since
        // notify-send has no standard one for it) becomes a relative "5m ago" in
        // place of a static "REPLAY" tag
        if (appName === "REPLAY") {
            const originalTimestamp = Number(n.hints?.["x-pibble-orig-ts"] ?? 0);
            const ago = originalTimestamp ? Format.timeAgo(originalTimestamp) : "";
            // That same arrival time is the cache entry's identity, and the
            // entry holds how the card looked when it first came in (see
            // remember). That wins over anything derived from the re-sent
            // notification, because the re-send cannot be the same message:
            // the server fills an empty icon in from the desktop-entry hint
            // (so a sender that showed none comes back wearing its app icon,
            // and tinted from it), and image data sent inline has no path to
            // send again. Entries from before the look was kept have no
            // `view` and derive from the re-send, as every replay used to.
            kept = NotifCache.items.find(item => item.timestamp === originalTimestamp)?.view ?? null;
            if (kept) {
                icon = kept.icon;
                image = kept.image;
                appName = kept.app ? (ago ? kept.app + " - " + ago : kept.app) : (ago || "REPLAY");
            } else {
                appName = entryId ? (ago ? entryId + " - " + ago : entryId) : (ago || "REPLAY");
            }
        } else if (entryId && (!appName || !icon)) {
            const entry = Array.from(DesktopEntries.applications.values).find(e => e.id.toLowerCase() === entryId.toLowerCase());
            if (entry) {
                if (!appName)
                    appName = entry.name;
                if (!icon && entry.icon)
                    icon = Icons.url(entry.icon);
            }
            if (!appName)
                appName = entryId;
        }
        return {
            // n.appName is forced to "REPLAY" by Notifier.fireReplay for every replayed
            // notification (see there) regardless of who originally sent it, so
            // a replay of pibble's own alert would otherwise stop counting as
            // "own" here and lose both its glyph rendering and its icon tinting
            // exemption; the desktop-entry hint still carries the true original
            // sender through a replay, so check that too
            own: kept ? kept.own : (n.appName === "pibble" || entryId === "pibble"),
            glyph: kept ? kept.glyph : root.glyphFor(iconName, n.urgency, String(n.summary ?? "")),
            app: appName,
            key: root.keyOf(n),
            summary: n.summary ?? "",
            body: n.body ?? "",
            image: image,
            icon: icon,
            // the colour the bubble settled on the first time round; only a
            // replay has one
            tint: kept?.tint ?? "",
            // which cache entry this notification was remembered as, for the
            // flyout to hand back with what it learns (see rememberLook); 0
            // for a replay, which is never remembered
            stamp: root.stamps[n.id] ?? 0,
            timeout: n.expireTimeout
        };
    }

    // Notification id -> the timestamp of the cache entry remember() wrote for
    // it. Kept here rather than as an `id` in the entry: ids start over with
    // every daemon, so one on disk would match a stranger after a restart.
    property var stamps: ({})

    // ---------- replay ----------

    // Two things per notification. The raw fields are enough to rebuild a
    // notify-send call: icon/image get the same slot-swap classification
    // viewOf does (some senders put a file path in appIcon, or route everything
    // through image as an "image://icon/NAME" pseudo-URL) but keep raw values -
    // a bare icon name or file path - since these feed notify-send's -i/-h flags
    // directly on replay, not a QML Image source.
    //
    // `view` is how the card looked, as viewOf derived it on arrival. Re-sending
    // the raw fields was meant to let the live pipeline derive that again, but
    // what comes back is not what was sent (see viewOf's replay branch), so the
    // look is kept and the replay wears it. Its image is kept only when it is a
    // file: one sent inline lives in the server's memory, under a URL that dies
    // with the notification, and the flyout writes that to mediaDir and reports
    // the path - along with the bubble's colour, which it only knows once it
    // has sampled the icon (see rememberLook).
    readonly property int replayCapacity: 5
    readonly property string mediaDir: SystemInfo.cacheRoot + "/notifications"
    // where it was before; see the sweep in remember()
    readonly property string legacyMediaDir: SystemInfo.cacheRoot + "/thumbnails/notifs"
    function mediaPath(stamp: double): string {
        return root.mediaDir + "/" + stamp + ".png";
    }
    property double lastStamp: 0
    function remember(n): void {
        // doubles as the entry's identity (see viewOf, rememberLook), so two
        // arrivals inside one millisecond must not share it - counted up
        // from the last one handed out rather than from what the cache
        // holds, which is only as unique as its contents happen to be
        const stamp = Math.max(Date.now(), root.lastStamp + 1);
        root.lastStamp = stamp;
        const view = root.viewOf(n);
        let icon = String(n.appIcon ?? "");
        let image = String(n.image ?? "");
        if (icon.startsWith("file://") || icon.startsWith("/")) {
            if (!image)
                image = icon;
            icon = "";
        }
        if (image.startsWith("image://icon/")) {
            const rest = image.slice("image://icon/".length);
            if (rest.startsWith("/"))
                image = rest;
            else {
                if (!icon)
                    icon = rest;
                image = "";
            }
        } else if (image.startsWith("file://")) {
            image = image.slice("file://".length);
        }
        const entry = {
            appName: String(n.appName ?? ""),
            appIcon: icon,
            image: image,
            summary: n.summary ?? "",
            body: n.body ?? "",
            urgency: NotificationUrgency.toString(n.urgency),
            // when the *original* notification arrived, so a later replay can
            // show "<original> - 5m ago" instead of a static "REPLAY" tag
            timestamp: stamp,
            view: {
                own: view.own,
                glyph: view.glyph,
                app: view.app,
                icon: view.icon,
                image: view.image.startsWith("file://") ? view.image : "",
                tint: ""
            }
        };
        NotifCache.items = [entry].concat(NotifCache.items).slice(0, root.replayCapacity);
        NotifCache.save();
        // only the notifications still in the cache can be reported on, so
        // the map is rebuilt around them and never outgrows it
        const stamps = {};
        for (const id in root.stamps) {
            if (NotifCache.items.some(item => item.timestamp === root.stamps[id]))
                stamps[id] = root.stamps[id];
        }
        stamps[n.id] = stamp;
        root.stamps = stamps;
        // Sweep the images of entries that have just fallen off the end, by
        // the same rule Clipboard prunes its thumbnails with: anything not
        // named after an entry still cached goes. Also makes the directory,
        // ahead of the flyout's first write into it.
        //
        // The directory this used to be is removed rather than carried
        // over, unlike the wallpaper and clipboard caches: the entries that
        // own those images name them by their old path, so moving the files
        // would save nothing. At most five replays lose their picture, the
        // same way one does when the wallpaper or clip it showed is deleted.
        // The rmdir is for thumbnails/, which it sat in beside folders of
        // Wallpapers' and Clipboard's - it goes with whichever of the three
        // moves out last.
        Quickshell.execDetached(["bash", "-c", `
            dir="$1" old="$2"; shift 2
            mkdir -p "$dir"
            if [ -d "$old" ]; then
                rm -f "$old"/*.png
                rmdir "$old" "\${old%/*}" 2>/dev/null
            fi
            for f in "$dir"/*.png; do
                [ -e "$f" ] || continue
                case " $* " in *" $(basename "$f" .png) "*) ;; *) rm -f "$f" ;; esac
            done`, "_", root.mediaDir, root.legacyMediaDir].concat(NotifCache.items.map(item => String(item.timestamp))));
    }

    // What only the flyout can find out about a remembered notification, and
    // only once it is on screen: where its inline image was written to
    // (`image`) and the colour sampled from its icon (`tint`). A no-op for a
    // stamp of 0 (a replay) or an entry that has been pushed out since.
    function rememberLook(stamp: double, look): void {
        const index = stamp ? NotifCache.items.findIndex(item => item.timestamp === stamp) : -1;
        if (index < 0 || !NotifCache.items[index].view)
            return;
        const items = NotifCache.items.slice();
        items[index] = Object.assign({}, items[index], { view: Object.assign({}, items[index].view, look) });
        NotifCache.items = items;
        NotifCache.save();
    }

    // Replays by re-sending a real notify-send call with the original
    // notification's own icon/image/urgency, rather than a separate "replay"
    // rendering path (the icon, image and colour it is *shown* with come from
    // the entry's kept look where there is one - see viewOf - and from this
    // re-send only for entries older than that): the re-sent notification lands in
    // NotificationServer.onNotification -> NotificationFlyout.accept() exactly
    // like any live one, so it animates and dismisses identically - a genuine
    // replay, not a second UI that can drift from the first. The sender identity
    // is always the literal "REPLAY" (not the original app), so repeated presses
    // always land in the flyout's own same-app "replace in-place" path - see
    // accept()'s appKey comparisons - regardless of which app each replayed
    // notification originally came from, and so a live notification from the
    // real sender never collides with it. The original sender rides along in the
    // desktop-entry hint purely so viewOf can show "<original> - <n> ago" on the
    // card; the original arrival time rides along the same way in a
    // pibble-private hint (no standard notify-send hint carries this) so that
    // "ago" reads relative to when the notification actually happened, not to
    // when it was replayed.
    function fireReplay(item): void {
        const args = ["notify-send"];
        if (item.urgency)
            args.push("-u", String(item.urgency).toLowerCase());
        // item.app is a one-release fallback for cache entries written by the
        // previous (display-derived) cache format, so an on-disk cache from
        // before that change doesn't replay unattributed the first time
        const appName = item.appName || item.app || "";
        args.push("-a", "REPLAY");
        if (appName)
            args.push("-h", "string:desktop-entry:" + appName);
        if (item.timestamp)
            args.push("-h", "string:x-pibble-orig-ts:" + item.timestamp);
        if (item.appIcon)
            args.push("-i", item.appIcon);
        if (item.image)
            args.push("-h", "string:image-path:" + item.image.replace(/^file:\/\//, ""));
        args.push(item.summary ?? "", item.body ?? "");
        Quickshell.execDetached(args);
    }

    // Cursor into NotifCache.items (0 = most recent) that each `pibble replay`
    // press steps forward by one, so consecutive presses walk back through
    // history one notification at a time instead of bursting the whole cache at
    // once; wraps back to the most recent once it reaches the deepest reachable
    // notification. A press arriving more than replaySessionTimeout after the
    // previous one is treated as a new session and also starts back over at the
    // most recent notification.
    property int replayIndex: -1
    property double replayLastFireMs: 0
    readonly property int replaySessionTimeout: 5000
    function replay(): void {
        if (!NotifCache.items.length)
            return;
        const depth = Math.max(1, Math.min(root.replayCapacity, Settings.replayCount, NotifCache.items.length));
        const now = Date.now();
        root.replayIndex = (root.replayIndex < 0 || now - root.replayLastFireMs > root.replaySessionTimeout) ? 0 : (root.replayIndex + 1) % depth;
        root.replayLastFireMs = now;
        root.fireReplay(NotifCache.items[root.replayIndex]);
    }
}
