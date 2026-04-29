import SwiftUI

/// Repository git log for a single file. Read-only view — listing only;
/// the user's repo isn't ours to modify.
struct CommitHistoryView: View {
    let url: URL
    let workspace: Workspace

    @Environment(\.dismiss) private var dismiss
    @State private var commits: [FileCommit] = []
    @State private var selection: FileCommit?
    @State private var diff: String = ""
    @State private var notInRepo: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, idealWidth: 880, minHeight: 460, idealHeight: 560)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Commit History")
                    .font(.headline)
                Text(url.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if notInRepo {
            VStack(spacing: 8) {
                Spacer()
                Text("Not a git repository")
                    .font(.system(size: 13, weight: .medium))
                Text("This folder isn't tracked by git, or git isn't available on the system.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if commits.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Text("No commits touch this file")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                List(commits, selection: $selection) { commit in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.subject)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            Text(commit.shortSha)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(commit.author)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .tag(commit)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 240, idealWidth: 280)
                .onChange(of: selection) { _, _ in loadDiff() }

                ScrollView {
                    if diff.isEmpty {
                        Text("Select a commit to see its diff")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(40)
                    } else {
                        Text(coloredDiff(diff))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
                .frame(minWidth: 360)
                .layoutPriority(1)
            }
        }
    }

    private var footer: some View {
        HStack {
            if notInRepo {
                Text("—")
            } else {
                Text("\(commits.count) commit\(commits.count == 1 ? "" : "s")")
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Loading

    private func load() {
        guard let rootURL = workspace.rootNode?.url else { return }
        let service = GitService(workingDirectory: rootURL)
        guard service.isGitRepo() else {
            notInRepo = true
            return
        }
        let rel = relativePath(of: url, under: rootURL)
        commits = FileCommitLog.fetch(rel: rel, in: rootURL)
        selection = commits.first
        loadDiff()
    }

    private func loadDiff() {
        guard let rootURL = workspace.rootNode?.url, let commit = selection else {
            diff = ""
            return
        }
        let rel = relativePath(of: url, under: rootURL)
        diff = FileCommitLog.diff(sha: commit.sha, rel: rel, in: rootURL) ?? ""
    }

    private func relativePath(of file: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return file.lastPathComponent
    }

    /// Build an attributed string colorizing diff +/- lines without
    /// pulling in a heavy syntax highlighter.
    private func coloredDiff(_ raw: String) -> AttributedString {
        var result = AttributedString()
        for line in raw.components(separatedBy: "\n") {
            var attrLine = AttributedString(line + "\n")
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                attrLine.foregroundColor = .green
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                attrLine.foregroundColor = .red
            } else if line.hasPrefix("@@") {
                attrLine.foregroundColor = .secondary
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") {
                attrLine.foregroundColor = .secondary
            }
            result += attrLine
        }
        return result
    }
}

struct FileCommit: Hashable, Identifiable {
    let sha: String
    let author: String
    let date: Date
    let subject: String
    var id: String { sha }
    var shortSha: String { String(sha.prefix(7)) }
}

enum FileCommitLog {
    static func fetch(rel: String, in workingDir: URL, limit: Int = 200) -> [FileCommit] {
        let raw = run([
            "log", "--pretty=format:%H|%an|%aI|%s", "-n", "\(limit)", "--", rel
        ], in: workingDir)
        guard let raw else { return [] }
        let formatter = ISO8601DateFormatter()
        return raw.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 3)
            guard parts.count == 4 else { return nil }
            return FileCommit(
                sha: String(parts[0]),
                author: String(parts[1]),
                date: formatter.date(from: String(parts[2])) ?? Date(),
                subject: String(parts[3])
            )
        }
    }

    static func diff(sha: String, rel: String, in workingDir: URL) -> String? {
        run(["show", "--no-color", "--pretty=format:%n", sha, "--", rel], in: workingDir)
    }

    private static func run(_ args: [String], in workingDir: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = workingDir
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
