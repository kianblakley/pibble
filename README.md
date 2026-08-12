<h1 align=center>
    pibble
</h1>

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
| [awww](https://codeberg.org/LGFae/awww) | Recommended wallpaper backend (can use any) |
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

| Key | Gesture | Action |
|---|---|---|
| `Tab` / `Shift+Tab` | swipe left/right | Cycle pages |
| `Arrow keys or scrollwheel` | swipe up/down | Navigate tiles in the current page |
| `Enter` | press | Activate the selected tile |
| `Ctrl+P` | swipe down from the top edge | Reveal power button |
| `Ctrl+R` | swipe up from the bottom edge | Reveal reboot button |
| `Ctrl+S` | press bottom right corner | Open settings |
| `Escape` | right-edge swipe | Go back or close the launcher |

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
| `accent`, `textColor`, `secondaryTextColor` | `color` | current values of `SETTINGS > General > Color theme` |
| `tileBg`, `tileBgActive`, `tileBorder` | `color` | ready-mixed colors based on `accent` that are used in tiles/buttons |
| `font` | `string` | curent value of `SETTINGS > General > Font` |
| `fontScale` | `real` | current value of `SETTINGS > General > Font size`. It's a multiplier, e.g. `1.2` — turn a size into a real pixel value with `Math.round(px * fontScale)` |
| `iconFont` | `string` | the name of pibble's icon font, you are required to find your own unicode |
| `pageActive` | `bool` | `true` while your page is the one currently showing |
| `launcherOpen` | `bool` | `true` while the launcher is open at all |
| `searchText` | `string` | the current value of pibble's text input |
| `releaseFocus()` | function | call this to give keyboard focus back to pibble if your page took it |
| `tileIn(item, slot, cols)` | function | makes `item` play pibble's tile spawn animation set in `SETTINGS > Pages > Grid animation` — pass `slot`/`cols` if it's one tile among several, so they can stagger in one after another |
| `setSetting(key, value)` / `getSetting(key, fallback)` | function | save/load your page's settings |

Note: Splitting your page across multiple files requires you to declare `import "." as Local`, then use `Local.Foo {}` instead of plain `Foo {}` to access them.

An example custom-page has been provided at `custom-pages/calendar.example/`. To see it in action remove `.example` from the folder name or upload it via `SETTINGS > Pages > Add a page...`.




