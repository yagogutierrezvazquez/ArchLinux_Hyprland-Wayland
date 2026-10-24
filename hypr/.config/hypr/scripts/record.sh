#!/usr/bin/env bash
# record.sh toggle | status: screen recording with wf-recorder (SUPER+SHIFT+R,
# or click the dot in Waybar). Video only, no audio, saved to ~/Vídeos/records.
# wf-recorder isn't on the screencopy allow-list (permissions.lua): Hyprland
# asks every time -> click "Allow once", never "remember".
#   status  JSON for the Waybar dot (custom/record): grey idle, red recording
#   toggle  start, or stop if it's running (SIGINT lets it finish the file)
set -uo pipefail

refresh() { pkill -RTMIN+8 -x waybar; }   # Waybar custom/record has "signal": 8

case ${1:-status} in
status)
    if pgrep -x wf-recorder >/dev/null; then
        echo '{"text": "", "class": "recording", "tooltip": "Recording · SUPER+SHIFT+R to stop"}'
    else
        echo '{"text": "", "class": "idle", "tooltip": "Not recording · SUPER+SHIFT+R to record"}'
    fi
    ;;
toggle)
    if pgrep -x wf-recorder >/dev/null; then
        pkill -INT -x wf-recorder          # the starting instance below reports the result
        exit 0
    fi
    dir="$(xdg-user-dir VIDEOS)/records"
    mkdir -p "$dir"
    file="$dir/recording-$(date +%Y%m%d-%H%M%S).mp4"
    # Intel GPU encodes (VAAPI): smooth 60 fps without loading the CPU
    wf-recorder -c h264_vaapi -d /dev/dri/renderD128 -f "$file" >/dev/null 2>&1 &
    sleep 0.3; refresh
    wait $!
    refresh
    if [[ -s $file ]]; then
        notify-send -a "Recorder" "Recording saved" "${file/#$HOME/\~}"
    else
        rm -f -- "$file"
        notify-send -a "Recorder" "Recording failed" "Permission denied, or the encoder failed"
    fi
    ;;
esac
