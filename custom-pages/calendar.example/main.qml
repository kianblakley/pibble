import QtQuick
// Sibling files need this qualified form: quickshell's own qmldir handling
// shadows the implicit same-directory import a plain Qt/QML app gets, so an
// unqualified `Settings {}` fails to resolve even though the file is right here.
import "." as Local
// Icons (the shell's Material Symbols font) and the settings controls the
// built-in tabs are built from - both fair game for a page, see the header
// of ui/PageContext.qml
import "root:/services"
import "root:/ui"

// pibble's example custom page: a month calendar, exercising the whole
// contract in ui/PageContext.qml - tileIn, getSetting/setSetting, searchText,
// shown, fontSize, and a settingsTab. Copy this directory out from under the
// .example suffix to try it (see services/CustomPages.qml).
Item {
    id: root

    readonly property int cell: 56
    readonly property int gap: 6
    readonly property int gridW: 7 * cell + 6 * gap + (showWeeks ? cell + gap : 0)

    width: gridW + 48
    height: content.implicitHeight + 48

    // assigned by pibble once the page has loaded - which is why the tile
    // entrance registers here and not in Component.onCompleted
    property var pibble: null
    onPibbleChanged: {
        pibble.tileIn(prevTile, 0, 1);
        pibble.tileIn(nextTile, 0, 1);
        springDays();
    }

    // true while this page is the one on screen; written by pibble
    property bool active: false

    // per-page persistent settings, namespaced by pibble. The week start
    // defaults off the locale, so the page looks right before it's configured.
    property bool startMonday: pibble ? pibble.getSetting("startMonday", Qt.locale().firstDayOfWeek === Locale.Monday) : true
    property bool showWeeks: pibble ? pibble.getSetting("showWeeks", true) : true

    function set(key: string, value: bool): void {
        if (key === "startMonday")
            startMonday = value;
        else
            showWeeks = value;
        pibble.setSetting(key, value);
    }

    // re-read while the launcher is up, so one left open across midnight
    // doesn't keep yesterday lit
    property date now: new Date()
    Timer {
        interval: 60000
        repeat: true
        running: root.shown
        onTriggered: root.now = new Date()
    }

    // The month on screen, and the day the selection ring sits on - today's
    // own marker never moves, so these stay independent: paging around or
    // searching only changes the view, and a ring left in another month is
    // simply off screen until you page back to it.
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
    // clicking a day rings it, following a spill-over day into its own month
    function select(d: date): void {
        selected = d;
        showMonth(d.getFullYear(), d.getMonth());
    }
    // whatever month it was left on, the next open starts on this one again -
    // the resting state every built-in pane comes back in
    readonly property bool shown: pibble ? pibble.shown : false
    onShownChanged: if (shown)
        select(now)

    // live text from pibble's own (hidden) search field, cleared for us on
    // every pane switch and reopen - that empty value is the reset above
    readonly property string query: pibble ? pibble.searchText : ""
    onQueryChanged: {
        const target = parseQuery(query);
        if (target)
            showMonth(target.year, target.month);
        else if (!query)
            showMonth(now.getFullYear(), now.getMonth());
    }
    // "march", "mar 2027", "2027-03", "3/2027", "2027". What the tokens don't
    // pin down falls back to today, so a query always resolves to one month
    // rather than drifting from wherever the view happened to be.
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

    // trailing days of the previous month the first row starts with; Qt's
    // Locale.dayName counts from Sunday = 0, same as Date.getDay()
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
    // ISO-8601: a week is numbered after the year its Thursday falls in, so
    // shift onto that Thursday and count weeks from the one holding Jan 4th
    function isoWeek(d: date): int {
        const t = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        t.setDate(t.getDate() + 3 - ((t.getDay() + 6) % 7));
        const jan4 = new Date(t.getFullYear(), 0, 4);
        return 1 + Math.round(((t.getTime() - jan4.getTime()) / 86400000 - 3 + ((jan4.getDay() + 6) % 7)) / 7);
    }
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

            StepperButton {
                id: prevTile
                anchors.left: parent.left
                icon: Icons.chevronLeft
                opacity: 0
                onPressed: root.shiftMonth(-1)
            }
            Text {
                anchors.centerIn: parent
                text: Qt.locale().standaloneMonthName(root.viewMonth, Locale.LongFormat) + " " + root.viewYear
                color: titleArea.containsMouse ? root.pibble.accent : root.pibble.fg
                font.family: root.pibble.font
                font.pixelSize: root.pibble.fontSize(22)
                font.weight: Font.DemiBold

                MouseArea {
                    id: titleArea
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    onClicked: root.select(root.now)
                }
            }
            StepperButton {
                id: nextTile
                anchors.right: parent.right
                icon: Icons.chevronRight
                opacity: 0
                onPressed: root.shiftMonth(1)
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
                    // Monday-first is the same seven names rotated by one
                    text: Qt.locale().dayName(root.startMonday ? (index + 1) % 7 : index, Locale.ShortFormat)
                    color: root.pibble.muted
                    font.family: root.pibble.font
                    font.pixelSize: root.pibble.fontSize(13)
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
                        // the row's own Thursday, whichever day it starts on
                        text: String(root.isoWeek(root.dateAt(index * 7 + (root.startMonday ? 3 : 4))))
                        color: root.pibble.muted
                        font.family: root.pibble.font
                        font.pixelSize: root.pibble.fontSize(12)
                    }
                }
            }

            Grid {
                columns: 7
                spacing: root.gap

                // 6 rows always fit a month (6 leading days + 31 = 37 <= 42),
                // which lets the grid keep one fixed set of delegates: they're
                // rebound on a month change, never recreated, so the items
                // pibble's tileIn() registry holds stay alive with the page.
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
                        // today is the filled one and stays put; whatever was
                        // last clicked is ringed instead, so the two read as
                        // different things (and stack on the same cell)
                        color: isToday ? root.pibble.fillActive : (cellArea.containsMouse ? root.pibble.fill : "transparent")
                        border.width: isSelected ? 1 : 0
                        border.color: root.pibble.accent

                        Text {
                            anchors.centerIn: parent
                            text: String(cell.cellDate.getDate())
                            color: cell.isToday ? root.pibble.accent : root.pibble.fg
                            // days spilling in from the neighbouring months
                            // stay readable but recede
                            opacity: cell.cellDate.getMonth() === root.viewMonth ? 1 : 0.35
                            font.family: root.pibble.font
                            font.pixelSize: root.pibble.fontSize(18)
                            font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            // clicking a spill-over day follows it into its own
                            // month, the way every calendar does
                            onClicked: root.select(cell.cellDate)
                        }
                    }
                }
            }
        }

        Text {
            width: root.gridW
            horizontalAlignment: Text.AlignHCenter
            text: root.query ? "“" + root.query + "”" : "type a month or year to jump"
            elide: Text.ElideRight
            color: root.pibble.muted
            font.family: root.pibble.font
            font.pixelSize: root.pibble.fontSize(13)
        }
    }

    // gives this page its own Settings tab, next to General/Pages/etc.
    readonly property Component settingsTab: Component {
        Local.Settings {
            pibble: root.pibble
            startMonday: root.startMonday
            showWeeks: root.showWeeks
            onPicked: (key, value) => root.set(key, value)
        }
    }
}
