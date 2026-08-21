import QtQuick
import Quickshell
import Quickshell.Wayland
import "root:/config"
import "root:/services"

// The picker itself: a frozen frame of the screen with a round magnifier
// centered under the cursor, whose border is the picked color itself.
//
// Active only while ScreenColor.overlayActive - see the note there for why
// this owns the interaction (and so freezes the screen) rather than handing it
// to the compositor, and for where the frozen frame's file comes from. The
// same Image is both the fullscreen backdrop and the lens's pixel source, so
// the color that lands is read from the very frame under the lens - it cannot
// drift between what was shown and what was clicked.
Scope {
    id: root

    // Native frame pixels across the lens. Odd, so there is a middle one for
    // the crosshair to sit on; wide enough that shapes stay recognizable,
    // which is what makes the zoom read as a zoom.
    readonly property int span: 21
    readonly property int magSize: 210

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
        anchors { top: true; bottom: true; left: true; right: true }
        mask: ScreenColor.overlayActive ? null : emptyInput
        Region { id: emptyInput }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "pibble-colorpicker"
        WlrLayershell.keyboardFocus: ScreenColor.overlayActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        property real cx: width / 2
        property real cy: height / 2
        property string hex: "#000000"
        // False until the pointer has reported a position for *this* pick -
        // before that, cx/cy still hold wherever the last pick ended, and a
        // lens shown there would visibly snap to the cursor on first motion.
        property bool aimed: false

        // A layer surface maps at Quickshell's default size and is only told
        // its real dimensions a moment later, so sampling waits: any earlier
        // and every logical-to-native coordinate is scaled by a ratio taken
        // against the wrong width.
        readonly property bool ready: width > 1000 && height > 1000 && frozen.status === Image.Ready
                                      && frozen.sourceSize.width >= width && frozen.sourceSize.height >= height

        onReadyChanged: {
            // the pointer usually spoke while the capture was still running -
            // cx/cy are live from those motions even though sampling had to
            // wait for the frame - so the lens can appear the moment the
            // frame is ready, already in the right place
            if (ready && (aimed || tracker.containsMouse))
                tracker.track(aimed ? cx : tracker.mouseX, aimed ? cy : tracker.mouseY);
            if (ready && tracker.containsMouse)
                aimed = true;
        }

        // The frozen frame, straight off the capture file: the fullscreen
        // backdrop the user sees, and the very image the lens samples. It
        // stands in for the real screen, so it must not be resampled into
        // something softer than what it replaced.
        Image {
            id: frozen
            anchors.fill: parent
            source: ScreenColor.shotPath ? "file://" + ScreenColor.shotPath : ""
            visible: ScreenColor.overlayActive && status === Image.Ready
            fillMode: Image.Stretch
            cache: false
            smooth: false
        }

        // A capture or decode that never delivers must not freeze a
        // transparent window forever - hand the pick to the compositor's own
        // picker instead. The window opens before the capture even starts, so
        // this bounds the launcher's exit animation plus the whole capture
        // and decode on the slowest observed path, with margin.
        Timer {
            running: ScreenColor.overlayActive
            interval: 6000
            onTriggered: {
                if (!window.ready)
                    ScreenColor.magnifyFailed();
            }
        }

        Connections {
            target: ScreenColor
            function onOverlayActiveChanged(): void {
                if (ScreenColor.overlayActive) {
                    window.aimed = false;
                    keys.forceActiveFocus();
                }
            }
        }

        MouseArea {
            id: tracker
            anchors.fill: parent
            enabled: ScreenColor.overlayActive
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            // the lens sits under the cursor and marks the target pixel itself,
            // so a pointer on top would only cover what it is aiming at
            cursorShape: Qt.BlankCursor
            // position always lands (the loupe follows it, and it is what
            // makes the lens appear at all); sampling additionally needs the
            // frame, so before `ready` it simply waits
            function track(mx: real, my: real): void {
                window.cx = mx;
                window.cy = my;
                if (!window.ready)
                    return;
                // The frame arrives at the output's native resolution, which on
                // a scaled display is larger than this window - so a logical
                // coordinate has to be taken up to native before sampling.
                // Derived from the image rather than asked of the compositor,
                // and computed here rather than kept as a bound property: a
                // binding chained through `ready` can still hold its stale
                // value inside the very onReadyChanged handler that calls this.
                //
                // Rounded, not floored: at fractional scale the pointer sits
                // between native pixels, and the pixel the user saw the cursor
                // on before the pick is the one the compositor snapped its
                // image to - the nearest, not the one containing the point.
                // Frame-vs-screen alignment itself is exact (verified by
                // cross-correlating a capture against the compositor's own
                // screenshot), so this rounding is the whole of the remaining
                // aim error; the arrow keys cover anything finer.
                const ratio = frozen.sourceSize.width > 0 ? frozen.sourceSize.width / window.width : 1;
                lens.sx = Math.max(0, Math.min(frozen.sourceSize.width - 1, Math.round(mx * ratio)));
                lens.sy = Math.max(0, Math.min(frozen.sourceSize.height - 1, Math.round(my * ratio)));
                lens.requestPaint();
            }
            onEntered: {
                tracker.track(tracker.mouseX, tracker.mouseY);
                window.aimed = true;
            }
            onPositionChanged: mouse => {
                tracker.track(mouse.x, mouse.y);
                window.aimed = true;
            }
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    ScreenColor.cancelOverlay();
                    return;
                }
                if (!window.ready)
                    return;
                // deliberately no track() here: the color delivered is exactly
                // the one the lens was showing when the button went down, not
                // one a pixel over because the hand moved in the press
                ScreenColor.finishOverlay(window.hex);
            }
        }

        // Escape cancels. Focus is taken when the overlay maps rather than
        // declaratively, since this window only exists while a pick is running.
        Item {
            id: keys
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    ScreenColor.cancelOverlay();
                    event.accepted = true;
                    return;
                }
                // At fractional scale the pointer is only good to about a
                // native pixel, so the arrows walk the sample one pixel at a
                // time for exact aim; Enter/Space take what the lens shows.
                // The next real mouse move re-tracks and wins.
                const step = { [Qt.Key_Left]: [-1, 0], [Qt.Key_Right]: [1, 0], [Qt.Key_Up]: [0, -1], [Qt.Key_Down]: [0, 1] }[event.key];
                if (step && window.ready) {
                    lens.sx = Math.max(0, Math.min(frozen.sourceSize.width - 1, lens.sx + step[0]));
                    lens.sy = Math.max(0, Math.min(frozen.sourceSize.height - 1, lens.sy + step[1]));
                    lens.requestPaint();
                    event.accepted = true;
                    return;
                }
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && window.ready) {
                    ScreenColor.finishOverlay(window.hex);
                    event.accepted = true;
                }
            }
        }

        // The lens. The magnified pixels are a Canvas (a circle needs a real
        // clip path, and this magnifies the *native* frame pixels instead of
        // the copy already downscaled to fit the window), but the color-band
        // border deliberately is not: canvas frames can reach the screen (and
        // grabs) mid-paint - fresh pixels, stale strokes, which is exactly the
        // "ring one pixel behind the target" this replaced - so the ring is a
        // Rectangle border bound to `hex`, which the scene graph updates
        // atomically and always settles to the last sampled value.
        Item {
            id: loupe
            width: root.magSize
            height: root.magSize
            x: window.cx - width / 2
            y: window.cy - height / 2
            visible: window.ready && ScreenColor.overlayActive && window.aimed

        Canvas {
            id: lens
            anchors.fill: parent
            // synchronous paints: sampling and strokes land in the same frame
            renderStrategy: Canvas.Immediate
            property int sx: 0
            property int sy: 0
            // a repaint requested while a canvas is still invisible is
            // dropped, and the loupe becomes visible in the same tick that
            // aims it - without this the ring sits on its stale hex (black,
            // on first use) until the first mouse move paints for real
            onVisibleChanged: {
                if (visible)
                    requestPaint();
            }
            onPaint: {
                if (frozen.status !== Image.Ready)
                    return;
                const ctx = getContext("2d");
                const r = width / 2;
                const cell = width / root.span;
                const half = (root.span - 1) / 2;
                ctx.reset();
                // The sample happens first, and at the origin: on a
                // fractionally scaled output the canvas backing store is
                // larger than the item, and getImageData indexes it in
                // *device* pixels - a read at the item's center coordinates
                // lands a couple of cells up-left of the center cell (which is
                // exactly what shipped: a border colored like the pixel two up
                // and two left of the target). Only at (0,0) do the two
                // coordinate spaces agree regardless of scale, so the target
                // pixel is drawn there, read, and wiped before the lens paints.
                ctx.imageSmoothingEnabled = false;
                ctx.drawImage(frozen, lens.sx, lens.sy, 1, 1, 0, 0, 2, 2);
                const mid = ctx.getImageData(0, 0, 1, 1).data;
                if (mid[3] === 0) {
                    // The very first paint after this canvas becomes visible
                    // cannot draw the frame yet - the image isn't available to
                    // the freshly created backing store, so the probe reads
                    // transparent (and the magnified region drew nothing
                    // either). Repaint next frame instead of publishing a
                    // black sample; the retry lands with real pixels.
                    ctx.reset();
                    Qt.callLater(lens.requestPaint);
                    return;
                }
                window.hex = "#" + [mid[0], mid[1], mid[2]].map(v => v.toString(16).padStart(2, "0")).join("").toUpperCase();
                ctx.clearRect(0, 0, 3, 3);
                ctx.save();
                // clip runs a few px *under* the ring band on purpose: a
                // canvas clip edge is aliased, so it is buried beneath the
                // opaque band and the visible inner boundary becomes the
                // ring's own antialiased border instead
                ctx.beginPath();
                ctx.arc(r, r, r - 8, 0, Math.PI * 2);
                ctx.clip();
                // Base fill, so that where the region runs past the edge of the
                // screen the lens reads as empty rather than letting the
                // unmagnified frame behind it show through at 1:1, which would
                // look like the magnification had simply stopped.
                ctx.fillStyle = "#1a1a1a";
                ctx.fillRect(0, 0, width, height);
                // nearest-neighbour: the whole point is to show pixels as
                // squares, not to interpolate them away
                ctx.imageSmoothingEnabled = false;
                // The view is always centred on the cursor's pixel, never
                // clamped: sliding it back inside the frame near an edge would
                // leave the target marking a pixel that is no longer in the
                // middle of what is drawn. Instead only the part of the region
                // that exists is drawn, at its matching offset, so the edge of
                // the screen reads as an edge.
                const ox = lens.sx - half;
                const oy = lens.sy - half;
                const x0 = Math.max(0, ox);
                const y0 = Math.max(0, oy);
                const x1 = Math.min(frozen.sourceSize.width, ox + root.span);
                const y1 = Math.min(frozen.sourceSize.height, oy + root.span);
                if (x1 > x0 && y1 > y0)
                    ctx.drawImage(frozen, x0, y0, x1 - x0, y1 - y0,
                                  (x0 - ox) * cell, (y0 - oy) * cell,
                                  (x1 - x0) * cell, (y1 - y0) * cell);

                // pixel grid, so the squares read as pixels and the middle
                // one reads as exactly one of them; mid gray stays visible
                // over light and dark content alike
                ctx.strokeStyle = "#4d808080";
                ctx.lineWidth = 1;
                ctx.beginPath();
                for (let i = 1; i < root.span; i++) {
                    ctx.moveTo(i * cell, 0);
                    ctx.lineTo(i * cell, height);
                    ctx.moveTo(0, i * cell);
                    ctx.lineTo(width, i * cell);
                }
                ctx.stroke();

                // the target cell, boxed in two tones so it reads against
                // whatever is under it
                const bx = half * cell;
                const by = half * cell;
                ctx.lineWidth = 2;
                ctx.strokeStyle = "#000000";
                ctx.strokeRect(bx - 1, by - 1, cell + 2, cell + 2);
                ctx.lineWidth = 1;
                ctx.strokeStyle = "#ffffff";
                ctx.strokeRect(bx, by, cell, cell);
                ctx.restore();
            }
        }

        // the border is the readout: the picked color itself, hairlined on
        // both sides so it still has an edge when the color matches what is
        // around it
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 11
            border.color: window.hex

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: "#c0ffffff"
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 11
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: "#80000000"
            }
        }
        }
    }
}
