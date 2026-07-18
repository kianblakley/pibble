<h1 align=center>
    pibble
</h1>

> [!IMPORTANT] 
> I have only extensively tested this on Niri so far. Please open a GitHub issue if you encounter any bugs.

[demo coming]

## Features

- Clock
- App drawer 
- Wallpaper selector
- Clipboard history 
- Power off
- Volume flyout
- Notification flyout
- Extensive settings

## Installation

**1. Install dependencies**

Necessary:

| Dependency | Use |
|---|---|
| [Quickshell](https://github.com/quickshell-mirror/quickshell) | Runs the shell |
| A Wayland compositor, e.g. [Niri](https://github.com/YaLTeR/niri), [Hyprland](https://github.com/hyprwm/Hyprland) | Hosts the shell |

Optional (required for full feature set):

| Dependency | Use |
|---|---|
| [cliphist](https://github.com/sentriz/cliphist) | Clipboard history |
| [ImageMagick](https://github.com/ImageMagick/ImageMagick) | Wallpaper/clip thumbnails |
| [awww](https://codeberg.org/LGFae/awww) | Sets the wallpaper (can use any program via settings) |
| [matugen](https://github.com/InioX/matugen) | Wallpaper-derived color theme |


**2. Clone**

```sh
git clone https://github.com/kianblakley/pibble.git
cd pibble
```

**3. Start the daemon**

```sh
./pibble
```

**4. Toggle the launcher**

```sh
./pibble toggle
```

## Core Keybindings

| Key | Action |
|---|---|
| `Tab` | Navigate pages |
| `Ctrl+P` (or swipe down) | Reveal power button |
| `Ctrl+S` | Open settings |

## Namespaces

Each pibble window has a layer-shell namespace which can be used to apply background effects in your compositor's configuration file.

| Namespace | Window |
|---|---|
| `pibble-launcher` | Main launcher window |
| `pibble-notifications` | Notification flyout |
| `pibble-volume` | Volume OSD |



