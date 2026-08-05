import QtQuick
import QtQuick.Effects
import "root:/config"
import "root:/services"

// The client-side stand-in for compositor blur ("xray", see Settings.bgBlur),
// deliberately a sibling of the launcher's content rather than a child of it:
// the compositor blur it imitates is a solid backdrop that the reveal circle
// uncovers, where content fades up from nothing over the same animation.
// Inside content it inherited that fade and read as a backdrop dissolving in -
// the one visible difference left between the two modes.
//
// Takes the same mask as content, so it is revealed by exactly the same
// circle, and in "fade"/"none" styles it simply appears with the window -
// which is also what the compositor's blur region does there.
Item {
    id: root

    // the growing reveal circle, handed in by LauncherWindow (which owns it,
    // since content masks against the very same item)
    required property Item maskSource

    anchors.fill: parent
    visible: Settings.bgBlur === "xray"
    // holds the oversized fallback image (see xrayBg) inside screen
    // geometry; a screen-sized, axis-aligned clip is a scissor test
    clip: true
    layer.enabled: LauncherState.growMode
    layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: root.maskSource
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.05
    }

    // The wallpaper, blurred, sitting exactly where the real
    // compositor blur would show through - at exactly screen
    // geometry, since any oversizing here reads as a zoomed-in
    // backdrop (PreserveAspectCrop scales the wallpaper to cover the
    // item, so a larger item is a larger wallpaper).
    //
    // Normally this is just an image: Wallpapers.xrayBlur is the wallpaper
    // already blurred (and saturated) to niri's own kernel, baked
    // into the cache alongside its thumbnail, so opening the launcher
    // costs one small texture upload and no effect pass at all. See
    // the xray block on root for the parameters.
    //
    // MultiEffect is only the stopgap for when that image doesn't
    // exist yet (no ImageMagick, or a folder still being worked
    // through). It cannot stand in for the real thing: blurMax caps
    // at 64, which is a sigma of about 8 against niri's 19, so this
    // is as wide a blur as the effect has. Saturation matches
    // exactly though - MultiEffect's saturation is an adjustment
    // around 0, so 0.5 is niri's `saturation 1.5`, the same mix
    // toward luma.
    readonly property real bgBlurAmount: 1.0
    readonly property int bgBlurMax: 64
    readonly property real bgBlurSaturation: 0.5
    // no baked file for the current wallpaper yet, so the wallpaper is
    // being blurred live below
    readonly property bool liveBlur: Settings.bgBlur === "xray" && Wallpapers.xrayShown === ""
    Image {
        id: xrayBg
        anchors.fill: parent
        // The live blur samples past the image's own edges, where
        // there is nothing but transparency, so the outer ~blurMax
        // pixels fade out - which is the transparent border around the
        // backdrop on the first open after a daemon restart, before
        // any bake exists. Oversize the image by that much and let the
        // parent clip it back, so the faded band lands off-screen. The
        // slight zoom this costs (see the PreserveAspectCrop note
        // above) only ever applies to the fallback.
        anchors.margins: root.liveBlur ? -root.bgBlurMax : 0
        fillMode: Image.PreserveAspectCrop
        // Deliberately keyed on the setting and not on this item's
        // `visible`: Item.visible reads *effective* visibility, so a
        // binding on it goes false every time the window hides,
        // which dropped the loaded pixmap and made the next open
        // decode the image again - visible as the backdrop arriving
        // a fraction of the way into the reveal (measured at ~30ms
        // for the baked image, far worse for the raw wallpaper).
        // Held loaded across opens instead.
        //
        // The raw wallpaper is only worth decoding once a scan that
        // was actually looking for the current backdrops has come
        // back without one; before that it is just a full-size
        // wallpaper decode that the baked path replaces moments
        // later.
        source: Settings.bgBlur !== "xray" ? ""
            : (Wallpapers.xrayShown !== "" ? "file://" + Wallpapers.xrayShown
                : (Wallpapers.scanKey === Wallpapers.xrayCacheKey ? Wallpapers.matugenSource : ""))
        asynchronous: true
        // the baked backdrop is small and reused across every open,
        // so it is worth keeping decoded; the raw wallpaper the
        // fallback loads is not
        cache: Wallpapers.xrayShown !== ""
        layer.enabled: root.liveBlur
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: root.bgBlurAmount
            blurMax: root.bgBlurMax
            saturation: root.bgBlurSaturation
        }
    }
}
