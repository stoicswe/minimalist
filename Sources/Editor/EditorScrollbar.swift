import SwiftUI
import AppKit

/// A standalone vertical scrollbar at the far-right of the editor pane.
/// Uses `NSScroller` in `.overlay` / `.small` style for the native thin,
/// translucent look — and adds SwiftUI-driven auto-hide so it fades out
/// when the user isn't scrolling, just like macOS's built-in overlay
/// scrollers in NSScrollView.
struct EditorScrollbar: View {
    @ObservedObject var bridge: MinimapBridge

    @State private var visible: Bool = false
    @State private var hideTask: Task<Void, Never>?

    /// How long to keep the scrollbar visible after the last activity.
    private let inactivityDelay: TimeInterval = 1.2

    var body: some View {
        ScrollerHost(bridge: bridge)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: visible)
            // Keep the area hoverable even while faded out so the user can
            // hover over the right edge to summon the scrollbar.
            .background(Color.clear.contentShape(Rectangle()))
            .onHover { hovering in
                if hovering {
                    cancelHide()
                    visible = true
                } else {
                    scheduleHide()
                }
            }
            .onChange(of: bridge.topFraction) { _, _ in
                visible = true
                scheduleHide()
            }
            .onChange(of: bridge.visibleFraction) { _, _ in
                visible = true
                scheduleHide()
            }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func scheduleHide() {
        cancelHide()
        let delay = inactivityDelay
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled { visible = false }
        }
    }
}

private struct ScrollerHost: NSViewRepresentable {
    @ObservedObject var bridge: MinimapBridge

    func makeNSView(context: Context) -> NSScroller {
        let scroller = NSScroller(frame: NSRect(x: 0, y: 0, width: 11, height: 100))
        scroller.scrollerStyle = .overlay
        scroller.controlSize = .small
        scroller.arrowsPosition = .scrollerArrowsNone
        scroller.target = context.coordinator
        scroller.action = #selector(Coordinator.scrollerAction(_:))
        return scroller
    }

    func updateNSView(_ scroller: NSScroller, context: Context) {
        context.coordinator.bridge = bridge
        guard bridge.visibleFraction.isFinite,
              bridge.topFraction.isFinite else { return }
        let visible = max(0.05, min(1.0, bridge.visibleFraction))
        let top = max(0.0, min(1.0, bridge.topFraction))
        let maxTop = max(0.001, 1.0 - visible)
        let value = min(1.0, max(0.0, top / maxTop))
        guard value.isFinite else { return }
        scroller.knobProportion = CGFloat(visible)
        scroller.doubleValue = value
    }

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    @MainActor
    final class Coordinator: NSObject {
        var bridge: MinimapBridge
        init(bridge: MinimapBridge) { self.bridge = bridge }

        @objc func scrollerAction(_ sender: NSScroller) {
            guard bridge.visibleFraction.isFinite else { return }
            let visible = max(0.05, min(1.0, bridge.visibleFraction))
            let maxTop = max(0.001, 1.0 - visible)
            let topFraction = Double(sender.doubleValue) * maxTop
            guard topFraction.isFinite else { return }
            bridge.scrollMainEditor?(topFraction)
        }
    }
}
