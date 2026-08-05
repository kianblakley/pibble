import QtQuick
import Quickshell.Services.Notifications
import "root:/config"
import "root:/services"
import "root:/ui"

// One slide of the settings filmstrip. `root.slideIndex` is where this tab sits in
// SettingsPane.tabOrder and `root.activeIndex` which slide is showing; the two
// together are the whole of the horizontal tab transition.
// Flyouts: the volume and notification OSDs, plus which alerts pibble is
// allowed to raise on its own behalf.
Column {
    id: root

    required property int slideIndex
    required property int activeIndex

    x: 20 + (root.slideIndex - root.activeIndex) * 840
    Behavior on x {
        NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
    }

    spacing: 14

    // enabled flyouts (unloading notifications releases the
    // org.freedesktop.Notifications DBus name for other daemons)
    Item {
        width: 780
        height: 34

        SettingLabel {
            anchors.left: parent.left
            text: "Flyouts"
        }
        ResetButton {
            key: "flyouts"
            anchors.right: parent.right
        }
        ChipRow {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            items: [
                { id: "volume", label: "volume" },
                { id: "notifs", label: "notifications" }
            ]
            isOn: Settings.flyoutEnabled
            toggle: SettingsSchema.toggleFlyout
        }
    }

    SettingRow { key: "volStyle"; label: "Volume style"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "volWidth"; label: "Volume size"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "volAnim"; label: "Volume animation"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "volPercent"; label: "Volume percent"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "volTimeout"; label: "Volume timeout"; valueWidth: Metrics.shortValueWidth }

    // pibble's own notify-send calls (missing tools, failed
    // commands, copy confirmations, low battery), independent
    // of the "notifications" flyout above which only gates
    // other apps' notifications
    Item {
        width: 780
        height: 34

        SettingLabel {
            anchors.left: parent.left
            text: "Pibble alerts"
        }
        ResetButton {
            key: "pibbleAlerts"
            anchors.right: parent.right
        }
        ChipRow {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            items: [
                { id: "errors", label: "errors" },
                { id: "missingDeps", label: "dependencies" },
                { id: "actions", label: "actions" },
                { id: "battery", label: "battery" }
            ]
            isOn: Settings.alertEnabled
            toggle: SettingsSchema.toggleAlert
        }
    }
    SettingRow { key: "notifStyle"; label: "Notification style"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "notifAnim"; label: "Notification animation"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "notifTimeout"; label: "Notification timeout"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "replayCount"; label: "Replay count"; hint: "how many recent notifications `pibble replay` can step back through"; valueWidth: Metrics.shortValueWidth }
}
