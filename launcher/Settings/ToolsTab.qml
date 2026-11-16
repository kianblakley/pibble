import QtQuick
import "root:/config"
import "root:/launcher"
import "root:/services"
import "root:/ui"

// One slide of the settings filmstrip. `root.slideIndex` is where this tab sits in
// SettingsPane.tabOrder and `root.activeIndex` which slide is showing; the two
// together are the whole of the horizontal tab transition.
// Tools: the screen tools (search, translate, record, pick a color - see
// services/ScreenTools.qml) and the menu `pibble toggle tools` opens them from.
Column {
    id: root

    required property int slideIndex
    required property int activeIndex
    // see FlyoutsTab's copy of this
    readonly property bool scrambleSuppressed: root.slideIndex !== root.activeIndex

    x: 20 + (root.slideIndex - root.activeIndex) * 840
    Behavior on x {
        NumberAnimation { duration: Anim.menu(420); easing.type: Easing.OutCubic }
    }

    spacing: 14

    // the menu, and how all of the tools look
    SettingRow { key: "toolsFace"; label: "Tools menu pointer"; hint: "what the pointer becomes in the middle of the menu"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "toolsTrail"; label: "Tools menu trails"; hint: "what the eyes leave behind them as they move"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "toolsSpread"; label: "Tools menu size"; hint: "how far the tools sit from the pointer"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "toolsHint"; label: "Tools menu labels"; hint: "what shows beside the chosen tool"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "toolsAnim"; label: "Tools menu animation"; valueWidth: Metrics.shortValueWidth }
    SettingRow { key: "toolsColors"; label: "Tools colors"; hint: "fixed is black and white over anything; theme follows pibble's colors"; valueWidth: Metrics.shortValueWidth }

    // search and translate
    TextSettingRow { key: "searchUrl"; label: "Search with"; placeholder: "a web address, %s where the words go" }
    TextSettingRow { key: "ocrLanguages"; label: "Reading languages"; placeholder: "every installed language, or e.g. eng+jpn" }
    TextSettingRow { key: "translateTo"; label: "Translate into"; placeholder: "pibble's language, or e.g. en, ja, zh-CN" }
    TextSettingRow {
        key: "translateCommand"
        label: "Translate command"
        placeholder: "Google Translate"
        hint: "gets one paragraph per line, the language in $PIBBLE_TRANSLATE_TO, and prints as many lines back"
    }

    // recording
    TextSettingRow { key: "recordDir"; label: "Recordings folder"; placeholder: "~/Videos" }
    SettingRow { key: "recordAudio"; label: "Recording sound"; valueWidth: Metrics.shortValueWidth }
    TextSettingRow { key: "recordArgs"; label: "Recorder options"; placeholder: "extra wf-recorder options, e.g. -c hevc_vaapi" }
}
