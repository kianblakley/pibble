import QtQuick
import "root:/services"
import "root:/ui"

// One slide of the settings filmstrip. `root.slideIndex` is where this tab sits in
// SettingsPane.tabOrder and `root.activeIndex` which slide is showing; the two
// together are the whole of the horizontal tab transition.
// General: the settings the launcher and both flyouts share - blur, type,
// theme - closing with the build identity.
Column {
    id: root

    required property int slideIndex
    required property int activeIndex
    // Every tab is laid out at once and the inactive ones are slid out behind
    // the filmstrip's clip, at full opacity - so nothing else tells a label in
    // here that it can't be seen. Every ScrambleText below this item reads it
    // (see ui/ScrambleText.qml) and sits the run out until this tab is the one
    // showing, which is what makes a tab switch its labels' arrival.
    readonly property bool scrambleSuppressed: root.slideIndex !== root.activeIndex

    x: 20 + (root.slideIndex - root.activeIndex) * 840
    Behavior on x {
        NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
    }

    spacing: 14

    SettingRow { key: "preload"; label: "Preload content"; hint: "stores large content in memory between toggles to improve performance" }
    SettingRow {
        key: "bgBlur"
        label: "Background blur"
        hint: "ext-background-effect requires compositor support"
    }
    SettingRow { key: "dimOpacity"; label: "Background opacity" }
    SettingRow {
        key: "roundedCorners"
        label: "Rounded corners"
        hint: "off squares every corner in the launcher and both flyouts"
    }
    SettingRow { key: "fontFamily"; label: "Font" }
    SettingRow { key: "fontScale"; label: "Font size" }
    ThemeRow {}
    ColorPickerRow {}

    // bundles version/build info, this run's recent log, and
    // the latest crash report (if any) for pasting into a
    // bug report; right-aligned with the same margin as
    // ResetButton elsewhere, even though this row has no reset
    Item {
        width: 780
        height: 40

        SettingLabel {
            anchors.left: parent.left
            content: "Copy debug info"
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            width: debugBtnRow.implicitWidth + 28
            height: 34
            radius: Theme.radius(10)
            color: Qt.alpha(Theme.accent, debugBtnArea.containsMouse ? 0.25 : 0.11)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.33)

            Row {
                id: debugBtnRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: Icons.copy
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                    font { family: Icons.family; pixelSize: Theme.fontSize(16) }
                }
                ScrambleText {
                    content: "Copy"
                    // the Row's implicitWidth sizes the button around it, so
                    // the button would breathe with the noise otherwise
                    width: restWidth
                    height: restHeight
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(15); weight: Font.Bold }
                }
            }
            MouseArea {
                id: debugBtnArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: SystemInfo.copyDebugInfo()
            }
        }
    }

    // closes out the tab with a divider and the repo's
    // commit, centered underneath; extra breathing room above
    // and below the divider itself, beyond the Column's
    // normal row spacing
    Item {
        width: 780
        height: 10 + 1 + 10 + versionText.height

        Rectangle {
            y: 10
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.muted, 0.25)
        }
        ScrambleText {
            id: versionText
            anchors.top: parent.top
            anchors.topMargin: 10 + 1 + 10
            anchors.horizontalCenter: parent.horizontalCenter
            visible: SystemInfo.commit !== ""
            // The reveal below fades this out and back in, which is an exit
            // and an arrival as far as the effect is concerned - so each half
            // of the easter egg resolves on its way in without asking for a
            // replay. `content` is what the timers swap, never `text`: `text`
            // is what the effect writes, and assigning it would tear that out.
            content: SystemInfo.commit
            height: restHeight
            color: Theme.muted
            font { family: Theme.fontFamily; pixelSize: Theme.fontSize(11) }

            property int clicks: 0
            property bool revealed: false

            Behavior on opacity {
                NumberAnimation { duration: 420; easing.type: Easing.InOutQuad }
            }
            Timer {
                id: clickWindow
                interval: 500
                onTriggered: versionText.clicks = 0
            }
            Timer {
                id: versionReveal
                interval: 420
                onTriggered: {
                    versionText.content = "I vibe coded this using a microphone.";
                    versionText.opacity = 1;
                    revealTimeout.start();
                }
            }
            Timer {
                id: revealTimeout
                interval: 3000
                onTriggered: {
                    versionText.opacity = 0;
                    versionHide.start();
                }
            }
            Timer {
                id: versionHide
                interval: 420
                onTriggered: {
                    versionText.content = SystemInfo.commit;
                    versionText.opacity = 1;
                    versionText.revealed = false;
                    versionText.clicks = 0;
                }
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                onClicked: {
                    if (versionText.revealed)
                        return;
                    versionText.clicks++;
                    clickWindow.restart();
                    if (versionText.clicks >= 3) {
                        versionText.revealed = true;
                        versionText.opacity = 0;
                        versionReveal.start();
                    }
                }
            }
        }
    }
}
