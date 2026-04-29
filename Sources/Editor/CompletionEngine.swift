import Foundation

/// Lightweight, dependency-free word completion. Sources candidates from
///   1. identifiers already in the document (so the suggestions reflect
///      whatever symbols the user has been working with — "context-aware
///      of patterns"), and
///   2. the language's keyword list (so common-but-not-yet-typed
///      keywords still show up early in a fresh file).
///
/// This is intentionally simple — no fuzzy matching, no LLM. The point is
/// to make finishing repetitive identifiers and keywords cheap, not to
/// rival a language server.
enum CompletionEngine {
    /// Find the best completion for `prefix` given the surrounding
    /// document text and language. Returns the *suffix* to append (i.e.
    /// the part the user hasn't typed yet), or nil when nothing useful
    /// matches.
    ///
    /// - Parameter includeKeywords: When true, the file's language
    ///   keywords are folded into the candidate pool alongside document
    ///   identifiers. When false, only identifiers from the file are
    ///   considered.
    static func suggest(
        prefix: String,
        in text: String,
        language: String,
        includeKeywords: Bool = true
    ) -> String? {
        guard prefix.count >= 2 else { return nil }

        var pool = identifiers(in: text)
        if includeKeywords {
            pool.formUnion(LanguageKeywords.list(for: language))
        }
        // Don't suggest the user's own current word back to them.
        let lower = prefix.lowercased()
        let matches = pool.filter {
            $0.count > prefix.count && $0.lowercased().hasPrefix(lower)
        }
        guard !matches.isEmpty else { return nil }

        // Prefer the shortest match — typically the most likely
        // continuation when the user has typed a 2-3 letter prefix.
        // Tiebreak alphabetically so the choice stays stable across edits.
        let best = matches.min { a, b in
            if a.count != b.count { return a.count < b.count }
            return a < b
        }!
        return String(best.dropFirst(prefix.count))
    }

    /// Tokenize the document into unique identifiers (alphanumeric +
    /// underscore), at least 3 chars long.
    private static func identifiers(in text: String) -> Set<String> {
        var set: Set<String> = []
        var current = ""
        for char in text {
            if char.isLetter || char.isNumber || char == "_" {
                current.append(char)
            } else {
                if current.count >= 3 { set.insert(current) }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= 3 { set.insert(current) }
        return set
    }
}

/// Per-language keyword lists. Kept compact — the document-derived
/// identifiers handle everything else.
enum LanguageKeywords {
    /// Returns the keyword set for `language`. Each set is a static
    /// constant — allocated once at first reference, returned by
    /// reference every call after, so dispatching by language string is
    /// effectively free even on a hot path.
    static func list(for language: String) -> Set<String> {
        switch language.lowercased() {
        case "swift":
            return swift
        case "python":
            return python
        case "javascript", "typescript", "tsx", "jsx":
            return javascript
        case "rust":
            return rust
        case "go":
            return go
        case "ruby":
            return ruby
        case "java", "kotlin":
            return java
        case "c", "cpp", "c++", "objc", "objective-c":
            return c
        case "haskell":
            return haskell
        case "bash", "shell", "sh", "zsh":
            return bash
        case "sql":
            return sql
        case "lua":
            return lua
        case "elixir":
            return elixir
        case "html", "xml":
            return html
        case "css", "scss":
            return css
        default:
            return []
        }
    }

    private static let swift: Set<String> = [
        "associatedtype", "break", "case", "catch", "class", "continue",
        "default", "defer", "deinit", "do", "else", "enum", "extension",
        "fallthrough", "false", "fileprivate", "final", "for", "func",
        "guard", "if", "import", "in", "indirect", "init", "inout",
        "internal", "is", "lazy", "let", "mutating", "nil", "open",
        "operator", "override", "private", "protocol", "public", "repeat",
        "return", "self", "static", "struct", "subscript", "super",
        "switch", "throw", "throws", "true", "try", "typealias", "var",
        "weak", "where", "while", "Any", "AnyObject", "Bool", "Double",
        "Int", "String", "Array", "Dictionary", "Set", "Optional",
    ]

    private static let python: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class",
        "continue", "def", "del", "elif", "else", "except", "finally",
        "for", "from", "global", "if", "import", "in", "is", "lambda",
        "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
        "with", "yield", "True", "False", "None", "self", "print", "len",
        "range", "list", "dict", "set", "tuple", "str", "int", "float",
    ]

    private static let javascript: Set<String> = [
        "abstract", "async", "await", "break", "case", "catch", "class",
        "const", "continue", "debugger", "default", "delete", "do", "else",
        "enum", "export", "extends", "false", "finally", "for", "from",
        "function", "if", "implements", "import", "in", "instanceof",
        "interface", "let", "new", "null", "of", "private", "protected",
        "public", "return", "static", "super", "switch", "this", "throw",
        "true", "try", "type", "typeof", "undefined", "var", "void",
        "while", "with", "yield", "console", "document", "window",
    ]

    private static let rust: Set<String> = [
        "as", "async", "await", "break", "const", "continue", "crate",
        "dyn", "else", "enum", "extern", "false", "fn", "for", "if",
        "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub",
        "ref", "return", "self", "Self", "static", "struct", "super",
        "trait", "true", "type", "unsafe", "use", "where", "while",
    ]

    private static let go: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer",
        "else", "fallthrough", "for", "func", "go", "goto", "if", "import",
        "interface", "map", "package", "range", "return", "select",
        "struct", "switch", "type", "var", "true", "false", "nil",
    ]

