#!/usr/bin/env bash
# Launcher wrapper: applies the icon theme chosen in the settings pane.
# Qt can't switch icon themes at runtime, so quickshell reads QS_ICON_THEME
# at startup; we pull it out of the launcher's persisted settings.
settings="$HOME/.local/state/quickshell/by-shell/b3c79d9b1b83e8627e01e1689066fbb2/settings.json"
theme=$(sed -n 's/.*"iconTheme": *"\([^"]*\)".*/\1/p' "$settings" 2>/dev/null | head -1)
[ -n "$theme" ] && export QS_ICON_THEME="$theme"
exec qs -p "$(dirname "$(readlink -f "$0")")"
