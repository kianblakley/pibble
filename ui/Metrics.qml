pragma Singleton
import QtQuick
import Quickshell
import "root:/services"

// Widths the settings rows share so their controls line up down the column,
// measured from the widest thing each could ever hold rather than from
// whatever happens to be in them right now — a row must not resize when a
// keybind changes length or a capture starts.
Singleton {
    id: root

    // The longest prompt a chord box ever shows while capturing.
    Text {
        id: captureMetrics
        visible: false
        text: "press a key…"
        font {
            family: Theme.fontFamily
            pixelSize: Theme.fontSize(13)
        }
    }
    // The longest two-key chord keyName() can produce: one modifier plus the
    // longest recognised key name.
    Row {
        id: chordMetrics
        visible: false
        spacing: 4
        KeyCap {
            label: "Shift"
        }
        KeyPlus {}
        KeyCap {
            label: "ScrollLock"
        }
    }

    readonly property real keybindBoxWidth: Math.max(110, Math.max(captureMetrics.implicitWidth, chordMetrics.implicitWidth) + 32)

    // A ‹›-stepper's *total* span (‹ + spacing + value + spacing + ›) matching a
    // chord box's width, not the value text alone — so subtract the two arrows
    // and their spacing back out. Used on the Navigation/Flyouts tabs, where
    // stepper rows sit directly alongside (or logically belong with) the chord
    // boxes.
    readonly property real shortValueWidth: root.keybindBoxWidth - 72
}