    private static let ruby: Set<String> = [
        "BEGIN", "END", "alias", "and", "begin", "break", "case", "class",
        "def", "defined?", "do", "else", "elsif", "end", "ensure", "false",
        "for", "if", "in", "module", "next", "nil", "not", "or", "redo",
        "rescue", "retry", "return", "self", "super", "then", "true",
        "undef", "unless", "until", "when", "while", "yield",
    ]

    private static let java: Set<String> = [
        "abstract", "assert", "boolean", "break", "byte", "case", "catch",
        "char", "class", "const", "continue", "default", "do", "double",
        "else", "enum", "extends", "final", "finally", "float", "for",
        "goto", "if", "implements", "import", "instanceof", "int",
        "interface", "long", "native", "new", "null", "package", "private",
        "protected", "public", "return", "short", "static", "strictfp",
        "super", "switch", "synchronized", "this", "throw", "throws",
        "transient", "true", "try", "void", "volatile", "while",
    ]

    private static let c: Set<String> = [
        "auto", "break", "case", "char", "const", "continue", "default",
        "do", "double", "else", "enum", "extern", "float", "for", "goto",
        "if", "int", "long", "register", "return", "short", "signed",
        "sizeof", "static", "struct", "switch", "typedef", "union",
        "unsigned", "void", "volatile", "while",
    ]

    private static let haskell: Set<String> = [
        "case", "class", "data", "default", "deriving", "do", "else",
        "family", "forall", "foreign", "hiding", "if", "import", "in",
        "infix", "infixl", "infixr", "instance", "let", "module", "newtype",
        "of", "qualified", "then", "type", "where", "as",
        // Common types
        "Bool", "Char", "Double", "Either", "Float", "IO", "Int", "Integer",
        "Maybe", "Ordering", "String", "Functor", "Monad", "Applicative",
        "Eq", "Ord", "Show", "Read",
        // Pervasive functions
        "True", "False", "Nothing", "Just", "Left", "Right",
        "map", "filter", "foldr", "foldl", "head", "tail", "length",
        "reverse", "return", "putStrLn", "print", "show", "read",
        "fst", "snd", "concat", "concatMap", "elem", "notElem", "null",
    ]

    private static let bash: Set<String> = [
        "if", "then", "else", "elif", "fi", "case", "esac", "for", "while",
        "until", "do", "done", "in", "function", "return", "break",
        "continue", "exit", "export", "local", "readonly", "declare",
        "unset", "shift", "source", "alias", "trap", "true", "false",
        "echo", "printf", "read", "cd", "pwd", "ls", "mkdir", "rm", "cp",
        "mv", "test", "set", "eval",
    ]

    private static let sql: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE",
        "SET", "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "ADD",
        "COLUMN", "INDEX", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
        "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "FULL", "ON", "AS",
        "AND", "OR", "NOT", "NULL", "IS", "IN", "BETWEEN", "LIKE",
        "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION",
        "DISTINCT", "COUNT", "SUM", "AVG", "MIN", "MAX", "CASE", "WHEN",
        "THEN", "ELSE", "END", "TRUE", "FALSE",
    ]

    private static let lua: Set<String> = [
        "and", "break", "do", "else", "elseif", "end", "false", "for",
        "function", "goto", "if", "in", "local", "nil", "not", "or",
        "repeat", "return", "then", "true", "until", "while",
        "print", "ipairs", "pairs", "tostring", "tonumber", "type",
        "table", "string", "math", "io", "os",
    ]

    private static let elixir: Set<String> = [
        "def", "defp", "defmodule", "defprotocol", "defimpl", "defmacro",
        "defmacrop", "defstruct", "defguard", "defguardp", "do", "end",
        "if", "unless", "else", "case", "cond", "when", "fn", "true",
        "false", "nil", "import", "alias", "require", "use", "with",
        "for", "raise", "throw", "try", "rescue", "catch", "after",
        "receive", "send", "spawn", "Enum", "Map", "List", "String",
        "IO", "GenServer", "Supervisor",
    ]

    private static let html: Set<String> = [
        "div", "span", "section", "article", "header", "footer", "nav",
        "main", "aside", "ul", "ol", "li", "table", "thead", "tbody",
        "tr", "td", "th", "a", "img", "input", "button", "form", "label",
        "select", "option", "textarea", "html", "head", "body", "title",
        "meta", "link", "script", "style",
    ]

    private static let css: Set<String> = [
        "background", "border", "color", "display", "flex", "grid",
        "height", "margin", "padding", "position", "width", "font",
        "font-size", "font-weight", "text-align", "transform", "opacity",
        "overflow", "transition", "animation", "z-index", "cursor",
        "important", "absolute", "relative", "fixed", "static", "sticky",
        "block", "inline", "none", "auto", "hidden", "visible",
    ]
}
