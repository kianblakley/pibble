import QtQuick
import Quickshell
import Quickshell.Wayland
import "root:/config"
import "root:/services"
import "root:/ui"

// The surface a color pick happens on when the launcher is not where it
// happens (see ScreenColor.host): the picker itself is ui/ColorPickView.qml,
// and this is only the window it needs.
Scope {
    id: root

    readonly property bool picking: ScreenColor.overlayActive && ScreenColor.host === "overlay"

    // see window.onScreenChanged
    function remapPicker(): void {
        if (!window.visible && window.screen && window.screen.width > 0)
            window.visible = true;
    }

    PanelWindow {
        id: window

        screen: ActiveOutput.screen
        // Permanently mapped, permanently fullscreen. Unmapping, and even
        // resizing away, a fullscreen surface with the pointer inside it
        // lands in QtWayland's handleScreensChanged with a stale
        // entered-screen entry and takes the whole shell down (observed on
        // every lifecycle variant tried - unmap, deferred unmap, collapse to
        // a corner speck). So the surface never changes at all between picks:
        // it stays exactly as it is, paints nothing, and flips only its
        // *input region* - empty and click-through when idle, whole-surface
        // during a pick. A mask change is a plain wl_surface attribute, no
        // configure, no lifecycle, no crash path.
        visible: true
        // The one way the surface does go: the compositor closes a layer
        // surface along with its output (niri, on unplug and on `output off`
        // alike), and Quickshell answers that by writing false over the
        // `visible` above - the binding is gone, and when the output comes
        // back nothing maps the picker again. Four such removals in one
        // daemon's log here, each leaving the eyedropper dead until a reload.
        // So it is put back the moment a real screen is there again - a new
        // surface on a new output, nothing like the unmap described above -
        // and not for the nameless 0x0 placeholder Qt stands in meanwhile,
        // which has nothing to map onto. A tick late, because mapping moves
        // the screen too and this would be answering itself.
        onScreenChanged: Qt.callLater(root.remapPicker)
        anchors { top: true; bottom: true; left: true; right: true }
        mask: root.picking ? null : emptyInput
        Region { id: emptyInput }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "pibble-colorpicker"
        WlrLayershell.keyboardFocus: root.picking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        ColorPickView {
            anchors.fill: parent
            active: root.picking
        }
    }
}
