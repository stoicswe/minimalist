import Foundation

enum LanguageDetector {
    private static let extensionMap: [String: String] = [
        "swift": "swift",
        "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
        "ts": "typescript", "tsx": "typescript",
        "py": "python", "pyi": "python",
        "rb": "ruby", "rake": "ruby",
        "rs": "rust",
        "go": "go",
        "c": "c", "h": "c",
        "cc": "cpp", "cpp": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp",
        "m": "objectivec", "mm": "objectivec",
        "java": "java",
        "kt": "kotlin", "kts": "kotlin",
        "scala": "scala", "sbt": "scala",
        "sh": "bash", "bash": "bash", "zsh": "bash",
        "ps1": "powershell",
        "lua": "lua",
        "php": "php",
        "html": "xml", "htm": "xml", "xml": "xml", "svg": "xml", "plist": "xml",
        "css": "css",
        "scss": "scss", "sass": "scss",
        "less": "less",
        "json": "json",
        "yaml": "yaml", "yml": "yaml",
        "toml": "ini", "ini": "ini", "conf": "ini",
        "md": "markdown", "markdown": "markdown",
        "sql": "sql",
        "r": "r",
        "dart": "dart",
        "ex": "elixir", "exs": "elixir",
        "erl": "erlang",
        "hs": "haskell",
        "clj": "clojure", "cljs": "clojure",
        "vim": "vim",
        "tex": "latex",
        "diff": "diff", "patch": "diff",
        "graphql": "graphql", "gql": "graphql",
        "proto": "protobuf",
    ]

    private static let nameMap: [String: String] = [
        "dockerfile": "dockerfile",
        "makefile": "makefile",
        "gnumakefile": "makefile",
        ".gitignore": "bash",
        ".gitattributes": "bash",
        ".env": "bash",
    ]

    static func language(for url: URL) -> String {
        let lowerName = url.lastPathComponent.lowercased()
        if let lang = nameMap[lowerName] { return lang }
        let ext = url.pathExtension.lowercased()
        return extensionMap[ext] ?? "plaintext"
    }
}
