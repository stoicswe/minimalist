import Foundation

/// Describes how a Minimalist window should boot up.
///
/// The very first window that the system opens at launch (no associated
/// value) is treated as `.primary` and reads from the persisted-windows
/// list at index 0. Additional persisted windows are restored via
/// `.restore(index:)`. `.fresh(UUID)` is used by ⌘⇧N — the embedded UUID
/// makes each invocation produce a unique value so SwiftUI's WindowGroup
/// doesn't dedupe back onto an existing window.
enum WindowLaunch: Hashable, Codable {
    case primary
    case fresh(UUID)
    case openFile(URL)
    case openFolder(URL)
    case restore(index: Int)

    /// Restored windows from a prior session always come back as a unique
    /// fresh window rather than fighting the primary window for persisted
    /// state. Encode is a no-op for the same reason.
    init(from decoder: any Decoder) throws { self = .fresh(UUID()) }
    func encode(to encoder: any Encoder) throws {}
}
