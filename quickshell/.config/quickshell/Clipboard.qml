// Clipboard history (SUPER+V, like Windows Win+V): rises from the bottom like
// the app launcher. Rows show what was copied (text, links, image previews).
//   qs ipc call clipboard toggle
// ↑ ↓ move, Enter / click = paste into the previous window, Del = remove,
// Tab = All / Text / Images, type = search, Esc / click outside = close.
// Data: hypr/scripts/clip-list.sh (cliphist, RAM only); paste: clip-paste.sh.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: cb

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts/"
    readonly property string thumbs: Quickshell.env("XDG_RUNTIME_DIR") + "/clip-thumbs"
    readonly property var filters: ["All", "Text", "Images"]
    readonly property int maxListHeight: 420

    property var entries: []                   // [{ id, kind: text|link|image, preview, image }]
    property int filter: 0
    property string query: ""
    property bool armed: false                 // "Clear all" waiting for its confirming click
    readonly property var shown: entries.filter(e =>
        (filter === 0 || (filter === 1) === (e.kind !== "image"))
        && (query === "" || (e.kind === "image" ? "image " + e.preview : e.preview)
                                .toLowerCase().includes(query.toLowerCase())))

    visible: false
    anchors.bottom: true                       // only bottom anchored -> centered horizontally
    margins.bottom: 24
    implicitWidth: 620
    implicitHeight: card.implicitHeight
    color: "transparent"
    focusable: true
    WlrLayershell.namespace: "quickshell-clipboard"

    IpcHandler {
        target: "clipboard"
        function toggle(): void { cb.visible = !cb.visible; }
    }

    HyprlandFocusGrab {
        windows: [ cb ]
        active: cb.visible
        onCleared: cb.visible = false
    }

    onVisibleChanged: {
        if (visible) {
            entries = [];
            filter = 0;
            armed = false;
            search.text = "";
            search.forceActiveFocus();
            listProc.running = true;
        } else {
            // Image previews only live while the panel is open
            Quickshell.execDetached(["rm", "-rf", thumbs]);
        }
    }

    Process {
        id: listProc
        command: [cb.scripts + "clip-list.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                cb.entries = text.split("\n").filter(l => l).map(l => {
                    const f = l.split("\t");
                    return { id: f[0], kind: f[1], preview: f.slice(2, -1).join(" "), image: f[f.length - 1] };
                });
                list.currentIndex = 0;
            }
        }
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: cb.armed = false
    }

    function paste() {
        const e = shown[list.currentIndex];
        if (!e)
            return;
        visible = false;
        Quickshell.execDetached([scripts + "clip-paste.sh", e.id]);
    }

    function remove(e) {
        if (!e)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete", "sh", e.id]);
        entries = entries.filter(x => x.id !== e.id);
    }

    function clearAll() {
        if (!armed) {
            armed = true;
            disarm.restart();
            return;
        }
        Quickshell.execDetached(["cliphist", "wipe"]);
        entries = [];
        armed = false;
    }

    component Glyph: Text {
        property int code
        text: String.fromCodePoint(code)
        font.family: Theme.font
        color: Theme.fg
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
            spacing: 12

            // ---------- Filter tabs + count + clear ----------
            Item {
                width: parent.width
                height: 32

                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: cb.filters
                        delegate: Rectangle {
                            id: tab
                            required property string modelData
                            required property int index
                            readonly property bool current: cb.filter === index
                            width: tabText.implicitWidth + 24
                            height: 30
                            radius: 10
                            color: current ? Theme.withAlpha(Theme.accent, 0.15)
                                 : tabHover.hovered ? Theme.surface : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                id: tabText
                                anchors.centerIn: parent
                                text: tab.modelData
                                font { family: Theme.font; pixelSize: 12; bold: tab.current }
                                color: tab.current ? Theme.accent : Theme.fgDim
                            }
                            HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    cb.filter = tab.index;
                                    list.currentIndex = 0;
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cb.shown.length === 1 ? "1 item" : cb.shown.length + " items"
                        font { family: Theme.font; pixelSize: 12 }
                        color: Theme.fgDim
                    }

                    // Clear all (second click within 3 s confirms)
                    Rectangle {
                        visible: cb.entries.length > 0
                        width: clearRow.implicitWidth + 20
                        height: 30
                        radius: 10
                        color: cb.armed ? Theme.withAlpha("#ef4444", 0.25)
                             : clearHover.hovered ? Theme.withAlpha(Theme.accent, 0.15) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            id: clearRow
                            anchors.centerIn: parent
                            spacing: 6
                            Glyph {
                                code: 0xf0a79                                  // md-trash-can
                                font.pixelSize: 15
                                color: cb.armed ? "#ef4444" : clearHover.hovered ? Theme.accent : Theme.fgDim
                            }
                            Text {
                                text: cb.armed ? "Click again" : "Clear all"
                                font { family: Theme.font; pixelSize: 12 }
                                color: cb.armed ? "#ef4444" : Theme.fgDim
                            }
                        }
                        HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: cb.clearAll() }
                    }
                }
            }

            // ---------- Empty state ----------
            Column {
                visible: cb.shown.length === 0
                width: parent.width
                topPadding: 18
                bottomPadding: 18
                spacing: 6
                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    code: 0xf0147                                          // md-clipboard
                    font.pixelSize: 32
                    color: Theme.fgDim
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: listProc.running ? "Loading…"
                        : cb.entries.length === 0 ? "Nothing copied yet" : "No matches"
                    font { family: Theme.font; pixelSize: 13 }
                    color: Theme.fgDim
                }
            }

            // ---------- History ----------
            ListView {
                id: list
                visible: cb.shown.length > 0
                width: parent.width
                height: Math.min(contentHeight, cb.maxListHeight)   // shrinks to the results
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                model: cb.shown

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: ListView.isCurrentItem
                    readonly property bool isImage: modelData.kind === "image"

                    width: ListView.view.width
                    height: rowContent.implicitHeight + 20

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: row.selected ? Theme.withAlpha(Theme.accent, 0.15)
                             : rowHover.hovered ? Theme.surface : "transparent"
                    }

                    HoverHandler {
                        id: rowHover
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: if (hovered) list.currentIndex = row.index
                    }
                    TapHandler { onTapped: cb.paste() }

                    Row {
                        id: rowContent
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                        spacing: 14

                        // Icon, or the image itself
                        Item {
                            width: row.isImage ? 96 : 34
                            height: row.isImage ? 54 : 34
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                visible: !row.isImage
                                anchors.fill: parent
                                radius: 17
                                color: row.selected ? Theme.withAlpha(Theme.accent, 0.2) : Theme.surface
                                Glyph {
                                    anchors.centerIn: parent
                                    code: row.modelData.kind === "link" ? 0xf0337   // md-link
                                                                        : 0xf09ee  // md-file-document-outline
                                    font.pixelSize: 17
                                    color: row.selected ? Theme.accent : Theme.fgDim
                                }
                            }
                            ClippingRectangle {
                                visible: row.isImage
                                anchors.fill: parent
                                radius: 8
                                color: Theme.surface
                                border.width: row.selected ? 2 : 0
                                border.color: Theme.accent
                                Image {
                                    anchors.fill: parent
                                    source: row.isImage ? "file://" + row.modelData.image : ""
                                    sourceSize.width: 192
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }
                        }

                        Column {
                            width: parent.width - (row.isImage ? 96 : 34) - 14 - 30
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: row.isImage ? "Image" : row.modelData.preview
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: row.selected ? 3 : 1
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font { family: Theme.font; pixelSize: 13 }
                                color: row.selected ? Theme.fg : Theme.withAlpha(Theme.fg, 0.8)
                            }
                            Text {
                                visible: row.isImage
                                text: row.modelData.preview                    // e.g. 1920x1080
                                font { family: Theme.font; pixelSize: 11 }
                                color: Theme.fgDim
                            }
                        }

                        // Remove this entry
                        Item {
                            width: 30
                            height: 30
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: row.selected ? 1 : 0
                            Glyph {
                                anchors.centerIn: parent
                                code: 0xf0156                                   // md-close
                                font.pixelSize: 16
                                color: delHover.hovered ? Theme.accent : Theme.fgDim
                            }
                            HoverHandler { id: delHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: cb.remove(row.modelData) }
                        }
                    }
                }
            }

            // ---------- Search ----------
            Rectangle {
                width: parent.width
                height: 44
                radius: 12
                color: Theme.surface

                Glyph {
                    id: searchIcon
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    code: 0xf002                                                // fa-search
                    font.pixelSize: 14
                    color: Theme.accent
                }

                TextInput {
                    id: search
                    anchors { left: searchIcon.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    font { family: Theme.font; pixelSize: 14 }
                    color: Theme.fg
                    selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                    clip: true
                    onTextChanged: {
                        cb.query = text;
                        list.currentIndex = 0;
                    }

                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onReturnPressed: cb.paste()
                    Keys.onEnterPressed: cb.paste()
                    Keys.onDeletePressed: cb.remove(cb.shown[list.currentIndex])
                    Keys.onTabPressed: event => {
                        cb.filter = (cb.filter + 1) % cb.filters.length;
                        list.currentIndex = 0;
                        event.accepted = true;
                    }
                    Keys.onEscapePressed: cb.visible = false

                    Text {
                        visible: !search.text
                        text: "Search clipboard…"
                        font: search.font
                        color: Theme.fgDim
                    }
                }

            }
        }
    }
}
