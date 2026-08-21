import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "root:/config"
import "root:/services"
import "root:/ui"

// Notification flyout, one notification at a time.
//
// "bubble": an app-tinted circle pops in below the top-right corner, pulses
// with an expanding ring, then a compact card staggers its lines in to the
// left of it. "pill" is the same card without the circle, tucked into the
// corner directly. Same-app arrivals replace the visible card (it slides out
// and the new one fires next; if the card hasn't appeared yet the content just
// swaps in place); other apps queue and fire after the current one dismisses.
// pibble's own error and missing-dependency alerts are the one exception -
// they queue against each other like separate senders (see Notifier.keyOf).
//
// The tint colour is the dominant colour of the app icon (Canvas pixel
// average, cached per icon), falling back to the flyout theme accent.
Scope {
    id: root

    // Own org.freedesktop.Notifications only while the flyout is enabled;
    // unloading releases the name for another daemon to claim.
    LazyLoader {
        active: Settings.flyoutEnabled("notifs")

        NotificationServer {
            bodySupported: true
            imageSupported: true
            onNotification: n => {
                // the eyedropper's frozen frame can be taken with the
                // compositor's own screenshot action, and niri announces
                // every capture - so while a pick is running its screenshot
                // toast is swallowed, or every eyedropper use would
                // celebrate itself
                if (ScreenColor.picking && (String(n.appName ?? "") === "niri" || /^Screenshot/.test(String(n.summary ?? "")))) {
                    n.dismiss();
                    return;
                }
                n.tracked = true;
                // notifications pibble replay fires itself must not become
                // replayable history, or replaying repeatedly would keep
                // pushing the same notification back to the front
                if (n.appName !== "REPLAY")
                    Notifier.remember(n);
                flyout.item?.accept(n);
            }
        }
    }

    LazyLoader {
        id: flyout
        active: Settings.flyoutEnabled("notifs")

        PanelWindow {
            id: window
            // hidden -> appear (circle pops in) -> pulse (overshoot + ring) ->
            // show (card staggers in, timeout runs) -> dismiss (lines stagger
            // out, card slides, circle shrinks) -> hidden
            property string phase: "hidden"
            // "pill" skips every bubble beat: no circle, no pulse phase, the
            // card claims the corner the circle vacated
            readonly property bool bubble: Settings.notifStyle !== "pill"
            property var current: null
            // snapshot of the notification's content: keeps the card intact
            // through the exit animation even if the sender closes the object
            property var view: ({ own: false, glyph: "", app: "", key: "", summary: "", body: "", image: "", icon: "", timeout: 0 })
            property var queue: []
            property int exitDir: 0
            // this dismissal keeps the bubble up until the card is gone
            property bool lingerOut: false
            // "simple" | "thumb" | "rich"; frozen when the card fires so a late
            // image probe can't reshape the visible card
            property string variant: "simple"
            property color tintColor: Theme.notification.accent
            property var tintCache: ({})
            Behavior on tintColor {
                ColorAnimation { duration: 220 }
            }

            // seeded here, then owned by fire() from the first card on
            screen: ActiveOutput.screen
            visible: phase !== "hidden"
            anchors.top: true
            anchors.right: true
            // fixed size: everything animates inside (see the OSD architecture
            // note); sized for the widest card at max font scale plus ring bloom
            // and a fully expanded body
            implicitWidth: 720
            implicitHeight: 640
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "pibble-notifications"

            function accept(n) {
                // sender may retract a queued notification before it fires
                n.closed.connect(() => window.unqueue(n));
                // fire straight away only when nothing is up AND nothing is
                // waiting (during the inter-notification gap the phase is hidden
                // but the queue must keep its order)
                if (phase === "hidden" && queue.length === 0) {
                    fire(n);
                    return;
                }
                // never hold two notifications of one app: replace in the queue
                for (let i = 0; i < queue.length; i++) {
                    if (appKey(queue[i]) === appKey(n)) {
                        const old = queue[i];
                        queue[i] = n;
                        old.expire();
                        return;
                    }
                }
                if (phase !== "hidden" && view.key === appKey(n)) {
                    if (phase === "appear" || phase === "pulse") {
                        // card isn't up yet: swap the content in place
                        const old = current;
                        snapshot(n);
                        if (old)
                            old.expire();
                        return;
                    }
                    // on screen: slide the current card out now, fire this next
                    queue.unshift(n);
                    if (phase === "show")
                        dismiss(0);
                    return; // already dismissing: it fires on finalize
                }
                if (queue.length >= 6)
                    queue.shift().expire();
                queue.push(n);
            }
            function unqueue(n) {
                const i = queue.indexOf(n);
                if (i >= 0)
                    queue.splice(i, 1);
            }
            // identity for replace-within-app; derived in Notifier so it can't
            // drift from the `key` its viewOf snapshot carries (compared
            // against above). pibble's own error/dependency alerts get a unique
            // key each and so queue instead of replacing - see Notifier.keyOf
            function appKey(n): string {
                return Notifier.keyOf(n);
            }
            function snapshot(n) {
                current = n;
                view = Notifier.viewOf(n);
                aspectProbe.source = view.image;
                // errors and low battery always read as red, regardless of
                // theme/tint, so severity is visible at a glance
                if (view.glyph === Icons.alertTriangle || view.glyph === Icons.batteryLow) {
                    tintColor = "#e01e18";
                    return;
                }
                // missing-dependency alerts read as orange rather than red:
                // less severe than an actual failure, just something to
                // install when convenient
                if (view.glyph === Icons.deployedCodeAlert) {
                    tintColor = "#e0691a";
                    return;
                }
                // "default" theme tints from the app icon (else the media
                // image); pinned themes use their accent everywhere. Own
                // (pibble-sent) alerts never carry a real app icon - those
                // render a synthetic glyph instead - so they only ever tint
                // from a real image (wallpaper-changed thumbnail, an image
                // clip's "Copied to clipboard"); glyph-only own alerts (e.g.
                // trash, watcher notices) fall through to the theme accent
                const src = !Theme.tintNotificationsFromIcon ? ""
                    : view.own ? view.image
                    : (view.icon || view.image);
                if (!src)
                    tintColor = Theme.notification.accent;
                else if (tintCache[src] !== undefined)
                    tintColor = tintCache[src];
                else {
                    tintColor = Theme.notification.accent;
                    tint.src = src; // updates tintColor when extracted
                }
            }
            function fire(n) {
                snapshot(n);
                exitDir = 0;
                // onto whichever monitor is in use. Only ever while the window
                // is unmapped (phase is "hidden" for as long as it is, and this
                // is the only thing that leaves it): a layer surface's output
                // is fixed when it's created, so a card already on screen -
                // including one being replaced in place by a same-app arrival,
                // which never comes through here - stays where it is.
                if (phase === "hidden" && ActiveOutput.screen)
                    window.screen = ActiveOutput.screen;
                phase = "appear";
                phaseTimer.restart();
            }
            // dir: swipe direction (-1 rubber-bands back before the drift),
            // 0 for timeout/bubble click/sender-close; all exit drifting right
            function dismiss(dir: int) {
                if (phase === "hidden" || phase === "dismiss")
                    return;
                exitDir = dir;
                phase = "dismiss";
                phaseTimer.restart();
            }
            function finalize() {
                const c = current;
                current = null;
                if (c)
                    c.expire();
                phase = "hidden";
                if (queue.length > 0)
                    gapTimer.restart();
            }
            function computeVariant(): string {
                if (!view.image)
                    return "simple";
                // wide images (16:10 and up: screenshots, photos) read best as a
                // full strip; squarer ones (avatars, album art) as a thumbnail
                if (aspectProbe.status === Image.Ready && aspectProbe.implicitHeight > 0
                    && aspectProbe.implicitWidth / aspectProbe.implicitHeight >= 1.6)
                    return "rich";
                return "thumb";
            }

            onPhaseChanged: {
                iconIn.stop();
                iconPop.stop();
                iconSettle.stop();
                iconOut.stop();
                iconOutDelay.stop();
                stagInAnim.stop();
                stagOutAnim.stop();
                wipeAnim.stop();
                switch (phase) {
                case "appear":
                    ringAnim.stop();
                    // pill: no circle to choreograph
                    // entry pose, applied instantly (inst gates the Behaviors)
                    card.inst = true;
                    card.stagIn = 0;
                    card.stagOut = 0;
                    card.imgWipe = 0;
                    card.cardO = 0;
                    card.cardYS = 0.92;
                    card.swipeX = 0;
                    card.expanded = false;
                    card.inst = false;
                    ring.scale = 1;
                    ring.opacity = 0;
                    if (window.bubble)
                        iconIn.restart();
                    break;
                case "pulse":
                    iconPop.restart();
                    ringAnim.restart();
                    break;
                case "show":
                    variant = computeVariant();
                    if (window.bubble)
                        iconSettle.restart();
                    card.cardO = 1;
                    card.cardYS = 1;
                    stagInAnim.restart();
                    wipeAnim.restart();
                    break;
                case "dismiss":
                    stagOutAnim.restart();
                    // hold the bubble until the card has fully left
                    window.lingerOut = window.bubble && card.cardO > 0;
                    if (window.bubble) {
                        if (window.lingerOut)
                            iconOutDelay.restart();
                        else
                            iconOut.restart();
                    }
                    // every dismissal fades with a gentle rightward drift; a
                    // left swipe rubber-bands back through rest to reach it
                    if (card.cardO > 0)
                        card.swipeX = (exitDir < 0 ? 0 : card.swipeX) + 18;
                    card.cardO = 0;
                    break;
                }
            }

            Timer {
                id: phaseTimer
                interval: Settings.notifAnim === "none" ? 0
                    : window.phase === "appear" ? (window.bubble ? 430 : 60)
                    : window.phase === "pulse" ? 210
                    : window.lingerOut ? 640 : 340
                onTriggered: {
                    switch (window.phase) {
                    case "appear":
                        if (window.bubble) {
                            window.phase = "pulse";
                            phaseTimer.restart();
                        } else {
                            window.phase = "show"; // showTimer takes over
                        }
                        break;
                    case "pulse":
                        window.phase = "show"; // showTimer takes over
                        break;
                    case "dismiss":
                        window.finalize();
                        break;
                    }
                }
            }
            Timer {
                id: showTimer
                // a sender timeout of exactly 0 means "never expire" (spec): the
                // notification stays until clicked or swiped away
                interval: window.view.timeout > 0 ? window.view.timeout : Settings.notifTimeout
                running: window.phase === "show" && !cardHover.hovered && window.view.timeout !== 0
                onTriggered: window.dismiss(0)
            }
            Timer {
                // small beat between one notification leaving and the next firing
                id: gapTimer
                interval: 160
                onTriggered: {
                    if (window.queue.length > 0 && window.phase === "hidden")
                        window.fire(window.queue.shift());
                }
            }
            // sender closed the on-screen notification - animate out
            Connections {
                target: window.current
                ignoreUnknownSignals: true
                function onClosed() {
                    window.current = null;
                    window.dismiss(0);
                }
            }

            // aspect-ratio probe for the notification image; the icon-circle
            // phases (~630ms) cover the async load before the card needs it
            Image {
                id: aspectProbe
                visible: false
                asynchronous: true
                // ratio-only probe: cap one dimension (ratio is preserved
                // when only one is set) so a 4K screenshot isn't decoded at
                // native size just to read its aspect
                sourceSize.width: 160
                // a big image can outlast the icon phases; when the probe lands
                // while the card is up, re-classify once so a wide screenshot
                // isn't stuck cropped into the thumbnail circle
                onStatusChanged: {
                    if (status === Image.Ready && window.phase === "show")
                        window.variant = window.computeVariant();
                }
            }
            // dominant-colour extraction: the icon is decoded at 26x26 (fast,
            // off the GUI thread regardless of the source's native size),
            // grabbed to a real file, then drawn into the canvas and
            // averaged, weighted by saturation and alpha, skipping
            // near-white/black pixels; the result is normalised into a band
            // that reads on the dark card.
            // Canvas.drawImage() can't sample a live Image item's texture
            // directly (reads back all-zero pixels even once Ready), and
            // Canvas.loadImage() never resolves the "itemgrabber:" URL that
            // Item.grabToImage() hands back (onImageLoaded never fires for
            // it) - but a real file:// path loads and draws fine, so the
            // grab is saved to disk and reloaded from there. Grabbing the
            // already 26x26-decoded item keeps this cheap even when a
            // full-size screenshot arrives as notification media (loading
            // it at native resolution via Canvas.loadImage directly stalled
            // the whole shell).
            Image {
                id: tintSource
                x: -60
                y: 0
                width: 26
                height: 26
                asynchronous: true
                sourceSize: Qt.size(26, 26)
                source: tint.src
                onStatusChanged: {
                    if (status === Image.Ready) {
                        tintSource.grabToImage(result => {
                            if (result.saveToFile(SystemInfo.tintGrabPath)) {
                                tint.grabUrl = "file://" + SystemInfo.tintGrabPath;
                                tint.loadImage(tint.grabUrl);
                            }
                        });
                    }
                }
            }
            Canvas {
                id: tint
                property string src: ""
                property string grabUrl: ""
                x: -60
                y: 0
                width: 26
                height: 26
                renderStrategy: Canvas.Immediate
                renderTarget: Canvas.Image
                onImageLoaded: {
                    if (grabUrl && isImageLoaded(grabUrl))
                        requestPaint();
                }
                onPaint: {
                    if (!src || !grabUrl || !isImageLoaded(grabUrl))
                        return;
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.drawImage(grabUrl, 0, 0, width, height);
                    const d = ctx.getImageData(0, 0, width, height).data;
                    let r = 0, g = 0, b = 0, w = 0;
                    for (let i = 0; i < d.length; i += 4) {
                        const a = d[i + 3] / 255;
                        if (a < 0.4)
                            continue;
                        const mx = Math.max(d[i], d[i + 1], d[i + 2]);
                        const mn = Math.min(d[i], d[i + 1], d[i + 2]);
                        const lum = (mx + mn) / 510;
                        if (lum > 0.95 || lum < 0.06)
                            continue;
                        const sat = mx > 0 ? (mx - mn) / mx : 0;
                        const wt = a * (0.1 + sat * sat);
                        r += d[i] * wt;
                        g += d[i + 1] * wt;
                        b += d[i + 2] * wt;
                        w += wt;
                    }
                    let c = Theme.notification.accent;
                    if (w > 3) {
                        c = Qt.rgba(r / w / 255, g / w / 255, b / w / 255, 1);
                        // pull into a visible band; leave true greys grey
                        c = (c.hslHue < 0 || c.hslSaturation < 0.12)
                            ? Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, Math.min(0.75, Math.max(0.5, c.hslLightness)), 1)
                            : Qt.hsla(c.hslHue, Math.max(c.hslSaturation, 0.5), Math.min(0.68, Math.max(0.45, c.hslLightness)), 1);
                    }
                    window.tintCache[src] = c;
                    if (src === window.view.icon || src === window.view.image)
                        window.tintColor = c;
                    unloadImage(grabUrl);
                    grabUrl = "";
                    src = ""; // also clears tintSource.source
                }
            }

            // input only over the card and bubble while they are interactive
            mask: Region {
                x: card.x
                y: card.y
                width: window.phase === "show" ? card.width : 0
                height: card.height
                regions: [
                    Region {
                        x: bubble.x
                        y: bubble.y
                        width: window.bubble && window.phase === "show" ? bubble.width : 0
                        height: bubble.height
                    }
                ]
            }
            // ── icon circle ──
            Item {
                id: bubble
                visible: window.bubble
                x: window.width - width - 26
                y: 24
                width: 52
                height: 52
                scale: 0
                opacity: 0
                // grow-on-hover rides a transform so the phase animations own
                // `scale`; independent of the card's (separate handlers)
                readonly property bool hov: bubbleHover.hovered && window.phase === "show"
                property real hoverS: hov ? 1.08 : 1
                Behavior on hoverS {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                transform: Scale {
                    origin.x: bubble.width / 2
                    origin.y: bubble.height / 2
                    xScale: bubble.hoverS
                    yScale: bubble.hoverS
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius(width / 2)
                    antialiasing: true
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(window.tintColor, 1.18) }
                        GradientStop { position: 1; color: Qt.darker(window.tintColor, 1.22) }
                    }

                }
                Rectangle {
                    id: ring
                    anchors.fill: parent
                    radius: Theme.radius(width / 2)
                    antialiasing: true
                    color: "transparent"
                    border.width: 2
                    border.color: window.tintColor
                    opacity: 0
                }
                Image {
                    id: circleIcon
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    sourceSize: Qt.size(56, 56)
                    asynchronous: true
                    source: window.view.own ? "" : window.view.icon
                    visible: String(source) !== ""
                }
                // no app icon (own or not - e.g. niri's screenshot
                // notification carries only an image, no icon): fall back
                // to the icon font's glyph (Icons.bell by default, see
                // Notifier.glyphFor) instead of a fixed drawing
                readonly property color inkC: "#f2f0ee"
                Text {
                    anchors.centerIn: parent
                    visible: !circleIcon.visible
                    text: window.view.glyph
                    color: bubble.inkC
                    font { family: Icons.family; pixelSize: Theme.fontSize(24) }
                }
                HoverHandler {
                    id: bubbleHover
                }
                // clicking the bubble dismisses the notification
                MouseArea {
                    anchors.fill: parent
                    enabled: window.phase === "show"
                    onClicked: window.dismiss(0)
                }
            }

            // icon keyframes ported from the reference CSS; all durations
            // collapse to 0 when notifAnim is "none" so the bubble/card land
            // on their final pose instantly instead of animating in/out
            readonly property bool noAnim: Settings.notifAnim === "none"
            SequentialAnimation {
                id: iconIn
                ParallelAnimation {
                    NumberAnimation { target: bubble; property: "opacity"; to: 1; duration: window.noAnim ? 0 : 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bubble; property: "scale"; to: 1.18; duration: window.noAnim ? 0 : 300; easing.type: Easing.OutCubic }
                }
                NumberAnimation { target: bubble; property: "scale"; to: 0.95; duration: window.noAnim ? 0 : 100; easing.type: Easing.InOutQuad }
                NumberAnimation { target: bubble; property: "scale"; to: 1; duration: window.noAnim ? 0 : 100; easing.type: Easing.InOutQuad }
            }
            SequentialAnimation {
                id: iconPop
                NumberAnimation { target: bubble; property: "scale"; to: 1.32; duration: window.noAnim ? 0 : 170; easing.type: Easing.OutCubic }
                NumberAnimation { target: bubble; property: "scale"; to: 1.1; duration: window.noAnim ? 0 : 120; easing.type: Easing.InOutQuad }
                NumberAnimation { target: bubble; property: "scale"; to: 1.18; duration: window.noAnim ? 0 : 95; easing.type: Easing.InOutQuad }
                NumberAnimation { target: bubble; property: "scale"; to: 1.1; duration: window.noAnim ? 0 : 95; easing.type: Easing.InOutQuad }
            }
            NumberAnimation {
                id: iconSettle
                target: bubble
                property: "scale"
                to: 1.1
                duration: window.noAnim ? 0 : 300
                easing.type: Easing.InOutQuad
            }
            ParallelAnimation {
                id: iconOut
                NumberAnimation { target: bubble; property: "scale"; to: 0; duration: window.noAnim ? 0 : 260; easing.type: Easing.InBack }
                NumberAnimation { target: bubble; property: "opacity"; to: 0; duration: window.noAnim ? 0 : 260; easing.type: Easing.InCubic }
            }
            Timer {
                // bubble hold on dismiss: fires the icon exit once the card's
                // slide/fade (~300ms) has finished
                id: iconOutDelay
                interval: window.noAnim ? 0 : 300
                onTriggered: iconOut.restart()
            }
            ParallelAnimation {
                id: ringAnim
                NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.4; duration: window.noAnim ? 0 : 600; easing.type: Easing.OutCubic }
                NumberAnimation { target: ring; property: "opacity"; from: 0.65; to: 0; duration: window.noAnim ? 0 : 600; easing.type: Easing.OutCubic }
            }
            // shared clocks for the per-line staggers (ms timelines; each line
            // derives its own eased window from them in lp/lq below)
            NumberAnimation { id: stagInAnim; target: card; property: "stagIn"; from: 0; to: 650; duration: window.noAnim ? 0 : 650 }
            NumberAnimation { id: stagOutAnim; target: card; property: "stagOut"; from: 0; to: 300; duration: window.noAnim ? 0 : 300 }
            SequentialAnimation {
                id: wipeAnim
                PauseAnimation { duration: window.noAnim ? 0 : 100 }
                NumberAnimation { target: card; property: "imgWipe"; from: 0; to: 1; duration: window.noAnim ? 0 : 500; easing.type: Easing.OutQuint }
            }

            // ── card ──
            Rectangle {
                id: card
                property real stagIn: 0
                property real stagOut: 0
                property real imgWipe: 0
                property real cardO: 0
                property real cardYS: 0.92
                property real swipeX: 0
                property real grabX: 0
                property bool dragging: false
                property bool inst: false
                // click-to-expand for a body longer than the collapsed clip
                property bool expanded: false
                // whether a tap can reveal more (drives the chevron + ellipses)
                readonly property bool expandable: bodyClip.truncated || subtitle.truncated

                // per-line enter/exit progress: 380ms windows offset 90ms apart
                // in (quint-out), 180ms offset 40ms apart out (quad-in)
                function lp(i: int): real {
                    const p = Math.max(0, Math.min(1, (stagIn - i * 90) / 380));
                    return 1 - Math.pow(1 - p, 4);
                }
                function lq(i: int): real {
                    const q = Math.max(0, Math.min(1, (stagOut - i * 40) / 180));
                    return q * q;
                }
                function lineO(i: int): real {
                    return lp(i) * (1 - lq(i));
                }
                function lineY(i: int): real {
                    return 10 * (1 - lp(i)) - 6 * lq(i);
                }

                readonly property bool rich: window.variant === "rich"
                readonly property bool thumb: window.variant === "thumb"
                readonly property int lineBase: rich ? 1 : 0
                readonly property real stripH: rich ? Theme.fontSize(104) : 0
                // a short single-line body renders as one subtitle line; anything longer
                // becomes a divided body block (they are mutually exclusive)
                readonly property bool bodyAsSubtitle: window.view.body !== "" && window.view.body.length <= 60
                    && window.view.body.indexOf("\n") < 0

                // natural content width clamped to a compact range; rich is fixed.
                // Every term is a resting measurement (restWidth, or the hidden
                // bodyMeasure): the card is sized before its text has resolved,
                // and sizing off the noise would have it breathing wider and
                // narrower on every reroll.
                readonly property real natW: 12 + (thumb ? 50 : 0) + 34 + Math.max(
                    appRow.implicitWidth,
                    headText.restWidth,
                    subtitle.visible ? subtitleElided.restWidth : 0,
                    bodyBlock.visible ? bodyMeasure.implicitWidth : 0)
                width: rich ? Theme.fontSize(336)
                    : Math.min(Theme.fontSize(344), Math.max(Theme.fontSize(210), Math.ceil(natW)))
                height: stripH + contentBox.height + 22
                radius: Theme.radius(16)
                antialiasing: true
                color: Theme.flyoutSurface
                visible: window.phase === "show" || window.phase === "dismiss"
                opacity: cardO
                // grow-on-hover, independent of the bubble's (separate handlers)
                readonly property bool hov: cardHover.hovered && window.phase === "show"
                property real hoverS: hov ? 1.025 : 1
                Behavior on hoverS {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                transform: [
                    Scale {
                        origin.x: card.width / 2
                        origin.y: card.height / 2
                        yScale: card.cardYS
                    },
                    Scale {
                        // top-pinned: a center origin tracks the animated height
                        // during expand and creeps the card upward
                        origin.x: card.width / 2
                        origin.y: 0
                        xScale: card.hoverS
                        yScale: card.hoverS
                    }
                ]

                // bubble: the card hangs left of the circle, its top at the
                // circle's vertical centre. pill: no circle, so the card
                // tucks into the corner the circle would have occupied.
                readonly property real restX: window.bubble
                    ? bubble.x - 10 - width
                    : window.width - width - 26
                x: restX + swipeX
                y: window.bubble ? bubble.y + bubble.height / 2 : 24
                Behavior on swipeX {
                    enabled: !card.inst && !card.dragging
                    NumberAnimation {
                        duration: window.noAnim ? 0 : 300
                        easing.type: window.phase === "dismiss" ? Easing.OutCubic : Easing.OutBack
                        easing.overshoot: 1.15
                    }
                }
                Behavior on cardO {
                    enabled: !card.inst
                    NumberAnimation {
                        duration: window.noAnim ? 0 : (window.phase === "dismiss" ? 260 : 320)
                        easing.type: window.phase === "dismiss" ? Easing.InCubic : Easing.OutCubic
                    }
                }
                Behavior on cardYS {
                    enabled: !card.inst
                    NumberAnimation { duration: window.noAnim ? 0 : 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                }

                // rich media strip: left-to-right wipe reveal. The inner clipper
                // overshoots the strip height so its bottom rounding falls below
                // the image (top corners round, bottom edge square).
                Item {
                    visible: card.rich
                    x: 0
                    y: 0
                    width: Math.round(card.width * card.imgWipe)
                    height: card.stripH
                    clip: true
                    opacity: 1 - card.lq(0)

                    // plain (unmasked) placeholder tint behind the image; kept
                    // separate from the ClippingRectangle below so its fill
                    // never bleeds into the offscreen mask's corner antialiasing
                    Rectangle {
                        width: card.width
                        height: card.stripH + 16
                        radius: Theme.radius(16)
                        color: Qt.alpha(window.tintColor, 0.2)
                    }

                    ClippingRectangle {
                        width: card.width
                        height: card.stripH + 16
                        radius: Theme.radius(16)
                        color: "transparent"

                        Image {
                            width: card.width
                            height: card.stripH
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            // decode at ~2x display width, not native size
                            sourceSize.width: 700
                            source: card.rich ? window.view.image : ""
                        }
                    }
                }

                Row {
                    id: contentBox
                    x: 12
                    y: card.stripH + 11
                    width: card.width - 12 - 34
                    spacing: 10

                    ClippingRectangle {
                        visible: card.thumb
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 40
                        radius: Theme.radius(20)
                        color: Qt.alpha(window.tintColor, 0.25)
                        border.width: 2
                        border.color: Qt.alpha(window.tintColor, 0.4)
                        opacity: card.lineO(0)
                        transform: Translate { y: card.lineY(0) }

                        Image {
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(80, 80)
                            source: card.thumb ? window.view.image : ""
                        }
                    }

                    Column {
                        width: parent.width - (card.thumb ? 50 : 0)
                        spacing: 3

                        Row {
                            id: appRow
                            spacing: 5
                            opacity: card.lineO(card.lineBase)
                            transform: Translate { y: card.lineY(card.lineBase) }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: Theme.radius(2.5)
                                antialiasing: true
                                color: window.tintColor
                            }
                            ScrambleText {
                                content: window.view.app || Strings.tr("notification")
                                // Every label on the card is pinned to its
                                // resting box, and the card's own width is
                                // measured off resting metrics too (see natW):
                                // a noise glyph is not as wide as the character
                                // it stands in for, and a card that sized
                                // itself off the noise would breathe for the
                                // length of the run.
                                width: restWidth
                                height: restHeight
                                scramble: !window.noAnim
                                // every label on this card answers to the flyouts' switch,
                                // not to whatever the launcher behind it is doing - see
                                // Settings.scrambleSections
                                scrambleSection: "notifs"
                                // this card arrives on its own schedule and
                                // owns no part of the launcher's - see
                                // followsPane in ui/ScrambleText.qml
                                followsPane: false
                                textFormat: Text.PlainText
                                color: Theme.notification.muted
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(10); letterSpacing: Strings.tracking(2); capitalization: Font.AllUppercase }
                            }
                        }
                        ScrambleText {
                            id: headText
                            // content, not text: `text` is what the effect
                            // renders, and a visibility that read it would feed
                            // back into whether this label may start at all
                            visible: content.length > 0
                            width: parent.width
                            // held at the resting string's height, so a summary
                            // whose noise happens to wrap onto a second line
                            // can't push the whole card taller mid-run
                            height: restHeight
                            content: window.view.summary
                            scramble: !window.noAnim
                            scrambleSection: "notifs"
                            followsPane: false // see the app label above
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: Theme.notification.fg
                            font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13); weight: Font.DemiBold }
                            opacity: card.lineO(card.lineBase + 1)
                            transform: Translate { y: card.lineY(card.lineBase + 1) }
                        }
                        // short body: an elided single line that, when it doesn't
                        // fit, expands to the full wrapped text on tap (the elided
                        // and wrapped copies crossfade inside an animated clip)
                        Item {
                            id: subtitle
                            visible: card.bodyAsSubtitle
                            width: parent.width
                            readonly property bool truncated: card.bodyAsSubtitle && subtitleElided.truncated
                            height: visible ? (card.expanded && truncated ? subtitleWrapped.paintedHeight : subtitleElided.restHeight) : 0
                            clip: true
                            opacity: card.lineO(card.lineBase + 2)
                            transform: Translate { y: card.lineY(card.lineBase + 2) }
                            Behavior on height {
                                enabled: window.phase === "show"
                                NumberAnimation { duration: 340; easing.type: Easing.InOutCubic }
                            }

                            ScrambleText {
                                id: subtitleElided
                                width: parent.width
                                content: card.bodyAsSubtitle ? window.view.body : ""
                                scramble: !window.noAnim
                                scrambleSection: "notifs"
                                followsPane: false // see the app label above
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                color: Theme.notification.muted
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(11) }
                                opacity: card.expanded && subtitle.truncated ? 0 : 1
                                Behavior on opacity {
                                    NumberAnimation { duration: 180 }
                                }
                            }
                            Text {
                                id: subtitleWrapped
                                width: parent.width
                                // .content, not .text: this copy only ever
                                // appears on a tap, long after the run is over,
                                // so it holds the real string rather than
                                // re-resolving one the user has already read
                                text: subtitleElided.content
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                color: Theme.notification.muted
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(11) }
                                opacity: 1 - subtitleElided.opacity
                                visible: opacity > 0
                            }
                        }
                        Column {
                            id: bodyBlock
                            visible: window.view.body !== "" && !card.bodyAsSubtitle
                            width: parent.width
                            topPadding: 5
                            spacing: 6
                            opacity: card.lineO(card.lineBase + 2)
                            transform: Translate { y: card.lineY(card.lineBase + 2) }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Qt.alpha(Theme.notification.fg, 0.09)
                            }
                            // body clips to 3 lines; tapping the card animates
                            // the clip open (text is fully laid out throughout,
                            // so the reveal is a smooth height change)
                            Item {
                                id: bodyClip
                                width: parent.width
                                clip: true
                                // Measured off bodyMeasure below, never off the
                                // label on screen: a paragraph of noise doesn't
                                // wrap where the real text does, so a line
                                // count taken mid-run would have the card's
                                // three-line clamp - and its whole height -
                                // moving for the length of the effect.
                                readonly property real lineH: bodyMeasure.lineCount > 0 ? bodyMeasure.paintedHeight / bodyMeasure.lineCount : Theme.fontSize(15)
                                readonly property real collapsedH: Math.min(bodyMeasure.paintedHeight, Math.ceil(lineH * 3))
                                readonly property bool truncated: bodyMeasure.paintedHeight > collapsedH + 1
                                height: card.expanded ? bodyMeasure.paintedHeight : collapsedH
                                Behavior on height {
                                    enabled: window.phase === "show"
                                    NumberAnimation { duration: 340; easing.type: Easing.InOutCubic }
                                }

                                ScrambleText {
                                    id: bodyText
                                    width: parent.width
                                    content: bodyBlock.visible ? window.view.body : ""
                                    scramble: !window.noAnim
                                    scrambleSection: "notifs"
                                    followsPane: false // see the app label above
                                    // Only the three lines the clip shows are
                                    // ever on screen, and a resolve spread
                                    // across the whole body hands those back
                                    // finished within their own fraction of
                                    // the span - on a pasted outline, the
                                    // first tenth of it, which reads as a body
                                    // that never scrambled. Pace across the
                                    // characters those three lines actually
                                    // hold, counted off the layout by the
                                    // probe below.
                                    paceLength: Math.min(bodyProbe.text.length,
                                        bodyProbe.positionAt(bodyClip.width, Math.max(0, bodyClip.collapsedH - bodyClip.lineH / 2)))
                                    // This label used to take longer than the
                                    // rest of the shell to resolve, on the
                                    // grounds that it has nothing on the card
                                    // to finish alongside. It doesn't any
                                    // more: the duration is one figure for
                                    // every string in the shell (see
                                    // Anim.scrambleSpan), and the pacing above
                                    // is all that separates a body from a
                                    // caption.
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 24
                                    textFormat: Text.PlainText
                                    color: Theme.notification.muted
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(11) }
                                }
                                // The resting body, laid out but never drawn:
                                // everything sized off the body reads this
                                // instead of the label above, which spends the
                                // first half-second as noise. restWidth is no
                                // use here - it measures the whole string on
                                // one line, where a body's natural width is its
                                // widest wrapped line. Same hidden-measurer
                                // trick the clipboard tiles size themselves by.
                                Text {
                                    id: bodyMeasure
                                    visible: false
                                    width: bodyClip.width
                                    text: bodyText.content
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 24
                                    textFormat: Text.PlainText
                                    font: bodyText.font
                                }
                                // Where the clip's third line ends, for the
                                // pacing above. A share of the body's height
                                // can't answer that: it assumes every line is
                                // about as long as the next, and the bodies
                                // that need the pacing most are the ones where
                                // that is wildest - a pasted outline's first
                                // three lines hold fifty characters where the
                                // ratio says five hundred (and bodyMeasure,
                                // clamped to 24 lines, isn't even measuring
                                // all of it). Only TextEdit can be asked where
                                // a point in a layout falls, so the question
                                // goes to one of those; it stays out of the
                                // way of input by being invisible.
                                //
                                // Sliced, because laying out four thousand
                                // characters to find the end of the third line
                                // is work nobody reads: no three lines this
                                // wide hold anything near this many.
                                TextEdit {
                                    id: bodyProbe
                                    visible: false
                                    width: bodyClip.width
                                    text: bodyText.content.slice(0, 600)
                                    wrapMode: TextEdit.Wrap
                                    textFormat: TextEdit.PlainText
                                    font: bodyText.font
                                }
                                // ellipses over the clipped last line; gone once
                                // expanded (card-coloured backing masks the text)
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    width: bodyEll.implicitWidth + 10
                                    height: bodyEll.implicitHeight
                                    color: card.color
                                    opacity: bodyClip.truncated && !card.expanded ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: 180 }
                                    }
                                    Text {
                                        id: bodyEll
                                        anchors.right: parent.right
                                        text: "…"
                                        color: Theme.notification.muted
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(11) }
                                    }
                                }
                            }

                            // the watcher-not-running alert's only actionable
                            // content is the setup commands in its body - a
                            // real button, not tap-to-copy-and-vanish, so
                            // expanding it behaves like any other
                            // notification and copying is a deliberate,
                            // separate step (fires the usual "Copied to
                            // clipboard" toast, replacing this one, same as
                            // any other same-app follow-up notification)
                            Rectangle {
                                id: watcherCopyBtn
                                // matched through Strings, not against the
                                // English literal: that summary is one of
                                // pibble's own and arrives in whatever
                                // language the shell is set to (see
                                // Clipboard's alert), so the test has to be
                                // asked in the same language the alert was
                                // written in
                                visible: card.expanded && window.view.own && window.view.summary === Strings.tr("Clipboard watcher not running")
                                width: watcherCopyText.implicitWidth + 24
                                height: 28
                                radius: Theme.radius(8)
                                color: Qt.alpha(Theme.notification.accent, watcherCopyHover.hovered ? 0.28 : 0.16)
                                border.width: 1
                                border.color: Qt.alpha(Theme.notification.accent, 0.5)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    id: watcherCopyText
                                    anchors.centerIn: parent
                                    text: Strings.tr("Copy setup commands")
                                    color: Theme.notification.fg
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(12) }
                                }
                                HoverHandler { id: watcherCopyHover }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Notifier.copyToClipboard(Notifier.clipWatcherFixCommand)
                                }
                            }
                        }
                    }
                }

                // expand-state chevron: fades in only while the card is hovered
                // and there is more to show. Drawn on a Canvas so up and down
                // share exact ink bounds (glyphs sit at different heights in the
                // em box and visually jumped); flipping direction morphs the
                // arms through a flat line into the opposite point.
                Item {
                    id: chevron
                    z: 5
                    // pinned to the card's top-right corner (over the media
                    // strip when there is one), inset to match the app-row
                    // dot's padding on the opposite side
                    x: card.width - width - 12
                    y: 12
                    width: 14
                    height: 14
                    // 1 = pointing down (can expand), -1 = pointing up
                    property real morph: card.expanded ? -1 : 1
                    Behavior on morph {
                        enabled: window.phase === "show" && !card.inst
                        NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
                    }
                    opacity: (card.expandable || card.expanded) && cardHover.hovered && window.phase === "show" ? 0.9 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    Canvas {
                        anchors.fill: parent
                        renderStrategy: Canvas.Immediate
                        renderTarget: Canvas.Image
                        property color col: Theme.notification.muted
                        property real m: chevron.morph
                        onColChanged: requestPaint()
                        onMChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = String(col);
                            ctx.lineWidth = 1.6;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.beginPath();
                            ctx.moveTo(3.5, 7.25 - 1.75 * m);
                            ctx.lineTo(7, 7.25 + 1.75 * m);
                            ctx.lineTo(10.5, 7.25 - 1.75 * m);
                            ctx.stroke();
                        }
                    }
                }
                HoverHandler {
                    id: cardHover
                }
                // swipe-dismiss: DragHandler measures in scene coordinates,
                // so the card moving under the cursor doesn't feed the drag
                DragHandler {
                    id: swipe
                    enabled: window.phase === "show"
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    onActiveChanged: {
                        if (active) {
                            card.dragging = true;
                            card.grabX = centroid.scenePosition.x - card.swipeX;
                        } else {
                            card.dragging = false;
                            if (window.phase === "show") {
                                if (card.swipeX > 60)
                                    window.dismiss(1);
                                else if (card.swipeX < -60)
                                    window.dismiss(-1);
                                else
                                    card.swipeX = 0; // springs home
                            }
                        }
                    }
                    onCentroidChanged: {
                        if (active) {
                            const raw = centroid.scenePosition.x - card.grabX;
                            // either direction dismisses; both share the same
                            // light asymptotic drag (cap ~140px) so the card
                            // feels equally weighted left and right
                            card.swipeX = 140 * raw / (140 + Math.abs(raw));
                        }
                    }
                }
                TapHandler {
                    // a tap (not a drag) expands the clipped body - same as
                    // any other long notification, including the "watcher
                    // not running" alert (its copy button, in the expanded
                    // body, is a nested MouseArea so it grabs the press
                    // before this handler sees it as a plain expand/collapse)
                    onTapped: {
                        if (card.expandable || card.expanded)
                            card.expanded = !card.expanded;
                    }
                }
            }
        }
    }
}
