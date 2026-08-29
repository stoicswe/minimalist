import Foundation

/// Two-track revision history for a workspace, stored in a `.minimal/`
/// folder inside the opened folder. Independent of any git repo the
/// workspace might already be in.
///
/// **Track 1 — Autosaves.** Every text-change debounce snapshots the file
/// to `.minimal/autosave/<relative-path>/<timestampMillis>.snap`. Keeps the
/// last 25 snapshots per file (rolling window).
///
/// **Track 2 — Manual commits.** On ⌘S of an existing file (and on app
/// quit for the session's edited files), the file is mirrored to
/// `.minimal/files/<relative-path>` and a commit is made in a private git
/// repo at `.minimal/files/.git`. No limit on how many commits.
///
/// Both tracks live side-by-side and a unified `revisions(for:)` method
/// merges them by date for the history viewer.
public final class RevisionTracker {
    public let workspaceURL: URL

    /// Hard cap on autosave snapshots per file.
    static let maxAutosavesPerFile = 25

    /// Minimum gap between autosave snapshots for the same file. Combined
    /// with the editor's debounce, this keeps a long typing session from
    /// rolling through the 25-snapshot cap in a few minutes.
    static let minAutosaveInterval: TimeInterval = 60

    private var lastAutosaveAt: [String: Date] = [:]
    private var lastAutosaveContent: [String: Int] = [:]

