// FC Barcelona panel (SUPER+B): slides in from the right edge with the next
// (or live) match, the upcoming fixtures and the latest results.
//   qs ipc call barca toggle
// Data: hypr/scripts/barca.py -> ~/.cache/barca/data.json (ESPN public JSON).
// Esc or a click outside closes it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: side

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts/"
    readonly property int panelWidth: 360
    property bool open: false

    // Stays mapped while the slide-out animation runs
    visible: open || slide.running
    anchors { top: true; right: true }
    margins.top: 8
    implicitWidth: panelWidth + 10
    implicitHeight: stack.implicitHeight + 10
    color: "transparent"
    focusable: true
    WlrLayershell.namespace: "quickshell-barca"

    IpcHandler {
        target: "barca"
        function toggle(): void { side.open = !side.open; }
    }

    HyprlandFocusGrab {
        windows: [ side ]
        active: side.open
        onCleared: side.open = false
    }

    onOpenChanged: {
        if (!open)
            return;
        keys.forceActiveFocus();
        refresh(false);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---------- FC Barcelona data ----------
    // hypr/scripts/barca.py writes ~/.cache/barca/data.json (ESPN public JSON)
    property var barca: null
    readonly property var hero: barca ? (barca.live ?? barca.next?.[0] ?? null) : null
    readonly property var upcoming: barca ? barca.next.filter(m => m !== hero).slice(0, 2) : []
    property bool fetchFailed: false

    FileView {
        id: barcaFile
        path: Quickshell.env("HOME") + "/.cache/barca/data.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                side.barca = JSON.parse(text());
            } catch (e) {
                side.barca = null;
            }
        }
    }

    Process {
        id: barcaProc
        command: [side.scripts + "barca.py"]
        onExited: code => {
            side.fetchFailed = code !== 0;
            barcaFile.reload();
        }
    }

    // Refresh when the data is older than 10 min, or older than 1 min while a
    // match is live (or should have kicked off by now)
    function refresh(force) {
        if (barcaProc.running)
            return;
        const age = Date.now() - (barca?.fetched ?? 0);
        const playing = barca?.live || (barca?.next?.[0]?.time ?? Infinity) <= Date.now();
        if (force || age > 10 * 60000 || (playing && age > 60000))
            barcaProc.running = true;
    }

    Timer {
        running: side.open
        interval: 60000
        repeat: true
        onTriggered: side.refresh(false)
    }

    // ---------- Helpers ----------
    function dayLabel(ms) {
        const d = new Date(ms);
        const now = clock.date;
        const days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate())
                                 - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000);
        if (days === 0)
            return "Today";
        if (days === 1)
            return "Tomorrow";
        if (days > 1 && days < 7)
            return Qt.formatDate(d, "dddd");
        return Qt.formatDate(d, "ddd d MMM");
    }

    function competition(m) {
        return m.competition === "LALIGA" ? "LaLiga" : m.competition;
    }

    // The other team, seen from Barça's side
    function rival(m) {
        return m.home.id === "83" ? m.away : m.home;
    }

    function atHome(m) {
        return m.home.id === "83";
    }

    // Fixed semantic colors (typed as color so Theme.withAlpha works on them)
    readonly property color winColor: "#8fd18a"
    readonly property color lossColor: "#e5534b"

    function resultColor(r) {
        return r === "W" ? winColor : r === "L" ? lossColor : Theme.fgDim;
    }

    // ---------- Reusable pieces ----------
    component Glyph: Text {
        property int code
        text: String.fromCodePoint(code)
        font.family: Theme.font
        color: Theme.fg
    }

    component Crest: Image {
        property string path
        source: path ? "file://" + path : ""
        sourceSize.width: 128
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
    }

    component SectionLabel: Text {
        Layout.topMargin: 6
        font { family: Theme.font; pixelSize: 11; bold: true; letterSpacing: 1 }
        color: Theme.fgDim
    }

    // ---------- Window ----------
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: side.open = false
    }

    Column {
        id: stack
        width: side.panelWidth
        x: side.open ? 0 : side.panelWidth + 10
        Behavior on x { NumberAnimation { id: slide; duration: 260; easing.type: Easing.OutCubic } }
        spacing: 10

        // ---------- Card: FC Barcelona ----------
        Rectangle {
            width: parent.width
            implicitHeight: barcaCol.implicitHeight + 32
            radius: 16
            color: Theme.bg
            border.width: 1
            border.color: Theme.withAlpha(Theme.accent, 0.25)

            ColumnLayout {
                id: barcaCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 8

                // Header: crest, name, league position, refresh
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Crest {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        path: side.barca?.crest ?? ""
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true          // lets the column (and the row) take the free space
                            text: "FC Barcelona"
                            font { family: Theme.font; pixelSize: 15; bold: true }
                            color: Theme.fg
                        }
                        Text {
                            visible: text !== ""
                            text: (side.barca?.standing ?? "").replace("LALIGA", "LaLiga")
                            font { family: Theme.font; pixelSize: 11 }
                            color: Theme.fgDim
                        }
                    }
                    Item {
                        implicitWidth: 30
                        implicitHeight: 30
                        Rectangle {
                            anchors.fill: parent
                            radius: 9
                            color: refreshHover.hovered ? Theme.withAlpha(Theme.accent, 0.15) : "transparent"
                        }
                        Glyph {
                            id: refreshGlyph
                            anchors.centerIn: parent
                            code: 0xf0450                         // md-refresh
                            font.pixelSize: 16
                            color: refreshHover.hovered ? Theme.accent : Theme.fgDim
                            RotationAnimation on rotation {
                                running: barcaProc.running
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                                onRunningChanged: if (!running) refreshGlyph.rotation = 0
                            }
                        }
                        HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: side.refresh(true) }
                    }
                }

                // Empty / error state
                Text {
                    visible: !side.hero
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    horizontalAlignment: Text.AlignHCenter
                    text: barcaProc.running ? "Loading matches…"
                        : side.fetchFailed ? "Couldn't reach ESPN"
                        : "No upcoming matches"
                    font { family: Theme.font; pixelSize: 12 }
                    color: Theme.fgDim
                }

                // Main match: live score, or the next kick-off
                Rectangle {
                    visible: side.hero !== null
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: heroCol.implicitHeight + 24
                    radius: 12
                    color: Theme.surface

                    ColumnLayout {
                        id: heroCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8

                        // Competition · when (or LIVE + minute)
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 6
                            Rectangle {
                                visible: side.hero?.state === "in"
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: "#e5534b"
                                SequentialAnimation on opacity {
                                    running: side.hero?.state === "in" && side.open
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 700 }
                                    NumberAnimation { to: 1; duration: 700 }
                                }
                            }
                            Text {
                                text: !side.hero ? ""
                                    : side.hero.state === "in" ? "LIVE  ·  " + side.hero.clock
                                    : side.competition(side.hero) + "  ·  " + side.dayLabel(side.hero.time)
                                font { family: Theme.font; pixelSize: 11; bold: side.hero?.state === "in" }
                                color: side.hero?.state === "in" ? "#e5534b" : Theme.fgDim
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: side.hero ? [side.hero.home, null, side.hero.away] : []
                                delegate: Item {
                                    id: slot
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: index !== 1
                                    Layout.preferredWidth: index === 1 ? 110 : 0
                                    implicitHeight: 82

                                    // Team: crest + short name
                                    Column {
                                        visible: slot.modelData !== null
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Crest {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 52
                                            height: 52
                                            path: slot.modelData?.crest ?? ""
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: Math.min(implicitWidth, slot.width)
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            text: slot.modelData?.name ?? ""
                                            font { family: Theme.font; pixelSize: 12; bold: slot.modelData?.id === "83" }
                                            color: slot.modelData?.id === "83" ? Theme.fg : Theme.fgDim
                                        }
                                    }

                                    // Middle: score while live, kick-off time before
                                    Column {
                                        visible: slot.modelData === null
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: !side.hero ? ""
                                                : side.hero.state === "pre" ? Qt.formatTime(new Date(side.hero.time), "HH:mm")
                                                : side.hero.home.score + " – " + side.hero.away.score
                                            font { family: Theme.font; pixelSize: 28; bold: true }
                                            color: side.hero?.state === "in" ? Theme.accent : Theme.fg
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            visible: side.hero?.state === "in"
                                            text: side.competition(side.hero ?? { competition: "" })
                                            font { family: Theme.font; pixelSize: 10 }
                                            color: Theme.fgDim
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: text !== ""
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: side.hero?.venue ?? ""
                            font { family: Theme.font; pixelSize: 11 }
                            color: Theme.fgDim
                        }
                    }
                }

                // Upcoming fixtures
                SectionLabel {
                    visible: side.upcoming.length > 0
                    text: "UPCOMING"
                }
                Repeater {
                    model: side.upcoming
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            Layout.preferredWidth: 76
                            text: side.dayLabel(parent.modelData.time)
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 12 }
                            color: Theme.fgDim
                        }
                        Crest {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            path: side.rival(parent.modelData).crest
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (side.atHome(parent.modelData) ? "vs " : "at ") + side.rival(parent.modelData).name
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 12 }
                            color: Theme.fg
                        }
                        Text {
                            text: side.competition(parent.modelData)
                            font { family: Theme.font; pixelSize: 10 }
                            color: Theme.fgDim
                        }
                    }
                }

                // Recent results (Barça's score first)
                SectionLabel {
                    visible: (side.barca?.recent ?? []).length > 0
                    text: "RECENT"
                }
                Repeater {
                    model: side.barca?.recent ?? []
                    delegate: RowLayout {
                        id: res
                        required property var modelData
                        readonly property var us: side.atHome(modelData) ? modelData.home : modelData.away
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            implicitWidth: 22
                            implicitHeight: 22
                            radius: 7
                            color: Theme.withAlpha(side.resultColor(res.modelData.result), 0.18)
                            Text {
                                anchors.centerIn: parent
                                text: res.modelData.result || "–"
                                font { family: Theme.font; pixelSize: 11; bold: true }
                                color: side.resultColor(res.modelData.result)
                            }
                        }
                        Crest {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            path: side.rival(res.modelData).crest
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (side.atHome(res.modelData) ? "vs " : "at ") + side.rival(res.modelData).name
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 12 }
                            color: Theme.fg
                        }
                        Text {
                            text: res.us.score + " – " + side.rival(res.modelData).score
                            font { family: Theme.font; pixelSize: 12; bold: true }
                            color: Theme.fg
                        }
                    }
                }
            }
        }
    }
}
