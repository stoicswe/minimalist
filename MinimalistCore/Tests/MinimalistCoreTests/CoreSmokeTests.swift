import Foundation
import Testing
@testable import MinimalistCore

/// Cross-platform smoke tests — the same suite runs on macOS and Linux,
/// exercising the pieces most likely to differ between platforms
/// (libgit2 linkage, file-system behavior).

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MinimalistCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct GitClientTests {

    @Test func createCommitLogRoundtrip() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let repo = try GitClient.create(at: dir)
        // Fresh repo: unborn HEAD, no branch yet.
        #expect(repo.currentBranch() == nil)

        let file = dir.appendingPathComponent("hello.txt")
        try "one\n".write(to: file, atomically: true, encoding: .utf8)
        try repo.stage(relativePath: "hello.txt")
        try repo.commit(message: "first", authorName: "Test", authorEmail: "test@local")

        #expect(repo.currentBranch() != nil)
        let log = repo.fileLog(relativePath: "hello.txt", limit: 10)
        #expect(log.count == 1)
        #expect(log.first?.subject == "first")

        // Second commit changes the blob; history and content lookup.
        try "one\ntwo\n".write(to: file, atomically: true, encoding: .utf8)
        try repo.stage(relativePath: "hello.txt")
        try repo.commit(message: "second", authorName: "Test", authorEmail: "test@local")

        let log2 = repo.fileLog(relativePath: "hello.txt", limit: 10)
        #expect(log2.count == 2)
        #expect(log2.first?.subject == "second")

        let oldSHA = try #require(log2.last?.sha)
        #expect(repo.blobContent(commitSHA: oldSHA, relativePath: "hello.txt") == "one\n")

        let patch = repo.patch(commitSHA: log2.first?.sha ?? "", relativePath: "hello.txt")
        #expect(patch?.contains("+two") == true)
    }

    @Test func branchesAndCheckout() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let repo = try GitClient.create(at: dir)
        let file = dir.appendingPathComponent("a.txt")
        try "a\n".write(to: file, atomically: true, encoding: .utf8)
        try repo.stage(relativePath: "a.txt")
        try repo.commit(message: "init", authorName: "Test", authorEmail: "test@local")

        let main = try #require(repo.currentBranch())
        try repo.createBranch(named: "feature")
        #expect(repo.currentBranch() == "feature")
        #expect(Set(repo.localBranches()).isSuperset(of: [main, "feature"]))

        try repo.checkout(branch: main)
        #expect(repo.currentBranch() == main)
    }

    @Test func openContainingSearchesParents() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try GitClient.create(at: dir)
        let nested = dir.appendingPathComponent("deep/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        #expect(GitClient.open(containing: nested) != nil)
        #expect(GitClient.open(at: nested) == nil)
    }
}

@Suite struct RevisionTrackerTests {

    @Test func autosaveAndCommitTracks() throws {
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("notes.md")
        try "draft\n".write(to: file, atomically: true, encoding: .utf8)

        let tracker = RevisionTracker(workspaceURL: workspace)
        tracker.recordAutosave(file: file, content: "draft\n")
        #expect(tracker.commitOnSave(file: file, content: "draft v2\n"))

        let revisions = tracker.revisions(for: file)
        #expect(revisions.contains { $0.kind == .autosave })
        #expect(revisions.contains { $0.kind == .commit })

        let commit = try #require(revisions.first { $0.kind == .commit })
        #expect(tracker.content(for: commit, file: file) == "draft v2\n")

        // The mirror repo must live in .minimal, hidden from the tree.
        #expect(FileManager.default.fileExists(
            atPath: workspace.appendingPathComponent(".minimal/files/.git").path
        ))
    }
}

@Suite struct TextModelTests {

    @Test func lineEndingDetectAndNormalize() {
        #expect(LineEnding.detect(in: "a\r\nb") == .crlf)
        #expect(LineEnding.detect(in: "a\rb") == .cr)
        #expect(LineEnding.detect(in: "a\nb") == .lf)
        #expect(LineEnding.crlf.normalize("a\nb") == "a\r\nb")
        #expect(LineEnding.lf.normalize("a\r\nb\rc") == "a\nb\nc")
    }

    @Test func indentationDetect() {
        #expect(Indentation.detect(in: "if x {\n\tfoo()\n}")?.kind == .tabs)
        let spaces = Indentation.detect(in: "if x {\n    foo()\n    bar()\n}")
        #expect(spaces?.kind == .spaces)
        #expect(spaces?.width == 4)
        #expect(Indentation.detect(in: "flat\nlines") == nil)
    }

    @Test func languageDetection() {
        #expect(LanguageDetector.language(for: URL(fileURLWithPath: "/x/main.swift")) == "swift")
        #expect(LanguageDetector.language(for: URL(fileURLWithPath: "/x/Dockerfile")) == "dockerfile")
        #expect(LanguageDetector.language(for: URL(fileURLWithPath: "/x/data.unknownext")) == "plaintext")
    }

    @Test func completionSuggestsIdentifiersFromDocument() {
        let suffix = CompletionEngine.suggest(
            prefix: "work",
            in: "let workspaceRoot = 1\nworkspaceRoot += 1",
            language: "swift"
        )
        #expect(suffix == "spaceRoot")
        #expect(CompletionEngine.suggest(prefix: "w", in: "whatever", language: "swift") == nil)
    }
}

