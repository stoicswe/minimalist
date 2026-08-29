import Adwaita
import CAdw
import CCodeEditor
import Foundation

/// The editor pane: a `GtkSourceView` in a scrolled window, with
/// `GtkSourceMap` docked at its trailing edge as the minimap — GNOME's
/// equivalent of the macOS app's custom minimap + external scrollbar.
///
/// The upstream `CodeEditor` widget covers only text + line numbers, so
/// this talks to GtkSourceView directly. It keeps **one buffer per open
/// document**, swapping the view's buffer on tab changes, which preserves
/// each tab's undo history, cursor, and scroll position the way the macOS
/// app's per-document `NSTextView` state does.
struct SourceEditor: AdwaitaWidget {

    /// Text of the *active* document. Edits flow back through the binding.
    @Binding var text: String
    /// Identity of the active document (its path). Switching this swaps
    /// buffers rather than replacing the text in place.
    var documentID: String
    /// Every open document, so buffers for closed tabs can be released.
    var liveIDs: Set<String>

    /// GtkSourceView language id, or nil for plain text.
    var language: String?
    /// GtkSourceView style scheme ids for light and dark appearance —
    /// the counterparts of the macOS app's two syntax-theme pickers.
    var lightScheme = "Adwaita"
    var darkScheme = "Adwaita-dark"
    var showLineNumbers = true
    var showMinimap = true
    var wordWrap = false
    var highlightCurrentLine = true
    var tabWidth = 4
    var insertSpaces = true
    var completionEnabled = true
    /// Extra completion words beyond the ones in the document — the
    /// active language's keywords, from `MinimalistCore`.
    var keywords: [String] = []
    /// A one-shot scroll request: `token` changes when a new jump is
    /// asked for (the search palette's `:line` jumps).
    var scrollLine: Int?
    var scrollToken = 0
    /// Editor background preset: nil (theme default), "sepia", "dark", "white".
    var background: String?

    private static let viewKey = "source-view"
    private static let mapKey = "source-map"
    private static let buffersKey = "buffers"
    private static let scrollKey = "scroll-offsets"
    private static let currentKey = "current-document"
    private static let tokenKey = "scroll-token"
    private static let wordsKey = "completion-words"
    private static let keywordsKey = "completion-keywords"
    private static let keywordBufferKey = "keyword-buffer"
    private static let keywordSignatureKey = "keyword-signature"

    init(text: Binding<String>, documentID: String, liveIDs: Set<String>) {
        self._text = text
        self.documentID = documentID
        self.liveIDs = liveIDs
    }

    // MARK: - Widget lifecycle

    func container<Data>(data: WidgetData, type: Data.Type) -> ViewStorage where Data: ViewRenderData {
        let box = gtk_box_new(.GTK_ORIENTATION_HORIZONTAL, 0)
        let scroller = gtk_scrolled_window_new()
        let view = gtk_source_view_new()
        let map = gtk_source_map_new()

        gtk_widget_set_hexpand(scroller, 1)
        gtk_widget_set_vexpand(scroller, 1)
        gtk_scrolled_window_set_child(scroller?.opaque(), view)
        gtk_box_append(box?.cast(), scroller)
        gtk_box_append(box?.cast(), map)
        gtk_source_map_set_view(map?.cast(), view?.cast())

        gtk_text_view_set_monospace(view?.cast(), 1)
        gtk_widget_add_css_class(view, "editor-view")
        gtk_widget_add_css_class(map, "editor-map")

        let storage = ViewStorage(box?.opaque())
        storage.content[Self.viewKey] = [ViewStorage(view?.opaque())]
        storage.content[Self.mapKey] = [ViewStorage(map?.opaque())]
        storage.fields[Self.buffersKey] = [String: ViewStorage]()
        storage.fields[Self.scrollKey] = [String: Double]()

        if completionEnabled, let completion = gtk_source_view_get_completion(view?.cast()) {
            let words = gtk_source_completion_words_new("Document")
            gtk_source_completion_add_provider(completion, words?.opaque())
            storage.fields[Self.wordsKey] = ViewStorage(words?.opaque())

            // The language's keywords come from MinimalistCore. GtkSource
            // only harvests words from buffers, so they live in a hidden
            // scratch buffer registered with a second provider.
            let keywords = gtk_source_completion_words_new("Keywords")
            let keywordBuffer = gtk_source_buffer_new(nil)
            keywordBuffer.map { g_object_ref(UnsafeMutableRawPointer($0)) }
            gtk_source_completion_words_register(keywords, keywordBuffer?.cast())
            gtk_source_completion_add_provider(completion, keywords?.opaque())
            storage.fields[Self.keywordsKey] = ViewStorage(keywords?.opaque())
            storage.fields[Self.keywordBufferKey] = ViewStorage(keywordBuffer?.opaque())
        }

        update(storage, data: data, updateProperties: true, type: type)
        return storage
    }

