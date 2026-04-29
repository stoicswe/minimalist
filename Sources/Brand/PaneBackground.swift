import SwiftUI
import AppKit

/// A pane's translucent fill. The window-level `NSVisualEffectView`
/// (installed by `TightTitlebarController`) provides the desktop blur; this
/// view simply controls how much of that blurred desktop shows through with
/// a solid color overlay whose opacity is `1 - transparency`.
///
/// At `transparency = 0` the overlay is fully opaque and the pane looks like
/// a normal solid background. At `transparency = 1` the overlay disappears
/// and the window-level blur (or, if `windowBlur = 0`, the bare desktop)
/// shows through.
struct PaneBackground: View {
    let baseColor: Color
    let transparency: Double

    var body: some View {
        baseColor.opacity(1.0 - transparency)
    }
}
