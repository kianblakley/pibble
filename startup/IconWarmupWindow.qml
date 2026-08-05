import QtQuick
import Quickshell
import Quickshell.Wayland
import "root:/services"

// Warms the app-icon pixmap cache the moment the daemon starts, so the very
// first launcher open renders icons immediately instead of briefly showing the
// two-letter fallback while the SVGs decode. QML decodes images on a single
// reader thread, so ~100 theme SVGs take a second or two - pay that at session
// start, not at first open.
//
// A tiny transparent overlay surface is enough to drive the image provider and
// populate the process-global cache; it unloads once the cache is warm, since
// the launcher's own in-window warm-up items keep every pixmap referenced after
// that and the cache never evicts them.
Scope {
    id: root

    property bool warming: true
    Timer {
        interval: 30000
        running: true
        onTriggered: root.warming = false
    }

    LazyLoader {
        active: root.warming

        PanelWindow {
            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "pibble-warmup"
            mask: Region {} // click-through, takes no input

            Item {
                anchors.fill: parent
                Repeater {
                    model: Apps.warmOrder
                    Image {
                        required property var modelData
                        width: 1
                        height: 1
                        asynchronous: true
                        sourceSize: Qt.size(88, 88)
                        source: Icons.url(modelData.icon)
                    }
                }
            }
        }
    }
}
