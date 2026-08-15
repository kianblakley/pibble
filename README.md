<h1 align=center>
    <img src="https://raw.githubusercontent.com/kianblakley/pibble/refs/heads/dev/assets/title.png" alt="pibble">
</h1>

<p align=center>
    <img src="https://img.shields.io/github/license/kianblakley/pibble?color=875DC4&labelColor=1a1a1a&style=for-the-badge" alt="License">
    <img src="https://img.shields.io/github/last-commit/kianblakley/pibble?color=875DC4&labelColor=1a1a1a&style=for-the-badge" alt="Last commit">
    <img src="https://img.shields.io/badge/Built%20with-Quickshell-875DC4?labelColor=1a1a1a&style=for-the-badge" alt="Built with Quickshell">
</p>

![App drawer](https://raw.githubusercontent.com/kianblakley/pibble/refs/heads/dev/assets/appdrawer.png)

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

## Configuring

### Settings
pibble has an extensive in-app settings page (`Ctrl+S`, or press the bottom right corner) covering appearance, animations, resource usage, layouts, navigation and flyouts.

### Namespaces

Each window has a layer-shell namespace which can be used to apply background effects/animations in your compositor's configuration file.

| Namespace | Window |
|---|---|
| `pibble-launcher` | Main launcher |
| `pibble-notifications` | Notification flyout |
| `pibble-volume` | Volume flyout |

### Custom pages

Custom page API coming.

<!--
To add your own page to pibble, create a folder within `custom-pages/` that contains a `main.qml` file. Pibble uses the name of your folder to determine the page name in settings as well as in `./pibble toggle [page]`

```
custom-pages/
└── your-page
    └── main.qml
```

Pibble will render any valid qml, use of the following API is optional. It allows you to sync your page's appearance with pibble's as well as handle settings, animations and text input.     

To use the properties exposed by pibble declare a `pibble` property in your page's root item (pibble will populate this). To define your own settings content, declare a `settingsTab` property in the root item (pibble will read from this).

```qml
Item {
    id: root 
    property var pibble: null
    readonly property Component settingsTab: Component { }
}
```

To access a `pibble` property use `pibble.property` as defined in the table below:


| Property | Type | Use |
|---|---|---|
| `accentColor`, `textColor`, `mutedTextColor` | `color` | current values of `SETTINGS > General > Color theme` |
| `tileColor`, `activeTileColor`, `borderColor` | `color` | ready-mixed colors based on `accentColor` that are used in tiles/buttons |
| `font` | `string` | curent value of `SETTINGS > General > Font` |
| `fontScale` | `real` | current value of `SETTINGS > General > Font size`. It's a multiplier, e.g. `1.2` — turn a size into a real pixel value with `Math.round(px * fontScale)` |
| `iconFont` | `string` | the name of pibble's icon font, you are required to find your own unicode |
| `radius(px)` | function | returns `px` while `SETTINGS > General > Rounded corners` is on and `0` while it's off — bind your corners through it (`radius: pibble.radius(8)`) so your page squares itself alongside the rest of the shell |
| `pageActive` | `bool` | `true` while your page is the one currently showing |
| `launcherOpen` | `bool` | `true` while the launcher is open at all |
| `textInput` | `string` | the current value of pibble's hidden text input |
| `releaseFocus()` | function | call this to give keyboard focus back to pibble if your page took it |
| `tileIn(item, slot, cols)` | function | makes `item` play pibble's tile spawn animation set in `SETTINGS > Animations > Pages` — pass `slot`/`cols` if it's one tile among several, so they can stagger in one after another |
| `setSetting(key, value)` / `getSetting(key, fallback)` | function | save/load your page's settings |

Note: Splitting your page across multiple files requires you to declare `import "." as Local`, then use `Local.Foo {}` instead of plain `Foo {}` to access them.

An example custom-page has been provided at `custom-pages/calendar.example/`. To see it in action remove `.example` from the folder name or upload it via `SETTINGS > Pages > Add a page...`.

-->


