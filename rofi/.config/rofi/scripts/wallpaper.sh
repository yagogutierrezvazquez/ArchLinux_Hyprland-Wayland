#!/usr/bin/env bash
# Fallback wallpaper picker (rofi). The main one is the Quickshell carousel
# (SUPER+W); both apply the choice with hypr/scripts/set-wallpaper.sh.
# Thumbnails come from rofi's XDG thumbnail support (thumbnail://, cached in
# ~/.cache/thumbnails).
set -euo pipefail

dir="$HOME/wallpapers"
current="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper/current"

mapfile -t files < <(find "$dir" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -printf '%f\n' | sort)
(( ${#files[@]} )) || { notify-send "Wallpaper" "No images in $dir"; exit 1; }

# One row of N equal columns (max 4): rofi splits the width evenly, so the
# strip is always symmetric; more wallpapers scroll page by page.
# Width: 260 per column (thumbnail 220 + padding 2x10 + spacing, plus slack
# that the grid spreads evenly) + window padding/border.
visible=$(( ${#files[@]} < 4 ? ${#files[@]} : 4 ))
width=$(( visible * 260 + 40 ))

# Start with the current wallpaper selected
active=$(basename "$(readlink "$current" 2>/dev/null)" 2>/dev/null || true)
selected=0
for i in "${!files[@]}"; do
    [[ ${files[i]} == "$active" ]] && selected=$i
done

# Rows: real filename (returned on select), shown without extension, with thumbnail
choice=$(for f in "${files[@]}"; do
    printf '%s\0display\x1f%s\x1ficon\x1fthumbnail://%s\n' "$f" "${f%.*}" "$dir/$f"
done | rofi -dmenu -i -show-icons \
    -p $'' \
    -selected-row "$selected" \
    -theme-str "window { width: ${width}px; } listview { columns: ${visible}; }" \
    -theme "$HOME/.config/rofi/wallpaper.rasi") || exit 0   # Esc = do nothing

"$HOME/.config/hypr/scripts/set-wallpaper.sh" "$dir/$choice"
