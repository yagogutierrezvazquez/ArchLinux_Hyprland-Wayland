// Dashboard: drops down from the top center (SUPER+A or Waybar's button).
//   qs ipc call dashboard toggle
// Tabs: Dashboard (clock, calendar, agenda from Google Calendar, media, power row) and
// Controls (Wi-Fi, Bluetooth, DND, stay awake, volume, brightness,
// Bluetooth devices), Notifications (history kept in RAM by Notifs) and
// Performance (CPU, GPU, storage, network, memory).
// Esc or a click outside closes it.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: dash

    property int tab: 0
    property int monthOffset: 0       // calendar: months away from the current one
    property string armed: ""         // power action waiting for its confirming click

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts/"

    // System stats (refreshed every 2 s while open, every 1 s on the Performance tab)
    property real cpu: 0
    property real ram: 0
    property real temp: 0
    property string uptime: ""
    property string host: ""
    property var last: null           // previous counters, to turn them into rates

    // Performance tab
    property string cpuModel: ""
    property string gpuName: ""
    property string diskName: ""
    property real cpuGhz: 0
    property real gpu: -1             // busy share; -1 = no RC6 counter (not an i915 GPU)
    property real gpuGhz: 0
    property real gpuMaxGhz: 0
    property real memUsed: 0          // KiB
    property real memTotal: 1
    property real diskUsed: 0         // KiB
    property real diskTotal: 1
    property real diskTemp: 0
    property string netDev: ""
    property real rxRate: 0           // bytes/s
    property real txRate: 0
    property real rxTotal: 0          // bytes since boot
    property real txTotal: 0
    property var rxHist: []           // last rates, for the network graph
    property var txHist: []
    readonly property int histLength: 40

    visible: false
    anchors.top: true                 // only top anchored -> centered horizontally
    margins.top: 8
    implicitWidth: 1000
    implicitHeight: card.implicitHeight
    color: "transparent"
    focusable: true
    WlrLayershell.namespace: "quickshell-dashboard"

    onVisibleChanged: {
        if (!visible)
            return;
        tab = 0;
        monthOffset = 0;
        armed = "";
        last = null;
        rxHist = [];
        txHist = [];
        selectedDay = null;
        refreshAgenda(false);
    }

    IpcHandler {
        target: "dashboard"
        function toggle(): void { dash.visible = !dash.visible; }
        // Open on a given tab (0 = Dashboard, 1 = Controls, 2 = Notifications, 3 = Performance)
        function open(tab: int): void { dash.visible = true; dash.tab = tab; }
    }

    HyprlandFocusGrab {
        windows: [ dash ]
        active: dash.visible
        onCleared: dash.visible = false
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---------- Stats ----------
    // One sample per run, as key=value lines (hypr/scripts/perf-stats.sh)
    Process {
        id: statProc
        command: [dash.scripts + "perf-stats.sh"]
        stdout: StdioCollector { onStreamFinished: dash.parseStats(text) }
    }

    Timer {
        running: dash.visible
        interval: dash.tab === 3 ? 1000 : 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: statProc.running = true
    }

    // Names that don't change: read once
    Process {
        running: true
        command: [dash.scripts + "perf-stats.sh", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = dash.keyValues(text);
                // "13th Gen Intel(R) Core(TM) i7-13620H" -> "Intel Core i7-13620H"
                dash.cpuModel = (s.cpuModel ?? "").replace(/\((R|TM)\)/g, "").replace(/^\d+th Gen /, "");
                // "Intel Corporation Raptor Lake-P [UHD Graphics]" -> "Intel UHD Graphics"
                const g = (s.gpuName ?? "").match(/^(\S+).*\[(.+)\]/);
                dash.gpuName = g ? g[1] + " " + g[2] : (s.gpuName ?? "").replace(" Corporation", "");
                dash.diskName = s.disk ?? "";
            }
        }
    }

    function keyValues(text) {
        const s = {};
        for (const line of text.trim().split("\n")) {
            const i = line.indexOf("=");
            if (i > 0)
                s[line.slice(0, i)] = line.slice(i + 1).trim();
        }
        return s;
    }

    function parseStats(text) {
        const s = keyValues(text);
        const f = (s.cpu ?? "").split(/\s+/).map(Number);
        const idle = f[3] + f[4];
        const total = f.reduce((a, b) => a + b, 0);
        const t = Number((s.uptime ?? "0").split(" ")[0]);   // seconds since boot
        const rc6 = s.rc6 ? Number(s.rc6) : -1;
        const rx = Number(s.rx || 0);
        const tx = Number(s.tx || 0);

        if (last && t > last.t) {
            const dt = t - last.t;
            // CPU: busy share of the time since the previous sample
            cpu = 1 - (idle - last.idle) / Math.max(1, total - last.total);
            // GPU: share of the time it was *not* idle in RC6
            gpu = rc6 < 0 ? -1 : Math.max(0, Math.min(1, 1 - (rc6 - last.rc6) / (dt * 1000)));
            rxRate = Math.max(0, (rx - last.rx) / dt);
            txRate = Math.max(0, (tx - last.tx) / dt);
            rxHist = [...rxHist, rxRate].slice(-histLength);
            txHist = [...txHist, txRate].slice(-histLength);
        }
        last = { idle: idle, total: total, t: t, rc6: rc6, rx: rx, tx: tx };

        // RAM: (total - available) / total
        memTotal = Number(s.memTotal) || 1;
        memUsed = memTotal - Number(s.memAvail);
        ram = memUsed / memTotal;
        temp = Number(s.temp) / 1000;
        cpuGhz = Number(s.cpuMhz) / 1000;
        gpuGhz = Number(s.gpuMhz) / 1000;
        gpuMaxGhz = Number(s.gpuMaxMhz) / 1000;
        netDev = s.netDev ?? "";
        rxTotal = rx;
        txTotal = tx;
        diskTotal = Number(s.diskTotal) || 1;
        diskUsed = Number(s.diskUsed);
        diskTemp = Number(s.diskTemp || 0) / 1000;

        const up = Math.floor(t / 60);
        uptime = up >= 60 ? Math.floor(up / 60) + "h " + (up % 60) + "m" : up + "m";
        host = s.host ?? "";
    }

    // 18300 -> "18.3 KB" (decimal units, like browsers and download managers)
    function bytes(b) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1000 && i < units.length - 1) {
            b /= 1000;
            i++;
        }
        return (i === 0 ? Math.round(b) : b.toFixed(b < 100 ? 1 : 0)) + " " + units[i];
    }

    function gib(kib) {
        return (kib / 1048576).toFixed(1);
    }

    // ---------- Agenda ----------
    // Read-only Google Calendar: hypr/scripts/agenda.py fetches the secret iCal
    // links in ~/.local/share/agenda/calendars and writes ~/.cache/agenda/data.json
    // (events grouped by day). Refreshed on open when older than 15 min.
    property var agenda: null
    property var selectedDay: null    // day clicked in the calendar; null = today
    readonly property var dayEvents: agenda?.days?.[dayKey(selectedDay ?? clock.date)] ?? []
    // Fixed colors per calendar (Google's colors aren't in the iCal feed)
    readonly property var calColors: ["#f2726f", "#7aa7f0", "#8fd18a", "#e8c46a", "#c592e8", "#6fcfcf", "#ff9e64", "#d8afff"]

    function calColor(i) {
        return calColors[i % calColors.length];
    }

    function dayKey(d) {
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    FileView {
        id: agendaFile
        path: Quickshell.env("HOME") + "/.cache/agenda/data.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                dash.agenda = JSON.parse(text());
            } catch (e) {
                dash.agenda = null;
            }
        }
    }

    Process {
        id: agendaProc
        command: [Quickshell.env("HOME") + "/.local/share/agenda/venv/bin/python", "-I", dash.scripts + "agenda.py"]
        onExited: agendaFile.reload()
    }

    // force = refresh button: download now, whatever the age
    function refreshAgenda(force) {
        if (!agendaProc.running && (force || Date.now() - (agenda?.fetched ?? 0) > 15 * 60000))
            agendaProc.running = true;
    }

    // ---------- Controls state ----------
    // Wi-Fi + brightness come from CLI tools (polled while the tab is
    // open); Bluetooth and volume come from Quickshell's native services.
    property bool wifiOn: false
    property string ssid: ""
    readonly property bool dnd: Notifs.dnd
    property real brightness: 0
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var btDevices: Array.from(Bluetooth.devices.values).filter(d => d.paired)

    // Volume/mute are only valid on a bound node
    PwObjectTracker { objects: [ dash.sink ] }

    Process {
        id: ctlProc
        command: ["sh", "-c",
            "printf '%s\\n' \"$(nmcli radio wifi)\" "
            + "\"$(nmcli -t -f NAME,TYPE connection show --active | sed -n 's/:802-11-wireless$//p' | head -1)\" "
            + "\"$(brightnessctl -m)\""]
        stdout: StdioCollector { onStreamFinished: dash.parseControls(text) }
    }

    Timer {
        running: dash.visible && dash.tab === 1
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: ctlProc.running = true
    }

    // Re-read state shortly after changing something
    Timer {
        id: refresh
        interval: 400
        onTriggered: ctlProc.running = true
    }

    function parseControls(text) {
        const l = text.split("\n");
        wifiOn = l[0] === "enabled";
        ssid = (l[1] ?? "").replace(/\\:/g, ":");
        const b = (l[2] ?? "").split(",");
        if (b.length >= 4)
            brightness = Number(b[3].replace("%", "")) / 100;
    }

    function run(command) {
        Quickshell.execDetached(command);
        refresh.restart();
    }

    // Bluetooth on = unblock the radio (rfkill soft block, allowed for the
    // active session via logind's uaccess) and then power the adapter.
    Timer {
        id: btPowerOn
        interval: 800
        onTriggered: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = true
    }
    function toggleBluetooth() {
        const a = Bluetooth.defaultAdapter;
        if (a?.enabled) {
            a.enabled = false;
            return;
        }
        Quickshell.execDetached(["rfkill", "unblock", "bluetooth"]);
        btPowerOn.restart();
    }

    // Brightness: apply at most every 60 ms while dragging, never below 5%
    property real pendingBrightness: -1
    Timer {
        id: brightnessApply
        interval: 60
        onTriggered: {
            Quickshell.execDetached(["brightnessctl", "-q", "set",
                                     Math.round(Math.max(0.05, dash.pendingBrightness) * 100) + "%"]);
        }
    }
    function setBrightness(v) {
        brightness = Math.max(0.05, v);
        pendingBrightness = v;
        if (!brightnessApply.running)
            brightnessApply.start();
    }

    // ---------- Power ----------
    // Destructive actions need a second click within 3 s
    Timer {
        id: disarm
        interval: 3000
        onTriggered: dash.armed = ""
    }

    function power(action, command, needsConfirm) {
        if (needsConfirm && armed !== action) {
            armed = action;
            disarm.restart();
            return;
        }
        armed = "";
        dash.visible = false;
        Quickshell.execDetached(command);
    }

    // ---------- Reusable pieces ----------
    component Card: Rectangle {
        radius: 12
        color: Theme.surface
    }

    component Glyph: Text {
        property int code
        text: String.fromCodePoint(code)
        font.family: Theme.font
        color: Theme.fg
    }

    component IconButton: Item {
        id: ib
        property int code
        property string label: ""
        property bool danger: false     // armed state is drawn in the warning color
        property bool highlighted: false
        signal activated()

        implicitWidth: Math.max(44, row.implicitWidth + 24)
        implicitHeight: 40

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: ib.highlighted ? Theme.withAlpha("#ef4444", 0.25)
                 : hov.hovered ? Theme.withAlpha(Theme.accent, 0.15) : "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Glyph {
                code: ib.code
                font.pixelSize: 18
                color: ib.highlighted ? "#ef4444" : hov.hovered ? Theme.accent : Theme.fg
            }
            Text {
                visible: ib.label !== ""
                text: ib.label
                font { family: Theme.font; pixelSize: 12 }
                color: ib.highlighted ? "#ef4444" : Theme.fgDim
            }
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.activated() }
    }

    // Toggle tile: click toggles; optional chevron opens a menu
    component Tile: Rectangle {
        id: tile
        property int code
        property string title
        property string subtitle
        property bool active: false
        property bool menu: false
        signal toggled()
        signal menuRequested()

        radius: 12
        color: active ? Theme.withAlpha(Theme.accent, 0.16) : Theme.surface
        border.width: 1
        border.color: mainHover.hovered || chevHover.hovered ? Theme.withAlpha(Theme.accent, 0.35) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                    spacing: 12

                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 21
                        color: tile.active ? Theme.accent : Theme.bg
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Glyph {
                            anchors.centerIn: parent
                            code: tile.code
                            font.pixelSize: 20
                            color: tile.active ? Theme.accentText : Theme.fgDim
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: tile.title
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 13; bold: true }
                            color: Theme.fg
                        }
                        Text {
                            Layout.fillWidth: true
                            text: tile.subtitle
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 11 }
                            color: tile.active ? Theme.accent : Theme.fgDim
                        }
                    }
                }
                HoverHandler { id: mainHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: tile.toggled() }
            }

            Item {
                visible: tile.menu
                Layout.preferredWidth: 34
                Layout.fillHeight: true
                Rectangle {
                    anchors { fill: parent; margins: 6 }
                    radius: 8
                    color: chevHover.hovered ? Theme.withAlpha(Theme.accent, 0.2) : "transparent"
                }
                Glyph {
                    anchors.centerIn: parent
                    code: 0xf0142   // md-chevron-right
                    font.pixelSize: 18
                    color: chevHover.hovered ? Theme.accent : Theme.fgDim
                }
                HoverHandler { id: chevHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: tile.menuRequested() }
            }
        }
    }

    // Horizontal slider: click or drag to set, scroll to nudge by 5%
    component Slider: Item {
        id: sl
        property real value: 0          // 0..1
        property bool dimmed: false
        signal moved(real v)

        implicitHeight: 24

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: Theme.bg
            Rectangle {
                height: parent.height
                radius: 3
                width: Math.max(height, parent.width * Math.min(1, sl.value))
                color: sl.dimmed ? Theme.fgDim : Theme.accent
            }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: (sl.width - width) * Math.min(1, sl.value)
            width: 14
            height: 14
            radius: 7
            color: Theme.fg
            opacity: area.containsMouse || area.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function update(mx) { sl.moved(Math.max(0, Math.min(1, mx / width))); }
            onPressed: e => update(e.x)
            onPositionChanged: e => { if (pressed) update(e.x); }
            onWheel: w => sl.moved(Math.max(0, Math.min(1, sl.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }

    // Round gauge. span 360 = full ring starting at the top; less = open at
    // the bottom (speedometer style). Turns red above 90%.
    component Ring: Item {
        id: ring
        property real value: 0          // 0..1
        property real span: 360
        property real thickness: 8
        readonly property real start: span >= 360 ? -90 : 90 + (360 - span) / 2
        readonly property real r: (Math.min(width, height) - thickness) / 2
        property real shown: Math.max(0, Math.min(1, value))
        Behavior on shown { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {                 // track
                fillColor: "transparent"
                strokeColor: Theme.bg
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: ring.r
                    radiusY: ring.r
                    startAngle: ring.start
                    sweepAngle: ring.span
                }
            }
            ShapePath {                 // value
                fillColor: "transparent"
                strokeColor: ring.value > 0.9 ? "#ef4444" : Theme.accent
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: ring.r
                    radiusY: ring.r
                    startAngle: ring.start
                    sweepAngle: Math.max(0.1, ring.span * ring.shown)
                }
            }
        }
    }

    // Thin horizontal bar
    component Bar: Rectangle {
        property real value: 0          // 0..1
        property bool hot: false        // drawn in the warning color
        implicitHeight: 6
        radius: 3
        color: Theme.bg
        Rectangle {
            height: parent.height
            radius: 3
            width: Math.max(height, parent.width * Math.max(0, Math.min(1, parent.value)))
            color: parent.hot ? "#ef4444" : Theme.accent
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }

    // Performance card for a processor: icon, name, model, one detail with
    // a bar under it, and the usage ring on the right
    component ChipCard: Card {
        id: chip
        property int code
        property string title
        property string model
        property int detailCode
        property string detail
        property string extra           // small text after the bar
        property real detailValue: 0    // 0..1
        property bool hot: false
        property real usage: 0          // 0..1, -1 = unknown

        RowLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 14

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 42
                implicitHeight: 42
                radius: 21
                color: Theme.bg
                Glyph {
                    anchors.centerIn: parent
                    code: chip.code
                    font.pixelSize: 20
                    color: Theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: chip.title
                    font { family: Theme.font; pixelSize: 15; bold: true }
                    color: Theme.fg
                }
                Text {
                    Layout.fillWidth: true
                    text: chip.model
                    elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: 12 }
                    color: Theme.fgDim
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 8
                    Glyph {
                        code: chip.detailCode
                        font.pixelSize: 14
                        color: chip.hot ? "#ef4444" : Theme.fgDim
                    }
                    Text {
                        text: chip.detail
                        font { family: Theme.font; pixelSize: 13; bold: true }
                        color: chip.hot ? "#ef4444" : Theme.fg
                    }
                    Bar {
                        Layout.fillWidth: true
                        value: chip.detailValue
                        hot: chip.hot
                    }
                    Text {
                        visible: chip.extra !== ""
                        text: chip.extra
                        font { family: Theme.font; pixelSize: 11 }
                        color: Theme.fgDim
                    }
                }
            }

            Item {
                implicitWidth: 76
                implicitHeight: 76
                Ring {
                    anchors.fill: parent
                    value: Math.max(0, chip.usage)
                    thickness: 7
                }
                Column {
                    anchors.centerIn: parent
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: chip.usage < 0 ? "–" : Math.round(chip.usage * 100) + "%"
                        font { family: Theme.font; pixelSize: 17; bold: true }
                        color: Theme.fg
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "usage"
                        font { family: Theme.font; pixelSize: 10 }
                        color: Theme.fgDim
                    }
                }
            }
        }
    }

    // ---------- Window ----------
    Rectangle {
        id: card
        width: parent.width
        implicitHeight: layout.implicitHeight + 36
        radius: 16
        color: Theme.bg
        border.width: 1
        border.color: Theme.withAlpha(Theme.accent, 0.25)

        Item {
            focus: true
            Keys.onEscapePressed: dash.visible = false
        }

        ColumnLayout {
            id: layout
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 14

            // ---------- Tabs ----------
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                Repeater {
                    model: [
                        { name: "Dashboard", code: 0xf056e },   // md-view-dashboard
                        { name: "Controls",  code: 0xf062e },   // md-tune
                        { name: "Notifications", code: 0xf009c }, // md-bell-outline
                        { name: "Performance", code: 0xf04c5 }    // md-speedometer
                    ]
                    delegate: Item {
                        id: tabItem
                        required property var modelData
                        required property int index
                        readonly property bool current: dash.tab === index
                        implicitWidth: tabRow.implicitWidth + 32
                        implicitHeight: 36

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: tabItem.current ? Theme.withAlpha(Theme.accent, 0.15)
                                 : tabHover.hovered ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 8
                            Glyph {
                                code: tabItem.modelData.code
                                font.pixelSize: 16
                                color: tabItem.current ? Theme.accent : Theme.fgDim
                            }
                            Text {
                                text: tabItem.modelData.name
                                font { family: Theme.font; pixelSize: 13; bold: tabItem.current }
                                color: tabItem.current ? Theme.accent : Theme.fgDim
                            }
                            // Notification count badge
                            Rectangle {
                                visible: tabItem.index === 2 && Notifs.history.length > 0
                                implicitHeight: 18
                                implicitWidth: Math.max(18, badge.implicitWidth + 10)
                                radius: 9
                                color: Theme.accent
                                Text {
                                    id: badge
                                    anchors.centerIn: parent
                                    text: Notifs.history.length
                                    font { family: Theme.font; pixelSize: 10; bold: true }
                                    color: Theme.accentText
                                }
                            }
                        }
                        HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: dash.tab = tabItem.index }
                    }
                }
            }

            // ---------- Tab: Dashboard ----------
            RowLayout {
                visible: dash.tab === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 270
                spacing: 12

                // Clock
                Card {
                    Layout.preferredWidth: 170
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDateTime(clock.date, "HH")
                            font { family: Theme.font; pixelSize: 52; bold: true }
                            color: Theme.accent
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Qt.formatDateTime(clock.date, "mm")
                            font { family: Theme.font; pixelSize: 52; bold: true }
                            color: Theme.fg
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 6
                            text: Qt.formatDateTime(clock.date, "ddd, d MMM")
                            font { family: Theme.font; pixelSize: 13 }
                            color: Theme.fgDim
                        }
                    }
                }

                // Calendar (weeks start on Monday)
                Card {
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true

                    ColumnLayout {
                        id: cal
                        anchors { fill: parent; margins: 14 }
                        spacing: 8

                        readonly property date first: new Date(clock.date.getFullYear(),
                                                                clock.date.getMonth() + dash.monthOffset, 1)
                        readonly property int lead: (first.getDay() + 6) % 7

                        RowLayout {
                            Layout.fillWidth: true
                            IconButton { code: 0xf053; implicitHeight: 28; onActivated: dash.monthOffset-- }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: Qt.formatDate(cal.first, "MMMM yyyy")
                                font { family: Theme.font; pixelSize: 13; bold: true }
                                color: Theme.fg
                            }
                            IconButton { code: 0xf054; implicitHeight: 28; onActivated: dash.monthOffset++ }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 7
                            rowSpacing: 0
                            columnSpacing: 0

                            Repeater {
                                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                                delegate: Text {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    font { family: Theme.font; pixelSize: 11; bold: true }
                                    color: Theme.fgDim
                                }
                            }

                            Repeater {
                                model: 42
                                delegate: Item {
                                    id: day
                                    required property int index
                                    readonly property date d: new Date(cal.first.getFullYear(), cal.first.getMonth(),
                                                                       1 - cal.lead + index)
                                    readonly property bool inMonth: d.getMonth() === cal.first.getMonth()
                                    readonly property bool today: d.toDateString() === clock.date.toDateString()
                                    readonly property bool selected: dash.selectedDay !== null && d.toDateString() === dash.selectedDay.toDateString()
                                    readonly property bool busy: (dash.agenda?.days?.[dash.dayKey(d)] ?? []).length > 0
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 26; height: 26; radius: 13
                                        color: day.today ? Theme.accent
                                             : dayHover.hovered ? Theme.withAlpha(Theme.accent, 0.15) : "transparent"
                                        border.width: day.selected ? 1.5 : 0
                                        border.color: Theme.accent
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: day.d.getDate()
                                        font { family: Theme.font; pixelSize: 12; bold: day.today || day.selected }
                                        color: day.today ? Theme.accentText : day.inMonth ? Theme.fg : Theme.withAlpha(Theme.fgDim, 0.5)
                                    }
                                    // Has events
                                    Rectangle {
                                        visible: day.busy && !day.today
                                        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 10 }
                                        width: 3; height: 3; radius: 1.5
                                        color: day.inMonth ? Theme.accent : Theme.withAlpha(Theme.accent, 0.4)
                                    }
                                    HoverHandler { id: dayHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: dash.selectedDay = day.today ? null : day.d }
                                }
                            }
                        }
                    }
                }

                // Agenda: today, or the day clicked in the calendar
                Card {
                    Layout.preferredWidth: 270
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors { fill: parent; margins: 14 }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: dash.selectedDay ? Qt.formatDate(dash.selectedDay, "dddd d MMM") : "Today"
                                elide: Text.ElideRight
                                font { family: Theme.font; pixelSize: 14; bold: true }
                                color: Theme.fg
                            }
                            IconButton {
                                id: agendaRefresh
                                implicitHeight: 26
                                implicitWidth: 30
                                code: 0xf0450                             // md-refresh
                                onActivated: dash.refreshAgenda(true)
                                RotationAnimation on rotation {
                                    running: agendaProc.running
                                    loops: Animation.Infinite
                                    from: 0
                                    to: 360
                                    duration: 900
                                    onRunningChanged: if (!running) agendaRefresh.rotation = 0
                                }
                            }
                            IconButton {
                                visible: dash.selectedDay !== null
                                implicitHeight: 26
                                code: 0xf00f6                             // md-calendar-today
                                label: "Today"
                                onActivated: dash.selectedDay = null
                            }
                        }

                        // Empty state
                        Item {
                            visible: dash.dayEvents.length === 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Glyph {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    code: 0xf00ed                         // md-calendar
                                    font.pixelSize: 30
                                    color: Theme.fgDim
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: dash.agenda ? "Nothing planned"
                                        : agendaProc.running ? "Loading calendars…" : "No calendars yet"
                                    font { family: Theme.font; pixelSize: 12 }
                                    color: Theme.fgDim
                                }
                            }
                        }

                        ListView {
                            visible: dash.dayEvents.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            model: dash.dayEvents

                            delegate: Item {
                                id: ev
                                required property var modelData
                                readonly property real nowMs: clock.date.getTime()
                                readonly property bool onToday: dash.selectedDay === null
                                readonly property bool past: onToday && !modelData.allDay && modelData.end <= nowMs
                                readonly property bool current: onToday && !modelData.allDay && modelData.start <= nowMs && nowMs < modelData.end
                                readonly property string calName: dash.agenda?.calendars?.[modelData.calendar]?.name ?? ""

                                width: ListView.view.width
                                height: evRow.implicitHeight + 12
                                opacity: past ? 0.45 : 1

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: ev.current ? Theme.withAlpha(Theme.accent, 0.15) : "transparent"
                                }

                                RowLayout {
                                    id: evRow
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
                                    spacing: 8

                                    // Calendar color
                                    Rectangle {
                                        Layout.fillHeight: true
                                        implicitWidth: 3
                                        radius: 1.5
                                        color: dash.calColor(ev.modelData.calendar)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            Layout.fillWidth: true
                                            text: ev.modelData.title
                                            elide: Text.ElideRight
                                            font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                                            color: Theme.fg
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (ev.current ? "Now  ·  " : "")
                                                + (ev.modelData.allDay ? "All day"
                                                   : Qt.formatTime(new Date(ev.modelData.start), "HH:mm")
                                                     + (ev.modelData.end > ev.modelData.start ? "–" + Qt.formatTime(new Date(ev.modelData.end), "HH:mm") : ""))
                                                + "  ·  " + ev.calName
                                                + (ev.modelData.location ? "  ·  " + ev.modelData.location : "")
                                            elide: Text.ElideRight
                                            font { family: Theme.font; pixelSize: 10; bold: ev.current }
                                            color: ev.current ? Theme.accent : Theme.fgDim
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Media
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true


                    ColumnLayout {
                        anchors { fill: parent; margins: 16 }
                        spacing: 8

                        ClippingRectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 110
                            Layout.preferredHeight: 110
                            radius: 12
                            color: Theme.bg
                            Image {
                                id: dashArt
                                anchors.fill: parent
                                source: Players.active?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Glyph {
                                anchors.centerIn: parent
                                visible: dashArt.status !== Image.Ready
                                code: 0xf001
                                font.pixelSize: 34
                                color: Theme.fgDim
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Players.active?.trackTitle || "Nothing playing"
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 14; bold: true }
                            color: Theme.fg
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Players.active?.trackArtist ?? ""
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 12 }
                            color: Theme.fgDim
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            visible: Players.active !== null
                            spacing: 6
                            IconButton { code: 0xf04ae; onActivated: Players.active?.previous() }
                            IconButton {
                                code: (Players.active?.isPlaying ?? false) ? 0xf03e4 : 0xf040a
                                onActivated: Players.active?.togglePlaying()
                            }
                            IconButton { code: 0xf04ad; onActivated: Players.active?.next() }
                        }
                    }
                }
            }

            // ---------- Tab: Controls ----------
            RowLayout {
                visible: dash.tab === 1
                Layout.fillWidth: true
                Layout.preferredHeight: 270
                spacing: 12

                // Toggles
                GridLayout {
                    Layout.preferredWidth: 420
                    Layout.fillWidth: false      // layouts fill by default; keep room for the right column
                    Layout.fillHeight: true
                    columns: 2
                    rowSpacing: 12
                    columnSpacing: 12

                    Tile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        code: dash.wifiOn ? 0xf05a9 : 0xf05aa          // md-wifi / md-wifi-off
                        title: "Wi-Fi"
                        subtitle: dash.wifiOn ? (dash.ssid || "Not connected") : "Off"
                        active: dash.wifiOn
                        menu: true                                     // chevron opens the network menu
                        onToggled: dash.run(["nmcli", "radio", "wifi", dash.wifiOn ? "off" : "on"])
                        onMenuRequested: {
                            dash.visible = false;
                            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/rofi/scripts/wifi.sh"]);
                        }
                    }
                    Tile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property var adapter: Bluetooth.defaultAdapter
                        code: adapter?.enabled ? 0xf00af : 0xf00b2     // md-bluetooth / md-bluetooth-off
                        title: "Bluetooth"
                        subtitle: !adapter ? "Unavailable"
                                : !adapter.enabled ? "Off"
                                : (dash.btDevices.filter(d => d.connected).map(d => d.name).join(", ") || "On")
                        active: adapter?.enabled ?? false
                        onToggled: dash.toggleBluetooth()
                    }
                    Tile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        code: dash.dnd ? 0xf009b : 0xf009a              // md-bell-off / md-bell
                        title: "Do not disturb"
                        subtitle: dash.dnd ? "Notifications hidden" : "Off"
                        active: dash.dnd
                        onToggled: Notifs.dnd = !Notifs.dnd
                    }
                    Tile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        code: Session.stayAwake ? 0xf0176 : 0xf06ca    // md-coffee / md-coffee-outline
                        title: "Stay awake"
                        subtitle: Session.stayAwake ? "Screen won't idle" : "Off"
                        active: Session.stayAwake
                        onToggled: Session.stayAwake = !Session.stayAwake
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12

                    // Sliders
                    Card {
                        Layout.fillWidth: true
                        implicitHeight: sliders.implicitHeight + 28

                        ColumnLayout {
                            id: sliders
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                            spacing: 10

                            RowLayout {
                                spacing: 10
                                IconButton {
                                    implicitWidth: 36; implicitHeight: 32
                                    code: (dash.sink?.audio?.muted ?? false) ? 0xf0581 : 0xf057e   // md-volume-off / high
                                    onActivated: if (dash.sink?.audio) dash.sink.audio.muted = !dash.sink.audio.muted
                                }
                                Slider {
                                    Layout.fillWidth: true
                                    value: dash.sink?.audio?.volume ?? 0
                                    dimmed: dash.sink?.audio?.muted ?? false
                                    onMoved: v => { if (dash.sink?.audio) dash.sink.audio.volume = v; }
                                }
                                Text {
                                    Layout.preferredWidth: 38
                                    horizontalAlignment: Text.AlignRight
                                    text: Math.round((dash.sink?.audio?.volume ?? 0) * 100) + "%"
                                    font { family: Theme.font; pixelSize: 12 }
                                    color: Theme.fgDim
                                }
                            }
                            RowLayout {
                                spacing: 10
                                Item {
                                    implicitWidth: 36; implicitHeight: 32
                                    Glyph { anchors.centerIn: parent; code: 0xf00df; font.pixelSize: 18 }   // md-brightness-6
                                }
                                Slider {
                                    Layout.fillWidth: true
                                    value: dash.brightness
                                    onMoved: v => dash.setBrightness(v)
                                }
                                Text {
                                    Layout.preferredWidth: 38
                                    horizontalAlignment: Text.AlignRight
                                    text: Math.round(dash.brightness * 100) + "%"
                                    font { family: Theme.font; pixelSize: 12 }
                                    color: Theme.fgDim
                                }
                            }
                        }
                    }

                    // Paired Bluetooth devices: click to connect / disconnect
                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors { fill: parent; margins: 14 }
                            spacing: 6

                            Text {
                                text: "Bluetooth devices"
                                font { family: Theme.font; pixelSize: 12; bold: true }
                                color: Theme.fgDim
                            }

                            Text {
                                visible: dash.btDevices.length === 0
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: !(Bluetooth.defaultAdapter?.enabled ?? false)
                                    ? "Turn Bluetooth on to see your devices."
                                    : "No paired devices yet (pair one with bluetoothctl)."
                                font { family: Theme.font; pixelSize: 12 }
                                color: Theme.fgDim
                            }

                            Repeater {
                                model: dash.btDevices
                                delegate: Item {
                                    id: dev
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 34

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        color: devHover.hovered ? Theme.withAlpha(Theme.accent, 0.15) : "transparent"
                                    }
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                        spacing: 10
                                        Glyph {
                                            code: dev.modelData.connected ? 0xf00b1 : 0xf00af   // md-bluetooth-connect / md-bluetooth
                                            font.pixelSize: 16
                                            color: dev.modelData.connected ? Theme.accent : Theme.fgDim
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: dev.modelData.name
                                            elide: Text.ElideRight
                                            font { family: Theme.font; pixelSize: 12 }
                                            color: dev.modelData.connected ? Theme.fg : Theme.fgDim
                                        }
                                        Text {
                                            visible: dev.modelData.batteryAvailable
                                            text: Math.round(dev.modelData.battery * 100) + "%"
                                            font { family: Theme.font; pixelSize: 11 }
                                            color: Theme.fgDim
                                        }
                                    }
                                    HoverHandler { id: devHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: dev.modelData.connected = !dev.modelData.connected }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }

            // ---------- Tab: Notifications ----------
            Card {
                visible: dash.tab === 2
                Layout.fillWidth: true
                Layout.preferredHeight: 270

                ColumnLayout {
                    anchors { fill: parent; margins: 14 }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.leftMargin: 4
                            text: Notifs.history.length === 1 ? "1 notification"
                                : Notifs.history.length + " notifications"
                            font { family: Theme.font; pixelSize: 12; bold: true }
                            color: Theme.fgDim
                        }
                        Item { Layout.fillWidth: true }
                        IconButton {
                            implicitHeight: 32
                            code: Notifs.dnd ? 0xf009b : 0xf009a          // md-bell-off / md-bell
                            label: Notifs.dnd ? "Do not disturb" : "Popups on"
                            onActivated: Notifs.dnd = !Notifs.dnd
                        }
                        IconButton {
                            visible: Notifs.history.length > 0
                            implicitHeight: 32
                            code: 0xf00e2                                 // md-broom
                            label: "Clear all"
                            onActivated: Notifs.clearAll()
                        }
                    }

                    // Empty state
                    Item {
                        visible: Notifs.history.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Glyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                code: 0xf009c                             // md-bell-outline
                                font.pixelSize: 36
                                color: Theme.fgDim
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "You're all caught up"
                                font { family: Theme.font; pixelSize: 13 }
                                color: Theme.fgDim
                            }
                        }
                    }

                    // History, newest first. Click = open (default action) or
                    // expand; the x on hover dismisses it.
                    ListView {
                        visible: Notifs.history.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        model: ScriptModel { values: [...Notifs.history].reverse() }

                        delegate: Item {
                            id: entry
                            required property var modelData
                            readonly property var n: modelData
                            readonly property var buttons: n.actions.filter(a => a.identifier !== "default")
                            property bool expanded: false

                            width: ListView.view.width
                            height: entryRow.implicitHeight + 16

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: entryHover.hovered ? Theme.withAlpha(Theme.accent, 0.1) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            HoverHandler { id: entryHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const def = entry.n.actions.find(a => a.identifier === "default");
                                    if (def) {
                                        def.invoke();
                                        dash.visible = false;
                                    } else {
                                        entry.expanded = !entry.expanded;
                                    }
                                }
                            }

                            RowLayout {
                                id: entryRow
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                                spacing: 12

                                // Icon bubble (same rules as the popups)
                                ClippingRectangle {
                                    Layout.alignment: Qt.AlignTop
                                    implicitWidth: 34
                                    implicitHeight: 34
                                    radius: 17
                                    color: Theme.bg

                                    Image {
                                        id: entryPic
                                        anchors.fill: parent
                                        visible: status === Image.Ready && !Notifs.glyphFor(entry.n)
                                        source: Notifs.imageFor(entry.n)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                    IconImage {
                                        id: entryIcon
                                        anchors.centerIn: parent
                                        visible: !entryPic.visible && status === Image.Ready
                                        implicitSize: 20
                                        source: Notifs.iconFor(entry.n)
                                    }
                                    Glyph {
                                        anchors.centerIn: parent
                                        visible: !entryPic.visible && !entryIcon.visible
                                        code: Notifs.glyphFor(entry.n) || 0xf009a
                                        font.pixelSize: 18
                                        color: entry.n.urgency === NotificationUrgency.Critical ? "#e5534b" : Theme.fgDim
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: entry.n.summary || entry.n.appName
                                            elide: Text.ElideRight
                                            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                                            color: Theme.fg
                                        }
                                        Text {
                                            text: (entry.n.appName || "Notification") + "  •  " + Notifs.age(entry.n)
                                            font { family: Theme.font; pixelSize: 11 }
                                            color: Theme.fgDim
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: entry.n.body
                                        textFormat: Text.StyledText
                                        wrapMode: Text.Wrap
                                        maximumLineCount: entry.expanded ? 8 : 1
                                        elide: Text.ElideRight
                                        font { family: Theme.font; pixelSize: 12 }
                                        color: Theme.fgDim
                                        linkColor: Theme.accent
                                    }
                                    // Actions (shown when expanded)
                                    Flow {
                                        Layout.fillWidth: true
                                        visible: entry.expanded && entry.buttons.length > 0
                                        topPadding: 4
                                        spacing: 6
                                        Repeater {
                                            model: entry.buttons
                                            Rectangle {
                                                required property var modelData
                                                width: actLabel.implicitWidth + 22
                                                height: 28
                                                radius: 9
                                                color: actArea.containsMouse ? Theme.withAlpha(Theme.accent, 0.2) : Theme.bg
                                                Text {
                                                    id: actLabel
                                                    anchors.centerIn: parent
                                                    text: parent.modelData.text
                                                    font { family: Theme.font; pixelSize: 11 }
                                                    color: actArea.containsMouse ? Theme.accent : Theme.fg
                                                }
                                                MouseArea {
                                                    id: actArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: parent.modelData.invoke()
                                                }
                                            }
                                        }
                                    }
                                }

                                // Dismiss (on hover)
                                Item {
                                    Layout.alignment: Qt.AlignTop
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    opacity: entryHover.hovered ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    Glyph {
                                        anchors.centerIn: parent
                                        code: 0xf0156                     // md-close
                                        font.pixelSize: 16
                                        color: closeArea.containsMouse ? Theme.accent : Theme.fgDim
                                    }
                                    MouseArea {
                                        id: closeArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: entry.n.dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- Tab: Performance ----------
            ColumnLayout {
                visible: dash.tab === 3
                Layout.fillWidth: true
                Layout.preferredHeight: 270
                spacing: 12

                // Processors
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 104
                    Layout.fillHeight: false     // layouts fill by default; the bottom row takes the rest
                    spacing: 12

                    ChipCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        code: 0xf0ee0                             // md-cpu-64-bit
                        title: "CPU"
                        model: dash.cpuModel
                        detailCode: 0xf050f                       // md-thermometer
                        detail: Math.round(dash.temp) + "°C"
                        detailValue: dash.temp / 100
                        hot: dash.temp >= 85
                        extra: dash.cpuGhz.toFixed(1) + " GHz"
                        usage: dash.cpu
                    }
                    ChipCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        code: 0xf08ae                             // md-expansion-card
                        title: "GPU"
                        model: dash.gpuName
                        detailCode: 0xf04c5                       // md-speedometer
                        detail: dash.gpuGhz > 0 ? dash.gpuGhz.toFixed(2) + " GHz" : "Idle"
                        detailValue: dash.gpuGhz / Math.max(0.1, dash.gpuMaxGhz)
                        extra: dash.gpuMaxGhz > 0 ? "max " + dash.gpuMaxGhz.toFixed(1) : ""
                        usage: dash.gpu
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12

                    // Storage (root filesystem)
                    Card {
                        Layout.preferredWidth: 300
                        Layout.fillHeight: true

                        RowLayout {
                            anchors { fill: parent; margins: 14 }
                            spacing: 16

                            Item {
                                implicitWidth: 120
                                implicitHeight: 120
                                Ring {
                                    anchors.fill: parent
                                    value: dash.diskUsed / dash.diskTotal
                                    span: 270
                                    thickness: 9
                                }
                                Column {
                                    anchors.centerIn: parent
                                    Glyph {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        code: 0xf02ca                     // md-harddisk
                                        font.pixelSize: 16
                                        color: Theme.fgDim
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Math.round(dash.diskUsed / dash.diskTotal * 100) + "%"
                                        font { family: Theme.font; pixelSize: 22; bold: true }
                                        color: Theme.fg
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "used"
                                        font { family: Theme.font; pixelSize: 10 }
                                        color: Theme.fgDim
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: "Storage"
                                    font { family: Theme.font; pixelSize: 15; bold: true }
                                    color: Theme.fg
                                }
                                Text {
                                    text: dash.gib(dash.diskUsed) + " / " + dash.gib(dash.diskTotal) + " GiB"
                                    font { family: Theme.font; pixelSize: 12 }
                                    color: Theme.fgDim
                                }
                                // Disk chip: device + its temperature
                                Rectangle {
                                    Layout.topMargin: 8
                                    visible: dash.diskName !== ""
                                    implicitWidth: diskRow.implicitWidth + 20
                                    implicitHeight: 28
                                    radius: 9
                                    color: Theme.bg
                                    RowLayout {
                                        id: diskRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Glyph {
                                            code: 0xf02ca
                                            font.pixelSize: 13
                                            color: Theme.accent
                                        }
                                        Text {
                                            text: dash.diskName + (dash.diskTemp > 0 ? "  ·  " + Math.round(dash.diskTemp) + "°C" : "")
                                            font { family: Theme.font; pixelSize: 11 }
                                            color: Theme.fg
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Network: live graph (download filled, upload as a line) + rates
                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors { fill: parent; margins: 14 }
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Glyph {
                                    code: 0xf04e1                         // md-swap-vertical
                                    font.pixelSize: 16
                                    color: Theme.accent
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Network"
                                    font { family: Theme.font; pixelSize: 15; bold: true }
                                    color: Theme.fg
                                }
                                Text {
                                    text: dash.netDev || "offline"
                                    font { family: Theme.font; pixelSize: 11 }
                                    color: Theme.fgDim
                                }
                            }

                            Canvas {
                                id: netGraph
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Connections {
                                    target: dash
                                    function onRxHistChanged() { netGraph.requestPaint(); }
                                }

                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.reset();
                                    // 10 KB/s floor so background chatter stays near the bottom
                                    const max = Math.max(10000, ...dash.rxHist, ...dash.txHist);
                                    const step = width / (dash.histLength - 1);
                                    const plot = (hist, color, fill) => {
                                        if (hist.length < 2)
                                            return;
                                        const x0 = width - (hist.length - 1) * step;
                                        const y = v => height - 1 - v / max * (height - 2);
                                        ctx.beginPath();
                                        ctx.moveTo(x0, y(hist[0]));
                                        for (let i = 1; i < hist.length; i++)
                                            ctx.lineTo(x0 + i * step, y(hist[i]));
                                        ctx.strokeStyle = color;
                                        ctx.lineWidth = 1.5;
                                        ctx.stroke();
                                        if (fill) {
                                            ctx.lineTo(width, height);
                                            ctx.lineTo(x0, height);
                                            ctx.closePath();
                                            ctx.fillStyle = color;
                                            ctx.globalAlpha = 0.15;
                                            ctx.fill();
                                            ctx.globalAlpha = 1;
                                        }
                                    };
                                    plot(dash.txHist, "" + Theme.fgDim, false);
                                    plot(dash.rxHist, "" + Theme.accent, true);
                                }
                            }

                            Repeater {
                                model: [
                                    { code: 0xf01da, name: "Download", value: dash.bytes(dash.rxRate) + "/s", accent: true },  // md-download
                                    { code: 0xf0552, name: "Upload", value: dash.bytes(dash.txRate) + "/s", accent: false },   // md-upload
                                    { code: 0xf04a0, name: "Total", value: "↓" + dash.bytes(dash.rxTotal) + "  ↑" + dash.bytes(dash.txTotal), accent: false } // md-sigma
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Glyph {
                                        code: parent.modelData.code
                                        font.pixelSize: 14
                                        color: parent.modelData.accent ? Theme.accent : Theme.fgDim
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: parent.modelData.name
                                        font { family: Theme.font; pixelSize: 12 }
                                        color: Theme.fgDim
                                    }
                                    Text {
                                        text: parent.modelData.value
                                        font { family: Theme.font; pixelSize: 12; bold: true }
                                        color: Theme.fg
                                    }
                                }
                            }
                        }
                    }

                    // Memory
                    Card {
                        Layout.preferredWidth: 190
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors { fill: parent; margins: 14 }
                            spacing: 6

                            RowLayout {
                                spacing: 8
                                Glyph {
                                    code: 0xf035b                         // md-memory
                                    font.pixelSize: 16
                                    color: Theme.accent
                                }
                                Text {
                                    text: "Memory"
                                    font { family: Theme.font; pixelSize: 15; bold: true }
                                    color: Theme.fg
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Ring {
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width, parent.height)
                                    height: width
                                    value: dash.ram
                                    thickness: 8
                                }
                                Column {
                                    anchors.centerIn: parent
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Math.round(dash.ram * 100) + "%"
                                        font { family: Theme.font; pixelSize: 18; bold: true }
                                        color: Theme.fg
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "used"
                                        font { family: Theme.font; pixelSize: 10 }
                                        color: Theme.fgDim
                                    }
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: dash.gib(dash.memUsed) + " / " + dash.gib(dash.memTotal) + " GiB"
                                font { family: Theme.font; pixelSize: 12 }
                                color: Theme.fgDim
                            }
                        }
                    }
                }
            }

            // ---------- Bottom: user + power ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: (Quickshell.env("USER") ?? "") + "@" + dash.host
                    font { family: Theme.font; pixelSize: 13; bold: true }
                    color: Theme.fg
                }
                Text {
                    Layout.leftMargin: 10
                    visible: dash.uptime !== ""
                    text: "up " + dash.uptime
                    font { family: Theme.font; pixelSize: 12 }
                    color: Theme.fgDim
                }
                Item { Layout.fillWidth: true }

                IconButton {
                    code: 0xf0343   // md-logout
                    label: dash.armed === "logout" ? "Click again" : "Log out"
                    highlighted: dash.armed === "logout"
                    onActivated: dash.power("logout", ["hyprctl", "dispatch", "hl.dsp.exit()"], true)
                }
                IconButton {
                    code: 0xf04b2   // md-sleep
                    label: "Suspend"
                    onActivated: dash.power("suspend", ["systemctl", "suspend"], false)
                }
                IconButton {
                    code: 0xf0709   // md-restart
                    label: dash.armed === "reboot" ? "Click again" : "Restart"
                    highlighted: dash.armed === "reboot"
                    onActivated: dash.power("reboot", ["systemctl", "reboot"], true)
                }
                IconButton {
                    code: 0xf0425   // md-power
                    label: dash.armed === "poweroff" ? "Click again" : "Power off"
                    highlighted: dash.armed === "poweroff"
                    onActivated: dash.power("poweroff", ["systemctl", "poweroff"], true)
                }
            }
        }
    }
}
