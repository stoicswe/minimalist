import Foundation

/// The sidebar's per-file monogram: a 1–3 character label and a muted
/// color suggesting the file's language or type. Platform-neutral so the
/// macOS sidebar (`FileTypeStyle`) and the Linux one render identical
/// chips — the apps only translate `rgb` into their toolkit's color type.
public struct FileTypeBadge: Hashable, Sendable {

    /// The monogram, e.g. `"SW"`. Empty for files with no known type.
    public let letter: String
    /// 0–255 sRGB components, intentionally desaturated so a sidebar full
    /// of files stays calm rather than circus-bright.
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(letter: String, red: Int, green: Int, blue: Int) {
        self.letter = letter
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A neutral grey chip with no monogram.
    public static let neutral = FileTypeBadge(letter: "", red: 140, green: 140, blue: 140)

    /// `#rrggbb`, for toolkits that take CSS-style colors (GTK).
    public var hex: String {
        String(format: "#%02x%02x%02x", red, green, blue)
    }

    /// Resolve the badge for a file: exact filename first (`Makefile`,
    /// `package.json`, …), then extension, then a generic chip built from
    /// the first two extension characters.
    public static func badge(for url: URL) -> FileTypeBadge {
        badge(forName: url.lastPathComponent)
    }

    public static func badge(forName filename: String) -> FileTypeBadge {
        let name = filename.lowercased()
        if let byName = nameMap[name] { return byName }

        let ext = (name as NSString).pathExtension
        if let byExt = extensionMap[ext] { return byExt }

        if ext.isEmpty { return grey("") }
        return grey(String(ext.prefix(2)).uppercased())
    }

    private static func badge(_ letter: String, _ red: Int, _ green: Int, _ blue: Int) -> FileTypeBadge {
        .init(letter: letter, red: red, green: green, blue: blue)
    }

    private static func grey(_ letter: String) -> FileTypeBadge {
        .init(letter: letter, red: 140, green: 140, blue: 140)
    }

    private static let extensionMap: [String: FileTypeBadge] = [
        // Apple
        "swift": badge("SW", 206, 110, 84),
        "m":     badge("M", 120, 144, 178),
        "mm":    badge("M+", 120, 144, 178),
        "h":     badge("H", 150, 152, 160),
        "plist": badge("PL", 132, 138, 152),

        // JS / TS family
        "js":   badge("JS", 196, 168, 78),
        "mjs":  badge("JS", 196, 168, 78),
        "cjs":  badge("JS", 196, 168, 78),
        "jsx":  badge("JX", 174, 162, 110),
        "ts":   badge("TS", 95, 130, 168),
        "tsx":  badge("TX", 95, 130, 168),

        // Web
        "html":   badge("H", 184, 116, 92),
        "htm":    badge("H", 184, 116, 92),
        "css":    badge("CS", 96, 132, 168),
        "scss":   badge("SC", 174, 116, 142),
        "sass":   badge("SC", 174, 116, 142),
        "less":   badge("LE", 110, 124, 168),
        "vue":    badge("V", 110, 154, 120),
        "svelte": badge("SV", 196, 116, 92),

        // Systems
        "c":   badge("C", 110, 130, 158),
        "cc":  badge("C+", 154, 116, 144),
        "cpp": badge("C+", 154, 116, 144),
        "cxx": badge("C+", 154, 116, 144),
        "hpp": badge("H+", 154, 116, 144),
        "hh":  badge("H+", 154, 116, 144),
        "rs":  badge("RS", 168, 110, 92),
        "go":  badge("GO", 110, 154, 168),
        "zig": badge("ZG", 184, 138, 96),

        // JVM
        "java":   badge("JV", 168, 124, 96),
        "kt":     badge("KT", 140, 116, 168),
        "kts":    badge("KT", 140, 116, 168),
        "scala":  badge("SC", 168, 100, 96),
        "groovy": badge("GR", 124, 156, 168),

        // Scripting
        "py":   badge("PY", 96, 130, 168),
        "pyi":  badge("PY", 96, 130, 168),
        "rb":   badge("RB", 168, 96, 100),
        "rake": badge("RB", 168, 96, 100),
        "php":  badge("PH", 116, 124, 156),
        "pl":   badge("PL", 140, 116, 144),
        "lua":  badge("LU", 96, 110, 148),
        "r":    badge("R", 96, 130, 168),

        // Shell / config
        "sh":   badge("SH", 124, 156, 116),
        "bash": badge("SH", 124, 156, 116),
        "zsh":  badge("SH", 124, 156, 116),
        "fish": badge("SH", 124, 156, 116),
        "ps1":  badge("PS", 95, 130, 168),
        "bat":  grey("BT"),
        "cmd":  grey("BT"),
        "env":  grey("EN"),

        // Data / markup
        "json": badge("{ }", 150, 138, 100),
        "yaml": badge("YL", 168, 116, 116),
        "yml":  badge("YL", 168, 116, 116),
        "toml": badge("TM", 150, 110, 100),
        "ini":  grey("IN"),
        "conf": grey("CF"),
        "xml":  badge("X", 140, 116, 168),
        "svg":  badge("SV", 168, 124, 96),
        "csv":  badge("CV", 124, 156, 116),
        "tsv":  badge("TV", 124, 156, 116),

        // Markup / docs
        "md":       badge("MD", 110, 134, 168),
        "markdown": badge("MD", 110, 134, 168),
        "mdx":      badge("MX", 110, 134, 168),
        "adoc":     badge("AD", 110, 134, 168),
        "asciidoc": badge("AD", 110, 134, 168),
        "txt":      grey("TX"),
        "rtf":      grey("RT"),
        "tex":      badge("LX", 110, 130, 110),
        "rst":      badge("RS", 110, 130, 168),

        // Database
        "sql": badge("SQ", 168, 138, 96),
        "db":  badge("DB", 140, 124, 96),

        // Other languages
        "dart":    badge("DT", 96, 148, 156),
        "ex":      badge("EX", 140, 116, 168),
        "exs":     badge("EX", 140, 116, 168),
        "erl":     badge("ER", 168, 96, 130),
        "hs":      badge("HS", 140, 116, 168),
        "clj":     badge("CJ", 110, 156, 130),
        "cljs":    badge("CJ", 110, 156, 130),
        "vim":     badge("VI", 110, 156, 116),
        "diff":    grey("DF"),
        "patch":   grey("DF"),
        "graphql": badge("GQ", 168, 96, 138),
        "gql":     badge("GQ", 168, 96, 138),
        "proto":   badge("PB", 96, 130, 168),
    ]

    private static let nameMap: [String: FileTypeBadge] = [
        "dockerfile":     badge("DK", 95, 132, 168),
        "makefile":       badge("MK", 140, 116, 96),
        "gnumakefile":    badge("MK", 140, 116, 96),
        "package.json":   badge("{ }", 150, 138, 100),
        "package.swift":  badge("SW", 206, 110, 84),
        "cargo.toml":     badge("CG", 168, 110, 92),
        ".gitignore":     grey("GI"),
        ".gitattributes": grey("GI"),
        ".env":           grey("EN"),
        "readme.md":      badge("RM", 110, 134, 168),
        "license":        grey("LC"),
    ]
}
