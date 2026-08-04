import QtQuick
import "root:/services"
import "root:/ui"

// One slide of the settings filmstrip. `root.slideIndex` is where this tab sits in
// SettingsPane.tabOrder and `root.activeIndex` which slide is showing; the two
// together are the whole of the horizontal tab transition.
// General: the settings the launcher and both flyouts share — animations,
// blur, type, theme — closing with the build identity.
Column {
    id: root

    required property int slideIndex
    required property int activeIndex

    x: 20 + (root.slideIndex - root.activeIndex) * 840
    Behavior on x {
        NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
    }

    spacing: 14

    SettingRow { key: "launchAnimation"; label: "Launch animation" }
    SettingRow { key: "hiddenMenuAnimations"; label: "Hidden menu animations"; hint: "settings pane and power-off/reboot prompts" }
    SettingRow {
        key: "bgBlur"
        label: "Background blur"
        hint: "ext-background-effect requires compositor support"
    }
    SettingRow { key: "dimOpacity"; label: "Background opacity" }
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
            text: "Copy debug info"
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            width: debugBtnRow.implicitWidth + 28
            height: 34
            radius: 10
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
                Text {
                    text: "Copy"
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
        height: 10 + 1 + 10 + versionText.implicitHeight

        Rectangle {
            y: 10
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.muted, 0.25)
        }
        Text {
            id: versionText
            anchors.top: parent.top
            anchors.topMargin: 10 + 1 + 10
            anchors.horizontalCenter: parent.horizontalCenter
            visible: SystemInfo.commit !== ""
            text: SystemInfo.commit
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
                    versionText.text = "I vibe coded this using a microphone.";
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
                    versionText.text = SystemInfo.commit;
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
