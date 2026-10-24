// Offline translator (SUPER+T): Spanish <-> English, bottom-center panel with
// your text on the left and the translation on the right.
//   qs ipc call translator toggle
// Translates as you type (hypr/scripts/translate.py, runs in the venv in
// ~/.local/share/translator; nothing goes over the network).
// Tab = change direction (Auto / ES -> EN / EN -> ES), Esc / click outside = close.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: tr

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/translate.py"
    readonly property string python: Quickshell.env("HOME") + "/.local/share/translator/venv/bin/python"
    readonly property var modes: [
        { mode: "auto", label: "Auto" },
        { mode: "es", label: "ES → EN" },
        { mode: "en", label: "EN → ES" }
    ]

    property string mode: "auto"           // source language: auto / es / en
    property string result: ""
    property string detected: ""           // source language of the last result
    property bool failed: false
    property string sent: ""               // mode + text of the running request

    // Language on each side, for the pane labels
    readonly property string source: mode !== "auto" ? mode : detected
    readonly property string target: source === "es" ? "en" : source === "en" ? "es" : ""

    visible: false
    anchors.bottom: true                   // only bottom anchored -> centered horizontally
    margins.bottom: 24
    implicitWidth: 760
    implicitHeight: card.implicitHeight
    color: "transparent"
    focusable: true
    WlrLayershell.namespace: "quickshell-translator"

    IpcHandler {
        target: "translator"
        function toggle(): void { tr.visible = !tr.visible; }
    }

    HyprlandFocusGrab {
        windows: [ tr ]
        active: tr.visible
        onCleared: tr.visible = false
    }

    // Keep the last text, selected, so typing replaces it
    onVisibleChanged: {
        if (!visible)
            return;
        input.forceActiveFocus();
        input.selectAll();
    }

    // One process per translation (~0.2 s incl. loading the model, so no daemon).
    // The text goes as an argument after "--", never through a shell.
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    tr.result = r.text;
                    tr.detected = r.from;
                    tr.failed = false;
                } catch (e) {
                    tr.failed = true;
                }
            }
        }
        // Text changed while it was running: translate the latest version
        onExited: if (tr.sent !== tr.mode + input.text) debounce.restart()
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: tr.translate()
    }

    function translate() {
        const text = input.text.trim();
        if (text === "") {
            result = "";
            detected = "";
            return;
        }
        if (proc.running)
            return;                        // onExited picks up the newer text
        sent = mode + input.text;
        proc.command = [python, "-I", script, "--json", "--from", mode, "--", text];
        proc.running = true;
    }

    function setMode(m) {
        mode = m;
        translate();
    }

    function langName(code) {
        return code === "es" ? "Spanish" : code === "en" ? "English" : "";
    }

    component Glyph: Text {
        property int code
        text: String.fromCodePoint(code)
        font.family: Theme.font
        color: Theme.fg
    }

    // Small uppercase label at the top of each pane
    component PaneLabel: Text {
        font { family: Theme.font; pixelSize: 11; bold: true; letterSpacing: 1 }
        color: Theme.fgDim
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: col.implicitHeight + 32
        radius: 18
        color: Theme.bg
        border.width: 1
        border.color: Theme.withAlpha(Theme.accent, 0.25)

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 12

            // Title + direction
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Glyph {
                    code: 0xf05ca                                 // md-translate
                    font.pixelSize: 18
                    color: Theme.accent
                }
                Text {
                    Layout.fillWidth: true
                    text: "Translator"
                    font { family: Theme.font; pixelSize: 15; bold: true }
                    color: Theme.fg
                }
                Rectangle {
                    implicitWidth: modeRow.implicitWidth + 6
                    implicitHeight: 30
                    radius: 10
                    color: Theme.surface
                    Row {
                        id: modeRow
                        anchors.centerIn: parent
                        Repeater {
                            model: tr.modes
                            delegate: Rectangle {
                                id: modeBtn
                                required property var modelData
                                readonly property bool current: tr.mode === modelData.mode
                                width: modeLabel.implicitWidth + 18
                                height: 24
                                radius: 8
                                color: current ? Theme.withAlpha(Theme.accent, 0.2) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    id: modeLabel
                                    anchors.centerIn: parent
                                    text: modeBtn.modelData.label
                                    font { family: Theme.font; pixelSize: 11; bold: modeBtn.current }
                                    color: modeBtn.current ? Theme.accent : Theme.fgDim
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: tr.setMode(modeBtn.modelData.mode)
                                }
                            }
                        }
                    }
                }
            }

            // Source | translation
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 210
                spacing: 12

                // Source text
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1                      // equal halves
                    radius: 12
                    color: Theme.surface
                    border.width: 1
                    border.color: input.activeFocus ? Theme.withAlpha(Theme.accent, 0.4) : "transparent"

                    PaneLabel {
                        id: srcLabel
                        anchors { left: parent.left; top: parent.top; margins: 12 }
                        text: tr.mode === "auto"
                              ? (tr.detected && input.text.trim() ? tr.langName(tr.detected).toUpperCase() + "  ·  DETECTED" : "DETECT LANGUAGE")
                              : tr.langName(tr.mode).toUpperCase()
                    }

                    Flickable {
                        id: inFlick
                        anchors { left: parent.left; right: parent.right; top: srcLabel.bottom; bottom: parent.bottom; margins: 12; topMargin: 8 }
                        contentHeight: input.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        TextEdit {
                            id: input
                            width: inFlick.width
                            wrapMode: TextEdit.Wrap
                            font { family: Theme.font; pixelSize: 14 }
                            color: Theme.fg
                            selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                            onTextChanged: debounce.restart()
                            // Keep the cursor visible while typing long text
                            onCursorRectangleChanged: {
                                if (cursorRectangle.y < inFlick.contentY)
                                    inFlick.contentY = cursorRectangle.y;
                                else if (cursorRectangle.y + cursorRectangle.height > inFlick.contentY + inFlick.height)
                                    inFlick.contentY = cursorRectangle.y + cursorRectangle.height - inFlick.height;
                            }
                            Keys.onEscapePressed: tr.visible = false
                            Keys.onTabPressed: {
                                const i = tr.modes.findIndex(m => m.mode === tr.mode);
                                tr.setMode(tr.modes[(i + 1) % tr.modes.length].mode);
                            }

                            Text {
                                visible: !input.text
                                text: "Type or paste text…"
                                font: input.font
                                color: Theme.fgDim
                            }
                        }
                    }
                }

                // Translation
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    radius: 12
                    color: Theme.withAlpha(Theme.accent, 0.08)

                    PaneLabel {
                        id: dstLabel
                        anchors { left: parent.left; top: parent.top; margins: 12 }
                        text: tr.target ? tr.langName(tr.target).toUpperCase() : "TRANSLATION"
                        color: Theme.accent
                    }

                    // Working indicator
                    Glyph {
                        anchors { right: parent.right; top: parent.top; margins: 10 }
                        visible: proc.running
                        code: 0xf0772                                 // md-loading
                        font.pixelSize: 14
                        color: Theme.fgDim
                        RotationAnimation on rotation {
                            running: proc.running
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                        }
                    }

                    Flickable {
                        id: outFlick
                        anchors { left: parent.left; right: parent.right; top: dstLabel.bottom; bottom: copyBtn.top; margins: 12; topMargin: 8; bottomMargin: 2 }
                        contentHeight: output.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        TextEdit {
                            id: output
                            width: outFlick.width
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            text: tr.failed ? "Translation failed (run ~/.config/hypr/scripts/translate.py in a terminal to see why)" : tr.result
                            font { family: Theme.font; pixelSize: 14 }
                            color: tr.failed ? "#e5534b" : Theme.fg
                            selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                        }
                    }

                    // Copy the translation
                    Item {
                        id: copyBtn
                        anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                        visible: tr.result !== "" && !tr.failed
                        implicitWidth: 30
                        implicitHeight: 28
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: copyHover.hovered ? Theme.withAlpha(Theme.accent, 0.15) : "transparent"
                        }
                        Glyph {
                            id: copyGlyph
                            anchors.centerIn: parent
                            property bool done: false
                            code: done ? 0xf012c : 0xf018f            // md-check / md-content-copy
                            font.pixelSize: 15
                            color: done || copyHover.hovered ? Theme.accent : Theme.fgDim
                            Timer {
                                id: copyReset
                                interval: 1200
                                onTriggered: copyGlyph.done = false
                            }
                        }
                        HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                Quickshell.execDetached(["wl-copy", "--", tr.result]);
                                copyGlyph.done = true;
                                copyReset.restart();
                            }
                        }
                    }
                }
            }
        }
    }
}
