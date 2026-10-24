#!/bin/sh
# Called by `wl-paste --watch` on every clipboard change; the content arrives on stdin.
# Stores it in cliphist UNLESS it looks like a password.

# 1. Password managers that mark secrets (x-kde-passwordManagerHint)
[ "$CLIPBOARD_STATE" = "sensitive" ] && exit 0

# 2. Proton Pass doesn't mark them, so skip anything copied while it's focused
hyprctl activewindow | grep -q "^[[:space:]]*class: Proton Pass$" && exit 0

exec cliphist store
