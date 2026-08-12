import QtQuick
import "root:/config"
import "root:/services"

// Small muted caption a tile-grid pane shows above its tiles, echoing the
// live search query. `queryText` is injected rather than read off
// LauncherState directly - a ui component can't reach up into the launcher
// layer (see CLAUDE.md's dependency direction).
ScrambleText {
    id: root

    property string queryText: ""

    readonly property bool hasQuery: root.queryText.length > 0
    content: root.queryText
    // pinned to the resting query's width so a centered label doesn't shuffle
    // sideways on every reroll while it resolves
    width: root.restWidth

    visible: Settings.pageIndicatorEnabled("query") && opacity > 0
    opacity: root.hasQuery ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    elide: Text.ElideRight
    color: Theme.muted
    font { family: Theme.fontFamily; pixelSize: Theme.fontSize(13) }
}
