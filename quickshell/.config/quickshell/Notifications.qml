// Notification popups, stacked in the bottom-right corner (newest at the bottom).
// Each card: app icon, app name + age, summary, body (chevron expands it) and
// action buttons. Hover pauses the timeout.
// Left click = default action (or hide), middle/right click = dismiss.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: win

    readonly property int cardWidth: 380
    readonly property int defaultTimeout: 5000   // ms, when the app doesn't ask for one

    visible: Notifs.popups.length > 0
    anchors { bottom: true; right: true }
    margins { bottom: 4; right: 10 }
    implicitWidth: cardWidth
    implicitHeight: 720
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    // Only the cards take clicks; the rest of the tall window is click-through
    mask: Region { item: stack }

    // Cards stack upward from the bottom edge. Each card animates its own
    // entry/exit and only leaves the model once its exit animation is done.
    Column {
        id: stack
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }

        Repeater {
            // ScriptModel diffs the array, so existing cards (and their timers) survive updates
            model: ScriptModel { values: Notifs.popups }

            delegate: Item {
                id: card

                required property var modelData
                readonly property var n: modelData
                readonly property bool critical: n.urgency === NotificationUrgency.Critical
                readonly property var buttons: n.actions.filter(a => a.identifier !== "default")
                property bool expanded: false
                property bool shown: false
                property bool leaving: false

                width: win.cardWidth
                height: shown && !leaving ? box.height + 8 : 0
                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Component.onCompleted: shown = true

                // Slide out, then drop from the popups (or dismiss entirely)
                function close(dismissIt) {
                    if (leaving)
                        return;
                    leaving = true;
                    exitTimer.dismissIt = dismissIt;
                    exitTimer.start();
                }

                Timer {
                    id: exitTimer
                    property bool dismissIt: false
                    interval: 220
                    onTriggered: dismissIt ? card.n.dismiss() : Notifs.hidePopup(card.n)
                }

                // Auto-hide: stays in history, only the popup goes away. Critical ones stay.
                Timer {
                    running: !card.critical && !hover.hovered && !card.leaving
                    interval: card.n.expireTimeout > 0 ? card.n.expireTimeout : win.defaultTimeout   // ms
                    onTriggered: card.close(false)
                }

                Rectangle {
                    id: box

                    width: win.cardWidth
                    height: content.implicitHeight + 24
                    x: card.shown && !card.leaving ? 0 : win.cardWidth
                    opacity: card.shown && !card.leaving ? 1 : 0
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    radius: 16
                    color: Theme.bg
                    border.width: 1
                    border.color: card.critical ? "#e5534b" : Theme.withAlpha(Theme.accent, hover.hovered ? 0.45 : 0.25)
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    HoverHandler { id: hover }

                    // Card click (sits under the content, so buttons on top win)
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button !== Qt.LeftButton) {
                                card.close(true);
                                return;
                            }
                            const def = card.n.actions.find(a => a.identifier === "default");
                            if (def)
                                def.invoke();
                            card.close(false);
                        }
                    }

                    Row {
                        id: content
                        x: 12
                        y: 12
                        width: parent.width - 24
                        spacing: 12

                        // Icon bubble: notification image, else app icon, else a grey glyph
                        ClippingRectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: Theme.surface

                            Image {
                                id: picture
                                anchors.fill: parent
                                visible: status === Image.Ready && !Notifs.glyphFor(card.n)
                                source: Notifs.imageFor(card.n)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            IconImage {
                                id: appIcon
                                anchors.centerIn: parent
                                visible: !picture.visible && status === Image.Ready
                                implicitSize: 24
                                source: Notifs.iconFor(card.n)
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !picture.visible && !appIcon.visible
                                text: String.fromCodePoint(Notifs.glyphFor(card.n) || 0xf009a)   // fallback md-bell
                                font.family: Theme.font
                                font.pixelSize: 22
                                color: Theme.fgDim
                            }
                        }

                        Column {
                            width: parent.width - 52
                            spacing: 3

                            // App name • age  ...  chevron
                            Item {
                                width: parent.width
                                height: header.implicitHeight

                                Text {
                                    id: header
                                    width: parent.width - 24
                                    elide: Text.ElideRight
                                    text: (card.n.appName || "Notification") + "  •  " + Notifs.age(card.n)
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    color: Theme.fgDim
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: header.verticalCenter
                                    visible: body.truncated || card.expanded
                                    text: String.fromCodePoint(card.expanded ? 0xf0143 : 0xf0140)   // md-chevron-up/down
                                    font.family: Theme.font
                                    font.pixelSize: 16
                                    color: chevronArea.containsMouse ? Theme.accent : Theme.fgDim

                                    MouseArea {
                                        id: chevronArea
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: card.expanded = !card.expanded
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: card.n.summary
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Text {
                                id: body
                                width: parent.width
                                visible: text !== ""
                                text: card.n.body
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                maximumLineCount: card.expanded ? 10 : 1
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 13
                                color: Theme.fgDim
                                linkColor: Theme.accent
                            }

                            // Action buttons
                            Flow {
                                width: parent.width
                                visible: card.buttons.length > 0
                                topPadding: 6
                                spacing: 6

                                Repeater {
                                    model: card.buttons

                                    Rectangle {
                                        required property var modelData
                                        width: label.implicitWidth + 24
                                        height: 30
                                        radius: 10
                                        color: btnArea.containsMouse ? Theme.withAlpha(Theme.accent, 0.2) : Theme.surface
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Text {
                                            id: label
                                            anchors.centerIn: parent
                                            text: parent.modelData.text
                                            font.family: Theme.font
                                            font.pixelSize: 12
                                            color: btnArea.containsMouse ? Theme.accent : Theme.fg
                                        }
                                        MouseArea {
                                            id: btnArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                parent.modelData.invoke();
                                                card.close(false);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
