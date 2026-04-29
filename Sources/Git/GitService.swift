import Foundation

/// Thin wrapper around `/usr/bin/git` for the operations the TopBar needs.
/// All calls are synchronous and meant to be invoked off the main thread
/// (see `GitState`).
struct GitService: Sendable {
    let workingDirectory: URL

    enum GitError: Error, LocalizedError {
        case notAGitRepo
        case commandFailed(String)
        var errorDescription: String? {
            switch self {
            case .notAGitRepo: return "This folder is not a git repository."
            case .commandFailed(let stderr): return stderr
            }
        }
    }

    /// Returns the current branch name, or a short SHA when HEAD is detached,
    /// or nil if the folder isn't a git repo.
    func currentBranch() -> String? {
        guard isGitRepo() else { return nil }
        let name = runCapturing(["rev-parse", "--abbrev-ref", "HEAD"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name == nil || name?.isEmpty == true { return nil }
        if name == "HEAD" {
            return runCapturing(["rev-parse", "--short", "HEAD"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name
    }

    func localBranches() -> [String] {
        guard isGitRepo() else { return [] }
        guard let raw = runCapturing(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads/"]
        ) else { return [] }
        return raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func isGitRepo() -> Bool {
        let result = runCapturing(["rev-parse", "--is-inside-work-tree"])
        return result?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    func checkout(_ branch: String) throws {
        try runOrThrow(["checkout", branch])
    }

    func createBranch(_ name: String) throws {
        try runOrThrow(["checkout", "-b", name])
    }

    // MARK: - Private

    private func runCapturing(_ args: [String]) -> String? {
        let process = makeProcess(args)
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
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

    private func runOrThrow(_ args: [String]) throws {
        let process = makeProcess(args)
        let errPipe = Pipe()
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let stderr = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw GitError.commandFailed(stderr.isEmpty ? "git \(args.joined(separator: " ")) exited with status \(process.terminationStatus)" : stderr)
        }
    }

    private func makeProcess(_ args: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = workingDirectory
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = env
        return process
    }
}
