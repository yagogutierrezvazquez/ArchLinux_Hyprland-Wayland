#!/usr/bin/env python3
"""Waybar custom/media: a music icon while a player is playing or paused.

Replaces Waybar's built-in mpris module, which crashed the whole bar now and
then (segfault in libplayerctl, upstream Waybar #4450 / #2065). Here playerctl
runs as a separate process: if it misbehaves only this script dies and Waybar
restarts it (restart-interval), the bar stays up.
Prints one JSON line per change; empty text = hidden (no player / stopped).
"""
import json
import subprocess

ICONS = {"spotify": ""}      # fa-spotify
DEFAULT = ""                 # fa-music
FORMAT = "{{status}}\t{{playerName}}\t{{markup_escape(title)}}\t{{markup_escape(artist)}}"


def main():
    # --follow prints a line on every change, and an empty line when the player goes away
    proc = subprocess.Popen(["playerctl", "--follow", "metadata", "--format", FORMAT],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    for line in proc.stdout:
        status, player, title, artist = (line.rstrip("\n").split("\t") + [""] * 4)[:4]
        if status not in ("Playing", "Paused"):
            out = {"text": ""}
        else:
            out = {"text": ICONS.get(player, DEFAULT), "class": status.lower(),
                   "tooltip": f"{title} — {artist}" if artist else title}
        print(json.dumps(out, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
