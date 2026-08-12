import QtQuick
import "." as Local

// pibble's example custom page: a month calendar, exercising the pibble
// contract (see ui/PageContext.qml) - tileIn, scramble, getSetting/setSetting,
// textInput, launcherOpen, fontScale, iconFont, and a settingsTab. Copy
// this directory out from under the .example suffix to try it.
Item {
    id: root

    readonly property int cell: 56
    readonly property int gap: 6
    readonly property int gridW: 7 * cell + 6 * gap + (showWeeks ? cell + gap : 0)

    width: gridW + 48
    height: content.implicitHeight + 48

    // The left/right chevron glyphs in pibble.iconFont - found by opening
    // that font in a codepoint viewer (FontForge, or similar) and looking
    // for the chevron shapes.
    readonly property string chevronLeft: String.fromCharCode(0xe5cb)
    readonly property string chevronRight: String.fromCharCode(0xe5cc)

    // pibble.fontScale is a multiplier, not a pixel size - this turns a
    // size into one that tracks the user's font-size setting.
    function px(size: int): int {
        return Math.round(size * pibble.fontScale);
    }

    // pibble sets this once the page has loaded - it's null until then,
    // which is why the tile-entrance animations start here, not in
    // Component.onCompleted.
    property var pibble: null
    onPibbleChanged: {
        pibble.tileIn(prevTile, 0, 1);
        pibble.tileIn(nextTile, 0, 1);
        springDays();
    }

    // Saved via pibble.setSetting/getSetting, so these survive a restart
    property bool startMonday: pibble ? pibble.getSetting("startMonday", Qt.locale().firstDayOfWeek === Locale.Monday) : true
    property bool showWeeks: pibble ? pibble.getSetting("showWeeks", true) : true

    function set(key: string, value: bool): void {
        if (key === "startMonday")
            startMonday = value;
        else
            showWeeks = value;
        pibble.setSetting(key, value);
    }

    property date now: new Date()
    Timer {
        interval: 60000
        repeat: true
        running: root.launcherOpen
        onTriggered: root.now = new Date()
    }

    property int viewYear: now.getFullYear()
    property int viewMonth: now.getMonth()
    property date selected: now
    onViewYearChanged: springDays()
    onViewMonthChanged: springDays()

    function showMonth(year: int, month: int): void {
        viewYear = year;
        viewMonth = month;
    }
    function shiftMonth(delta: int): void {
        const d = new Date(viewYear, viewMonth + delta, 1);
        showMonth(d.getFullYear(), d.getMonth());
    }
    function select(d: date): void {
        selected = d;
        showMonth(d.getFullYear(), d.getMonth());
    }
    // Copying pibble.launcherOpen onto our own property lets us write a
    // plain onLauncherOpenChanged below, with no extra setup - jump back
    // to today every time the launcher reopens.
    readonly property bool launcherOpen: pibble ? pibble.launcherOpen : false
    onLauncherOpenChanged: if (launcherOpen)
        select(now)

    // Whatever the user's typed into pibble's search box
    readonly property string query: pibble ? pibble.textInput : ""
    onQueryChanged: {
        const target = parseQuery(query);
        if (target)
            showMonth(target.year, target.month);
        else if (!query)
            showMonth(now.getFullYear(), now.getMonth());
    }
    // Understands things like "march", "mar 2027", "2027-03", "3/2027", "2027"
    function parseQuery(text: string): var {
        let year = -1;
        let month = -1;
        for (const token of text.toLowerCase().split(/[^a-z0-9]+/)) {
            if (/^\d{4}$/.test(token)) {
                year = parseInt(token, 10);
            } else if (/^\d{1,2}$/.test(token)) {
                const n = parseInt(token, 10);
                if (n >= 1 && n <= 12)
                    month = n - 1;
            } else if (token.length >= 3) {
                for (let m = 0; m < 12; m++)
                    if (Qt.locale().standaloneMonthName(m, Locale.LongFormat).toLowerCase().startsWith(token))
                        month = m;
            }
        }
        if (year < 0 && month < 0)
            return null;
        return {
            year: year < 0 ? now.getFullYear() : year,
            month: month < 0 ? now.getMonth() : month
        };
    }

    readonly property int lead: {
        const firstDow = new Date(viewYear, viewMonth, 1).getDay();
        return startMonday ? (firstDow + 6) % 7 : firstDow;
    }
    function dateAt(index: int): date {
        return new Date(viewYear, viewMonth, 1 - lead + index);
    }
    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function isoWeek(d: date): int {
        const t = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        t.setDate(t.getDate() + 3 - ((t.getDay() + 6) % 7));
        const jan4 = new Date(t.getFullYear(), 0, 4);
        return 1 + Math.round(((t.getTime() - jan4.getTime()) / 86400000 - 3 + ((jan4.getDay() + 6) % 7)) / 7);
    }
    // Same 42 day-cell items every month, just rebound to new dates - so
    // calling tileIn again on each one replays its pop-in animation
    function springDays(): void {
        if (!pibble)
            return;
        for (let i = 0; i < dayCells.count; i++)
            pibble.tileIn(dayCells.itemAt(i), i, 7);
    }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: 12

        Item {
            width: root.gridW
            height: 34

            Rectangle {
                id: prevTile
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                radius: 8
                opacity: 0
                color: prevArea.containsMouse ? root.pibble.activeTileColor : root.pibble.tileColor
                border.width: 1
                border.color: root.pibble.borderColor

                Text {
                    anchors.centerIn: parent
                    text: root.chevronLeft
                    color: root.pibble.accentColor
                    font.family: root.pibble.iconFont
                    font.pixelSize: root.px(15)
                }
                MouseArea {
                    id: prevArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.shiftMonth(-1)
                }
            }
            Text {
                anchors.centerIn: parent
                // pibble.scramble() resolves this out of random glyphs as the
                // page opens, in step with the built-in pages' own labels. It
                // has to sit in the binding like this, not be assigned once:
                // what it returns changes for the length of the run and then
                // settles on the string passed in.
                text: root.pibble.scramble(Qt.locale().standaloneMonthName(root.viewMonth, Locale.LongFormat) + " " + root.viewYear)
                color: titleArea.containsMouse ? root.pibble.accentColor : root.pibble.textColor
                font.family: root.pibble.font
                font.pixelSize: root.px(22)
                font.weight: Font.DemiBold

                MouseArea {
                    id: titleArea
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    onClicked: root.select(root.now)
                }
            }
            Rectangle {
                id: nextTile
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                radius: 8
                opacity: 0
                color: nextArea.containsMouse ? root.pibble.activeTileColor : root.pibble.tileColor
                border.width: 1
                border.color: root.pibble.borderColor

                Text {
                    anchors.centerIn: parent
                    text: root.chevronRight
                    color: root.pibble.accentColor
                    font.family: root.pibble.iconFont
                    font.pixelSize: root.px(15)
                }
                MouseArea {
                    id: nextArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.shiftMonth(1)
                }
            }
        }

        Row {
            spacing: root.gap

            Item {
                width: root.cell
                height: 1
                visible: root.showWeeks
            }
            Repeater {
                model: 7

                Text {
                    required property int index

                    width: root.cell
                    horizontalAlignment: Text.AlignHCenter
                    // scramble's slot/cols stagger it exactly as tileIn's do,
                    // so the header resolves across the week left to right
                    text: root.pibble.scramble(Qt.locale().dayName(root.startMonday ? (index + 1) % 7 : index, Locale.ShortFormat), index, 7)
                    color: root.pibble.mutedTextColor
                    font.family: root.pibble.font
                    font.pixelSize: root.px(13)
                }
            }
        }

        Row {
            spacing: root.gap

            Column {
                spacing: root.gap
                visible: root.showWeeks

                Repeater {
                    model: 6

                    Text {
                        required property int index

                        width: root.cell
                        height: root.cell
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.pibble.scramble(String(root.isoWeek(root.dateAt(index * 7 + (root.startMonday ? 3 : 4)))), index * 7, 7)
                        color: root.pibble.mutedTextColor
                        font.family: root.pibble.font
                        font.pixelSize: root.px(12)
                    }
                }
            }

            Grid {
                columns: 7
                spacing: root.gap

                Repeater {
                    id: dayCells
                    model: 42

                    Rectangle {
                        id: cell
                        required property int index

                        readonly property date cellDate: root.dateAt(index)
                        readonly property bool isToday: root.sameDay(cellDate, root.now)
                        readonly property bool isSelected: root.sameDay(cellDate, root.selected)

                        width: root.cell
                        height: root.cell
                        radius: 16
                        opacity: 0
                        color: isToday ? root.pibble.activeTileColor : (cellArea.containsMouse ? root.pibble.tileColor : "transparent")
                        border.width: isSelected ? 1 : 0
                        border.color: root.pibble.accentColor

                        Text {
                            anchors.centerIn: parent
                            // same slot/cols this cell's own tileIn() uses (see
                            // springDays), so a day's number resolves as its
                            // tile lands rather than ahead of it
                            text: root.pibble.scramble(String(cell.cellDate.getDate()), cell.index, 7)
                            color: cell.isToday ? root.pibble.accentColor : root.pibble.textColor
                            opacity: cell.cellDate.getMonth() === root.viewMonth ? 1 : 0.35
                            font.family: root.pibble.font
                            font.pixelSize: root.px(18)
                            font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.select(cell.cellDate)
                        }
                    }
                }
            }
        }

        Text {
            width: root.gridW
            horizontalAlignment: Text.AlignHCenter
            text: root.pibble.scramble(root.query ? "“" + root.query + "”" : "type a month or year to jump")
            elide: Text.ElideRight
            color: root.pibble.mutedTextColor
            font.family: root.pibble.font
            font.pixelSize: root.px(13)
        }
    }

    // gives this page its own Settings tab, next to General/Pages/etc.
    readonly property Component settingsTab: Component {
        Local.Settings {
            pibble: root.pibble
            chevronLeft: root.chevronLeft
            chevronRight: root.chevronRight
            startMonday: root.startMonday
            showWeeks: root.showWeeks
            onPicked: (key, value) => root.set(key, value)
        }
    }
}
