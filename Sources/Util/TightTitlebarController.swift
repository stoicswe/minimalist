import AppKit

/// Configures an `NSWindow` for a tight, custom-header layout, manages the
/// traffic-light button positions across resize/focus changes, and installs
/// a window-level `NSVisualEffectView` to provide desktop blur when the user
/// enables it.
///
/// **Why one window-level VEV instead of per-pane?** A single VEV at the
/// content-view level is the pattern Apple's own apps (Finder, Notes,
/// Music) use. It avoids state thrash from SwiftUI re-creating per-pane
/// representable layers, gives both panes a consistent blur substrate, and
/// makes it trivial to "remove" the blur entirely (for true sharp see-
/// through) just by swapping the contentView back.
final class TightTitlebarController: NSObject {
    static let shared = TightTitlebarController()

    /// Where to plant the close button. The miniaturize and zoom buttons are
    /// laid out 20pt apart from there.
    var trafficLightOrigin = NSPoint(x: 10, y: 7)

    private var observers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    private var visualEffects: [ObjectIdentifier: NSVisualEffectView] = [:]
    private var swiftUIHosts: [ObjectIdentifier: NSView] = [:]

    /// Idempotent. Call from `NSViewRepresentable.updateNSView` once the
    /// hosting `NSView`'s `window` is non-nil. Configures the window and
    /// registers observers; the visual-effect view is installed lazily by
    /// `setWindowBlur` only when the user actually wants Glass mode.
    func attach(to window: NSWindow) {
        let id = ObjectIdentifier(window)
        configure(window)
        repositionButtons(in: window)

        guard observers[id] == nil else { return }

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didEnterFullScreenNotification,
        ]
        let tokens = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.repositionButtons(in: window)
            }
        }
        observers[id] = tokens
    }

    /// Apply the user's blur level. Above the threshold the VEV is installed
    /// (or its material updated); at or below it the VEV is removed entirely
    /// from the view hierarchy so the window can be truly solid — `state =
    /// .inactive` alone leaves residual rendering in the title-bar area.
    func setWindowBlur(_ level: Double, in window: NSWindow) {
        let id = ObjectIdentifier(window)
        if level > 0.02 {
            installOrUpdateBlur(level: level, in: window, id: id)
        } else {
            removeBlur(in: window, id: id)
        }
    }

    private func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // Top of the window doubles as a window-drag region. Buttons are
        // interactive and intercept their own clicks; empty space drags.
        window.isMovableByWindowBackground = true
        // A toolbar forces the titlebar to a minimum height (~38–41pt).
        // We build our own header in SwiftUI, so make sure none is set.
        window.toolbar = nil
        // Required for translucency — keep these even when blur is off so
        // "transparency at blur 0" gives a sharp see-through.
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    private func repositionButtons(in window: NSWindow) {
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in types.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            button.setFrameOrigin(NSPoint(
                x: trafficLightOrigin.x + CGFloat(index) * 20,
                y: trafficLightOrigin.y
            ))
        }
    }

    // MARK: - Window-level blur

    private func installOrUpdateBlur(level: Double, in window: NSWindow, id: ObjectIdentifier) {
        if let vev = visualEffects[id] {
            vev.material = material(for: level)
            vev.state = .followsWindowActiveState
            return
        }
        guard let originalContent = window.contentView,
              !(originalContent is NSVisualEffectView)
        else { return }

        let vev = NSVisualEffectView(frame: originalContent.frame)
        vev.autoresizingMask = [.width, .height]
        vev.material = material(for: level)
        vev.blendingMode = .behindWindow
        vev.state = .followsWindowActiveState

        window.contentView = vev
        originalContent.translatesAutoresizingMaskIntoConstraints = false
        vev.addSubview(originalContent)
        NSLayoutConstraint.activate([
            originalContent.leadingAnchor.constraint(equalTo: vev.leadingAnchor),
            originalContent.trailingAnchor.constraint(equalTo: vev.trailingAnchor),
            originalContent.topAnchor.constraint(equalTo: vev.topAnchor),
            originalContent.bottomAnchor.constraint(equalTo: vev.bottomAnchor),
        ])

        visualEffects[id] = vev
        swiftUIHosts[id] = originalContent
    }

    private func removeBlur(in window: NSWindow, id: ObjectIdentifier) {
        guard let vev = visualEffects[id], let original = swiftUIHosts[id] else { return }

        original.removeFromSuperview()
        original.translatesAutoresizingMaskIntoConstraints = true
        original.autoresizingMask = [.width, .height]
        original.frame = vev.frame
        window.contentView = original

        visualEffects.removeValue(forKey: id)
        swiftUIHosts.removeValue(forKey: id)
    }

    /// Mapping recommended by macOS UI conventions — `.popover` and
    /// `.titlebar` are deliberately avoided because they apply heavy tints
    /// in light mode that wash out the desktop image.
    private func material(for level: Double) -> NSVisualEffectView.Material {
        let v = max(0.0, min(1.0, level))
        if v < 0.25 { return .underWindowBackground }
        if v < 0.50 { return .sidebar }
        if v < 0.75 { return .headerView }
        return .fullScreenUI
    }
}
