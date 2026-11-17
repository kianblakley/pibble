pragma Singleton
import QtQuick

// Factory values for every setting that more than one place needs to know:
// Settings declares them as its adapter defaults, and SettingsSchema.reset()
// puts them back. Kept in their own singleton rather than on either of those
// so neither has to import the other (Settings is the store's adapter;
// SettingsSchema writes to Settings), and so "what is the default" has one
// answer instead of a literal repeated at both ends.
QtObject {
    readonly property string wallCommand: 'pkill mpvpaper; case "$WALL" in *.mp4|*.webm|*.mkv|*.mov|*.gif) mpvpaper -s -a MAX -o "no-audio --loop-file=inf" HDMI-A-1 "$WALL";; *) awww img "$WALL" --transition-type fade --transition-duration 1;; esac'
    readonly property string wallpaperDir: "~/Pictures/wallpapers"
    // id of the shipped translation the shell renders in
    readonly property string language: "en"
    // Every language pibble ships, and the two things other than its strings
    // that a language decides: `locale` is what its dates are formatted
    // against, `wttr` the code wttr.in wants for the clock page's weather
    // line. `name` is the language's own name for itself - somebody hunting
    // for their language is looking for that spelling, not for the English
    // one.
    //
    // The catalogue lives here rather than next to the tables in
    // services/Strings.qml because Settings.heal() has to be able to reject an
    // id nothing ships, and this is the one file both it and Strings may read
    // without pointing the layers at each other. The strings themselves, and
    // every decision made from them, stay in services.
    readonly property var languages: [
        { id: "en", name: "English", locale: "en_US", wttr: "en" },
        { id: "zh", name: "中文", locale: "zh_CN", wttr: "zh-cn" },
        { id: "es", name: "Español", locale: "es_ES", wttr: "es" },
        { id: "ru", name: "Русский", locale: "ru_RU", wttr: "ru" },
        { id: "fr", name: "Français", locale: "fr_FR", wttr: "fr" },
        { id: "ja", name: "日本語", locale: "ja_JP", wttr: "ja" },
        { id: "hi", name: "हिन्दी", locale: "hi_IN", wttr: "hi" },
        { id: "ar", name: "العربية", locale: "ar_SA", wttr: "ar" }
    ]

    readonly property var pages: ({ clock: true, apps: true, walls: true, clips: true })
    readonly property var pageOrder: ["clock", "apps", "walls", "clips"]
    readonly property var clockShow: ({ date: true, battery: true, weather: true })
    // per-page tile grid decorations: the live search query above the tiles,
    // and a page-of-tiles dot indicator below them. Both off out of the box -
    // the grid reads cleaner without them, and neither is load-bearing (the
    // query is echoed by what the grid filters to, the dots by the tiles
    // themselves changing)
    readonly property var pageIndicators: ({ query: false, dots: false })
    readonly property var flyouts: ({ volume: true, notifs: true })
    // per-surface switches for the text scramble, and the whole of that
    // setting (see Anim.scrambleAllowed). One key per surface the user can
    // point at: every built-in page of the launcher's stage, each flyout, the
    // settings pane and the power prompts. All off out of the box - it is much
    // the loudest thing the shell does, so it is opt-in. A custom page has no
    // key here and needs none - an unknown one reads as off too (see
    // Settings.scrambleEnabled).
    readonly property var scrambleSections: ({ clock: false, apps: false, walls: false, clips: false, volume: false, notifs: false, settings: false, power: false, tools: false })
    readonly property var pibbleAlerts: ({ errors: true, missingDeps: true, actions: true, battery: true })
    readonly property var keybinds: ({
        cycle: "Tab",
        reverseCycle: "Shift+Tab",
        launch: "Return",
        exit: "Escape",
        settings: "Ctrl+S",
        power: "Ctrl+P",
        reboot: "Ctrl+R",
        navLeft: "Left",
        navRight: "Right",
        navUp: "Up",
        navDown: "Down",
        pagePrev: "PageUp",
        pageNext: "PageDown"
    })

    // the retired Mono preset's palette, which the custom theme is seeded from
    readonly property string customAccent: "#cfcfcf"
    readonly property string customFg: "#f0f0f0"
    readonly property string customMuted: "#8a8a8a"

    readonly property int appsCols: 4
    readonly property int appsRows: 3
    readonly property int wallsCols: 3
    readonly property int wallsRows: 3
    readonly property int wallsVisible: 7
    readonly property int clipsCols: 4
    readonly property int clipsRows: 3
    readonly property int clipsMax: 120

    // the screen tools (see Settings for what each means)
    // How the tools menu can arrive and leave, the volume OSD's four. Here for
    // the same reason the languages are: the schema steps through the list
    // and the menu checks a name against it, and this is the file both read.
    readonly property var toolsAnims: ["pop", "fade", "slide", "none"]
    readonly property string toolsAnim: "pop"
    // What stands in for the pointer in the middle of the tools menu (see
    // ui/ToolsPie.qml for each).
    readonly property var toolsFaces: ["face", "visor", "cat", "sprout"]
    readonly property string toolsFace: "face"
    // How far the tools menu's buttons sit from the mark in its middle, in
    // pixels, and the steps the setting moves in - from where five buttons
    // just clear one another to where a flick has a long way to go.
    readonly property int toolsSpread: 84
    // What comes out beside the chosen tool: "full" its name and key, "name"
    // the name alone, "off" nothing.
    readonly property var toolsHints: ["full", "name", "off"]
    // Whether the eyes leave a streak behind them as they move (see
    // ui/ToolsPie.qml): "streak" fades out along its length, "solid" is the
    // eyes' own colour all the way to its point, "off" leaves none.
    readonly property var toolsTrails: ["streak", "solid", "off"]
    // What shape the pointer face's eyes are (see ui/ToolsPie.qml): upright
    // pills, or apostrophes.
    readonly property var toolsEyesChoices: ["pill", "apostrophe"]
    readonly property string toolsEyes: "pill"
    readonly property string toolsTrail: "streak"
    readonly property string toolsHint: "full"
    readonly property int toolsSpreadMin: 64
    readonly property int toolsSpreadMax: 160
    // How big the pointer face in the middle of the tools menu is, as a
    // percentage of its own size, and how far either way it can go - past
    // these it is either a speck or crowding the buttons.
    readonly property int toolsFaceSize: 100
    readonly property int toolsFaceSizeMin: 50
    readonly property int toolsFaceSizeMax: 150
    // "fixed" black and white, or "theme" - the palette the rest of pibble
    // is drawn in (see Theme.tools)
    readonly property var toolsColorModes: ["fixed", "theme"]
    readonly property string toolsColors: "fixed"
    readonly property string searchUrl: "https://www.google.com/search?q=%s"
    readonly property string recordDir: "~/Videos"
    readonly property var recordAudioChoices: ["desktop", "mic", "off"]

    // battery % the low-battery alert fires at (see Battery.checkLevel)
    readonly property int batteryAlertLevel: 5
}
