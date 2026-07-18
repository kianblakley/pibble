<h1 align=center>
    pibble
</h1>

> [!NOTE] 
> only tested on niri so far. Other WMs may work but aren't verified.

## Video

todo

## Features

- Clock
- App drawer 
- Wallpaper selector
- Clipboard history 
- Power off
- Volume flyout
- Notification flyout

## Core keybindings

| Key | Action |
|---|---|
| Tab | Navigate pages |
| Ctrl+P (or swipe down) | Reveal power button |
| Ctrl+S | Open settings |

## Installation

**1. Install dependencies**

Necessary:

| Dependency | Use |
|---|---|
| [Quickshell](https://github.com/quickshell-mirror/quickshell) | Runs the shell |
| A Wayland compositor, e.g. [Niri](https://github.com/YaLTeR/niri), [Hyprland](https://github.com/hyprwm/Hyprland) | Hosts the shell |

Optional - required for full features:

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

