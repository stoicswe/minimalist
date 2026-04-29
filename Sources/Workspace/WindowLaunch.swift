import Foundation

/// Describes how a Minimalist window should boot up.
///
/// The very first window that the system opens at launch (no associated
/// value) is treated as `.primary` and is the only one that reads or
/// writes the persisted last-folder / open-files state. All other windows
/// — opened via `⌘⇧N`, "Open in New Window", etc. — are transient and do
/// not touch persisted state.
enum WindowLaunch: Hashable, Codable {
    case primary
    case fresh
    case openFile(URL)
    case openFolder(URL)

    /// Restored windows from a prior session always come back empty rather
    /// than fighting the primary window for the persisted state. Encode is
    /// a no-op for the same reason.
    init(from decoder: any Decoder) throws { self = .fresh }
    func encode(to encoder: any Encoder) throws {}
}
