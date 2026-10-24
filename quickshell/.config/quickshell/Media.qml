// Media popup under Waybar's music icon: album art, track, progress and
// controls for the active MPRIS player (Spotify, browsers, mpv...).
// Opened from Waybar with:  qs ipc call media toggle
// Closes on a click outside (Hyprland focus grab) or Esc.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: popup

    readonly property var player: Players.active

    visible: false
    anchors { top: true; right: true }   // sits under Waybar (respects its zone)
    margins { top: 8; right: 10 }
    implicitWidth: 360
    implicitHeight: card.implicitHeight
    color: "transparent"
    focusable: true
    WlrLayershell.namespace: "quickshell-media"

    IpcHandler {
        target: "media"
        function toggle(): void { popup.visible = !popup.visible; }
    }

    HyprlandFocusGrab {
        windows: [ popup ]
        active: popup.visible
        onCleared: popup.visible = false
    }

    // Position only updates when asked (see MprisPlayer.position docs)
    Timer {
        running: popup.visible && (popup.player?.isPlaying ?? false)
        interval: 1000
        repeat: true
        onTriggered: popup.player.positionChanged()
    }

    component ControlButton: Item {
        id: btn
        property string glyph
        property bool primary: false   // the play/pause button: filled accent circle
        signal activated()

        implicitWidth: 44
        implicitHeight: 44

        Rectangle {
            anchors.fill: parent
            radius: btn.primary ? width / 2 : 10
            color: btn.primary ? Theme.accent : Theme.withAlpha(Theme.accent, 0.15)
            opacity: btn.primary || hover.hovered ? 1 : 0
            scale: btn.primary && hover.hovered ? 1.08 : 1
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: Theme.font
            font.pixelSize: btn.primary ? 22 : 20
            color: btn.primary ? Theme.accentText : (hover.hovered ? Theme.accent : Theme.fg)
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: btn.activated() }
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: content.implicitHeight + 32
        radius: 14
        color: Theme.bg
        border.width: 1
        border.color: Theme.withAlpha(Theme.accent, 0.25)

        // Esc closes the popup
        Item {
            focus: true
            Keys.onEscapePressed: popup.visible = false
        }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 14

            // ---------- Art + track ----------
            RowLayout {
                spacing: 14

                ClippingRectangle {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 72
                    radius: 10
                    color: Theme.surface

                    Image {
                        id: art
                        anchors.fill: parent
                        source: popup.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: String.fromCodePoint(0xf001)   // fa-music
                        font.family: Theme.font
                        font.pixelSize: 26
                        color: Theme.fgDim
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: popup.player?.trackTitle || "Nothing playing"
                        elide: Text.ElideRight
                        font { family: Theme.font; pixelSize: 15; bold: true }
                        color: Theme.fg
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: popup.player?.trackArtist ?? ""
                        elide: Text.ElideRight
                        font { family: Theme.font; pixelSize: 13 }
                        color: Theme.fgDim
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: popup.player?.identity ?? ""
                        elide: Text.ElideRight
                        font { family: Theme.font; pixelSize: 11 }
                        color: Theme.accent
                    }
                }
            }

            // ---------- Progress ----------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: (popup.player?.lengthSupported ?? false) && popup.player.length > 0

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Theme.surface

                    Rectangle {
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                        width: popup.player && popup.player.length > 0
                            ? parent.width * Math.min(1, popup.player.position / popup.player.length)
                            : 0
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: popup.player ? Players.fmt(popup.player.position) : ""
                        font { family: Theme.font; pixelSize: 11 }
                        color: Theme.fgDim
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: popup.player ? Players.fmt(popup.player.length) : ""
                        font { family: Theme.font; pixelSize: 11 }
                        color: Theme.fgDim
                    }
                }
            }

            // ---------- Controls ----------
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 20
                visible: popup.player !== null

                ControlButton {
                    glyph: String.fromCodePoint(0xf04ae)   // md-skip-previous
                    opacity: (popup.player?.canGoPrevious ?? false) ? 1 : 0.4
                    onActivated: if (popup.player?.canGoPrevious) popup.player.previous()
                }
                ControlButton {
                    primary: true
                    glyph: String.fromCodePoint((popup.player?.isPlaying ?? false) ? 0xf03e4 : 0xf040a)   // md-pause / md-play
                    onActivated: if (popup.player?.canTogglePlaying) popup.player.togglePlaying()
                }
                ControlButton {
                    glyph: String.fromCodePoint(0xf04ad)   // md-skip-next
                    opacity: (popup.player?.canGoNext ?? false) ? 1 : 0.4
                    onActivated: if (popup.player?.canGoNext) popup.player.next()
                }
            }
        }
    }
}
