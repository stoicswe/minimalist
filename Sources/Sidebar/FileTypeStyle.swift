import SwiftUI

/// Visual style for a file in the sidebar: a 1–3 character monogram
/// and a muted color that suggests the file's language/type.
struct FileTypeStyle {
    let letter: String
    let color: Color

    static let neutral = FileTypeStyle(letter: "", color: Color(white: 0.55))

    static func style(for url: URL) -> FileTypeStyle {
        let name = url.lastPathComponent.lowercased()
        if let byName = nameMap[name] { return byName }

        let ext = url.pathExtension.lowercased()
        if let byExt = extensionMap[ext] { return byExt }

        if ext.isEmpty { return neutral }
        // Fallback: first 1–2 characters of extension on a neutral chip.
        return FileTypeStyle(
            letter: ext.prefix(2).uppercased(),
            color: Color(white: 0.55)
        )
    }

    // Brand-derived colors, intentionally desaturated so a sidebar full
    // of files stays calm rather than circus-bright.
    private static func brand(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    private static let extensionMap: [String: FileTypeStyle] = [
        // Apple
        "swift": FileTypeStyle(letter: "SW", color: brand(206, 110, 84)),  // muted Swift orange
        "m":     FileTypeStyle(letter: "M",  color: brand(120, 144, 178)), // ObjC blue-grey
        "mm":    FileTypeStyle(letter: "M+", color: brand(120, 144, 178)),
        "h":     FileTypeStyle(letter: "H",  color: brand(150, 152, 160)),
        "plist": FileTypeStyle(letter: "PL", color: brand(132, 138, 152)),

        // JS / TS family
        "js":   FileTypeStyle(letter: "JS", color: brand(196, 168, 78)),   // muted yellow
        "mjs":  FileTypeStyle(letter: "JS", color: brand(196, 168, 78)),
        "cjs":  FileTypeStyle(letter: "JS", color: brand(196, 168, 78)),
        "jsx":  FileTypeStyle(letter: "JX", color: brand(174, 162, 110)),
        "ts":   FileTypeStyle(letter: "TS", color: brand(95, 130, 168)),   // muted TS blue
        "tsx":  FileTypeStyle(letter: "TX", color: brand(95, 130, 168)),

        // Web
        "html": FileTypeStyle(letter: "H",  color: brand(184, 116, 92)),
        "htm":  FileTypeStyle(letter: "H",  color: brand(184, 116, 92)),
        "css":  FileTypeStyle(letter: "CS", color: brand(96, 132, 168)),
        "scss": FileTypeStyle(letter: "SC", color: brand(174, 116, 142)),
        "sass": FileTypeStyle(letter: "SC", color: brand(174, 116, 142)),
        "less": FileTypeStyle(letter: "LE", color: brand(110, 124, 168)),
        "vue":  FileTypeStyle(letter: "V",  color: brand(110, 154, 120)),
        "svelte": FileTypeStyle(letter: "SV", color: brand(196, 116, 92)),

        // Systems
        "c":   FileTypeStyle(letter: "C",   color: brand(110, 130, 158)),
        "cc":  FileTypeStyle(letter: "C+",  color: brand(154, 116, 144)),
        "cpp": FileTypeStyle(letter: "C+",  color: brand(154, 116, 144)),
        "cxx": FileTypeStyle(letter: "C+",  color: brand(154, 116, 144)),
        "hpp": FileTypeStyle(letter: "H+",  color: brand(154, 116, 144)),
        "hh":  FileTypeStyle(letter: "H+",  color: brand(154, 116, 144)),
        "rs":  FileTypeStyle(letter: "RS",  color: brand(168, 110, 92)),   // muted Rust
        "go":  FileTypeStyle(letter: "GO",  color: brand(110, 154, 168)),  // muted Go cyan
        "zig": FileTypeStyle(letter: "ZG",  color: brand(184, 138, 96)),

        // JVM
        "java":  FileTypeStyle(letter: "JV", color: brand(168, 124, 96)),
        "kt":    FileTypeStyle(letter: "KT", color: brand(140, 116, 168)),
        "kts":   FileTypeStyle(letter: "KT", color: brand(140, 116, 168)),
        "scala": FileTypeStyle(letter: "SC", color: brand(168, 100, 96)),
        "groovy": FileTypeStyle(letter: "GR", color: brand(124, 156, 168)),

        // Scripting
        "py":   FileTypeStyle(letter: "PY", color: brand(96, 130, 168)),   // muted Py blue
        "pyi":  FileTypeStyle(letter: "PY", color: brand(96, 130, 168)),
        "rb":   FileTypeStyle(letter: "RB", color: brand(168, 96, 100)),   // muted Ruby
        "rake": FileTypeStyle(letter: "RB", color: brand(168, 96, 100)),
        "php":  FileTypeStyle(letter: "PH", color: brand(116, 124, 156)),
        "pl":   FileTypeStyle(letter: "PL", color: brand(140, 116, 144)),
        "lua":  FileTypeStyle(letter: "LU", color: brand(96, 110, 148)),
        "r":    FileTypeStyle(letter: "R",  color: brand(96, 130, 168)),

        // Shell / config
        "sh":    FileTypeStyle(letter: "SH", color: brand(124, 156, 116)),
        "bash":  FileTypeStyle(letter: "SH", color: brand(124, 156, 116)),
        "zsh":   FileTypeStyle(letter: "SH", color: brand(124, 156, 116)),
        "fish":  FileTypeStyle(letter: "SH", color: brand(124, 156, 116)),
        "ps1":   FileTypeStyle(letter: "PS", color: brand(95, 130, 168)),
        "bat":   FileTypeStyle(letter: "BT", color: brand(140, 140, 140)),
        "cmd":   FileTypeStyle(letter: "BT", color: brand(140, 140, 140)),
        "env":   FileTypeStyle(letter: "EN", color: brand(140, 140, 140)),

        // Data / markup
        "json": FileTypeStyle(letter: "{ }", color: brand(150, 138, 100)),
        "yaml": FileTypeStyle(letter: "YL",  color: brand(168, 116, 116)),
        "yml":  FileTypeStyle(letter: "YL",  color: brand(168, 116, 116)),
        "toml": FileTypeStyle(letter: "TM",  color: brand(150, 110, 100)),
        "ini":  FileTypeStyle(letter: "IN",  color: brand(140, 140, 140)),
        "conf": FileTypeStyle(letter: "CF",  color: brand(140, 140, 140)),
        "xml":  FileTypeStyle(letter: "X",   color: brand(140, 116, 168)),
        "svg":  FileTypeStyle(letter: "SV",  color: brand(168, 124, 96)),
        "csv":  FileTypeStyle(letter: "CV",  color: brand(124, 156, 116)),
        "tsv":  FileTypeStyle(letter: "TV",  color: brand(124, 156, 116)),

        // Markup / docs
        "md":       FileTypeStyle(letter: "MD", color: brand(110, 134, 168)),
        "markdown": FileTypeStyle(letter: "MD", color: brand(110, 134, 168)),
        "mdx":      FileTypeStyle(letter: "MX", color: brand(110, 134, 168)),
        "txt":      FileTypeStyle(letter: "TX", color: brand(140, 140, 140)),
        "rtf":      FileTypeStyle(letter: "RT", color: brand(140, 140, 140)),
        "tex":      FileTypeStyle(letter: "LX", color: brand(110, 130, 110)),
        "rst":      FileTypeStyle(letter: "RS", color: brand(110, 130, 168)),

        // Database
        "sql": FileTypeStyle(letter: "SQ", color: brand(168, 138, 96)),
        "db":  FileTypeStyle(letter: "DB", color: brand(140, 124, 96)),

        // Other languages
        "dart":  FileTypeStyle(letter: "DT", color: brand(96, 148, 156)),
        "ex":    FileTypeStyle(letter: "EX", color: brand(140, 116, 168)),
        "exs":   FileTypeStyle(letter: "EX", color: brand(140, 116, 168)),
        "erl":   FileTypeStyle(letter: "ER", color: brand(168, 96, 130)),
        "hs":    FileTypeStyle(letter: "HS", color: brand(140, 116, 168)),
        "clj":   FileTypeStyle(letter: "CJ", color: brand(110, 156, 130)),
        "cljs":  FileTypeStyle(letter: "CJ", color: brand(110, 156, 130)),
        "vim":   FileTypeStyle(letter: "VI", color: brand(110, 156, 116)),
        "diff":  FileTypeStyle(letter: "DF", color: brand(140, 140, 140)),
        "patch": FileTypeStyle(letter: "DF", color: brand(140, 140, 140)),
        "graphql": FileTypeStyle(letter: "GQ", color: brand(168, 96, 138)),
        "gql":   FileTypeStyle(letter: "GQ", color: brand(168, 96, 138)),
        "proto": FileTypeStyle(letter: "PB", color: brand(96, 130, 168)),
    ]

    private static let nameMap: [String: FileTypeStyle] = [
        "dockerfile":     FileTypeStyle(letter: "DK", color: brand(95, 132, 168)),
        "makefile":       FileTypeStyle(letter: "MK", color: brand(140, 116, 96)),
        "gnumakefile":    FileTypeStyle(letter: "MK", color: brand(140, 116, 96)),
        "package.json":   FileTypeStyle(letter: "{ }", color: brand(150, 138, 100)),
        "package.swift":  FileTypeStyle(letter: "SW", color: brand(206, 110, 84)),
        "cargo.toml":     FileTypeStyle(letter: "CG", color: brand(168, 110, 92)),
        ".gitignore":     FileTypeStyle(letter: "GI", color: brand(140, 140, 140)),
        ".gitattributes": FileTypeStyle(letter: "GI", color: brand(140, 140, 140)),
        ".env":           FileTypeStyle(letter: "EN", color: brand(140, 140, 140)),
        "readme.md":      FileTypeStyle(letter: "RM", color: brand(110, 134, 168)),
        "license":        FileTypeStyle(letter: "LC", color: brand(140, 140, 140)),
    ]
}
