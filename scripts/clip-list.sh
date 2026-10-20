#!/usr/bin/env bash
# clip-list.sh: clipboard history for the Quickshell panel (SUPER+V), newest
# first, one "id<TAB>kind<TAB>preview<TAB>image" line per entry.
# Images are decoded for previews into $XDG_RUNTIME_DIR/clip-thumbs (RAM,
# mode 700); the panel deletes that folder when it closes.
set -euo pipefail

umask 077   # previews are private (folder 700, files 600)
thumbs="${XDG_RUNTIME_DIR:?}/clip-thumbs"
mkdir -p -m 700 "$thumbs"

cliphist -preview-width 300 list | while IFS=$'\t' read -r id preview; do
    [[ $id =~ ^[0-9]+$ ]] || continue
    if [[ $preview =~ ^\[\[\ binary\ data\ .*\ (png|jpeg|jpg|webp|gif|bmp)\ ([0-9]+x[0-9]+) ]]; then
        img="$thumbs/$id.${BASH_REMATCH[1]}"
        [[ -f $img ]] || cliphist decode "$id" > "$img"
        printf '%s\timage\t%s\t%s\n' "$id" "${BASH_REMATCH[2]}" "$img"
    elif [[ $preview =~ ^https?:// ]]; then
        printf '%s\tlink\t%s\t\n' "$id" "${preview//$'\t'/ }"
    else
        printf '%s\ttext\t%s\t\n' "$id" "${preview//$'\t'/ }"
    fi
done
