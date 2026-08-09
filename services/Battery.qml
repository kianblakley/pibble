pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "root:/config"

// The clock page's battery readout, and the low-battery alert.
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: {
        const d = root.device;
        return !!d && d.ready && d.isLaptopBattery;
    }
    // PendingCharge covers charge-limited/topping-off devices (e.g. a
    // threshold-charging laptop sitting at its cap while plugged in) -
    // still "plugged in and not draining" for every purpose this drives
    // (accent color, the charging glyph, suppressing low-battery alerts),
    // even though UPower won't call it "Charging"
    readonly property bool charging: root.present
        && (root.device.state === UPowerDeviceState.Charging || root.device.state === UPowerDeviceState.PendingCharge)
    // always icon + percentage, charging or not
    readonly property string text: root.present ? Math.round(root.device.percentage * 100) + "%" : ""

    // fires once per discharge dip below 5%, not once per tick; re-arms once
    // the level recovers with some headroom (plugging in, or just climbing
    // back past the boundary) so it can't flap right at the threshold
    property bool alerted: false
    function checkLevel(): void {
        if (!root.present || root.charging) {
            root.alerted = false;
            return;
        }
        const pct = root.device.percentage * 100;
        if (pct <= 5) {
            if (!root.alerted) {
                root.alerted = true;
                if (Settings.alertEnabled("battery"))
                    Quickshell.execDetached(["notify-send", "-a", "pibble", "-u", "critical",
                        "-i", "battery-low", "Low battery", Math.round(pct) + "% remaining - plug in soon."]);
            }
        } else if (pct > 8) {
            root.alerted = false;
        }
    }
    Connections {
        target: root.device
        function onPercentageChanged() { root.checkLevel(); }
        function onStateChanged() { root.checkLevel(); }
    }
}
