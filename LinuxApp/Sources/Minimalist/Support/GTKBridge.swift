import CAdw
import Foundation

/// Thin helpers over the parts of GTK that Adwaita for Swift doesn't wrap
/// yet: raw signal connections with typed arguments, the key and click
/// controllers behind ⇧⇧ and right-click menus, GIO's trash, and CSS for
/// individual widgets. GTK is single-threaded, so everything here is
/// main-thread-only by construction.
enum GTKBridge {

    // MARK: - Signal plumbing

    /// Retains a Swift closure for the lifetime of a GObject signal
    /// connection. `g_signal_connect_data`'s destroy notify releases it.
    private final class Box {
        let handler: Any
        init(_ handler: Any) { self.handler = handler }
    }

    private static let releaseBox: GClosureNotify = { data, _ in
        guard let data else { return }
        Unmanaged<Box>.fromOpaque(data).release()
    }

    /// Install a key controller on `widget` in the capture phase, so the
    /// app sees key presses before the focused text view consumes them.
    /// `handler` returns true to swallow the event.
    ///
    /// - Parameters:
    ///   - onlyModifiers: also fire for bare modifier presses (Shift on
    ///     its own has no keyval otherwise interesting to us — it's what
    ///     the double-shift palette listens for).
    static func onKeyPressed(
        _ widget: OpaquePointer?,
        handler: @escaping (_ keyval: UInt32, _ state: UInt32) -> Bool
    ) {
        guard let widget else { return }
        let controller = gtk_event_controller_key_new()
        gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE)
        gtk_widget_add_controller(widget.cast(), controller)

        let callback: @convention(c) (
            UnsafeMutableRawPointer?, UInt32, UInt32, UInt32, UnsafeMutableRawPointer?
        ) -> Int32 = { _, keyval, _, state, data in
            guard let data,
                  let handler = Unmanaged<Box>.fromOpaque(data).takeUnretainedValue()
                      .handler as? (UInt32, UInt32) -> Bool
            else { return 0 }
            return handler(keyval, state) ? 1 : 0
        }
        connect(
            object: controller,
            signal: "key-pressed",
            callback: unsafeBitCast(callback, to: GCallback.self),
            box: .init(handler)
        )
    }

    /// Fire `handler` when a secondary (right) click lands on `widget`.
    static func onSecondaryClick(_ widget: OpaquePointer?, handler: @escaping () -> Void) {
        guard let widget else { return }
        let gesture = gtk_gesture_click_new()
        gtk_gesture_single_set_button(gesture, 3)
        gtk_event_controller_set_propagation_phase(gesture, GTK_PHASE_BUBBLE)
        gtk_widget_add_controller(widget.cast(), gesture)

        let callback: @convention(c) (
            UnsafeMutableRawPointer?, Int32, Double, Double, UnsafeMutableRawPointer?
        ) -> Void = { _, _, _, _, data in
            guard let data,
                  let handler = Unmanaged<Box>.fromOpaque(data).takeUnretainedValue()
                      .handler as? () -> Void
            else { return }
            handler()
        }
        connect(
            object: gesture,
            signal: "pressed",
            callback: unsafeBitCast(callback, to: GCallback.self),
            box: .init(handler)
        )
    }

    /// Fire `handler` on a double primary click (used to pin preview tabs).
    static func onDoubleClick(_ widget: OpaquePointer?, handler: @escaping () -> Void) {
        guard let widget else { return }
        let gesture = gtk_gesture_click_new()
        gtk_gesture_single_set_button(gesture, 1)
        gtk_event_controller_set_propagation_phase(gesture, GTK_PHASE_BUBBLE)
        gtk_widget_add_controller(widget.cast(), gesture)

        let callback: @convention(c) (
            UnsafeMutableRawPointer?, Int32, Double, Double, UnsafeMutableRawPointer?
        ) -> Void = { _, count, _, _, data in
            guard count == 2, let data,
                  let handler = Unmanaged<Box>.fromOpaque(data).takeUnretainedValue()
                      .handler as? () -> Void
            else { return }
            handler()
        }
        connect(
            object: gesture,
            signal: "pressed",
            callback: unsafeBitCast(callback, to: GCallback.self),
            box: .init(handler)
        )
    }

    private static func connect(
        object: OpaquePointer?,
        signal: String,
        callback: GCallback,
        box: Box
    ) {
        g_signal_connect_data(
            object.map { UnsafeMutableRawPointer($0) },
            signal,
            callback,
            Unmanaged.passRetained(box).toOpaque(),
            releaseBox,
            GConnectFlags(rawValue: 0)
        )
    }

    // MARK: - Widget helpers

    /// The window a widget currently lives in, or nil before it's mapped.
    static func root(of widget: OpaquePointer?) -> OpaquePointer? {
        guard let widget, let root = gtk_widget_get_root(widget.cast()) else { return nil }
        return root
    }

    /// Whether Pango can parse this markup. The reader view renders
    /// generated markup, and one unbalanced tag would make GtkLabel drop
    /// the whole document — so it checks first and falls back to plain
    /// text.
    static func isValidMarkup(_ markup: String) -> Bool {
        var error: UnsafeMutablePointer<GError>?
        let valid = pango_parse_markup(markup, -1, 0, nil, nil, nil, &error) != 0
        if let error { g_error_free(error) }
        return valid
    }

    // MARK: - Files

    /// Move a file or folder to the desktop trash (GIO — the same place
    /// Nautilus puts it). Returns false when the file system has no trash
    /// (e.g. some mounts), leaving the caller to report it.
    static func moveToTrash(_ url: URL) -> Bool {
        let file = g_file_new_for_path(url.path)
        defer { file.map { g_object_unref(UnsafeMutableRawPointer($0)) } }
        var error: UnsafeMutablePointer<GError>?
        let ok = g_file_trash(file, nil, &error)
        if let error {
            g_error_free(error)
        }
        return ok != 0
    }

    /// Hand a URI to the desktop (used by the markdown reader's links).
    static func openURI(_ uri: String) {
        let launcher = gtk_uri_launcher_new(uri)
        gtk_uri_launcher_launch(launcher, nil, nil, nil, nil)
        launcher.map { g_object_unref(UnsafeMutableRawPointer($0)) }
    }
}
