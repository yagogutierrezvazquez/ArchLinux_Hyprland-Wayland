#!/usr/bin/env bash
# wallpaper-list.sh: one line per image in ~/wallpapers -> "name<TAB>path<TAB>thumb".
# Thumbnails (480x270, cropped to fill) are cached in ~/.cache/wallpaper-thumbs
# and only regenerated when the image is newer, so 8K images decode once.
set -euo pipefail

dir="$HOME/wallpapers"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-thumbs"
mkdir -p "$cache"

find "$dir" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -printf '%f\n' | sort | while IFS= read -r f; do
    thumb="$cache/$f.jpg"   # full name: a.jpg and a.png get separate thumbs
    if [[ ! -f $thumb || $dir/$f -nt $thumb ]]; then
        # jpeg:size lets the decoder downscale while reading (fast for 8K)
        magick -define jpeg:size=960x540 "$dir/$f" -thumbnail 480x270^ \
            -gravity center -extent 480x270 -quality 85 "$thumb"
    fi
    printf '%s\t%s\t%s\n' "${f%.*}" "$dir/$f" "$thumb"
done
