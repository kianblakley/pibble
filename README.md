# App Launcher

A Quickshell app launcher implementing the [Claude Design "App Launcher"](https://claude.ai/design/p/b7f6f3a0-488e-43ce-9bf7-af1264cd473d) mockup, with two deltas from the design: real system icons (via desktop entries + icon theme) and a transparent, compositor-blurred background (`ext-background-effect-v1`) instead of the mocked gradient.

## Usage

The shell runs as a persistent daemon hosting the launcher and the OSDs:

```sh
./launch.sh            # start the daemon (spawn-at-startup)
./launch.sh toggle     # show/hide the launcher (bind this; starts the daemon if needed)
```

The launcher opens instantly over IPC (`qs -p <repo> ipc call launcher toggle`) as a fullscreen overlay that fades in and out:

- **Idle** — shows a clock and date. Enter/Tab opens the app drawer with the most-used apps.
- **Tab / Shift+Tab** — cycles panes forward/backward: clock → apps → wallpapers → clipboard → clock.
- **Apps** — typing fuzzy-matches installed apps (launch count first, fuzzy score second; counts persisted in Quickshell's state dir) into a paged grid; emptying the query shows the most-used apps.
- **Wallpapers** — paged grid of `wallpaperDir` images, fuzzy-filterable. Selecting one sets it via `awww` (`workspaces` namespace) with a blurred variant on `overview`. Missing thumbnails and blurred variants are generated with ImageMagick in the background at startup.
- **Clipboard** — cliphist history in a masonry grid, fuzzy-filterable (text matches content; images match their type/dimensions — clipboard images have no filename). Text tiles grow with content up to a square, captioned with an exact character count; image tiles keep their real aspect ratio at column width, captioned with their resolution. Enter/click copies via `wl-copy` and the tile grows into a details card (type, size, resolution/lines) while the rest of the grid animates away; Escape/Enter collapses it. Requires `cliphist` + `wl-clipboard`; the niri config spawns the `wl-paste --watch cliphist store` watchers at startup.
- **Arrows** — ←/→ previous/next; ↓/↑ walks the entire column across pages, then hops to the next/previous column.
- **Enter** / click — launch app / apply wallpaper / copy clip, then exit. Apps launch through `gtk-launch` (GLib), which parses `Exec=` shell-style; entries with single-quoted arguments (e.g. `sh -lc '…'`) that quickshell's strict spec parser would split mid-quote launch correctly, falling back to quickshell's own `execute()` only if `gtk-launch` can't resolve the id.
- **Escape** — steps back from an expanded clip or the settings pane, otherwise exits.
- **Scroll wheel** — walks the current grid (down the column, across pages).
- **Bottom-right hover** — settings button (Ctrl+S toggles it; closing returns to the pane you came from). Inside settings, the cycle keys (Tab / Shift+Tab) switch between the Launcher and Flyouts tabs. Every setting has a ↺ reset-to-default button. Tabs (Launcher / Flyouts) slide horizontally; the Flyouts tab covers per-OSD size, animation and timeout (volume timeout + notification timeout), the volume style (a level `pill` or one of three equalizer visualizers — `mirror` / `spectrum` / `flicker`), notification font size and max on-screen count, a shared font family and opacity, a theme, and checkboxes to enable each flyout (unchecking notifications releases the `org.freedesktop.Notifications` name for another daemon). Launcher tab: enabled pages, per-pane grid sizes, clipboard history size, animation style (wave / pop / fade / slide / none — none disables every animation including the reveal), font size, monospace font family, opacity, icon theme (applied on the next launch — `launch.sh` exports `QS_ICON_THEME` from the saved settings, or falls back to the GTK icon theme, and the niri bind uses it), color themes with palette previews (including a matugen-powered Dynamic theme derived from the current wallpaper), circle reveal origin (center or any corner), wallpaper directory, the wallpaper-apply command (`$WALL`/`$BLUR` placeholders, default drives awww on both namespaces; blur variants are only generated when the command references `$BLUR`, so non-awww/non-blur setups just replace the command), and rebindable cycle/reverse-cycle/launch/settings/exit keys. Stored in `settings.json` in Quickshell's state dir.

## OSDs

The same daemon provides a volume OSD (PipeWire default sink; slides up from the bottom edge to a resting offset — either a level `pill` or, per the volume-style setting, an equalizer visualizer of 12 bars mirrored around a centre axis, in `mirror` / `spectrum` / `flicker` motion variants, recreated from a Claude Design handoff and tinted with the flyout accent) and notification popups (quickshell's built-in `NotificationServer`) as a stack of pill cards below the top-right corner — newest on top, older ones reflowing down as cards are dismissed, up to the configurable max-on-screen count. Each notification card can be clicked to expand truncated body text (the clip height animates so it grows smoothly), and swiped left or right to dismiss (past a threshold; otherwise it springs back). Hovering a card pauses its dismiss timeout; moving off it resumes the countdown. A gentle entry bounce is built into the animations. The launcher's own messages (copied-to-clipboard, which carries the full copied text, and errors) render with themed glyph badges instead of icons; other apps show their image or icon-theme icon (a file path in the icon field, as niri screenshots send, is handled). Both OSDs take their color theme, opacity and font from the Flyouts settings, and each is hosted in a single fixed-size layer window whose cards animate inside it — so rapid volume changes and back-to-back notifications never pay a window-recreate cost. The blur regions are ellipse-scanline rounded rects tracking each card, collapsing to nothing as a card fades out (niri does not clip layer-surface blur to `geometry-corner-radius`). Give the `launcher-vol-osd` and `launcher-notif-osd` layer namespaces the same blur layer-rule as the launcher. Note: only one process can own `org.freedesktop.Notifications` — disable any other notification daemon (mako/dunst/etc.), or uncheck the notifications flyout to hand the name back.

## niri keybind

```kdl
binds {
    Mod+Space { spawn "/home/kian/Projects/launcher/launch.sh"; }
}
```

## Requirements

- Quickshell ≥ 0.3.0 (Wayland module)
- A compositor with `zwlr_layer_shell_v1`; blur needs `ext_background_effect_manager_v1` (degrades to plain transparency without it)
- JetBrains Mono font
