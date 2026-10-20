#!/usr/bin/env bash
# clip-paste.sh <id>: put a clipboard-history entry back on the clipboard and
# paste it into the focused window (like Windows Win+V). Pasting uses wtype
# (Wayland virtual keyboard: no input group, no root); without it, only copies.
set -euo pipefail

id=${1:?usage: clip-paste.sh <id>}
[[ $id =~ ^[0-9]+$ ]] || exit 1

cliphist decode "$id" | wl-copy
command -v wtype >/dev/null || exit 0

# Let the panel close and focus return to the previous window
sleep 0.15
# Terminals paste with Ctrl+Shift+V
class=$(hyprctl activewindow | sed -n 's/^[[:space:]]*class: //p')
case $class in
    kitty|Alacritty|foot|org.wezfurlong.wezterm|com.mitchellh.ghostty)
        wtype -M ctrl -M shift v -m shift -m ctrl ;;
    *)
        wtype -M ctrl v -m ctrl ;;
esac
