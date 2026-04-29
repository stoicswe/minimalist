import SwiftUI
import AppKit

/// Three preset choices for the editor pane's background color when the
/// user opts into the override. Each is held by a per-appearance
/// preference (`editorBackgroundLight` / `editorBackgroundDark`) so the
/// user can pair, say, sepia for daytime and dark for night.
enum EditorBackgroundOption: String, CaseIterable, Identifiable {
    case white
    case sepia
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: return "White"
        case .sepia: return "Sepia"
        case .dark:  return "Dark"
        }
    }

    /// Concrete color used in the SwiftUI pane background.
    var color: Color {
        switch self {
        case .white: return Color(red: 1.00, green: 1.00, blue: 1.00)
        case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.84)
        case .dark:  return Color(red: 0.12, green: 0.13, blue: 0.15)
        }
    }

    /// Defaults the user gets the first time they enable the override —
    /// "white" for light mode, "dark" for dark mode.
    static func resolve(rawValue: String, fallback: EditorBackgroundOption) -> EditorBackgroundOption {
        EditorBackgroundOption(rawValue: rawValue) ?? fallback
    }

    /// Does the override want a dark editor right now?
    /// Reads the current preference values and the supplied appearance.
    static func currentColor(forDarkAppearance isDark: Bool) -> Color? {
        let on = UserDefaults.standard.bool(forKey: PreferenceKeys.editorBackgroundOverride)
        guard on else { return nil }
        let key = isDark ? PreferenceKeys.editorBackgroundDark
                         : PreferenceKeys.editorBackgroundLight
        let raw = UserDefaults.standard.string(forKey: key) ?? (isDark ? "dark" : "white")
        let option = resolve(rawValue: raw, fallback: isDark ? .dark : .white)
        return option.color
    }

    /// True when the editor pane is currently rendering on a dark
    /// background — either because the app is in dark appearance with
    /// no override, or because the user picked the "dark" preset for
    /// the current appearance. Drives the syntax theme + ruler + current-
    /// line highlight so they always contrast with the actual surface
    /// the editor is drawing on, not just the system appearance.
    static func editorIsDarkSurface() -> Bool {
        let appearanceIsDark = appAppearanceIsDark()
        let override = UserDefaults.standard.bool(forKey: PreferenceKeys.editorBackgroundOverride)
        guard override else { return appearanceIsDark }
        let key = appearanceIsDark
            ? PreferenceKeys.editorBackgroundDark
            : PreferenceKeys.editorBackgroundLight
        let raw = UserDefaults.standard.string(forKey: key)
            ?? (appearanceIsDark ? "dark" : "white")
        return raw == "dark"
    }

    private static func appAppearanceIsDark() -> Bool {
        let pref = UserDefaults.standard.string(forKey: PreferenceKeys.colorScheme) ?? "system"
        switch pref {
        case "dark": return true
        case "light": return false
        default:
            return NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }
}

// MARK: - Environment plumbing for SwiftUI surfaces drawn over the editor

private struct EditorSurfaceIsDarkKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Tabs, corner buttons, status pill — anything sitting over the
    /// editor pane reads this to pick a contrasting tone, instead of
    /// blindly trusting `Color.primary` (which follows the app
    /// appearance, not the actual surface behind the view).
    var editorSurfaceIsDark: Bool {
        get { self[EditorSurfaceIsDarkKey.self] }
        set { self[EditorSurfaceIsDarkKey.self] = newValue }
    }
}

extension EditorBackgroundOption {
    /// Drop-in for `Color.primary` for views drawn over the editor.
    static func primary(onDarkSurface: Bool) -> Color {
        onDarkSurface ? Color.white : Color.black
    }

    /// Drop-in for `Color.secondary` for views drawn over the editor.
    static func secondary(onDarkSurface: Bool) -> Color {
        let base: Color = onDarkSurface ? .white : .black
        return base.opacity(0.65)
    }
}
