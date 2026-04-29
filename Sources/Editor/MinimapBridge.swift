import SwiftUI

/// Shared state between an `EditorView` (the source of truth for scroll
/// position) and a `MinimapView` (which mirrors that state and can request
/// scroll changes back). Both fractions are in `0...1` of the editor's
/// total content height.
@MainActor
final class MinimapBridge: ObservableObject {
    /// Fraction of the document above the visible viewport's top edge.
    @Published var topFraction: Double = 0

    /// Fraction of the document covered by the visible viewport's height.
    @Published var visibleFraction: Double = 1.0

    /// Closure registered by the main editor's coordinator. Calling it scrolls
    /// the editor so the supplied fraction is the new top of the viewport.
    var scrollMainEditor: ((Double) -> Void)?
}