    func update<Data>(
        _ storage: ViewStorage,
        data: WidgetData,
        updateProperties: Bool,
        type: Data.Type
    ) where Data: ViewRenderData {
        guard let view = storage.content[Self.viewKey]?.first else { return }
        let buffer = buffer(for: documentID, in: storage, view: view)

        // Text in / out. Setting the buffer emits "changed", so only push
        // when the two sides actually differ.
        buffer.connectSignal(name: "changed") {
            let current = Self.text(of: buffer)
            if self.text != current { self.text = current }
        }
        if updateProperties, Self.text(of: buffer) != text {
            gtk_text_buffer_set_text(buffer.opaquePointer?.cast(), text, -1)
        }

        guard updateProperties else { return }

        applyLanguage(to: buffer)
        applyScheme(to: buffer, storage: storage)
        applyViewProperties(view: view, storage: storage)
        applyScroll(view: view, storage: storage)
        applyKeywords(storage: storage)
        pruneBuffers(in: storage)
    }

    // MARK: - Buffers

    /// The buffer backing `id`, creating it (and attaching it to the view
    /// on a tab switch) as needed.
    private func buffer(for id: String, in storage: ViewStorage, view: ViewStorage) -> ViewStorage {
        var buffers = storage.fields[Self.buffersKey] as? [String: ViewStorage] ?? [:]
        let existing = buffers[id]
        let buffer: ViewStorage
        if let existing {
            buffer = existing
        } else {
            let pointer = gtk_source_buffer_new(nil)
            // The view holds only the buffer it currently shows; keep our
            // own reference so background tabs' buffers stay alive.
            pointer.map { g_object_ref(UnsafeMutableRawPointer($0)) }
            gtk_text_buffer_set_enable_undo(pointer?.cast(), 1)
            buffer = ViewStorage(pointer?.opaque())
            buffers[id] = buffer
            storage.fields[Self.buffersKey] = buffers
            if let words = storage.fields[Self.wordsKey] as? ViewStorage {
                gtk_source_completion_words_register(words.opaquePointer?.cast(), pointer?.cast())
            }
        }

        let previous = storage.fields[Self.currentKey] as? String
        if previous != id {
            if let previous {
                rememberScroll(for: previous, view: view, storage: storage)
            }
            gtk_text_view_set_buffer(view.opaquePointer?.cast(), buffer.opaquePointer?.cast())
            storage.fields[Self.currentKey] = id
            restoreScroll(for: id, view: view, storage: storage)
        }
        return buffer
    }

    /// Release buffers for documents whose tabs have been closed.
    private func pruneBuffers(in storage: ViewStorage) {
        guard var buffers = storage.fields[Self.buffersKey] as? [String: ViewStorage] else { return }
        var offsets = storage.fields[Self.scrollKey] as? [String: Double] ?? [:]
        var changed = false
        for (id, buffer) in buffers where !liveIDs.contains(id) {
            if let words = storage.fields[Self.wordsKey] as? ViewStorage {
                gtk_source_completion_words_unregister(
                    words.opaquePointer?.cast(),
                    buffer.opaquePointer?.cast()
                )
            }
            g_object_unref(buffer.opaquePointer.map { UnsafeMutableRawPointer($0) })
            buffers.removeValue(forKey: id)
            offsets.removeValue(forKey: id)
            changed = true
        }
        if changed {
            storage.fields[Self.buffersKey] = buffers
            storage.fields[Self.scrollKey] = offsets
        }
    }

