pragma Singleton
import QtQuick
import Quickshell.Io

// Single source of truth for all user-configurable state. This is the
// JsonAdapter itself rather than a wrapper around one, so every setting reads
// as `Settings.<name>` with no intermediate hop; SettingsStore owns the
// FileView that binds it to disk (a singleton can't be reparented into a
// FileView's default property, so the two halves have to live apart).
//
// Mutating a property only changes it in memory — call Settings.save()
// afterwards to persist.
JsonAdapter {
    id: settings

    // SettingsStore listens for these; they exist so this adapter never has
    // to reach back at the FileView that owns it.
    signal saveRequested
    signal loaded

    function save(): void {
        settings.saveRequested();
    }

    // Membership tests for the three object-valued toggle sets. All three
    // default to on for an unknown key, so a category added in a later release
    // is enabled for configs written before it existed.
    function flyoutEnabled(name: string): bool {
        return (settings.flyouts ?? {})[name] !== false;
    }
    function alertEnabled(name: string): bool {
        return (settings.pibbleAlerts ?? {})[name] !== false;
    }
    function gesturesEnabled(): bool {
        return settings.gestures !== false;
    }

    property int appsCols: Defaults.appsCols
    property int appsRows: Defaults.appsRows
    property int wallsCols: Defaults.wallsCols
    property int wallsRows: Defaults.wallsRows
    // bars visible in the "windows" carousel: the selected center plus equal
    // wings, so always odd (heal() clamps to 3–9)
    property int wallsVisible: Defaults.wallsVisible
    property int clipsCols: Defaults.clipsCols
    property int clipsRows: Defaults.clipsRows
    property int clipsMax: Defaults.clipsMax

    property var pages: Defaults.pages
    // cycle order of the pages (drag the chips in settings to change)
    property var pageOrder: Defaults.pageOrder
    // pages added via the Pages settings row's upload picker; each is
    // { id, label, path, on } and starts unchecked. Loaded and cycled
    // alongside the built-in four once ticked on — see LauncherState.pageOrder
    // and CustomPageHost
    property var uploadedPages: []
    // per-page persistent storage for custom pages, namespaced by page id (see
    // PageContext.getSetting/setSetting) — never read or written to directly
    // by pibble itself otherwise
    property var customPageData: ({})

    property string animStyle: "bloom"
    // independent of animStyle: gates the settings pane's entrance spring and
    // the power-off/reboot pull-back animation, neither of which is a "grid"
    // (see Anim.menu())
    property bool hiddenMenuAnimations: true

    // shared across the launcher and both flyouts
    property real fontScale: 1.0
    property string fontFamily: ""
    property string iconTheme: ""

    property string theme: "matugen"
    // user-editable palette for the "custom" theme; defaults match the retired
    // Mono preset so a first-time pick starts from something sane
    property string customAccent: Defaults.customAccent
    property string customFg: Defaults.customFg
    property string customMuted: Defaults.customMuted

    // "grid" is the grid picker; "carousel" and "carousel-flat" are the
    // horizontal carousel (see WallpaperCarousel), the latter with the backdrop
    // parallax pan disabled — shown to the user as "carousel" and "parallax
    // carousel" respectively (see SettingsSchema.display's wallpaperStyle case);
    // the internal ids stay as-is because "carousel"/"carousel-flat" already
    // once meant something else (the pre-rename windows/windows-flat styles)
    // and reusing "carousel" as the flat variant's new id would collide with
    // old saved configs mid-migration
    property string wallpaperStyle: "grid"
    property string wallpaperDir: Defaults.wallpaperDir
    // command run when a wallpaper is chosen; $WALL is the image (or video —
    // pibble stays backend-agnostic, so a command that wants to handle .mp4
    // differently, e.g. via mpvpaper instead of an image-only tool like the
    // default awww, has to branch on $WALL's extension and tear down/start the
    // right backend itself), $BLUR the blurred variant (only generated if
    // referenced)
    property string wallCommand: Defaults.wallCommand
    // path of the last wallpaper applied through the launcher; the Dynamic
    // theme samples this directly instead of asking the compositor what it's
    // currently showing, since wallCommand is freeform and may not even go
    // through the tool we'd query
    property string currentWallpaper: ""

    property real dimOpacity: 0.4
    property string launchAnimation: "grow-top-left"
    // how the launcher blurs whatever's behind it — "off", real compositor blur
    // ("compositor", see BackgroundEffect.blurRegion), or the client-side fake
    // ("xray", a blurred wallpaper — see XrayBackdrop); independent of
    // launchAnimation
    property string bgBlur: "xray"

    // gates every navigation gesture as one switch: the edge swipe-up/swipe-down
    // power-off/reboot drag (and, once that prompt is armed, the screen-wide
    // swipe that confirms/dismisses it), swipe-left/swipe-right to cycle
    // panes/tabs (or scroll the windows wallpaper carousel), swipe-up/swipe-down
    // to page through the current pane's grid, and the right-edge
    // swipe-to-go-back drag (LauncherState.goBack()). The keybind/Enter-confirm
    // flow the power gesture feeds into stays available either way.
    property bool gestures: true
    // when on, a single click on an app/wall/clip tile activates it
    // immediately. Off means clicking a tile that isn't already selected only
    // highlights it — a second click (on the now-selected tile) is what
    // actually activates it. The wallpaper carousel already behaves like the
    // "off" mode inherently (tapping a bar off-center recenters it, tapping the
    // centered one applies it) so isn't gated by this.
    property bool singleClickActivate: false
    property var keybinds: Defaults.keybinds

    // flyouts (volume + notification OSDs) — independent of whether other apps'
    // notifications show
    property var flyouts: Defaults.flyouts
    // gates notify-send calls pibble sends on its own behalf, split by kind:
    // errors (failed commands), missingDeps (a required external tool isn't
    // installed), actions (copy confirmations, custom page discovery, page
    // trashed, wallpaper changed), battery (low battery warning)
    property var pibbleAlerts: Defaults.pibbleAlerts

    property real volWidth: 420
    property string volAnim: "pop"
    // volume OSD content style: pill (a level bar) or sine (equalizer)
    property string volStyle: "sine"
    // numeric volume % readout on the OSD
    property bool volShowPercent: true
    property int volTimeout: 2000

    property int notifTimeout: 5000
    // one notification at a time (queue across apps, replace within an app):
    // "bubble" = tinted circle + card, "pill" = card only
    property string notifStyle: "bubble"
    // "pop" = the bubble/card pop-in and stagger animation, "none" disables all
    // notification entry/exit animation
    property string notifAnim: "pop"
    // how many of the most recent cached notifications `pibble replay` can step
    // back through on repeated presses (see NotifCache); 1-5
    property int replayCount: 1

    // clock-page weather readout (wttr.in); empty location auto-detects by IP
    property bool weatherEnabled: true
    property string weatherLocation: ""
    // clock page layout: which of date/battery/weather show; the line grouping
    // itself is fixed (see ClockPage.visibleGroups)
    property var clockShow: Defaults.clockShow

    // Heal out-of-range / retired values. Hooked to the store's loaded signal
    // (not Component.onCompleted) so it also covers hot reloads and hand edits
    // picked up by the file watcher — which means every branch below must be a
    // no-op on an already-healed config, because this also runs if a load ever
    // surfaces adapter defaults (an unconditional save here once clobbered the
    // file).
    function heal(): void {
        // clamp out-of-range clip rows (old list-style pane stored large
        // values; the grid renders 2–4 rows) — clamp, don't reset, so a
        // hand-edited value degrades to the nearest legal one
        if (settings.clipsRows > 4 || settings.clipsRows < 2) {
            settings.clipsRows = Math.max(2, Math.min(4, settings.clipsRows));
            settings.save();
        }
        // the windows carousel shows a selected center bar plus equal wings, so
        // the visible count must be odd; clamp to 3–9 and round even
        // hand-edited values down
        if (settings.wallsVisible < 3 || settings.wallsVisible > 9 || settings.wallsVisible % 2 === 0) {
            settings.wallsVisible = Math.max(3, Math.min(9, settings.wallsVisible % 2 === 0 ? settings.wallsVisible - 1 : settings.wallsVisible));
            settings.save();
        }
        if (settings.replayCount < 1 || settings.replayCount > 5) {
            settings.replayCount = Math.max(1, Math.min(5, settings.replayCount));
            settings.save();
        }
        // One-time migrations, keyed strictly on values only old configs can
        // contain.
        if (settings.theme === "dynamic") {
            settings.theme = "matugen"; // renamed
            settings.save();
        }
        // the "wave" tile animation was renamed "bloom"
        if (settings.animStyle === "wave") {
            settings.animStyle = "bloom";
            settings.save();
        }
        // the "reveal" tile animation was renamed "cascade"
        if (settings.animStyle === "reveal") {
            settings.animStyle = "cascade";
            settings.save();
        }
        // the retired equalizer visualizers collapse into the sine wave
        if (["mirror", "spectrum", "flicker"].includes(settings.volStyle)) {
            settings.volStyle = "sine";
            settings.save();
        }
        // "flyout" was renamed "bubble"; the retired stack style folds in too
        if (settings.notifStyle === "flyout" || settings.notifStyle === "stack") {
            settings.notifStyle = "bubble";
            settings.save();
        }
        // the Mono preset was retired in favor of the custom color picker
        // (seeded with Mono's old palette); configs that had it selected fall
        // back to the default so a theme always shows as selected
        if (settings.theme === "mono") {
            settings.theme = "matugen";
            settings.save();
        }
        // "windows"/"windows-flat" (the parallax bar carousel) renamed
        // "carousel"/"carousel-flat"
        if (settings.wallpaperStyle === "windows" || settings.wallpaperStyle === "windows-flat") {
            settings.wallpaperStyle = settings.wallpaperStyle === "windows-flat" ? "carousel-flat" : "carousel";
            settings.save();
        }
        // "tiles" (the grid picker) renamed "grid"
        if (settings.wallpaperStyle === "tiles") {
            settings.wallpaperStyle = "grid";
            settings.save();
        }
        if (!["grid", "carousel", "carousel-flat"].includes(settings.wallpaperStyle)) {
            settings.wallpaperStyle = "grid";
            settings.save();
        }
        // the single "alerts" flyout checkbox split into per-category
        // pibbleAlerts (errors/system/battery)
        if (settings.flyouts && Object.prototype.hasOwnProperty.call(settings.flyouts, "alerts")) {
            const wasOn = settings.flyouts.alerts !== false;
            settings.pibbleAlerts = { errors: wasOn, system: wasOn, battery: wasOn };
            const fly = Object.assign({}, settings.flyouts);
            delete fly.alerts;
            settings.flyouts = fly;
            settings.save();
        }
        // pibbleAlerts' "system" category renamed "actions"
        if (settings.pibbleAlerts && Object.prototype.hasOwnProperty.call(settings.pibbleAlerts, "system")) {
            const alerts = Object.assign({}, settings.pibbleAlerts);
            alerts.actions = alerts.system;
            delete alerts.system;
            settings.pibbleAlerts = alerts;
            settings.save();
        }
        // the old power/panes per-category gesture toggles collapsed back into a
        // single "gestures" switch that gates all navigation gestures at once —
        // on only if both halves were
        if (settings.gestures && typeof settings.gestures === "object") {
            settings.gestures = settings.gestures.power !== false && settings.gestures.panes !== false;
            settings.save();
        }
        // bgBlur was a plain bool toggle for compositor blur; it grew a
        // client-side fake-blur mode alongside it. The property is declared
        // `string` now, so JsonAdapter coerces an old on-disk `true`/`false`
        // into the strings "true"/"false" on load rather than leaving it a JS
        // boolean — check for those, not typeof.
        if (settings.bgBlur === "true" || settings.bgBlur === "false") {
            settings.bgBlur = settings.bgBlur === "true" ? "compositor" : "off";
            settings.save();
        }
        // there was briefly a second fake-blur mode that blurred a capture of
        // the screen instead of the wallpaper. It's gone: taking that capture
        // means a screencopy session, and attaching/detaching one segfaults Qt's
        // Wayland client in its own screen tracking, reliably enough to kill the
        // daemon within a handful of opens (reproducible in a few lines of
        // Quickshell with no shell around it). "xray" is the surviving
        // client-side blur.
        if (settings.bgBlur === "snapshot") {
            settings.bgBlur = "xray";
            settings.save();
        }
    }
}
