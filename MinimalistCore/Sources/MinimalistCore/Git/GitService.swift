import Foundation

/// Git operations for the TopBar's branch UI, backed by the embedded
/// libgit2 (`GitClient`) — App Sandbox forbids spawning `/usr/bin/git`.
/// All calls are synchronous and meant to be invoked off the main thread
/// (see `GitState`).
public struct GitService: Sendable {
    public let workingDirectory: URL

    public init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    public enum GitError: Error, LocalizedError {
        case notAGitRepo
        case commandFailed(String)
        public var errorDescription: String? {
            switch self {
            case .notAGitRepo: return "This folder is not a git repository."
            case .commandFailed(let message): return message
            }
        }
    }

    /// Returns the current branch name, or a short SHA when HEAD is detached,
    /// or nil if the folder isn't a git repo.
    public func currentBranch() -> String? {
        GitClient.open(containing: workingDirectory)?.currentBranch()
    }

    public func localBranches() -> [String] {
        GitClient.open(containing: workingDirectory)?.localBranches() ?? []
    }

    public func isGitRepo() -> Bool {
        GitClient.open(containing: workingDirectory) != nil
    }

    public func checkout(_ branch: String) throws {
        guard let client = GitClient.open(containing: workingDirectory) else {
            throw GitError.notAGitRepo
        }
        do {
            try client.checkout(branch: branch)
        } catch {
            throw GitError.commandFailed(error.localizedDescription)
        }
    }

    public func createBranch(_ name: String) throws {
        guard let client = GitClient.open(containing: workingDirectory) else {
            throw GitError.notAGitRepo
        }
        do {
            try client.createBranch(named: name)
        } catch {
            throw GitError.commandFailed(error.localizedDescription)
        }
    }
}
