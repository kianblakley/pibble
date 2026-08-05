pragma Singleton
import QtQuick
import Quickshell

// pibble's own UI glyphs (weather/battery/checks/etc, as opposed to other
// apps' resolved icons) come from one vendored icon webfont, addressed by
// codepoint rather than name.
//
// Deliberately dependency-free: both Theme (which paints them) and Notifier
// (which classifies notifications by them) need this, and keeping it a leaf
// means neither has to import the other.
Singleton {
    id: root

    FontLoader {
        id: iconFont
        source: Qt.resolvedUrl("../fonts/MaterialSymbolsSharp_48pt-SemiBold.ttf")
    }

    readonly property string family: iconFont.name

    // Another app's icon by freedesktop name → a displayable URL. Senders (and
    // .desktop Icon= entries) sometimes resolve the icon themselves, so paths
    // and urls pass straight through.
    function url(name: string): string {
        if (!name)
            return "";
        if (name.startsWith("file://"))
            return name;
        if (name.startsWith("/"))
            return "file://" + name;
        return Quickshell.iconPath(name, true);
    }

    // codepoints looked up by hand from Material Symbols' own cmap - Private
    // Use Area codepoints carry no standard meaning outside this font.
    readonly property string sun: "\ue430"
    readonly property string cloud: "\ue2bd"
    readonly property string cloudRain: "\uf176"
    readonly property string cloudStorm: "\uebdb"
    readonly property string snowflake: "\ued5b"
    readonly property string bolt: "\uea0b"
    readonly property string check: "\ue5ca"
    readonly property string settings: "\ue8b8"
    readonly property string refresh: "\ue5d5"
    readonly property string copy: "\ue14d"
    readonly property string bell: "\ue7f4"
    readonly property string alertTriangle: "\ue002"
    readonly property string cornerDownLeft: "\ue31b"
    readonly property string wallpaperSlideshow: "\uf672"
    readonly property string plus: "\uf710"
    readonly property string trash: "\ue872"
    readonly property string batteryLow: "\uf251"
    readonly property string chevronLeft: "\ue5cb"
    readonly property string chevronRight: "\ue5cc"
    readonly property string deployedCodeAlert: "\uf5f2"
    readonly property string arrowLeft: "\ue5c4"
    readonly property string arrowRight: "\ue5c8"
    readonly property string arrowUp: "\ue5d8"
    readonly property string arrowDown: "\ue5db"
}
