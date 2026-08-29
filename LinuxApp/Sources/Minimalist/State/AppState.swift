import Foundation
import MinimalistCore

/// User preferences, mirroring the macOS Preferences window's editor and
/// appearance sections. macOS keeps these in `UserDefaults` (and syncs
/// them through iCloud); Linux writes plain JSON under XDG config.
struct Settings: Codable, Equatable {
    var editorFontFamily = "Monospace"
    var editorFontSize = 12
    /// GtkSourceView style scheme ids — the counterparts of the macOS
    /// app's Highlightr light/dark themes.
    var syntaxThemeLight = "Adwaita"
    var syntaxThemeDark = "Adwaita-dark"
    var showLineNumbers = true
    var showMinimap = true
    var wordWrap = false
    var highlightCurrentLine = true
    var indentKind = Indentation.Kind.spaces.rawValue
    var indentWidth = 4
    var defaultLineEnding = LineEnding.lf.rawValue
    var completionEnabled = true
    var completionKeywords = true
    /// nil / "white" / "sepia" / "dark" — the editor pane background.
    var editorBackground: String?

    var indentation: Indentation {
        .init(kind: Indentation.Kind(rawValue: indentKind) ?? .spaces, width: indentWidth)
    }

    var lineEnding: LineEnding {
        LineEnding(rawValue: defaultLineEnding) ?? .lf
    }
}

/// What the window looked like when the app last quit: the open folder,
/// the pinned tabs, the active one, and the recent-files list feeding the
/// search palette. The macOS app stores security-scoped bookmarks; on
/// Linux plain paths are enough.
struct SessionState: Codable, Equatable {
    var folderPath: String?
    var openFilePaths: [String] = []
    var activeFilePath: String?
    var recentPaths: [String] = []
}

/// Reads and writes both files. Saves are best-effort: a read-only home
/// directory costs the user persistence, never a crash.
enum AppState {

    private static let appDirectory = "m-txt"

    static func configURL() -> URL {
        base(env: "XDG_CONFIG_HOME", fallback: ".config").appendingPathComponent("settings.json")
    }

    static func sessionURL() -> URL {
        base(env: "XDG_STATE_HOME", fallback: ".local/state").appendingPathComponent("session.json")
    }

    static func loadSettings() -> Settings {
        guard let data = try? Data(contentsOf: configURL()),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    static func save(_ settings: Settings) {
        write(settings, to: configURL())
        exportIndentationDefaults(settings)
    }

    static func loadSession() -> SessionState {
        guard let data = try? Data(contentsOf: sessionURL()),
              let session = try? JSONDecoder().decode(SessionState.self, from: data)
        else { return SessionState() }
        return session
    }

    static func save(_ session: SessionState) {
        write(session, to: sessionURL())
    }

    /// `MinimalistCore.Indentation.defaultsFromUserPrefs()` reads
    /// `UserDefaults` on both platforms — publish the Linux settings
    /// there so newly opened documents pick up the same defaults.
    static func exportIndentationDefaults(_ settings: Settings) {
        UserDefaults.standard.set(settings.indentKind, forKey: "default.indent.kind")
        UserDefaults.standard.set(settings.indentWidth, forKey: "default.indent.width")
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func base(env: String, fallback: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root: URL
        if let value = ProcessInfo.processInfo.environment[env], !value.isEmpty {
            root = URL(fileURLWithPath: value, isDirectory: true)
        } else {
            root = home.appendingPathComponent(fallback, isDirectory: true)
        }
        return root.appendingPathComponent(appDirectory, isDirectory: true)
    }
}