@Suite struct DocumentTests {

    @Test @MainActor func saveNormalizesLineEndings() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("doc.txt")
        try "a\nb\n".write(to: url, atomically: true, encoding: .utf8)

        let doc = try #require(Document(url: url))
        #expect(doc.kind == .text)
        #expect(!doc.isDirty)

        doc.text = "a\nb\nc\n"
        #expect(doc.isDirty)
        doc.lineEnding = .crlf
        try doc.save()
        #expect(!doc.isDirty)

        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == "a\r\nb\r\nc\r\n")
    }
}

@Suite struct FileOpsTests {

    @Test func createRenameDuplicateMove() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = try FileOps.createFile(named: "notes.txt", in: dir)
        #expect(FileManager.default.fileExists(atPath: file.path))

        // A second file with the same name is refused, not silently overwritten.
        #expect(throws: FileOps.OpError.self) {
            try FileOps.createFile(named: "notes.txt", in: dir)
        }

        let renamed = try FileOps.rename(file, to: "todo.txt")
        #expect(renamed.lastPathComponent == "todo.txt")
        #expect(!FileManager.default.fileExists(atPath: file.path))

        let copy = try FileOps.duplicate(renamed)
        #expect(copy.lastPathComponent == "todo copy.txt")
        let secondCopy = try FileOps.duplicate(renamed)
        #expect(secondCopy.lastPathComponent == "todo copy 2.txt")

        let folder = try FileOps.createFolder(named: "sub", in: dir)
        let moved = try FileOps.move(renamed, into: folder)
        #expect(moved.path == folder.appendingPathComponent("todo.txt").path)
        // Moving into the folder it already lives in is a no-op.
        #expect(try FileOps.move(moved, into: folder).path == moved.path)
        // A folder can't be moved inside itself.
        #expect(throws: FileOps.OpError.self) {
            try FileOps.move(folder, into: folder)
        }
    }
}

@Suite struct FileTypeBadgeTests {

    @Test func badgesResolveByNameThenExtension() {
        #expect(FileTypeBadge.badge(forName: "Package.swift").letter == "SW")
        #expect(FileTypeBadge.badge(forName: "main.swift").letter == "SW")
        #expect(FileTypeBadge.badge(forName: "README.md").letter == "RM")
        #expect(FileTypeBadge.badge(forName: "guide.md").letter == "MD")
        // Unknown extensions fall back to a two-letter grey chip.
        #expect(FileTypeBadge.badge(forName: "archive.qqq").letter == "QQ")
        #expect(FileTypeBadge.badge(forName: "noextension").letter == "")
        #expect(FileTypeBadge.badge(forName: "main.swift").hex == "#ce6e54")
    }
}

@Suite struct WorkspaceSearchTests {

    @Test func parsesLineSuffixAndRanksNames() throws {
        #expect(WorkspaceSearch.parseQuery("view.swift:42").line == 42)
        #expect(WorkspaceSearch.parseQuery("view.swift:42").text == "view.swift")
        #expect(WorkspaceSearch.parseQuery("view.swift").line == nil)
        // A trailing colon without digits isn't a line jump.
        #expect(WorkspaceSearch.parseQuery("http://x").line == nil)

        let urls = [
            URL(fileURLWithPath: "/w/MainView.swift"),
            URL(fileURLWithPath: "/w/View.swift"),
            URL(fileURLWithPath: "/w/deep/nested/other.txt"),
        ]
        let ranked = WorkspaceSearch.rank(candidates: urls, query: "view")
        #expect(ranked.first?.lastPathComponent == "View.swift")
        #expect(ranked.count == 2)
    }

    @Test func skipsHiddenAndBuildDirectories() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("node_modules"),
            withIntermediateDirectories: true
        )
        try "x".write(
            to: dir.appendingPathComponent("node_modules/dep.js"),
            atomically: true,
            encoding: .utf8
        )
        try "x".write(to: dir.appendingPathComponent("app.swift"), atomically: true, encoding: .utf8)

        let files = WorkspaceSearch.files(under: dir)
        #expect(files.map(\.lastPathComponent) == ["app.swift"])

        let hits = WorkspaceSearch.lineMatches(query: "beta", in: "alpha\nbeta\ngamma\n")
        #expect(hits.count == 1)
        #expect(hits.first?.line == 2)
    }
}

@Suite struct HexDumpTests {

    @Test func formatsOffsetsHexAndAscii() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("blob.bin")
        try Data([0x7F, 0x45, 0x4C, 0x46, 0x41, 0x00]).write(to: url)

        let result = HexDump.dump(url: url)
        #expect(!result.truncated)
        #expect(result.totalSize == 6)
        let line = try #require(result.text.components(separatedBy: "\n").first)
        #expect(line.hasPrefix("00000000"))
        #expect(line.contains("7f 45 4c 46 41 00"))
        // Non-printable bytes render as dots in the ASCII column.
        #expect(line.hasSuffix(".ELFA."))
        #expect(HexDump.magic(url: url) == "ELF")
        #expect(HexDump.byteCount(2_048) == "2.0 KB")
    }
}
