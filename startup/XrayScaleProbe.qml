import QtQuick
import Quickshell
import Quickshell.Wayland
import "root:/services"

// Measures the output scale the xray blur is baked against, once, by asking
// for a single still screencopy frame of the output and dividing its pixel
// size by the screen's logical size.
//
// Screencopy only delivers to a surface that is actually being composited, so
// this has to be a real (1x1, click-through, invisible) window rather than a
// bare item. The frame is never displayed or read — only its dimensions — and
// the surface goes away the moment the number lands. A compositor with no
// screencopy support leaves Wallpapers' own timeout to settle it at 1, i.e.
// logical pixels stand in for output pixels, which is exactly right on an
// unscaled output.
LazyLoader {
    active: Wallpapers.xrayScaleWanted

    PanelWindow {
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

        ScreencopyView {
            width: 1
            height: 1
            live: false
            paintCursor: false
            captureSource: Wallpapers.screen
            onHasContentChanged: {
                const s = Wallpapers.screen;
                if (hasContent && s && s.width > 0)
                    Wallpapers.setXrayOutputScale(sourceSize.width / s.width);
            }
        }
    }
}
