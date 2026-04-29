import SwiftUI
import AppKit

/// Transparent NSView that lets the user drag the window when clicking on it.
/// Used in the TopBar and TabBar so the borderless window remains movable.
struct WindowDraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
