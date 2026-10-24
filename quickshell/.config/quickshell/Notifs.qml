pragma Singleton

// Notification daemon (replaces mako). Owns org.freedesktop.Notifications,
// keeps every notification in memory until dismissed (history, RAM only) and
// tracks which ones are currently shown as popups.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    // Do not disturb: new notifications go straight to history (critical ones still pop up)
    property bool dnd: false

    // Notifications currently on screen as popups, oldest first
    property var popups: []
    // Arrival time per notification id (the spec doesn't carry one)
    property var times: ({})

    readonly property var history: server.trackedNotifications.values
    readonly property int maxHistory: 50
    readonly property int maxPopups: 4    // older popups leave the screen (still in history)

    // Ticks once a minute so "now" / "3m" ages update
    SystemClock { id: clock; precision: SystemClock.Minutes }

    function age(n) {
        const s = (clock.date.getTime() - (times[n.id] ?? Date.now())) / 1000;
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + "m" : Math.floor(s / 3600) + "h";
    }

    // Generic status icons (dialog-information, dialog-warning...) become a grey
    // glyph so they match any wallpaper; real app logos are kept.
    // (notify-send -i passes the icon as the image, e.g. image://icon/dialog-information)
    function glyphFor(n) {
        const ic = (n.appIcon + " " + n.image).replace(/image:\/\/icon\//g, "");
        if (/warning|important/.test(ic))
            return 0xf002a;                     // md-alert-outline
        if (/error|critical/.test(ic))
            return 0xf05d6;                     // md-alert-circle-outline
        if (/(^|\s)(dialog-|notification-|info)/.test(ic))
            return 0xf02fd;                     // md-information-outline
        return 0;
    }

    // Notification image. Theme icons arrive as image://icon/<name> and load Qt's
    // magenta placeholder when the name doesn't exist, so check those first.
    function imageFor(n) {
        const img = n.image;
        if (img.startsWith("image://icon/"))
            return Quickshell.iconPath(img.slice(13), true) ? img : "";
        return img;
    }

    // Icon for a notification: its app icon, else the app's desktop entry icon
    function iconFor(n) {
        if (glyphFor(n))
            return "";
        const ic = n.appIcon || DesktopEntries.byId(n.desktopEntry)?.icon || "";
        if (ic.startsWith("/"))
            return "file://" + ic;
        if (ic.includes("://"))
            return ic;
        return ic ? Quickshell.iconPath(ic, true) : "";
    }

    function hidePopup(n) {
        popups = popups.filter(p => p !== n);
    }

    function clearAll() {
        for (const n of history.slice())
            n.dismiss();
    }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            root.times[n.id] = Date.now();
            n.closed.connect(() => root.hidePopup(n));

            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                if (!root.popups.includes(n))
                    root.popups = [...root.popups, n];

            // Too many on screen: drop the oldest non-critical popup
            if (root.popups.length > root.maxPopups) {
                const old = root.popups.find(p => p.urgency !== NotificationUrgency.Critical);
                if (old)
                    root.hidePopup(old);
            }

            // Cap the in-memory history
            const all = server.trackedNotifications.values;
            if (all.length > root.maxHistory)
                all[0].dismiss();
        }
    }
}