    public init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
        bootstrapIfNeeded()
    }

    private var minimalDir: URL { workspaceURL.appendingPathComponent(".minimal") }
    private var filesDir: URL { minimalDir.appendingPathComponent("files") }
    private var autosaveDir: URL { minimalDir.appendingPathComponent("autosave") }
    private var gitDir: URL { filesDir.appendingPathComponent(".git") }

    private func bootstrapIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: minimalDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: autosaveDir, withIntermediateDirectories: true)
        // Ensure .minimal/.gitignore so it doesn't trip up the user's repo
        let ignoreURL = minimalDir.appendingPathComponent(".gitignore")
        if !fm.fileExists(atPath: ignoreURL.path) {
            try? "*\n".write(to: ignoreURL, atomically: true, encoding: .utf8)
        }
        if !fm.fileExists(atPath: gitDir.path) {
            // Embedded libgit2 (`GitClient`) rather than /usr/bin/git —
            // the sandbox can't spawn subprocesses. Commit identity is
            // passed per-commit, so no repo config is needed.
            if let repo = try? GitClient.create(at: filesDir) {
                try? repo.commit(
                    message: "Initial",
                    authorName: Self.signatureName,
                    authorEmail: Self.signatureEmail
                )
            }
        }
    }

    /// Identity stamped on every `.minimal` mirror commit.
    private static let signatureName = "Minimalist"
    private static let signatureEmail = "minimalist@local"

    /// The mirror repo, opened exactly at `.minimal/files` — never via
    /// parent search, which could wrongly land on the user's own repo.
    private func mirrorRepo() -> GitClient? {
        GitClient.open(at: filesDir)
    }

    // MARK: - Path helpers

    /// Path of `url` relative to the workspace root, suitable for keying
    /// snapshots and as a git path.
    private func relativePath(for url: URL) -> String? {
        let workspacePath = workspaceURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(workspacePath + "/") else { return nil }
        return String(filePath.dropFirst(workspacePath.count + 1))
    }

    private func autosaveFolder(for relPath: String) -> URL {
        autosaveDir.appendingPathComponent(relPath, isDirectory: true)
    }

    // MARK: - Track 1: autosave snapshots

    /// Drop a timestamped snapshot of the file's current content. Caller is
    /// responsible for invoking this on the appropriate cadence (debounced
    /// in the editor's text-change handler).
    public func recordAutosave(file url: URL, content: String) {
        guard let rel = relativePath(for: url) else { return }

        // Skip if this exact content was just snapshotted — no point
        // recording two identical revisions back-to-back.
        let hash = content.hashValue
        if lastAutosaveContent[rel] == hash { return }

        // Skip if we recorded for this file too recently.
        if let last = lastAutosaveAt[rel],
           Date().timeIntervalSince(last) < Self.minAutosaveInterval {
            return
        }

        let folder = autosaveFolder(for: rel)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let snap = folder.appendingPathComponent("\(timestamp).snap")
        try? content.write(to: snap, atomically: true, encoding: .utf8)

        lastAutosaveAt[rel] = Date()
        lastAutosaveContent[rel] = hash

        pruneAutosaves(in: folder)
    }

    private func pruneAutosaves(in folder: URL) {
        guard let snaps = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ) else { return }
        let sorted = snaps.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for snap in sorted.dropFirst(Self.maxAutosavesPerFile) {
            try? FileManager.default.removeItem(at: snap)
        }
    }

    // MARK: - Track 2: manual commits

    /// Commit the given file's current content into the `.minimal/files`
    /// git repo. The mirror at `files/<relative-path>` is updated first,
    /// then `git add` + `git commit`.
    @discardableResult
    public func commitOnSave(file url: URL, content: String, message: String? = nil) -> Bool {
        guard let rel = relativePath(for: url) else { return false }
        let dest = filesDir.appendingPathComponent(rel)
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: dest, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        guard let repo = mirrorRepo() else { return false }
        // Best-effort, like the old subprocess calls: a failed stage or
        // commit must never disrupt the user's editing flow. The commit
        // always lands even when the content is unchanged — the history
        // entry the user explicitly asked for shouldn't silently vanish
        // (the old `--allow-empty` behavior).
        try? repo.stage(relativePath: rel)
        try? repo.commit(
            message: message ?? "Save \(rel)",
            authorName: Self.signatureName,
            authorEmail: Self.signatureEmail
        )
        return true
    }

    /// Commit a batch of files at once — used at app quit so all the open
    /// dirty docs land as a single "session end" snapshot.
    public func commitSessionEnd(files: [(url: URL, content: String)]) {
        guard !files.isEmpty, let repo = mirrorRepo() else { return }
        for entry in files {
            guard let rel = relativePath(for: entry.url) else { continue }
            let dest = filesDir.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? entry.content.write(to: dest, atomically: true, encoding: .utf8)
            try? repo.stage(relativePath: rel)
        }
        let formatter = ISO8601DateFormatter()
        try? repo.commit(
            message: "Session end \(formatter.string(from: Date()))",
            authorName: Self.signatureName,
            authorEmail: Self.signatureEmail
        )
    }

    // MARK: - Reading history

    /// Combined autosave + commit history for a file, newest first.
    public func revisions(for url: URL) -> [Revision] {
        guard let rel = relativePath(for: url) else { return [] }
        return (autosaves(for: rel) + commits(for: rel))
            .sorted { $0.date > $1.date }
    }

    private func autosaves(for rel: String) -> [Revision] {
        let folder = autosaveFolder(for: rel)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls.compactMap { snap -> Revision? in
            let name = snap.deletingPathExtension().lastPathComponent
            guard let ms = Int(name) else { return nil }
            let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
            return Revision(
                kind: .autosave,
                identifier: snap.path,
                date: date,
                summary: "Autosave"
            )
        }
    }

    private func commits(for rel: String) -> [Revision] {
        guard let repo = mirrorRepo() else { return [] }
        return repo.fileLog(relativePath: rel, limit: 200).map { commit in
            Revision(
                kind: .commit,
                identifier: commit.sha,
                date: commit.date,
                summary: commit.subject
            )
        }
    }

    /// Read the file's content as it existed at a given revision.
    public func content(for revision: Revision, file url: URL) -> String? {
        switch revision.kind {
        case .autosave:
            let snapURL = URL(fileURLWithPath: revision.identifier)
            return try? String(contentsOf: snapURL, encoding: .utf8)
        case .commit:
            guard let rel = relativePath(for: url) else { return nil }
            return mirrorRepo()?.blobContent(commitSHA: revision.identifier, relativePath: rel)
        }
    }

    /// Replace the file on disk with its content at `revision`. The current
    /// content is captured as a fresh autosave first so the revert itself
    /// is undoable from the history viewer.
    @discardableResult
    public func revert(file url: URL, to revision: Revision) -> String? {
        if let current = try? String(contentsOf: url, encoding: .utf8) {
            recordAutosave(file: url, content: current)
        }
        guard let restored = content(for: revision, file: url) else { return nil }
        try? restored.write(to: url, atomically: true, encoding: .utf8)
        return restored
    }

}

/// One entry in a file's history — either an autosave snapshot or a
/// commit in the `.minimal` git mirror.
public struct Revision: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable { case autosave, commit }

    public let kind: Kind
    /// For autosaves: full path to the snapshot file. For commits: the
    /// short SHA used to look the commit up via `git show`.
    public let identifier: String
    public let date: Date
    public let summary: String

    public var id: String { "\(kind)\(identifier)" }
}
