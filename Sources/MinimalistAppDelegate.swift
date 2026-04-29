import AppKit
import SwiftUI
import ObjectiveC.runtime

/// Hooks into the AppKit lifecycle so we can record a `.minimal` session
/// commit on app quit. SwiftUI's `WindowGroup` doesn't expose
/// `applicationWillTerminate`, so we bridge through this minimal delegate.
final class MinimalistAppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `MinimalistApp.onAppear` so we can reach the active workspace
    /// without rebuilding it here.
    weak var workspace: Workspace?

    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort. If anything goes wrong recording the session, we
        // shouldn't block app shutdown.
        workspace?.recordSessionEnd()
    }
}

// MARK: - System accent override

/// Replaces the AppKit accent / selection color getters for our process so
/// menu highlights, focus rings, default buttons, and selection bars use
/// the user's chosen preset. SwiftUI's `.tint(...)` doesn't reach NSMenu —
/// this is the cleanest way to make those AppKit-painted surfaces match.
enum AccentColorOverride {
    private static var installed = false

    static func installOnce() {
        guard !installed else { return }
        installed = true

        // Class methods live on the metaclass — that's what we patch.
        guard let meta = object_getClass(NSColor.self) else { return }
        guard
            let accentMethod = class_getClassMethod(NSColor.self, #selector(NSColor.mn_accentColor)),
            let unemphasizedMethod = class_getClassMethod(NSColor.self, #selector(NSColor.mn_unemphasizedAccentColor))
        else { return }

        let accentIMP = method_getImplementation(accentMethod)
        let unemphasizedIMP = method_getImplementation(unemphasizedMethod)
        let typeEncoding = method_getTypeEncoding(accentMethod)

        // Different AppKit surfaces consult different system colors —
        // menu highlight in particular tends to read
        // selectedContentBackgroundColor on modern macOS, while focus
        // rings read keyboardFocusIndicatorColor. Patch all of them so
        // the chosen accent shows up everywhere AppKit paints accents.
        let installs: [(String, IMP)] = [
            ("controlAccentColor",                         accentIMP),
            ("selectedContentBackgroundColor",             accentIMP),
            ("unemphasizedSelectedContentBackgroundColor", unemphasizedIMP),
            ("keyboardFocusIndicatorColor",                accentIMP),
        ]
        for (name, imp) in installs {
            let sel = NSSelectorFromString(name)
            // Use class_replaceMethod so each selector ends up pointing
            // at our IMP — using method_exchangeImplementations would
            // chain-swap the replacement's IMP after the first call.
            _ = class_replaceMethod(meta, sel, imp, typeEncoding)
        }

        // Nudge AppKit to drop any cached system-color values it may have
        // already resolved before this point.
        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
    }
}

extension NSColor {
    @objc class func mn_accentColor() -> NSColor {
        return AccentPresets.current.nsColor
    }

    @objc class func mn_unemphasizedAccentColor() -> NSColor {
        return AccentPresets.current.nsColor.withAlphaComponent(0.55)
    }
}
