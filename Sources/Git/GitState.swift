import SwiftUI

/// Observable git state for the currently open workspace folder.
/// Refreshes on demand; cheap enough to call after every checkout.
@MainActor
final class GitState: ObservableObject {
    @Published var isRepo: Bool = false
    @Published var currentBranch: String?
    @Published var branches: [String] = []
    @Published var lastError: String?

    private(set) var folder: URL?

    func refresh(folder: URL?) async {
        self.folder = folder
        guard let folder else {
            isRepo = false
            currentBranch = nil
            branches = []
            return
        }

        let snapshot = await Task.detached(priority: .userInitiated) {
            let service = GitService(workingDirectory: folder)
            let inRepo = service.isGitRepo()
            return (
                isRepo: inRepo,
                branch: inRepo ? service.currentBranch() : nil,
                branches: inRepo ? service.localBranches() : []
            )
        }.value

        self.isRepo = snapshot.isRepo
        self.currentBranch = snapshot.branch
        self.branches = snapshot.branches
    }

    func checkout(_ branch: String) async {
        guard let folder else { return }
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                try GitService(workingDirectory: folder).checkout(branch)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        self.lastError = result
        await refresh(folder: folder)
    }

    func createBranch(_ name: String) async {
        guard let folder else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                try GitService(workingDirectory: folder).createBranch(trimmed)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        self.lastError = result
        await refresh(folder: folder)
    }
}
