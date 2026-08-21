pragma Singleton
import QtQuick
import Quickshell
import "root:/config"
import "root:/services"

// Widths the settings rows share so their controls line up down the column,
// measured from the widest thing each could ever hold rather than from
// whatever happens to be in them right now - a row must not resize when a
// keybind changes length or a capture starts.
//
// "Could ever hold" is a question about the current language too: every string
// measured here goes through Strings, so switching language re-measures rather
// than leaving a box sized for the words it used to hold.
Singleton {
    id: root

    // The longest prompt a chord box ever shows while capturing.
    Text {
        id: captureMetrics
        visible: false
        text: Strings.tr("press a key…")
        font {
            family: Theme.fontFamily
            pixelSize: Theme.fontSize(13)
        }
    }
    // The longest two-key chord keyName() can produce: one modifier plus the
    // longest recognised key name. Not translated - these are the keys' own
    // names, which is what is printed on the keyboard.
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
    // Every value a ‹›-stepper on one of the narrow rows can show, in the
    // current language (see SettingsSchema.shortValueChoices). A translated
    // "off" is routinely longer than the English one, and a value laid out
    // into too little width overhangs its own arrows rather than wrapping - so
    // the narrow rows are sized from the longest of these instead of from a
    // figure that only ever fitted English.
    Row {
        id: shortValueMetrics
        visible: false
        Repeater {
            model: SettingsSchema.shortValueChoices
            Text {
                required property string modelData
                text: modelData
                font {
                    family: Theme.fontFamily
                    pixelSize: Theme.fontSize(14)
                }
            }
        }
    }
    // Widest of those. Every child is read (the Repeater among them, which is
    // zero-width), which is also what keeps this subscribed as each label's
    // metrics settle.
    readonly property real widestShortValue: {
        let w = 0;
        for (let i = 0; i < shortValueMetrics.children.length; i++)
            w = Math.max(w, shortValueMetrics.children[i].implicitWidth);
        return w;
    }

    // A chord box, and - via shortValueWidth below - the narrow stepper rows
    // that line up with it. Both are one figure so the two kinds of control
    // stay the same width as each other; whichever of the three demands more
    // room in the current language is what both grow to.
    readonly property real keybindBoxWidth: Math.max(110, captureMetrics.implicitWidth + 32, chordMetrics.implicitWidth + 32, root.widestShortValue + 24 + 72)

    // A ‹›-stepper's *total* span (‹ + spacing + value + spacing + ›) matching a
    // chord box's width, not the value text alone - so subtract the two arrows
    // and their spacing back out. Used on the Navigation/Flyouts tabs, where
    // stepper rows sit directly alongside (or logically belong with) the chord
    // boxes.
    readonly property real shortValueWidth: root.keybindBoxWidth - 72
}
