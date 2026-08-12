import QtQuick
import "root:/config"
import "root:/launcher"
import "root:/services"
import "root:/ui"

// One slide of the settings filmstrip. `root.slideIndex` is where this tab sits in
// SettingsPane.tabOrder and `root.activeIndex` which slide is showing; the two
// together are the whole of the horizontal tab transition.
// Pages: which panes exist and in what order, the grid sizes they use, and
// where wallpapers come from.
Column {
    id: root

    required property int slideIndex
    required property int activeIndex

    x: 20 + (root.slideIndex - root.activeIndex) * 840
    Behavior on x {
        NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
    }

    spacing: 14

    // enabled pages: click the box to toggle, drag a row up/down
    // to reorder the cycle (topmost is the home pane). Vertical
    // list rather than a horizontal chip row so it can hold an
    // arbitrary number of uploaded pages (see below) without
    // running out of width - grows with the page count up to
    // 6 rows (including the "add a page" row), then scrolls.

    PageList {}

    // clock-page layout: three stationary tickboxes (date,
    // battery, weather). The grouping itself is fixed, not
    // user-arranged: the clock always sits on its own line up
    // top, date (if ticked) directly under it, and battery +
    // weather (if either is ticked) always share one line at
    // the bottom.
    Item {
        width: 780
        height: 34

        SettingLabel {
            anchors.left: parent.left
            text: "Clock"
        }
        ResetButton {
            key: "clock"
            anchors.right: parent.right
        }
        ChipRow {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            items: [
                { id: "date", label: "date" },
                { id: "battery", label: "battery" },
                { id: "weather", label: "weather" }
            ]
            isOn: id => (Settings.clockShow ?? {})[id] !== false
            toggle: LauncherState.toggleClockItem
        }
    }

    // tile grid decorations: the live search query above the tiles (apps/
    // walls-grid/clips), and a page-of-tiles dot indicator below them
    Item {
        width: 780
        height: 34

        SettingLabel {
            anchors.left: parent.left
            text: "Tile page indicators"
        }
        ResetButton {
            key: "pageIndicators"
            anchors.right: parent.right
        }
        ChipRow {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            items: [
                { id: "query", label: "search query" },
                { id: "dots", label: "page dots" }
            ]
            isOn: Settings.pageIndicatorEnabled
            toggle: SettingsSchema.toggleIndicator
        }
    }

    // grid size: one visible tile grid, switchable between the
    // three pages that have a configurable grid size
    Item {
        width: 780
        height: 34

        SettingLabel {
            anchors.left: parent.left
            text: "Grid size"
        }
        ResetButton {
            key: SettingsSchema.gridTargets[LauncherState.gridTarget].resetKey
            anchors.right: parent.right
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 34
            spacing: 24
            height: parent.height

            Repeater {
                model: ["apps", "walls", "clips"]

                Item {
                    id: gridTargetChip
                    required property string modelData
                    readonly property bool active: LauncherState.gridTarget === modelData
                    width: gridTargetText.implicitWidth
                    height: parent.height

                    Text {
                        id: gridTargetText
                        anchors.verticalCenter: parent.verticalCenter
                        text: SettingsSchema.gridTargets[gridTargetChip.modelData].label
                        color: gridTargetChip.active ? Theme.fg : Theme.muted
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                    }
                    Rectangle {
                        anchors.top: gridTargetText.bottom
                        anchors.topMargin: 4
                        width: parent.width
                        height: 2
                        radius: 1
                        color: Theme.accent
                        opacity: gridTargetChip.active ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Anim.menu(150); easing.type: Easing.OutCubic }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: LauncherState.gridTarget = gridTargetChip.modelData
                    }
                }
            }
        }
    }

    GridSizePicker {
        target: LauncherState.gridTarget
    }

    SettingRow { key: "animStyle"; label: "Grid animation" }

    SettingRow { key: "iconTheme"; label: "App icon theme"; hint: "applied after daemon reload" }

    SettingRow { key: "wallpaperStyle"; label: "Wallpapers style" }

    // wallpaper path
    Item {
        width: 780
        height: 38

        SettingLabel {
            anchors.left: parent.left
            text: "Wallpapers path"
        }
        ResetButton {
            key: "wallpaperDir"
            anchors.right: parent.right
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            width: 444
            height: 34
            radius: 8
            color: Qt.alpha(Theme.accent, pathInput.activeFocus ? 0.16 : 0.08)
            border.width: 1
            border.color: pathInput.activeFocus ? Theme.accent : Qt.alpha(Theme.accent, 0.33)

            Text {
                anchors.fill: parent
                anchors.margins: 8
                verticalAlignment: Text.AlignVCenter
                visible: pathInput.text.length === 0
                text: "type the path to your wallpapers"
                color: Theme.muted
                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
            }
            TextInput {
                id: pathInput
                anchors.fill: parent
                anchors.margins: 8
                verticalAlignment: TextInput.AlignVCenter
                text: Settings.wallpaperDir
                color: Theme.fg
                clip: true
                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                onEditingFinished: {
                    if (text !== Settings.wallpaperDir) {
                        Settings.wallpaperDir = text;
                        Settings.save();
                        Wallpapers.rescan();
                    }
                    LauncherState.focusInput();
                }
                Keys.onEscapePressed: LauncherState.focusInput()
                Connections {
                    target: Settings
                    function onWallpaperDirChanged() {
                        pathInput.text = Settings.wallpaperDir;
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.IBeamCursor
            }
        }
    }

    // wallpaper command ($WALL = image, $BLUR = blurred variant)
    Item {
        width: 780
        height: 38 + 2 + commandHint.implicitHeight

        Item {
        id: commandRow
        width: parent.width
        height: 38

        SettingLabel {
            anchors.left: parent.left
            text: "Wallpapers command"
        }
        ResetButton {
            key: "wallCommand"
            anchors.right: parent.right
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            width: 444
            height: 34
            radius: 8
            color: Qt.alpha(Theme.accent, cmdInput.activeFocus ? 0.16 : 0.08)
            border.width: 1
            border.color: cmdInput.activeFocus ? Theme.accent : Qt.alpha(Theme.accent, 0.33)

            Text {
                anchors.fill: parent
                anchors.margins: 8
                verticalAlignment: Text.AlignVCenter
                visible: cmdInput.text.length === 0
                text: "type the command to be executed when a wallpaper is selected"
                color: Theme.muted
                elide: Text.ElideRight
                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
            }
            TextInput {
                id: cmdInput
                anchors.fill: parent
                anchors.margins: 8
                verticalAlignment: TextInput.AlignVCenter
                text: Settings.wallCommand
                color: Theme.fg
                clip: true
                font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
                onEditingFinished: {
                    if (text !== Settings.wallCommand) {
                        Settings.wallCommand = text;
                        Settings.save();
                    }
                    LauncherState.focusInput();
                }
                Keys.onEscapePressed: LauncherState.focusInput()
                Connections {
                    target: Settings
                    function onWallCommandChanged() {
                        cmdInput.text = Settings.wallCommand;
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.IBeamCursor
            }
        }
        }

        SettingHint {
            id: commandHint
            anchors.top: commandRow.bottom
            anchors.topMargin: 2
            text: "$WALL = selected image, $BLUR = blurred variant (auto-generated)"
        }
    }

    SettingRow { key: "clipsMax"; label: "Clipboard entries" }

    SettingRow { key: "hiddenMenuAnimations"; label: "Hidden menu animations"; hint: "settings pane and power-off/reboot prompts" }

}

