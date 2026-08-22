import QtQuick
import "." as Local

// pibble's example custom page: one persistent scratch note, in the
// smallest page that can exercise the whole contract (see
// ui/PageContext.qml). Covers scramble() on a standalone label,
// launcherOpen and pageActive (the note saves itself when you close the
// launcher or tab away), releaseFocus() after the editor takes keyboard
// focus, getSetting/setSetting, the color/font members, and a settingsTab
// (Settings.qml). Hint.qml and Settings.qml alongside show the split-file
// import. Copy this directory out from under the .example suffix to try it.
Item {
    id: root

    property var pibble

    // The box's width as a percentage of its default, set from this page's
    // own Settings tab below. Saved via pibble.setSetting/getSetting, so it
    // survives a restart.
    property int size: pibble.getSetting("size", 100)

    width: Math.round(420 * size / 100)
    height: column.implicitHeight + 48

    // The note is saved when it stops being looked at, not per keystroke:
    // launcherOpen going false catches the launcher closing, pageActive
    // going false catches tabbing to another page. Mirroring the two onto
    // our own properties is what makes the plain onXChanged handlers work.
    readonly property bool launcherOpen: pibble.launcherOpen
    onLauncherOpenChanged: if (!launcherOpen)
        save()
    readonly property bool pageActive: pibble.pageActive
    onPageActiveChanged: if (!pageActive)
        save()

    function save(): void {
        if (editor.text !== pibble.getSetting("note", ""))
            pibble.setSetting("note", editor.text);
    }

    Column {
        id: column
        anchors.centerIn: parent
        width: parent.width - 48
        spacing: 12

        Text {
            // a label with no tile under it scrambles through pibble
            // directly - and it has to sit in a binding like this, never
            // be assigned once
            text: root.pibble.scramble("Scratch note")
            color: root.pibble.accentColor
            font.family: root.pibble.font
            font.pixelSize: root.pibble.px(18)
            font.weight: Font.DemiBold
        }

        Rectangle {
            width: parent.width
            height: Math.max(editor.implicitHeight + 24, Math.round(120 * root.size / 100))
            radius: root.pibble.radius(12)
            color: root.pibble.tileColor
            border.width: 1
            border.color: editor.activeFocus ? root.pibble.accentColor : root.pibble.borderColor

            TextEdit {
                id: editor
                anchors.fill: parent
                anchors.margins: 12
                text: root.pibble.getSetting("note", "")
                wrapMode: TextEdit.Wrap
                color: root.pibble.textColor
                font.family: root.pibble.font
                font.pixelSize: root.pibble.px(14)
                // Clicking in takes keyboard focus, which turns pibble's own
                // keybinds off (they live on its hidden search box) - so
                // Escape hands focus back. Without this the user is stuck
                // in the editor.
                Keys.onEscapePressed: {
                    root.save();
                    root.pibble.releaseFocus();
                }
            }
        }

        Local.Hint {
            pibble: root.pibble
            text: editor.activeFocus ? "Esc when done" : "click to write - saves when you leave"
        }
    }

    // this page's own tab in Settings, next to General/Pages/etc: the
    // Component lives here, its content in Settings.qml, reached through
    // the Local import above
    readonly property Component settingsTab: Component {
        Local.Settings {
            pibble: root.pibble
            size: root.size
            onPicked: value => {
                root.size = value;
                root.pibble.setSetting("size", value);
            }
        }
    }
}
