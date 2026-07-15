import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications

// Persistent OSD daemon: volume bar + notification popups.
// Start at login: spawn-at-startup "qs" "-p" "<repo>/daemon"
// Blur comes from a niri layer-rule on the "app-launcher-osd" namespace.
ShellRoot {
    id: root

    readonly property color accent: "#e8a24a"
    readonly property color fg: "#f3ede4"
    readonly property color muted: "#8a8378"
    readonly property string mono: "JetBrains Mono"

    // ---------- volume OSD ----------
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool sinkMuted: sink && sink.audio ? sink.audio.muted : false

    // ignore the initial property churn while pipewire connects
    property bool volReady: false
    Timer {
        interval: 2000
        running: true
        onTriggered: root.volReady = true
    }
    onVolChanged: if (volReady) volOsd.ping()
    onSinkMutedChanged: if (volReady) volOsd.ping()

    Scope {
        id: volOsd
        property bool show: false
        function ping() {
            show = true;
            volHide.restart();
        }
        Timer {
            id: volHide
            interval: 1600
            onTriggered: volOsd.show = false
        }

        LazyLoader {
            active: volOsd.show

            PanelWindow {
                id: volWin
                anchors.bottom: true
                margins.bottom: 90
                implicitWidth: 380
                implicitHeight: 68
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "app-launcher-osd"
                BackgroundEffect.blurRegion: Region {
                    width: volWin.width
                    height: volWin.height
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 18
                    color: Qt.rgba(10 / 255, 9 / 255, 8 / 255, 0.4)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.33)
                    opacity: 0
                    scale: 0.92
                    Component.onCompleted: {
                        opacity = 1;
                        scale = 1;
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 16

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.sinkMuted ? "🔇" : root.vol < 0.01 ? "🔈" : root.vol < 0.5 ? "🔉" : "🔊"
                            font.pixelSize: 20
                        }
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 220
                            height: 8

                            Rectangle {
                                anchors.fill: parent
                                radius: 4
                                color: Qt.alpha(root.accent, 0.15)
                            }
                            Rectangle {
                                width: parent.width * Math.min(1, root.vol)
                                height: parent.height
                                radius: 4
                                color: root.sinkMuted ? Qt.alpha(root.muted, 0.8) : root.accent
                                Behavior on width {
                                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52
                            horizontalAlignment: Text.AlignRight
                            text: root.sinkMuted ? "mute" : Math.round(root.vol * 100) + "%"
                            color: root.fg
                            font { family: root.mono; pixelSize: 14 }
                        }
                    }
                }
            }
        }
    }

    // ---------- notification OSD ----------
    // Shows the most recent notification as a popup; a new one replaces it.
    property var notif: null
    NotificationServer {
        id: notifServer
        bodySupported: true
        imageSupported: true
        onNotification: n => {
            n.tracked = true;
            root.notif = n;
            notifHide.restart();
        }
    }
    Timer {
        id: notifHide
        interval: root.notif && root.notif.expireTimeout > 0 ? root.notif.expireTimeout : 5000
        onTriggered: root.dismissNotif()
    }
    function dismissNotif() {
        if (notif) {
            notif.expire();
            notif = null;
        }
    }

    LazyLoader {
        active: root.notif !== null

        PanelWindow {
            id: notifWin
            anchors.top: true
            anchors.right: true
            margins.top: 24
            margins.right: 24
            implicitWidth: 420
            implicitHeight: notifCard.height
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "app-launcher-osd"
            BackgroundEffect.blurRegion: Region {
                width: notifWin.width
                height: notifWin.height
            }

            Rectangle {
                id: notifCard
                width: parent.width
                height: notifCol.height + 30
                radius: 18
                color: Qt.rgba(10 / 255, 9 / 255, 8 / 255, 0.4)
                border.width: 1
                border.color: Qt.alpha(root.accent, 0.33)
                opacity: 0
                scale: 0.94
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                }
                Behavior on opacity {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                }

                Row {
                    id: notifRow
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 15
                    spacing: 14

                    Image {
                        id: notifImage
                        visible: source !== ""
                        width: visible ? 48 : 0
                        height: 48
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        source: {
                            const n = root.notif;
                            if (!n)
                                return "";
                            if (n.image)
                                return n.image;
                            return n.appIcon ? Quickshell.iconPath(n.appIcon, true) : "";
                        }
                    }

                    Column {
                        id: notifCol
                        width: 390 - (notifImage.visible ? 62 : 0) - 15
                        spacing: 4

                        Text {
                            visible: text.length > 0
                            text: root.notif ? root.notif.appName : ""
                            color: root.muted
                            font { family: root.mono; pixelSize: 11; letterSpacing: 2; capitalization: Font.AllUppercase }
                        }
                        Text {
                            visible: text.length > 0
                            width: parent.width
                            text: root.notif ? root.notif.summary : ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: root.fg
                            font { family: root.mono; pixelSize: 14; weight: Font.DemiBold }
                        }
                        Text {
                            visible: text.length > 0
                            width: parent.width
                            text: root.notif ? root.notif.body : ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            color: root.muted
                            font { family: root.mono; pixelSize: 12 }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.dismissNotif()
                }
            }
        }
    }
}
