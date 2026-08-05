import QtQuick
import Quickshell
import Quickshell.Wayland
import "root:/services"

// Measures the output scale the xray blur is baked against, once, by reading
// the device pixel ratio the compositor hands a real surface.
//
// It has to be a real (1x1, click-through, invisible) window rather than the
// screen's own devicePixelRatio: only a mapped surface is told the *fractional*
// scale (wp-fractional-scale-v1), which is the number the blur needs — 1.25
// against a screen and a never-shown window that both report the rounded 2.
// The surface goes away the moment the number lands.
//
// This used to take a still screencopy frame of the output and divide its pixel
// size by the screen's logical size, which measures the same thing. Do not go
// back to that: asking for a screencopy frame makes Quickshell bind a second
// wl_output, and the compositor then sends every one of this process's surfaces
// a wl_surface.enter naming an output Qt did not bind and cannot resolve, which
// poisons Qt's per-surface screen bookkeeping for the rest of the session — the
// next surface to leave an output (i.e. the first time the launcher closes)
// segfaults inside QWaylandWindow::handleScreensChanged. That reproduced on
// every `pibble toggle` against a cold daemon.
Scope {
    id: root

    property real measured: 0

    // A freshly created surface reports 1, then the output's rounded integer
    // scale, and only lands on the fractional scale a few milliseconds later,
    // so publish on a debounce rather than latching the first value — the whole
    // wallpaper folder gets baked against whatever this resolves to. Publishing
    // is also what unloads the window below (it clears xrayScaleWanted), which
    // is why the timer sits outside the LazyLoader: it has to outlive what it
    // destroys. Wallpapers' own 3s timeout still backstops a compositor that
    // reports nothing at all.
    Timer {
        id: settle
        interval: 500
        onTriggered: Wallpapers.setXrayOutputScale(root.measured)
    }

    LazyLoader {
        active: Wallpapers.xrayScaleWanted

        PanelWindow {
            id: probe

            anchors.top: true
            anchors.left: true
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            screen: Wallpapers.screen
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "pibble-probe"
            mask: Region {}

            // seeded here as well as on change, since an unscaled output can
            // map at 1 and never report anything different
            Component.onCompleted: {
                root.measured = probe.devicePixelRatio;
                settle.restart();
            }
            onDevicePixelRatioChanged: {
                root.measured = probe.devicePixelRatio;
                settle.restart();
            }
        }
    }
}
