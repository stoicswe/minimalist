import Foundation

/// Backing logic for the double-shift search palette: filename lookup
/// across the workspace, `:line` jumps, and in-file line matches. Pure
/// Foundation so both front ends rank results identically.
public enum WorkspaceSearch {

    /// Directory names never worth walking into.
    private static let skippedDirectories: Set<String> = [
        ".git", ".minimal", ".build", "node_modules", ".venv", "__pycache__",
        ".svn", ".hg", "DerivedData", ".next", ".cache", "target",
    ]

    /// Upper bound on files visited per scan, so a search inside a huge
    /// tree can't stall the UI thread.
    public static let scanCeiling = 20_000

    public struct Match: Hashable, Identifiable, Sendable {
        public enum Kind: Hashable, Sendable {
            case file
            case recent
            /// A line inside the active document (1-based).
            case line(Int)
        }

        public let kind: Kind
        public let url: URL
        /// Primary label — the filename, or the trimmed line text.
        public let title: String
        /// Secondary label — path relative to the workspace root.
        public let subtitle: String

        public var id: String {
            switch kind {
            case .file: "file-\(url.path)"
            case .recent: "recent-\(url.path)"
            case .line(let number): "line-\(url.path)-\(number)"
            }
        }

        public init(kind: Kind, url: URL, title: String, subtitle: String) {
            self.kind = kind
            self.url = url
            self.title = title
            self.subtitle = subtitle
        }
    }

    /// Split `"view.swift:42"` into its query and line number.
    public static func parseQuery(_ raw: String) -> (text: String, line: Int?) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.lastIndex(of: ":") else { return (trimmed, nil) }
        let suffix = trimmed[trimmed.index(after: colon)...]
        guard !suffix.isEmpty, let line = Int(suffix), line > 0 else { return (trimmed, nil) }
        return (String(trimmed[trimmed.startIndex..<colon]), line)
    }

    /// Every file under `root`, skipping hidden entries and build /
    /// dependency directories. Breadth-first so shallow files — the ones
    /// users mean most often — come first and survive the cap.
    public static func files(under root: URL, limit: Int = scanCeiling) -> [URL] {
        var results: [URL] = []
        var queue = [root]
        let manager = FileManager.default
        while !queue.isEmpty, results.count < limit {
            let directory = queue.removeFirst()
            guard let entries = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { continue }
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = entry.lastPathComponent
                if name.hasPrefix(".") || skippedDirectories.contains(name) { continue }
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    queue.append(entry)
                } else {
                    results.append(entry)
                    if results.count >= limit { break }
                }
            }
        }
        return results
    }

    /// Rank `candidates` against `query`: names starting with the query
    /// win, then substring hits, then subsequence ("fzf-style") hits;
    /// shorter names break ties.
    public static func rank(candidates: [URL], query: String, limit: Int = 8) -> [URL] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        var scored: [(url: URL, score: Int)] = []
        for url in candidates {
            let name = url.lastPathComponent.lowercased()
            let score: Int
            if name == needle { score = 0 } else if name.hasPrefix(needle) { score = 1 } else if name.contains(needle) {
                score = 2
            } else if url.path.lowercased().contains(needle) {
                score = 3
            } else if isSubsequence(needle, of: name) {
                score = 4
            } else {
                continue
            }
            scored.append((url, score))
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                let leftName = lhs.url.lastPathComponent
                let rightName = rhs.url.lastPathComponent
                if leftName.count != rightName.count { return leftName.count < rightName.count }
                return leftName < rightName
            }
            .prefix(limit)
            .map(\.url)
    }

    /// Lines in `text` containing `query`, as 1-based (number, trimmed text) pairs.
    public static func lineMatches(query: String, in text: String, limit: Int = 6) -> [(line: Int, text: String)] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        var hits: [(Int, String)] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            guard line.lowercased().contains(needle) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            hits.append((index + 1, trimmed.isEmpty ? "(empty line)" : trimmed))
            if hits.count >= limit { break }
        }
        return hits
    }

    /// `url` written relative to the workspace root, for result subtitles.
    public static func relativePath(of url: URL, root: URL?) -> String {
        guard let root else { return url.path }
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath { return root.lastPathComponent }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        for character in needle {
            var found = false
            while let next = iterator.next() {
                if next == character {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }
}
