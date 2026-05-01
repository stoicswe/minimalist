import SwiftUI
import AppKit

enum PreferenceKeys {
    static let showLineNumbers = "pref.showLineNumbers"
    static let uiFontName = "pref.uiFontName"
    static let uiFontSize = "pref.uiFontSize"
    static let editorFontName = "pref.editorFontName"
    static let editorFontSize = "pref.editorFontSize"
    static let lastFolderBookmark = "lastFolderBookmark"
    static let openFilePaths = "openFilePaths"
    static let activeFilePath = "activeFilePath"
    /// Multi-window persistence: an ordered list of `WindowSnapshot` (one
    /// per open window at quit time). Encoded as JSON Data. The primary
    /// window restores from index 0; additional windows are reopened by
    /// the AppDelegate at launch.
    static let savedWindows = "savedWindows"

    // Appearance
    static let colorScheme = "pref.colorScheme"          // "system" | "light" | "dark"
    static let windowGlass = "pref.windowGlass"          // bool: false = solid, true = glass
    static let syntaxThemeLight = "pref.syntaxThemeLight"
    static let syntaxThemeDark = "pref.syntaxThemeDark"
    static let showMinimap = "pref.showMinimap"

    /// "ask" | "same" | "new" — how ⌘O / ⌘⇧O resolve when invoked.
    static let openLocationBehavior = "pref.openLocationBehavior"

    // Accent customization
    static let accentPresetID = "pref.accentPresetID"
    /// On/off — apply accent tint to folder icons.
    static let accentTintFolders = "pref.accentTintFolders"
    /// On/off — apply accent tint to the active tab background.
    static let accentTintTabs = "pref.accentTintTabs"
    /// On/off — apply accent tint to the editor's current-line highlight.
    static let accentTintCurrentLine = "pref.accentTintCurrentLine"
    /// On/off — wash the sidebar (file tree) background with a tint of
    /// the accent color. Light mode gets a subtle pastel wash; dark mode
    /// gets a richer, more saturated tint.
    static let accentTintSidebar = "pref.accentTintSidebar"

    /// On/off — show inline ghost-text completion suggestions while typing.
    static let enableAutocomplete = "pref.enableAutocomplete"

    /// On/off — also suggest the file's language keywords (e.g., `func`,
    /// `class`, `import` for Swift). Only effective when
    /// `enableAutocomplete` is on. Independent toggle so users can keep
    /// document-identifier completion without the keyword noise (or vice
    /// versa).
    static let enableLanguageKeywords = "pref.enableLanguageKeywords"

    /// On/off — wrap long lines at the editor's visible width. Off means
    /// the editor scrolls horizontally for content past the right edge.
    static let wordWrap = "pref.wordWrap"

    /// On/off — override the editor pane's background with one of the
    /// preset colors below. When off, the system's `textBackgroundColor`
    /// is used (current behavior).
    static let editorBackgroundOverride = "pref.editorBackgroundOverride"
    /// Preset name to use when in light appearance: "white" / "sepia" / "dark".
    static let editorBackgroundLight = "pref.editorBackgroundLight"
    /// Preset name to use when in dark appearance: "white" / "sepia" / "dark".
    static let editorBackgroundDark = "pref.editorBackgroundDark"

    /// Background pattern overlay: "none" | "sand" | "ripples" | "mist" |
    /// "stars" | "waves". All patterns render as a low-alpha tone on top
    /// of the editor pane background.
    static let editorBackgroundPattern = "pref.editorBackgroundPattern"
    /// On/off — animate the chosen pattern.
    static let editorBackgroundPatternAnimated = "pref.editorBackgroundPatternAnimated"
    /// 0.1...2.0 — pattern animation speed (1.0 is baseline).
    static let editorBackgroundPatternSpeed = "pref.editorBackgroundPatternSpeed"

    /// On/off — Zen mode hides the sidebar, tabs, and editor overlay
    /// buttons. Search is reachable via ⇧⇧.
    static let zenMode = "pref.zenMode"

    /// Persisted recently-edited file paths (for the Zen search palette
    /// when the query is empty).
    static let recentEditedPaths = "recentEditedPaths"

    /// On/off — mirror appearance, accent, autocomplete, and (standard-
    /// font-only) typography settings to iCloud Key-Value Store so they
    /// follow the user across Macs signed in with the same Apple ID.
    static let iCloudSyncEnabled = "pref.iCloudSyncEnabled"
}

enum OpenLocationBehavior {
    static let ask = "ask"
    static let same = "same"
    static let new = "new"
    static let `default` = ask
}

/// Curated list of Highlightr themes that read well as a code editor (high
/// enough contrast, sensible color choices). Full theme list is much larger
/// but most are gimmicky or low-contrast.
enum SyntaxThemes {
    static let light: [String] = [
        "atom-one-light",
        "github",
        "xcode",
        "vs",
        "solarized-light",
        "tomorrow",
    ]
    static let dark: [String] = [
        "tomorrow-night-bright",
        "monokai-sublime",
        "dracula",
        "atom-one-dark",
        "nord",
        "vs2015",
        "tomorrow-night-eighties",
    ]
    static let defaultLight = "atom-one-light"
    static let defaultDark = "tomorrow-night-bright"
}

extension Notification.Name {
    /// Posted when any editor-affecting preference changes (font, line numbers).
    static let editorPreferencesChanged = Notification.Name("editorPreferencesChanged")
}

enum Preferences {
    static var editorFont: NSFont {
        let name = UserDefaults.standard.string(forKey: PreferenceKeys.editorFontName) ?? ""
        let size = userFontSize(key: PreferenceKeys.editorFontSize, default: 13)
        if !name.isEmpty, let font = NSFont(name: name, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static var uiFont: Font? {
        let name = UserDefaults.standard.string(forKey: PreferenceKeys.uiFontName) ?? ""
        let size = userFontSize(key: PreferenceKeys.uiFontSize, default: 13)
        if name.isEmpty { return nil }
        return Font.custom(name, size: size)
    }

    static var showLineNumbers: Bool {
        if UserDefaults.standard.object(forKey: PreferenceKeys.showLineNumbers) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: PreferenceKeys.showLineNumbers)
    }

    static var wordWrap: Bool {
        if UserDefaults.standard.object(forKey: PreferenceKeys.wordWrap) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: PreferenceKeys.wordWrap)
    }

    private static func userFontSize(key: String, default fallback: Double) -> CGFloat {
        let raw = UserDefaults.standard.double(forKey: key)
        return raw > 0 ? CGFloat(raw) : CGFloat(fallback)
    }
}