    private static func text(of buffer: ViewStorage) -> String {
        let start = UnsafeMutablePointer<GtkTextIter>.allocate(capacity: 1)
        let end = UnsafeMutablePointer<GtkTextIter>.allocate(capacity: 1)
        defer {
            start.deallocate()
            end.deallocate()
        }
        gtk_text_buffer_get_start_iter(buffer.opaquePointer?.cast(), start)
        gtk_text_buffer_get_end_iter(buffer.opaquePointer?.cast(), end)
        guard let raw = gtk_text_buffer_get_text(buffer.opaquePointer?.cast(), start, end, 1) else {
            return ""
        }
        defer { g_free(raw) }
        return String(cString: raw)
    }

    // MARK: - Properties

    private func applyLanguage(to buffer: ViewStorage) {
        let manager = gtk_source_language_manager_get_default()
        let resolved = language.flatMap { gtk_source_language_manager_get_language(manager, $0) }
        gtk_source_buffer_set_language(buffer.opaquePointer?.cast(), resolved)
        gtk_source_buffer_set_highlight_syntax(buffer.opaquePointer?.cast(), resolved == nil ? 0 : 1)
    }

    private func applyScheme(to buffer: ViewStorage, storage: ViewStorage) {
        let manager = gtk_source_style_scheme_manager_get_default()
        let dark = adw_style_manager_get_dark(adw_style_manager_get_default()) != 0
        let name = dark ? darkScheme : lightScheme
        let scheme = gtk_source_style_scheme_manager_get_scheme(manager, name)
            ?? gtk_source_style_scheme_manager_get_scheme(manager, dark ? "Adwaita-dark" : "Adwaita")
        gtk_source_buffer_set_style_scheme(buffer.opaquePointer?.cast(), scheme)

        // Re-apply when the system (or the app's own preference) flips
        // between light and dark — the scheme is chosen, not inherited.
        if let manager = adw_style_manager_get_default() {
            storage.notify(name: "dark", id: "scheme", pointer: manager) {
                if let current = storage.fields[Self.currentKey] as? String,
                   let buffers = storage.fields[Self.buffersKey] as? [String: ViewStorage],
                   let active = buffers[current] {
                    self.applyScheme(to: active, storage: storage)
                }
            }
        }
    }

    private func applyViewProperties(view: ViewStorage, storage: ViewStorage) {
        let pointer: UnsafeMutablePointer<GtkSourceView>? = view.opaquePointer?.cast()
        gtk_source_view_set_show_line_numbers(pointer, showLineNumbers.cBool)
        gtk_source_view_set_highlight_current_line(pointer, highlightCurrentLine.cBool)
        gtk_source_view_set_tab_width(pointer, UInt32(max(1, tabWidth)))
        gtk_source_view_set_indent_width(pointer, Int32(max(1, tabWidth)))
        gtk_source_view_set_insert_spaces_instead_of_tabs(pointer, insertSpaces.cBool)
        gtk_source_view_set_auto_indent(pointer, 1)
        gtk_source_view_set_smart_backspace(pointer, 1)
        gtk_text_view_set_wrap_mode(
            view.opaquePointer?.cast(),
            wordWrap ? .GTK_WRAP_WORD_CHAR : .GTK_WRAP_NONE
        )
        gtk_text_view_set_left_margin(view.opaquePointer?.cast(), 12)
        gtk_text_view_set_right_margin(view.opaquePointer?.cast(), 12)
        gtk_text_view_set_top_margin(view.opaquePointer?.cast(), 10)
        gtk_text_view_set_bottom_margin(view.opaquePointer?.cast(), 24)

        for preset in ["sepia", "dark", "white"] {
            let className = "editor-bg-\(preset)"
            if background == preset {
                gtk_widget_add_css_class(view.opaquePointer?.cast(), className)
            } else {
                gtk_widget_remove_css_class(view.opaquePointer?.cast(), className)
            }
        }

        if let map = storage.content[Self.mapKey]?.first {
            gtk_widget_set_visible(map.opaquePointer?.cast(), showMinimap.cBool)
        }
    }

