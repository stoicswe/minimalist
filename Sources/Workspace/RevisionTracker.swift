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
final class RevisionTracker {
    let workspaceURL: URL

    /// Hard cap on autosave snapshots per file.
    static let maxAutosavesPerFile = 25

    /// Minimum gap between autosave snapshots for the same file. Combined
    /// with the editor's debounce, this keeps a long typing session from
    /// rolling through the 25-snapshot cap in a few minutes.
    static let minAutosaveInterval: TimeInterval = 60

    private var lastAutosaveAt: [String: Date] = [:]
    private var lastAutosaveContent: [String: Int] = [:]

    init(workspaceURL: URL) {
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
            runGit(["init", "-q"])
            runGit(["config", "user.name", "Minimalist"])
            runGit(["config", "user.email", "minimalist@local"])
            runGit(["commit", "--allow-empty", "-q", "-m", "Initial"])
        }
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
    func recordAutosave(file url: URL, content: String) {
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
    func commitOnSave(file url: URL, content: String, message: String? = nil) -> Bool {
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
        let escaped = rel.replacingOccurrences(of: "\"", with: "\\\"")
        runGit(["add", "--", rel])
        let msg = message ?? "Save \(escaped)"
        // `--allow-empty` because if the user saves with no changes the
        // git commit would otherwise fail and we'd silently lose the
        // history entry the user explicitly asked for.
        runGit(["commit", "-q", "--allow-empty", "-m", msg])
        return true
    }

    /// Commit a batch of files at once — used at app quit so all the open
    /// dirty docs land as a single "session end" snapshot.
    func commitSessionEnd(files: [(url: URL, content: String)]) {
        guard !files.isEmpty else { return }
        for entry in files {
            guard let rel = relativePath(for: entry.url) else { continue }
            let dest = filesDir.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? entry.content.write(to: dest, atomically: true, encoding: .utf8)
            runGit(["add", "--", rel])
        }
        let formatter = ISO8601DateFormatter()
        runGit(["commit", "-q", "--allow-empty", "-m", "Session end \(formatter.string(from: Date()))"])
    }

    // MARK: - Reading history

    /// Combined autosave + commit history for a file, newest first.
    func revisions(for url: URL) -> [Revision] {
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
        guard let raw = runGitCapturing([
            "log",
            "--pretty=format:%H|%aI|%s",
            "-n", "200",
            "--", rel,
        ]) else { return [] }
        return raw.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3 else { return nil }
            let date = ISO8601DateFormatter().date(from: String(parts[1])) ?? Date()
            return Revision(
                kind: .commit,
                identifier: String(parts[0]),
                date: date,
                summary: String(parts[2])
            )
        }
    }

    /// Read the file's content as it existed at a given revision.
    func content(for revision: Revision, file url: URL) -> String? {
        switch revision.kind {
        case .autosave:
            let snapURL = URL(fileURLWithPath: revision.identifier)
            return try? String(contentsOf: snapURL, encoding: .utf8)
        case .commit:
            guard let rel = relativePath(for: url) else { return nil }
            return runGitCapturing(["show", "\(revision.identifier):\(rel)"])
        }
    }

    /// Replace the file on disk with its content at `revision`. The current
    /// content is captured as a fresh autosave first so the revert itself
    /// is undoable from the history viewer.
    @discardableResult
    func revert(file url: URL, to revision: Revision) -> String? {
        if let current = try? String(contentsOf: url, encoding: .utf8) {
            recordAutosave(file: url, content: current)
        }
        guard let restored = content(for: revision, file: url) else { return nil }
        try? restored.write(to: url, atomically: true, encoding: .utf8)
        return restored
    }

    // MARK: - Git helpers

    private func runGit(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = filesDir
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Swallow — `.minimal` tracking is best-effort and shouldn't
            // disrupt the user's editing flow.
        }
    }

    private func runGitCapturing(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = filesDir
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

/// One entry in a file's history — either an autosave snapshot or a
/// commit in the `.minimal` git mirror.
struct Revision: Hashable, Identifiable {
    enum Kind: Hashable { case autosave, commit }

    let kind: Kind
    /// For autosaves: full path to the snapshot file. For commits: the
    /// short SHA used to look the commit up via `git show`.
    let identifier: String
    let date: Date
    let summary: String

    var id: String { "\(kind)\(identifier)" }
}
