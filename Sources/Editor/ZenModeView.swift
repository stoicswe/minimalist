import SwiftUI
import AppKit

/// Distraction-free editor surface — replaces the entire ContentView body
/// when `pref.zenMode` is on. Hides the sidebar, tabs, status pill, and
/// editor overlay buttons. The user reaches the search palette via a
/// double-shift tap.
struct ZenModeView: View {
    @EnvironmentObject var workspace: Workspace
    @StateObject private var minimapBridge = MinimapBridge()

    var body: some View {
        Group {
            if let doc = workspace.activeDocument {
                EditorView(
                    document: doc,
                    workspace: workspace,
                    minimapBridge: minimapBridge,
                    hidesScroller: false
                )
                .id(doc.id)
            } else {
                ZenEmptyState()
            }
        }
    }
}

private struct ZenEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Zen")
                .font(.system(size: 38, weight: .light, design: .serif))
                .foregroundStyle(.secondary)
            Text("Press ⇧⇧ to search.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Double-shift detection

/// Listens for two clean shift taps within ~400ms and fires `onTrigger`.
/// Installed as a `.background` of the zen view so it lives only while
/// zen mode is active.
struct DoubleShiftMonitor: NSViewRepresentable {
    var onTrigger: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.onTrigger = onTrigger
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? MonitorView)?.onTrigger = onTrigger
    }

    final class MonitorView: NSView {
        var onTrigger: (() -> Void)?
        private var monitor: Any?
        private var lastDownAt: TimeInterval = 0
        private var lastUpAt: TimeInterval = 0
        private var shiftCurrentlyDown = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handle(event: event)
                return event
            }
        }

        deinit { removeMonitor() }

        private func removeMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        private func handle(event: NSEvent) {
            // Left shift = 56, right shift = 60.
            guard event.keyCode == 56 || event.keyCode == 60 else { return }

            let clean = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Reject chord presses — only count pure shift events.
            let nowDown = clean.contains(.shift)
            let onlyShiftOrEmpty: Bool = {
                let withoutShift = clean.subtracting(.shift)
                return withoutShift.isEmpty
            }()
            guard onlyShiftOrEmpty else { return }

            let now = event.timestamp

            if nowDown && !shiftCurrentlyDown {
                // Shift just pressed.
                let withinWindow = (now - lastDownAt) < 0.40
                let releasedBetween = lastUpAt > lastDownAt
                if withinWindow && releasedBetween {
                    // Second tap of a tap-tap pair — fire.
                    onTrigger?()
                    lastDownAt = 0
                    lastUpAt = 0
                } else {
                    lastDownAt = now
                }
                shiftCurrentlyDown = true
            } else if !nowDown && shiftCurrentlyDown {
                // Shift just released.
                lastUpAt = now
                shiftCurrentlyDown = false
            }
        }
    }
}
