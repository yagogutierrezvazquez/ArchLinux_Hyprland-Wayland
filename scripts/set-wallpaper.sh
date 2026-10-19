#!/usr/bin/env bash
# set-wallpaper.sh <image>: hyprpaper shows it, matugen recolors the system.
# The choice is kept as a symlink that hyprpaper.conf points at, so it
# survives logins. Used by the Quickshell carousel (SUPER+W) and rofi picker.
set -euo pipefail

path=$(realpath -- "${1:?usage: set-wallpaper.sh <image>}")
[[ -f $path ]] || { echo "not a file: $path" >&2; exit 1; }
# hyprpaper's IPC splits its argument on commas
if [[ $path == *,* ]]; then
    notify-send "Wallpaper" "Rename the file: commas are not supported"
    exit 1
fi

state="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper"
mkdir -p "$state"
ln -sfn "$path" "$state/current"
hyprctl hyprpaper wallpaper ", $path, cover" >/dev/null

# Black/white/grey wallpapers have no hue: matugen would invent one (or use
# its blue fallback). Measure the share of clearly colored pixels (HSL
# saturation > 25%, not near black/white); under 2% = monochrome.
colorful=$(magick "$path" -resize 200x200 -colorspace HSL \
    -fx 'g>0.25 && b>0.15 && b<0.85' -format '%[fx:mean]' info:)
mono=$(awk -v c="$colorful" 'BEGIN { print (c < 0.02) ? "true" : "false" }')

# Extra template data: templates use mono_accent (white) instead of the
# wallpaper color when mono is true
palette="$state/palette.json"
printf '{ "mono": %s, "mono_accent": "#e8e8e8" }\n' "$mono" > "$palette"

if [[ $mono == true ]]; then
    # Neutral greys (no invented tint)
    matugen color hex "#808080" -t scheme-monochrome -m dark --import-json "$palette" --quiet
else
    # fidelity: accent = the wallpaper's real color (not a pastel); always dark
    matugen image "$path" -t scheme-fidelity -m dark --import-json "$palette" --quiet
fi

# Terminal fetch logo: Arch logo as white dots on a grid tinted with the new
# dim color (needs the colors matugen just wrote)
dim=$(sed -n 's/.*"fgDim": "\(#[0-9a-fA-F]*\)".*/\1/p' "$HOME/.config/quickshell/colors.json")
"$HOME/.config/hypr/scripts/fetch-logo.py" "${XDG_CACHE_HOME:-$HOME/.cache}/fetch-logo.png" "${dim:-#6e6e6e}"
