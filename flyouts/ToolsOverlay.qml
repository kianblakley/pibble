import QtQuick
import Quickshell
import Quickshell.Wayland
import "root:/config"
import "root:/services"
import "root:/ui"

// The surface the screen tools' gestures happen on when nothing else of
// pibble's is up (see services/ScreenTools.qml for what they are, and
// ui/ToolsView.qml for the frozen frame they are made on - drawn over the
// launcher instead when the launcher is up).
//
// Everything about how this window exists is the color picker's, copied on
// purpose rather than rediscovered (see ColorPickerOverlay for the long form):
// it is mapped once and never unmapped or resized, because doing either to a
// fullscreen surface with the pointer inside it takes the shell down in
// QtWayland; idle, it paints nothing and has an empty input region; in use, it
// takes the whole surface's input and the keyboard with it. The only thing that
// ever changes between gestures is the mask.
//
// The menu that starts them, when it is opened with no launcher up
// (`pibble toggle tools`), is drawn here too, over everything else: it needs
// exactly this surface's arrangement - the whole screen's input and the
// keyboard while it is up, nothing while it is not - and a third fullscreen
// surface kept mapped for the sake of four buttons would be a poor trade.
// Opened with the launcher up it is the launcher's instead (see
// PowerOverlay), drawn over the launcher's own backdrop.
Scope {
    id: root

    // see window.onScreenChanged
    function remap(): void {
        if (!window.visible && window.screen && window.screen.width > 0)
            window.visible = true;
    }

    PanelWindow {
        id: window

        screen: ActiveOutput.screen
        // permanently mapped - see the header, and ColorPickerOverlay
        visible: true
        // The one way the surface does go is with its output; put it back when
        // a real screen is there again, a tick late because mapping moves the
        // screen too and this would be answering itself.
        onScreenChanged: Qt.callLater(root.remap)
        anchors { top: true; bottom: true; left: true; right: true }
        mask: tools.active || menu.up ? null : emptyInput
        Region { id: emptyInput }

        // Nothing of this surface is ever blurred behind - the frame is opaque
        // and the menu stands on the bare desktop - so it asks for one pixel
        // off the surface rather than for nothing, which a compositor rule
        // that blurs this namespace could take for "all of it".
        BackgroundEffect.blurRegion: noBlurRegion
        Region {
            id: noBlurRegion
            x: -8
            y: -8
            width: 1
            height: 1
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "pibble-tools"
        WlrLayershell.keyboardFocus: tools.active || ScreenTools.menuOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        ToolsView {
            id: tools
            anchors.fill: parent
            active: ScreenTools.active && ScreenTools.host === "overlay"
        }

        // The gesture belongs to the output it started on. Focus moving to
        // another one mid-way would carry this window there with a frame of
        // the wrong screen in it, so that ends the gesture instead.
        Connections {
            target: ActiveOutput
            function onNameChanged(): void {
                if (tools.active)
                    ScreenTools.close();
                ScreenTools.menuOpen = false;
            }
        }

        // the menu's keys, while it is up - the view takes its own
        Item {
            id: menuKeys
            Keys.onPressed: event => {
                if (!ScreenTools.menuOpen)
                    return;
                event.accepted = true;
                menu.key(event);
            }
        }
        Connections {
            target: ScreenTools
            function onMenuOpenChanged(): void {
                if (ScreenTools.menuOpen)
                    menuKeys.forceActiveFocus();
            }
        }

        // ---------- the menu ----------

        // `pibble toggle tools`'s menu; the launcher draws its own. Closed
        // first whatever was picked: the gestures and a new recording all
        // photograph the screen, and each waits for the menu's exit on its
        // own account (ScreenTools.afterMenu).
        ToolsMenu {
            id: menu
            anchors.fill: parent
            open: ScreenTools.menuOpen
            onDismissed: ScreenTools.menuOpen = false
            onPicked: action => {
                ScreenTools.menuOpen = false;
                ScreenTools.run(action);
            }
        }
    }
}
