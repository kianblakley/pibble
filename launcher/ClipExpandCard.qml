import QtQuick
import Quickshell.Widgets
import "root:/services"

// The expanded clip: grows out of the selected tile while the rest of the
// grid animates away (no dimming overlay). Text scrolls past its viewport
// rather than truncating; images render at native size, capped to fit.
Item {
    id: root

    // The pane this grew out of: the collapse animation flies back toward the
    // tile's recorded position, which is in that item's coordinate space.
    required property Item pane

    // Consumed unconditionally by the launcher's background wheel handler (even
    // when the text doesn't overflow) so a scroll never falls through and
    // shifts the hidden grid behind this card.
    function scrollBy(delta: real): void {
        if (!textViewport.overflow)
            return;
        const maxContentY = Math.max(0, textFlick.contentHeight - textFlick.height);
        textFlick.contentY = Math.max(0, Math.min(maxContentY, textFlick.contentY - delta));
    }

    visible: LauncherState.expandedClip !== null
    readonly property bool isImg: LauncherState.expandedClip !== null && LauncherState.expandedClip.image === true
    // images render at native size, capped to fit the screen
    // (58% of width, 53% of height to leave room for the
    // text/metadata below the image and the card's margins)
    readonly property size imgFit: {
        if (!isImg)
            return Qt.size(0, 0);
        const d = (LauncherState.expandedClip.dims || "").split("x");
        const iw = parseInt(d[0]) || 16;
        const ih = parseInt(d[1]) || 9;
        const maxW = LauncherState.screenWidth * 0.58;
        const maxH = LauncherState.screenHeight * 0.53;
        const s = Math.min(1, maxW / iw, maxH / ih);
        return Qt.size(Math.max(320, Math.round(iw * s)), Math.max(180, Math.round(ih * s)));
    }
    anchors.centerIn: parent
    width: isImg ? imgFit.width + 48 : 560
    height: column.height + 44
    // large images cover much more of the screen than text
    // cards, so the same growth duration reads as an abrupt
    // pop; ease it in more slowly
    readonly property int expandDur: isImg ? 560 : 380
    // the decoded full text arrives async and is longer than
    // the preview; grow smoothly instead of jumping
    Behavior on height {
        NumberAnimation { duration: Anim.tile(380); easing.type: Easing.OutCubic }
    }
    transform: Translate { id: flyTransform }

    // swallow clicks so they don't fall through to the
    // background (which collapses the expansion). Wheel
    // scrolling isn't handled here - it's handled centrally
    // by bgArea below, since a plain MouseArea without
    // onWheel doesn't intercept wheel events on this layer-
    // shell surface (see bgArea's note), so they already
    // pass straight through this to reach it regardless of
    // whether the pointer is over the card or the
    // surrounding faded grid
    MouseArea {
        anchors.fill: parent
    }

    ParallelAnimation {
        id: growAnim
        NumberAnimation { target: flyTransform; property: "x"; to: 0; duration: Anim.tile(root.expandDur); easing.type: Easing.OutCubic }
        NumberAnimation { target: flyTransform; property: "y"; to: 0; duration: Anim.tile(root.expandDur); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "opacity"; from: 0.3; to: 1; duration: Anim.tile(Math.round(root.expandDur * 0.58)); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; from: 0.35; to: 1; duration: Anim.tile(root.expandDur); easing.type: Easing.OutBack; easing.overshoot: 1.1 }
    }
    SequentialAnimation {
        id: collapseAnim
        ParallelAnimation {
            NumberAnimation {
                target: flyTransform
                property: "x"
                to: LauncherState.expandOrigin.x - root.pane.width / 2
                duration: Anim.tile(260)
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: flyTransform
                property: "y"
                to: LauncherState.expandOrigin.y - root.pane.height / 2
                duration: Anim.tile(260)
                easing.type: Easing.InCubic
            }
            NumberAnimation { target: root; property: "scale"; to: 0.35; duration: Anim.tile(260); easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: Anim.tile(260); easing.type: Easing.InCubic }
        }
        ScriptAction { script: LauncherState.expandedClip = null }
    }
    Connections {
        target: LauncherState
        function onExpandAnimStart() {
            collapseAnim.stop();
            flyTransform.x = LauncherState.expandOrigin.x - root.pane.width / 2;
            flyTransform.y = LauncherState.expandOrigin.y - root.pane.height / 2;
            growAnim.restart();
        }
        function onExpandAnimCollapse() {
            growAnim.stop();
            collapseAnim.restart();
        }
    }

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 22
        width: parent.width - 48
        spacing: 14

        ClippingRectangle {
            visible: root.isImg
            width: parent.width
            height: root.imgFit.height
            radius: Theme.radius(12)
            color: "transparent"

            Image {
                anchors.fill: parent
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(LauncherState.screenWidth, LauncherState.screenHeight)
                // prefer the on-demand full-res decode; the
                // small thumb is an instant placeholder while
                // it lands, and the fallback if decode fails
                source: {
                    const c = LauncherState.expandedClip;
                    if (!c || !c.image)
                        return "";
                    if (LauncherState.expandedFullPath && LauncherState.expandedFullId === c.id)
                        return "file://" + LauncherState.expandedFullPath;
                    return c.thumb ? "file://" + c.thumb : "";
                }
            }
        }
        // the full text reveals gradually as the container
        // grows, instead of jumping when the decode lands -
        // but only up to textMaxH: past that, the container
        // stops growing and the text scrolls instead, since
        // clipInfo's decode cap is now generous (200000
        // bytes) rather than a hard 4000-byte truncation
        Item {
            id: textViewport
            visible: LauncherState.expandedClip !== null && LauncherState.expandedClip.image !== true
            readonly property real textMaxH: LauncherState.screenHeight * 0.42
            readonly property bool overflow: bodyText.paintedHeight > textMaxH
            width: parent.width
            height: Math.min(bodyText.paintedHeight, textMaxH)
            clip: true
            Behavior on height {
                NumberAnimation { duration: Anim.tile(380); easing.type: Easing.OutCubic }
            }

            Flickable {
                id: textFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: bodyText.paintedHeight
                clip: true
                interactive: textViewport.overflow
                boundsBehavior: Flickable.StopAtBounds

                Text {
                    id: bodyText
                    width: parent.width
                    text: LauncherState.expandedText || (LauncherState.expandedClip ? LauncherState.expandedClip.preview : "")
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.fg
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.accent, 0.25)
        }

        Repeater {
            model: LauncherState.expandedInfo

            Item {
                required property var modelData
                width: column.width
                height: Theme.fontSize(20)

                Text {
                    anchors.left: parent.left
                    text: parent.modelData[0]
                    color: Theme.muted
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                }
                Text {
                    anchors.right: parent.right
                    text: parent.modelData[1]
                    color: Theme.fg
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                }
            }
        }
    }

    // expanded text's scrollbar: sits outside the card's own
    // right edge entirely (a sibling of column, not a
    // child squeezed into its width) so the text column
    // never loses width to make room for it - only its
    // height tracks the scrollable text viewport
    // (textViewport), styled to match the Pages list
    // scrollbar in settings (pagesScrollTrack/Thumb)
    Item {
        id: scrollBar
        // column (the text column) is centered with a
        // 24px gutter to the card's own edge on each side -
        // anchoring to parent.right (the card edge) left
        // that whole gutter as dead space before the
        // scrollbar even started. Anchor to the text
        // column's actual edge instead so it sits right
        // next to the text, still outside column itself.
        anchors.left: column.right
        anchors.leftMargin: 5
        y: column.y + textViewport.y
        height: textViewport.height
        width: 10
        visible: textViewport.overflow

        Rectangle {
            id: scrollTrack
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: parent.height
            radius: Theme.radius(3)
            color: Qt.alpha(Theme.muted, 0.15)

            Rectangle {
                id: scrollThumb
                width: parent.width
                radius: Theme.radius(3)
                color: Qt.alpha(Theme.accent, scrollDrag.pressed ? 0.85 : 0.6)
                height: Math.min(scrollTrack.height, Math.max(12, textFlick.visibleArea.heightRatio * scrollTrack.height))
                y: {
                    const range = 1 - textFlick.visibleArea.heightRatio;
                    const progress = range > 0 ? textFlick.visibleArea.yPosition / range : 0;
                    return progress * (scrollTrack.height - height);
                }
            }
        }

        MouseArea {
            id: scrollDrag
            anchors.fill: parent
            enabled: textViewport.overflow
            preventStealing: true
            property real pressY: 0
            property real pressThumbY: 0
            onPressed: mouse => {
                pressY = mouse.y;
                pressThumbY = scrollThumb.y;
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const usable = Math.max(1, scrollTrack.height - scrollThumb.height);
                const newY = Math.max(0, Math.min(usable, pressThumbY + (mouse.y - pressY)));
                const maxContentY = Math.max(0, textFlick.contentHeight - textFlick.height);
                textFlick.contentY = (newY / usable) * maxContentY;
            }
        }
    }
}
