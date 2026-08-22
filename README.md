<h1 align=center>
    <img src="https://raw.githubusercontent.com/kianblakley/pibble/refs/heads/dev/assets/title.png" alt="pibble">
</h1>

<p align=center>
    <img src="https://img.shields.io/github/license/kianblakley/pibble?color=875DC4&labelColor=1a1a1a&style=for-the-badge" alt="License">
    <img src="https://img.shields.io/github/last-commit/kianblakley/pibble?color=875DC4&labelColor=1a1a1a&style=for-the-badge" alt="Last commit">
    <img src="https://img.shields.io/badge/Built%20with-Quickshell-875DC4?labelColor=1a1a1a&style=for-the-badge" alt="Built with Quickshell">
</p>

![App drawer](https://raw.githubusercontent.com/kianblakley/pibble/refs/heads/dev/assets/appdrawer.png?v=2)

## Features

- **Launcher** - clock, app drawer, wallpaper selector, clipboard history, and power/reboot menus
- **Volume and notification flyouts** - OSDs that pop up over whatever you're doing
- **Weather and battery** - shown on the clock page
- **In-app settings** - configurable layout, animations, theming, keybindings, resource usage and much more
- **Custom pages** - create your own qml page and have it show up in the launcher
- **Dynamic theming** - matugen-driven color extraction from your current wallpaper, or a custom palette
- **Notification replay** - re-fire recent notifications, stepping further back in history on each repeated call
- **Live wallpaper support** - live wallpaper previews, with auto-generated blurred variants
- **Multi-monitor support** - the launcher and flyouts follow whichever output is focused
- **Gesture and keyboard support** - entirely navigateable with either keyboard or gestures alone
  
## Installation

### 1. Install dependencies

Necessary:

| Dependency | Use |
|---|---|
| A Wayland compositor, e.g. [Niri](https://github.com/YaLTeR/niri), [Hyprland](https://github.com/hyprwm/Hyprland), [Sway](https://github.com/swaywm/sway) | Hosts the shell |
| [Quickshell](https://github.com/quickshell-mirror/quickshell) | Runs the shell |

Optional (required for full feature set):

| Dependency | Use |
|---|---|
| [matugen](https://github.com/InioX/matugen) | Wallpaper-derived color theme |
| [ImageMagick](https://github.com/ImageMagick/ImageMagick) | Static wallpaper/clipboard thumbnails |
| [ffmpeg](https://ffmpeg.org/) | Live wallpaper thumbnails |
| [qtmultimedia](https://doc.qt.io/qt-6/qtmultimedia-index.html) | Live wallpaper previews (install via your distro's package manager) |
| [awww](https://codeberg.org/LGFae/awww) | Recommended static wallpaper backend (can use any) |
| [mpvpaper](https://github.com/GhostNaN/mpvpaper) | Recommended live wallpaper backend (can use any) |
| [cliphist](https://github.com/sentriz/cliphist) | Clipboard history support |
| [grim](https://sr.ht/~emersion/grim) | Screen color picker capture on wlroots compositors (niri needs nothing, but grim is much faster) |
| [hyprpicker](https://github.com/hyprwm/hyprpicker) | Screen color picker fallback where `grim` is absent |

### 2. Clone

```sh
git clone https://github.com/kianblakley/pibble.git
cd pibble
```

### 3. Start the daemon

```sh
./pibble start
```

### 4. Toggle the launcher

```sh
./pibble toggle
```

## Usage

### Keybindings

| Action | Key | Gesture |
|---|---|---|
| Cycle pages | `Tab` / `Shift+Tab` | swipe left/right |
| Navigate tiles in the current page | `Arrow keys or scrollwheel` | press |
| Jump a page of tiles within the current page | `PageUp` / `PageDown` | swipe up/down |
| Activate the selected tile | `Enter` | press |
| Reveal power button | `Ctrl+P` | swipe down from the top edge |
| Reveal reboot button | `Ctrl+R` | swipe up from the bottom edge |
| Open settings | `Ctrl+S` | press bottom right corner |
| Go back or close the launcher | `Escape` | right-edge swipe |

### `./pibble` commands

| Command | Description |
|---|---|
| `help` | List the available commands |
| `start` | Start the daemon |
| `stop` | Stop the daemon |
| `restart` | Restart the daemon |
| `toggle [page]` | Show/hide the launcher, starting the daemon first if needed; with a page id, opens/switches straight to that page |
| `replay` | Re-fire one recent notification; repeated presses step back through history |
| `env` | Print the environment a daemon starts with (resolved font, icon theme), as shell exports |

## Configuring

### Settings
pibble has an extensive in-app settings page (`Ctrl+S`, or press the bottom right corner) covering appearance, animations, resource usage, layouts, navigation and flyouts.

### Language

`SETTINGS > General > Language` sets the language every string pibble writes is rendered in — the settings page, the launcher's own labels and prompts, and the notifications pibble raises on its own behalf. Dates on the clock page are formatted for the chosen language, and the weather line is fetched in it.

| | |
|---|---|
| English | `English` |
| Chinese (Simplified) | `中文` |
| Spanish | `Español` |
| Russian | `Русский` |
| French | `Français` |
| Japanese | `日本語` |
| Hindi | `हिन्दी` |
| Arabic | `العربية` |

Text that isn't pibble's stays as it arrives: an app's name in the drawer, a wallpaper's filename, a clipboard entry, another app's notification, and the names of your installed fonts and icon themes. Arabic renders right-to-left as text, but the shell's layout itself is not mirrored.

Translations live in [`services/Translations.qml`](services/Translations.qml), one table per language keyed by the English source string; a key with no translation falls back to English, so adding a language is a matter of adding a table there and an entry to `Defaults.languages`.

### Namespaces

Each window has a layer-shell namespace which can be used to apply background effects/animations in your compositor's configuration file.

| Namespace | Window |
|---|---|
| `pibble-launcher` | Main launcher |
| `pibble-notifications` | Notification flyout |
| `pibble-volume` | Volume flyout |
| `pibble-colorpicker` | Screen color picker |

### Custom pages

To add your own page to pibble, create a folder within `custom-pages/` that contains a `main.qml` file. Pibble uses the name of your folder to determine the page name in settings as well as in `./pibble toggle [page]`

```
custom-pages/
└── your-page
    └── main.qml
```

Pibble will render any valid qml; use of the following API is optional. It lets your page match pibble's appearance and animations, and handle settings and text input.

Declare a `pibble` property on your page's root item and pibble fills it in as the page is created — before any of your own bindings first run, so it is never null from where your page sits and needs no guards. To define your own settings content, also declare a `settingsTab` Component (pibble reads from it and gives your page a tab in `SETTINGS`, named after your folder):

```qml
Item {
    id: root
    property var pibble
    readonly property Component settingsTab: Component { /* optional */ }
}
```

To access a `pibble` property use `pibble.property` as defined in the table below:

| Property | Type | Use |
|---|---|---|
| `accentColor`, `textColor`, `mutedTextColor` | `color` | current values of `SETTINGS > General > Color theme` |
| `tileColor`, `activeTileColor`, `borderColor` | `color` | ready-mixed shades of `accentColor`, the same numbers pibble's own tiles/buttons use |
| `font` | `string` | current value of `SETTINGS > General > Font` |
| `iconFont` | `string` | the family name of pibble's icon font — draw `icon()`'s glyphs in it |
| `icon(name)` | function | a glyph from pibble's icon font by name: `chevron-left`, `chevron-right`, `arrow-left`, `arrow-right`, `arrow-up`, `arrow-down`, `check`, `plus`, `trash`, `settings`, `refresh`, `copy`, `bell`, `warning`. Unknown names return `""`. For anything beyond these, `iconFont` is already loaded — find your own codepoints |
| `px(size)` | function | `size` scaled by `SETTINGS > General > Font size`, as a pixel value — use it for text and anything else that should grow with that setting |
| `fontScale` | `real` | the raw multiplier behind `px()`, for math `px()` can't express |
| `radius(px)` | function | returns `px` while `SETTINGS > General > Rounded corners` is on and `0` while it's off — bind your corners through it (`radius: pibble.radius(8)`) so your page squares itself alongside the rest of the shell |
| `pageActive` | `bool` | `true` while your page is the one currently showing |
| `launcherOpen` | `bool` | `true` while the launcher is open at all |
| `textInput` | `string` | the current value of pibble's hidden text input — watch it to filter your own content |
| `releaseFocus()` | function | call this to give keyboard focus back to pibble if your page took it |
| `scramble(text, slot, cols)` | function | `text` mid-resolve during the entrance scramble — bind through it and your label settles alongside pibble's own. Binding through it *is* the opt-in: custom pages have no chip under `SETTINGS > Animations > Text scramble`, so only the labels you bind take part (the run still skips when `Tile animations` is `none`). For a label sitting on a `PageTile`, use the tile's `scrambled()` instead |
| `setSetting(key, value)` / `getSetting(key, fallback)` | function | save/load your page's settings — binding through `getSetting` is live |

**Tile animations** — wrap anything tile-shaped in a `PageTile` and it plays the same entrance pibble's own grids do (per `SETTINGS > Animations > Tile animations`): hidden until its first spring, staggered within its group, replaying itself whenever your page comes back on screen.

```qml
import "root:/ui" as Pibble

Pibble.PageTile {
    id: tile
    pibble: root.pibble            // wire the contract in, once per tile
    slot: index                    // position in the group — staggers the wave
    cols: 7                        // how many columns the group has
    replayOn: [root.viewMonth]     // replay whenever any of these change
    width: 56; height: 56
    color: pibble.tileColor        // it's a Rectangle — style it, or leave it
    radius: pibble.radius(8)       // transparent and use it as a plain wrapper

    Text { text: tile.scrambled("7") }   // resolves as its tile lands
}
```

`tile.play()` replays the entrance by hand, for a trigger `replayOn` can't express.

Note: Splitting your page across multiple files requires you to declare `import "." as Local`, then use `Local.Foo {}` instead of plain `Foo {}` to access them.



One example page ships under `custom-pages/`: `note.example/`, a persistent scratch note exercising the contract — keyboard focus and `releaseFocus()`, saving on close via `launcherOpen`/`pageActive`, `getSetting`/`setSetting`, a standalone `scramble()`, and its own settings tab (`Settings.qml`, reached through the split-file `import "." as Local`). To see it in action remove `.example` from the folder name or upload it via `SETTINGS > Pages > Add a page...`.
