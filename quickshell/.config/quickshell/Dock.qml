// Auto-hidden dock: touch the bottom edge of the screen to show pinned and
// open apps as floating icons (Qt renders them sharp at fractional scaling).
//   left click   open the app, or focus it (cycles through its windows)
//   middle click open a new window
//   right click  pin / unpin
// Colors: Theme.qml (matugen colors.json, reloaded live).
// Pinned apps: dock.json (app ids = Hyprland window classes).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: dock

    // ---------- Settings ----------
    readonly property int iconSize: 32
    readonly property int edgeGap: 6       // space above the screen edge, like Waybar's top gap
    readonly property int hotspot: 2       // px strip at the bottom edge that reveals the dock
    readonly property int hideDelay: 400   // ms to wait after the pointer leaves

    property bool shown: false

    // Transparent full-width layer at the bottom. Only the hotspot strip
    // (hidden) or the dock area (shown) takes input; the rest clicks through.
    anchors { left: true; right: true; bottom: true }
    implicitHeight: iconSize + 20 + edgeGap
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-dock"
    mask: Region { item: dock.shown ? content : hotspotStrip }

    // ---------- Data ----------
    FileView {
        path: Quickshell.shellPath("dock.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: config
            property list<string> pinned: []
        }
    }

    // Pinned apps first, then open apps that aren't pinned
    readonly property var apps: {
        const ids = Array.from(config.pinned);
        for (const t of Array.from(ToplevelManager.toplevels.values))
            if (t.appId && !ids.includes(t.appId))
                ids.push(t.appId);
        return ids;
    }

    // Window class -> desktop entry. heuristicLookup misses apps whose .desktop
    // name differs from their class (spotify -> spotify-launcher.desktop via
    // StartupWMClass, "Proton Pass" -> proton-pass.desktop).
    function findEntry(id) {
        const found = DesktopEntries.heuristicLookup(id);
        if (found)
            return found;
        const lower = id.toLowerCase();
        return Array.from(DesktopEntries.applications.values).find(e =>
            e.startupClass.toLowerCase() === lower
            || e.id === lower.replace(/ /g, "-")) ?? null;
    }

    function launch(app) {
        if (app.entry)
            app.entry.execute();
    }

    // Not open: start it. Open: focus it, cycling through its windows.
    function activate(app) {
        const wins = app.windows;
        if (wins.length === 0) {
            launch(app);
            return;
        }
        const i = wins.findIndex(t => t.activated);
        wins[(i + 1) % wins.length].activate();
    }

    function togglePin(id) {
        const list = Array.from(config.pinned);
        const i = list.indexOf(id);
        if (i >= 0)
            list.splice(i, 1);
        else
            list.push(id);
        config.pinned = list;
    }

    // Dashboard's "Stay awake" toggle lives here: the dock window is always mapped
    IdleInhibitor {
        window: dock
        enabled: Session.stayAwake
    }

    Timer {
        id: hideTimer
        interval: dock.hideDelay
        onTriggered: dock.shown = false
    }

    // ---------- UI ----------
    Item {
        id: content
        anchors.fill: parent

        HoverHandler {
            onHoveredChanged: {
                if (hovered) {
                    hideTimer.stop();
                    dock.shown = true;
                } else {
                    hideTimer.restart();
                }
            }
        }

        Item {
            id: hotspotStrip
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: dock.hotspot
        }

        Row {
            id: panel
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            // Slides up from below the screen edge
            y: dock.shown ? parent.height - height - dock.edgeGap : parent.height + 4
            opacity: dock.shown ? 1 : 0
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Repeater {
                model: dock.apps

                delegate: Item {
                    id: app
                    required property string modelData
                    readonly property var entry: dock.findEntry(modelData)
                    readonly property var windows: Array.from(ToplevelManager.toplevels.values)
                        .filter(t => t.appId === modelData)
                    readonly property bool focused: windows.some(t => t.activated)

                    width: dock.iconSize + 16
                    height: dock.iconSize + 20

                    // Hover: small dark backdrop so the icon reads on any wallpaper
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: Theme.bg
                        opacity: appHover.hovered ? 0.6 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 6
                        implicitSize: dock.iconSize
                        source: Quickshell.iconPath(app.entry?.icon || app.modelData.toLowerCase(),
                                                    "application-x-executable")
                        scale: appHover.hovered ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }

                    // Running indicator: dot = 1 window, wider = several, longest = focused
                    Rectangle {
                        visible: app.windows.length > 0
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 3 }
                        height: 4
                        radius: 2
                        width: app.focused ? 16 : (app.windows.length > 1 ? 10 : 5)
                        color: Theme.accent
                        opacity: app.focused ? 1 : 0.7
                        Behavior on width { NumberAnimation { duration: 150 } }
                    }

                    HoverHandler { id: appHover }
                    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: dock.activate(app) }
                    TapHandler { acceptedButtons: Qt.MiddleButton; onTapped: dock.launch(app) }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: dock.togglePin(app.modelData) }
                }
            }
        }
    }
}
