pragma Singleton

// The media player to show: the one playing, otherwise the first one
// (e.g. paused Spotify). Shared by the media popup and the dashboard.
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    readonly property var active: {
        const all = Array.from(Mpris.players.values);
        return all.find(p => p.isPlaying) ?? all[0] ?? null;
    }

    function fmt(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
}