    /// Refill the keyword scratch buffer when the language changes.
    private func applyKeywords(storage: ViewStorage) {
        guard let buffer = storage.fields[Self.keywordBufferKey] as? ViewStorage else { return }
        let signature = keywords.isEmpty ? "" : (language ?? "") + "#" + String(keywords.count)
        guard storage.fields[Self.keywordSignatureKey] as? String != signature else { return }
        storage.fields[Self.keywordSignatureKey] = signature
        let text = keywords.sorted().joined(separator: "\n")
        gtk_text_buffer_set_text(buffer.opaquePointer?.cast(), text, -1)
    }

    // MARK: - Scrolling

    private func applyScroll(view: ViewStorage, storage: ViewStorage) {
        guard let line = scrollLine,
              (storage.fields[Self.tokenKey] as? Int ?? -1) != scrollToken
        else { return }
        storage.fields[Self.tokenKey] = scrollToken
        let iter = UnsafeMutablePointer<GtkTextIter>.allocate(capacity: 1)
        defer { iter.deallocate() }
        guard let buffer = gtk_text_view_get_buffer(view.opaquePointer?.cast()) else { return }
        gtk_text_buffer_get_iter_at_line(buffer, iter, Int32(max(0, line - 1)))
        gtk_text_buffer_place_cursor(buffer, iter)
        gtk_text_view_scroll_to_iter(view.opaquePointer?.cast(), iter, 0.1, 1, 0, 0.3)
        gtk_widget_grab_focus(view.opaquePointer?.cast())
    }

    private func rememberScroll(for id: String, view: ViewStorage, storage: ViewStorage) {
        guard let adjustment = gtk_scrollable_get_vadjustment(view.opaquePointer) else { return }
        var offsets = storage.fields[Self.scrollKey] as? [String: Double] ?? [:]
        offsets[id] = gtk_adjustment_get_value(adjustment)
        storage.fields[Self.scrollKey] = offsets
    }

    private func restoreScroll(for id: String, view: ViewStorage, storage: ViewStorage) {
        guard let offsets = storage.fields[Self.scrollKey] as? [String: Double],
              let value = offsets[id],
              let adjustment = gtk_scrollable_get_vadjustment(view.opaquePointer)
        else { return }
        // The new buffer hasn't been laid out yet; set the offset once GTK
        // has measured it.
        Idle {
            gtk_adjustment_set_value(adjustment, value)
        }
    }

    // MARK: - Modifiers

    func language(_ language: String?) -> Self {
        modified { $0.language = language }
    }

    func schemes(light: String, dark: String) -> Self {
        modified {
            $0.lightScheme = light
            $0.darkScheme = dark
        }
    }

    func highlightCurrentLine(_ highlight: Bool) -> Self {
        modified { $0.highlightCurrentLine = highlight }
    }

    func lineNumbers(_ visible: Bool) -> Self {
        modified { $0.showLineNumbers = visible }
    }

    func minimap(_ visible: Bool) -> Self {
        modified { $0.showMinimap = visible }
    }

    func wordWrap(_ wrap: Bool) -> Self {
        modified { $0.wordWrap = wrap }
    }

    func indentation(width: Int, spaces: Bool) -> Self {
        modified {
            $0.tabWidth = width
            $0.insertSpaces = spaces
        }
    }

    func completion(_ enabled: Bool, keywords: [String] = []) -> Self {
        modified {
            $0.completionEnabled = enabled
            $0.keywords = keywords
        }
    }

    func scroll(to line: Int?, token: Int) -> Self {
        modified {
            $0.scrollLine = line
            $0.scrollToken = token
        }
    }

    func background(_ preset: String?) -> Self {
        modified { $0.background = preset }
    }

    private func modified(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
    }
}
