// Wallpaper carousel (SUPER+W): thumbnails in a strip at the bottom; the
// selected one sits in the middle, bigger and brighter.
//   qs ipc call wallpapers toggle
// Two modes (Tab or click the switch on top):
//   Desktop      ~/wallpapers: runs hypr/scripts/set-wallpaper.sh (hyprpaper + matugen)
//   Lock screen  ~/lock_wallpapers: points ~/.local/state/wallpaper/lock (read
//                by hyprlock.conf) at the image; colors stay the desktop's
// ← → / wheel = move, Enter or click on the selected one = apply (stays open
// so you can watch the colors change), type = filter, Esc / click outside = close.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: picker

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts/"
    // Sized for a 1280px-wide logical screen (1920x1080 at 1.5 scale): ~970px panel
    readonly property int thumbW: 160          // side thumbnails
    readonly property int selW: 236            // selected one
    readonly property int visibleCount: 5

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/wallpaper/"
    readonly property var modes: [
        { mode: "desktop", label: "Desktop", icon: 0xf0379 },          // md-monitor
        { mode: "lock", label: "Lock screen", icon: 0xf033e }          // md-lock
    ]

    property string mode: "desktop"
    property var all: []                       // [{ name, path, thumb }]
    property string current: ""                // path of the image in use (this mode)
    property string query: ""
    readonly property var shown: all.filter(w => w.name.toLowerCase().includes(query.toLowerCase()))

    visible: false
    anchors.bottom: true                       // only bottom anchored -> centered horizontally
    margins.bottom: 24
    implicitWidth: (visibleCount - 1) * (thumbW + list.spacing) + selW + 40
    implicitHeight: card.implicitHeight
    color: "transparent"
    focusable: true
    WlrLayershell.namespace: "quickshell-wallpapers"

    IpcHandler {
        target: "wallpapers"
        function toggle(): void { picker.visible = !picker.visible; }
    }

    HyprlandFocusGrab {
        windows: [ picker ]
        active: picker.visible
        onCleared: picker.visible = false
    }

    onVisibleChanged: {
        if (!visible)
            return;
        mode = "desktop";
        search.text = "";
        search.forceActiveFocus();
        listProc.running = true;
    }

    function setMode(m) {
        if (m === mode)
            return;
        mode = m;
        all = [];
        search.text = "";
        listProc.running = false;              // restart even if a listing is running
        listProc.running = true;
    }

    // First line: image in use; then one "name<TAB>path<TAB>thumb" per image
    Process {
        id: listProc
        command: picker.mode === "lock"
                 ? ["sh", "-c", "readlink -f \"$HOME/.local/state/wallpaper/lock\"; exec \"$0\" lock",
                    picker.scripts + "wallpaper-list.sh"]
                 : ["sh", "-c", "readlink -f \"$HOME/.local/state/wallpaper/current\"; exec \"$0\"",
                    picker.scripts + "wallpaper-list.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                picker.current = lines.shift() ?? "";
                picker.all = lines.map(l => l.split("\t"))
                                  .filter(f => f.length === 3)
                                  .map(f => ({ name: f[0], path: f[1], thumb: f[2] }));
                const i = picker.shown.findIndex(w => w.path === picker.current);
                list.currentIndex = Math.max(0, i);
                list.positionViewAtIndex(list.currentIndex, ListView.Center);
            }
        }
    }

    function apply() {
        const w = shown[list.currentIndex];
        if (!w)
            return;
        current = w.path;
        if (mode === "lock")
            Quickshell.execDetached(["ln", "-sfn", "--", w.path, stateDir + "lock"]);
        else
            Quickshell.execDetached([scripts + "set-wallpaper.sh", w.path]);
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: col.implicitHeight + 28
        radius: 18
        color: Theme.bg
        border.width: 1
        border.color: Theme.withAlpha(Theme.accent, 0.25)

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10

            // Desktop | Lock screen (same segmented look as the translator's)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: modeRow.implicitWidth + 6
                implicitHeight: 30
                radius: 10
                color: Theme.surface
                Row {
                    id: modeRow
                    anchors.centerIn: parent
                    Repeater {
                        model: picker.modes
                        delegate: Rectangle {
                            id: modeBtn
                            required property var modelData
                            readonly property bool active: picker.mode === modelData.mode
                            width: modeLabel.implicitWidth + 22
                            height: 24
                            radius: 8
                            color: active ? Theme.withAlpha(Theme.accent, 0.2) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: modeLabel
                                anchors.centerIn: parent
                                text: String.fromCodePoint(modeBtn.modelData.icon) + "  " + modeBtn.modelData.label
                                font { family: Theme.font; pixelSize: 11; bold: modeBtn.active }
                                color: modeBtn.active ? Theme.accent : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.setMode(modeBtn.modelData.mode)
                            }
                        }
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: picker.selW * 9 / 16 + 34      // tallest thumbnail + its label
                orientation: ListView.Horizontal
                spacing: 14
                clip: true
                interactive: false                    // keys, wheel and clicks only
                model: picker.shown

                // Keep the selected item centered (also the first and last ones)
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - picker.selW) / 2
                preferredHighlightEnd: (width + picker.selW) / 2
                highlightMoveDuration: 250

                WheelHandler {
                    onWheel: event => {
                        const d = event.angleDelta.y || event.angleDelta.x;
                        if (d < 0) list.incrementCurrentIndex();
                        else if (d > 0) list.decrementCurrentIndex();
                    }
                }

                delegate: Item {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool selected: ListView.isCurrentItem
                    readonly property bool inUse: modelData.path === picker.current

                    width: selected ? picker.selW : picker.thumbW
                    height: list.height
                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    ClippingRectangle {
                        id: thumb
                        width: parent.width
                        height: width * 9 / 16
                        y: (list.height - 26 - height) / 2
                        radius: 12
                        color: Theme.surface
                        border.width: item.selected ? 2 : 0
                        border.color: Theme.accent

                        Image {
                            anchors.fill: parent
                            source: "file://" + item.modelData.thumb
                            sourceSize.width: 480
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: item.selected || hover.hovered ? 1 : 0.8
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        // Badge on the wallpaper currently in use
                        Rectangle {
                            visible: item.inUse
                            anchors { top: parent.top; right: parent.right; margins: 8 }
                            width: 24
                            height: 24
                            radius: 12
                            color: Theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xf012c)   // md-check
                                font.family: Theme.font
                                font.pixelSize: 15
                                color: Theme.accentText
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: thumb.bottom
                        anchors.topMargin: 6
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: item.modelData.name.replace(/[_-]/g, " ")
                        font.family: Theme.font
                        font.pixelSize: item.selected ? 13 : 12
                        font.bold: item.selected
                        color: item.selected ? Theme.fg : Theme.fgDim
                    }

                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (item.selected)
                                picker.apply();
                            else
                                list.currentIndex = item.index;
                        }
                    }
                }
            }

            // Search bar (same look as the app launcher's)
            Rectangle {
                width: parent.width
                height: 44
                radius: 12
                color: Theme.surface

                Text {
                    id: searchIcon
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    text: String.fromCodePoint(0xf002)   // fa-search
                    font.family: Theme.font
                    font.pixelSize: 14
                    color: Theme.accent
                }

                TextInput {
                    id: search
                    anchors { left: searchIcon.right; leftMargin: 12; right: hint.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    font.family: Theme.font
                    font.pixelSize: 14
                    color: Theme.fg
                    selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                    clip: true
                    onTextChanged: {
                        picker.query = text;
                        list.currentIndex = 0;
                    }

                    Keys.onLeftPressed: list.decrementCurrentIndex()
                    Keys.onRightPressed: list.incrementCurrentIndex()
                    Keys.onReturnPressed: picker.apply()
                    Keys.onEnterPressed: picker.apply()
                    Keys.onEscapePressed: picker.visible = false
                    Keys.onTabPressed: picker.setMode(picker.mode === "desktop" ? "lock" : "desktop")

                    Text {
                        visible: !search.text
                        text: picker.mode === "lock" ? "Search lock screens…" : "Search wallpapers…"
                        font: search.font
                        color: Theme.fgDim
                    }
                }

                Text {
                    id: hint
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    visible: picker.shown.length === 0 && !listProc.running
                    text: picker.all.length === 0
                          ? (picker.mode === "lock" ? "~/lock_wallpapers is empty" : "~/wallpapers is empty")
                          : "No matches"
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.fgDim
                }
            }
        }
    }
}
