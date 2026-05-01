import Foundation

/// Captured state of a single Minimalist window — the folder it was
/// pointed at (as a security-scoped bookmark) plus the open / active tab
/// paths. Persisted as an array under `PreferenceKeys.savedWindows` so
/// every window is restored on next launch, not just the primary.
struct WindowSnapshot: Codable, Hashable {
    var folderBookmark: Data?
    var openFilePaths: [String]
    var activeFilePath: String?

    static let empty = WindowSnapshot(folderBookmark: nil, openFilePaths: [], activeFilePath: nil)
}

enum SavedWindowsStore {
    static func load() -> [WindowSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: PreferenceKeys.savedWindows) else {
            return []
        }
        return (try? JSONDecoder().decode([WindowSnapshot].self, from: data)) ?? []
    }

    static func save(_ snapshots: [WindowSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: PreferenceKeys.savedWindows)
    }

    /// Read snapshot at `index` if present.
    static func snapshot(at index: Int) -> WindowSnapshot? {
        let all = load()
        guard all.indices.contains(index) else { return nil }
        return all[index]
    }
}
