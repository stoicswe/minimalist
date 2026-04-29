import SwiftUI
import AppKit
import Highlightr

struct EditorView: NSViewRepresentable {
    @ObservedObject var document: Document
    var workspace: Workspace?
    var minimapBridge: MinimapBridge?
    /// When true, the editor's vertical scroller is hidden. Used when the
    /// minimap is showing — the minimap acts as the visual scroll indicator
    /// and sits at the window's far-right edge instead.
    var hidesScroller: Bool = false
    /// Top content inset on the underlying NSScrollView. Used in glass
    /// mode so the editor's content can scroll *behind* the floating tab
    /// bar while keeping the cursor visible at this offset from the top.
    var topContentInset: CGFloat = 0

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = !hidesScroller
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        // Build the CodeTextView manually so we can use our subclass that
        // draws the current-line highlight. This replicates what
        // `NSTextView.scrollableTextView()` does internally.
        let contentSize = scroll.contentSize
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = CodeTextView(
            frame: NSRect(origin: .zero, size: contentSize),
            textContainer: textContainer
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scroll.documentView = textView
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
        scroll.scrollerInsets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
        // Clip view paints a background by default — turn it off so
        // content scrolling behind a translucent toolbar shows through
        // without a seam.
        scroll.contentView.drawsBackground = false

        configure(textView, coordinator: context.coordinator)
        context.coordinator.textView = textView
        context.coordinator.scrollView = scroll
        context.coordinator.workspace = workspace
        textView.string = document.text
        context.coordinator.applyFontPreferences()
        context.coordinator.applyLineNumberPreference()
        context.coordinator.applyWordWrapPreference()
        context.coordinator.applyHighlight()
        context.coordinator.subscribeToPreferenceChanges()
        context.coordinator.attachMinimapBridge(minimapBridge, scrollView: scroll)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let coord = context.coordinator
        let previousLanguage = coord.lastAppliedLanguage
        coord.document = document
        nsView.hasVerticalScroller = !hidesScroller

        if nsView.contentInsets.top != topContentInset {
            nsView.contentInsets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
            nsView.scrollerInsets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
        }

        if textView.string != document.text {
            let selected = textView.selectedRanges
            textView.string = document.text
            textView.selectedRanges = selected
            coord.applyHighlight()
        } else if previousLanguage != document.language {
            coord.applyHighlight()
        }

        if let line = document.pendingScrollLine {
            // Defer one runloop turn so the layout manager has produced
            // glyph rects for the current text before we ask for the
            // bounding rect of a specific line.
            DispatchQueue.main.async {
                coord.scrollToLine(line)
                document.pendingScrollLine = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    private func configure(_ tv: NSTextView, coordinator: Coordinator) {
        tv.delegate = coordinator
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = false
        tv.isRichText = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.textContainerInset = NSSize(width: 14, height: 14)
        // Let the editor pane's `PaneBackground` (in ContentView) show
        // through. When the user has zero translucency, that background is
        // a solid `textBackgroundColor`, matching what the text view would
        // have drawn itself.
        tv.drawsBackground = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.insertionPointColor = AccentPresets.current.nsColor
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: Document
        weak var workspace: Workspace?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var lastAppliedLanguage: String = ""

        private var highlightr: Highlightr?
        private var currentTheme: String = ""
        private var highlightWork: DispatchWorkItem?
        private var draftSnapshotWork: DispatchWorkItem?
        private var autosaveRecordWork: DispatchWorkItem?
        private var isApplyingHighlight = false
        private var prefsObserver: NSObjectProtocol?
        private var appearanceObserver: NSObjectProtocol?
        private weak var minimapBridge: MinimapBridge?
        private var scrollObserver: NSObjectProtocol?

        // Inline ghost-text completion. `pendingCompletion` describes a
        // run of ghost characters currently sitting in the text storage;
        // `isMutatingGhost` guards against re-entrant text-change calls
        // while we add or remove that run.
        private struct PendingCompletion {
            let location: Int
            let length: Int
            var range: NSRange { NSRange(location: location, length: length) }
        }
        private var pendingCompletion: PendingCompletion?
        private var isMutatingGhost = false
        private var completionWork: DispatchWorkItem?

        init(document: Document) {
            self.document = document
            let initialTheme = Self.preferredTheme()
            let hl = Highlightr()
            hl?.setTheme(to: initialTheme)
            self.highlightr = hl
            self.currentTheme = initialTheme
        }

        /// Rebuild the Highlightr instance with the desired theme. We re-
        /// create it (rather than just calling `setTheme(to:)`) because the
        /// fast-render path caches per-token style state and can serve stale
        /// colors when the theme changes on an existing instance.
        private func rebuildHighlighter(theme: String) {
            let hl = Highlightr()
            hl?.setTheme(to: theme)
            self.highlightr = hl
            self.currentTheme = theme
        }

        deinit {
            if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
            if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        // MARK: - Minimap bridge

        @MainActor
        func attachMinimapBridge(_ bridge: MinimapBridge?, scrollView: NSScrollView) {
            minimapBridge = bridge
            guard let bridge else { return }

            // Provide a way for the minimap to scroll the editor.
            bridge.scrollMainEditor = { [weak self, weak scrollView] fraction in
                guard fraction.isFinite,
                      let scrollView,
                      let documentView = scrollView.documentView else { return }
                let totalHeight = max(documentView.frame.height, 1)
                let viewportHeight = scrollView.contentView.bounds.height
                let maxOffset = max(0, totalHeight - viewportHeight)
                let target = max(0, min(maxOffset, totalHeight * CGFloat(fraction)))
                guard target.isFinite else { return }
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: target))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                scrollView.verticalRulerView?.needsDisplay = true
                // Defer the bridge update — it publishes @Published values,
                // which can't safely happen synchronously during a SwiftUI
                // view update pass.
                DispatchQueue.main.async { self?.publishScrollState() }
            }

            // Listen to scroll changes so we can publish them to the bridge.
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                // Same reason — defer to the next run loop so we don't
                // publish during a SwiftUI update.
                DispatchQueue.main.async { self?.publishScrollState() }
            }

            DispatchQueue.main.async { [weak self] in self?.publishScrollState() }
        }

        @MainActor
        private func publishScrollState() {
            guard let bridge = minimapBridge,
                  let scroll = scrollView,
                  let documentView = scroll.documentView else { return }
            let totalHeight = max(documentView.frame.height, 1)
            let viewport = scroll.contentView.bounds
            guard totalHeight.isFinite, viewport.height.isFinite, viewport.minY.isFinite
            else { return }
            let topFraction = Double(viewport.minY / totalHeight)
            let visibleFraction = Double(min(viewport.height, totalHeight) / totalHeight)
            guard topFraction.isFinite, visibleFraction.isFinite else { return }
            if abs(bridge.topFraction - topFraction) > 0.0001 {
                bridge.topFraction = max(0, min(1, topFraction))
            }
            if abs(bridge.visibleFraction - visibleFraction) > 0.0001 {
                bridge.visibleFraction = max(0.02, min(1, visibleFraction))
            }
        }

        func subscribeToPreferenceChanges() {
            prefsObserver = NotificationCenter.default.addObserver(
                forName: .editorPreferencesChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.refreshTheme()
                    self.applyFontPreferences()
                    self.applyLineNumberPreference()
                    self.applyWordWrapPreference()
                    self.applyHighlight()
                    self.applyAccentPreferences()
                }
            }
            // Re-resolve the syntax theme whenever the system flips between
            // light and dark mode, so the editor follows along.
            appearanceObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.refreshTheme()
                    self.applyHighlight()
                }
            }
        }

        @MainActor
        private func refreshTheme() {
            let target = Self.preferredTheme()
            guard target != currentTheme else { return }
            rebuildHighlighter(theme: target)
        }

        private static func preferredTheme() -> String {
            // Pick the theme based on the *editor surface* tone, not the
            // app appearance. If the user forced a dark background under
            // a light system appearance, we still want the dark syntax
            // theme so the text stays legible (and vice versa).
            let isDark = EditorBackgroundOption.editorIsDarkSurface()
            let key = isDark ? PreferenceKeys.syntaxThemeDark : PreferenceKeys.syntaxThemeLight
            let fallback = isDark ? SyntaxThemes.defaultDark : SyntaxThemes.defaultLight
            let saved = UserDefaults.standard.string(forKey: key) ?? fallback
            return saved.isEmpty ? fallback : saved
        }

        /// Resolve "is the editor rendering in dark appearance right now?".
        /// Equivalent to `EditorBackgroundOption.editorIsDarkSurface()` —
        /// kept here for the few internal call sites that already use it.
        private static func isInDarkAppearance() -> Bool {
            EditorBackgroundOption.editorIsDarkSurface()
        }

        // MARK: - Preferences

        @MainActor
        func applyFontPreferences() {
            guard let tv = textView else { return }
            tv.font = Preferences.editorFont
        }

        /// Toggle word wrap. When wrap is off, the text container grows
        /// horizontally and the scroll view shows a horizontal scroller.
        ///
        /// Notes on the wrap-on path: with `widthTracksTextView = true`
        /// AppKit auto-tracks the container's width to the text view's
        /// width, and `autoresizingMask = .width` keeps the text view
        /// pinned to the scroll view's width. So we don't set
        /// `containerSize.width` or `tv.frame.size.width` ourselves —
        /// doing that fought the auto-tracking and could surface a
        /// stale width during transient layouts (e.g. when the pattern
        /// overlay was driving frequent SwiftUI redraws), which in
        /// turn produced a phantom horizontal scroller.
        @MainActor
        func applyWordWrapPreference() {
            guard let tv = textView, let scroll = scrollView,
                  let container = tv.textContainer
            else { return }
            if Preferences.wordWrap {
                container.widthTracksTextView = true
                container.containerSize = NSSize(
                    width: 0,                                // ignored when widthTracksTextView is true
                    height: CGFloat.greatestFiniteMagnitude
                )
                tv.isHorizontallyResizable = false
                tv.autoresizingMask = [.width]
                scroll.hasHorizontalScroller = false
            } else {
                container.widthTracksTextView = false
                container.containerSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                tv.isHorizontallyResizable = true
                tv.autoresizingMask = []
                scroll.hasHorizontalScroller = true
            }
            tv.needsLayout = true
            tv.layoutManager?.invalidateLayout(
                forCharacterRange: NSRange(location: 0, length: tv.string.count),
                actualCharacterRange: nil
            )
            tv.needsDisplay = true
        }

        /// Move the cursor to the start of `line` (1-based) and bring it
        /// into view. Used by the Zen-mode search palette for in-file
        /// match jumps.
        @MainActor
        func scrollToLine(_ line: Int) {
            guard let tv = textView else { return }
            let nsText = tv.string as NSString
            var location = 0
            var currentLine = 1
            while currentLine < line && location < nsText.length {
                let range = nsText.lineRange(for: NSRange(location: location, length: 0))
                let next = range.upperBound
                if next == location { break }   // safety against zero-width loops
                location = next
                currentLine += 1
            }
            let target = NSRange(location: min(location, nsText.length), length: 0)
            tv.setSelectedRange(target)
            tv.scrollRangeToVisible(target)
            tv.window?.makeFirstResponder(tv)
        }

        @MainActor
        func applyAccentPreferences() {
            guard let tv = textView else { return }
            tv.insertionPointColor = AccentPresets.current.nsColor
            // The current-line highlight reads its color from
            // UserDefaults at draw time, so we just need a redraw.
            tv.needsDisplay = true
        }

        @MainActor
        func applyLineNumberPreference() {
            guard let scrollView, let textView else { return }
            if Preferences.showLineNumbers {
                if !(scrollView.verticalRulerView is LineNumberRulerView) {
                    scrollView.hasVerticalRuler = true
                    scrollView.verticalRulerView = LineNumberRulerView(textView: textView)
                    scrollView.rulersVisible = true
                }
            } else {
                scrollView.rulersVisible = false
                scrollView.verticalRulerView = nil
                scrollView.hasVerticalRuler = false
            }
        }

        // MARK: - Editing

        func textDidChange(_ notification: Notification) {
            guard !isApplyingHighlight, !isMutatingGhost, let tv = textView else { return }
            // The user typed (or paste/etc.). Drop any active ghost suggestion
            // so the document we feed the highlighter doesn't include it,
            // then schedule a fresh suggestion after a short pause.
            dismissGhostInline()
            document.text = tv.string
            scheduleHighlight()
            scheduleDraftSnapshot()
            scheduleAutosaveRecord()
            scheduleCompletion()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Cursor moved (arrow keys, mouse) — drop any active suggestion.
            // Do nothing while we're the ones causing the move (during
            // accept/dismiss).
            guard !isMutatingGhost else { return }
            if pendingCompletion != nil {
                dismissGhostInline()
            }
        }

        // MARK: - Ghost text completion

        /// Marker attribute used to identify ghost-text characters in the
        /// text storage. Distinct from any real attributes the highlighter
        /// applies, so we can find and strip them precisely.
        static let ghostAttribute = NSAttributedString.Key("minimalist.ghostCompletion")

        private func scheduleCompletion() {
            completionWork?.cancel()
            // Skip entirely if the user has the feature off.
            let enabled = UserDefaults.standard.object(forKey: PreferenceKeys.enableAutocomplete) as? Bool ?? true
            guard enabled else { return }
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.computeAndShowSuggestion() }
            }
            completionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
        }

        @MainActor
        private func computeAndShowSuggestion() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            // Need an empty cursor selection to suggest.
            let selection = tv.selectedRange()
            guard selection.length == 0, selection.location <= storage.length else { return }

            // Only suggest at end-of-word: cursor must sit just after an
            // identifier character with a non-identifier (or EOL) immediately
            // after it. Otherwise the user is editing inside a word.
            let nsText = storage.string as NSString
            guard let prefix = currentWordPrefix(in: nsText, before: selection.location),
                  prefix.count >= 2
            else { return }
            if selection.location < nsText.length {
                let next = nsText.character(at: selection.location)
                if Self.isIdentifierChar(next) { return }
            }

            // Compute against the document MINUS the prefix, so a unique
            // identifier the user is currently typing doesn't suggest itself.
            // The keyword fold-in is gated by its own preference so users
            // can keep document-identifier completion without language
            // keywords (or vice versa).
            let includeKeywords = UserDefaults.standard.object(
                forKey: PreferenceKeys.enableLanguageKeywords
            ) as? Bool ?? true
            guard let suffix = CompletionEngine.suggest(
                prefix: prefix,
                in: storage.string,
                language: document.language,
                includeKeywords: includeKeywords
            ), !suffix.isEmpty
            else { return }

            insertGhost(suffix, at: selection.location, textView: tv, storage: storage)
        }

        @MainActor
        private func insertGhost(_ suffix: String, at location: Int, textView tv: NSTextView, storage: NSTextStorage) {
            isMutatingGhost = true
            defer { isMutatingGhost = false }

            // Don't pollute the undo stack with ghost insertions/removals.
            let undo = tv.undoManager
            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }

            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.tertiaryLabelColor,
                Self.ghostAttribute: true,
                .font: tv.font ?? Preferences.editorFont,
            ]
            let ghost = NSAttributedString(string: suffix, attributes: attrs)
            storage.beginEditing()
            storage.insert(ghost, at: location)
            storage.endEditing()
            tv.setSelectedRange(NSRange(location: location, length: 0))
            pendingCompletion = PendingCompletion(location: location, length: ghost.length)
        }

        /// Tab handler — accept the active ghost text. Returns true when a
        /// suggestion was accepted so the caller can swallow the keystroke.
        @discardableResult
        @MainActor
        func acceptPendingCompletion() -> Bool {
            guard pendingCompletion != nil,
                  let tv = textView,
                  let storage = tv.textStorage,
                  let range = currentGhostRange(in: storage)
            else {
                pendingCompletion = nil
                return false
            }

            isMutatingGhost = true
            defer { isMutatingGhost = false }

            storage.beginEditing()
            storage.removeAttribute(Self.ghostAttribute, range: range)
            storage.removeAttribute(.foregroundColor, range: range)
            storage.endEditing()
            tv.setSelectedRange(NSRange(location: range.upperBound, length: 0))
            pendingCompletion = nil

            document.text = tv.string
            scheduleHighlight()
            scheduleDraftSnapshot()
            scheduleAutosaveRecord()
            return true
        }

        /// Dismiss without accepting. Public entry point for Esc.
        @discardableResult
        @MainActor
        func dismissPendingCompletion() -> Bool {
            guard pendingCompletion != nil else { return false }
            dismissGhostInline()
            return true
        }

        /// Internal dismiss — strips ghost characters from the text storage.
        ///
        /// We *don't* trust `pendingCompletion.location` here. When the user
        /// types a character at the cursor (which sits right before the
        /// ghost), NSTextView inserts at that position and shifts the ghost
        /// rightward. By the time we reach this method, the cached location
        /// is stale. So we look up the ghost by its custom attribute, which
        /// AppKit faithfully shifts along with its characters.
        @MainActor
        private func dismissGhostInline() {
            guard let tv = textView, let storage = tv.textStorage else {
                pendingCompletion = nil
                return
            }
            guard let range = currentGhostRange(in: storage) else {
                pendingCompletion = nil
                return
            }

            isMutatingGhost = true
            defer { isMutatingGhost = false }

            let undo = tv.undoManager
            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }

            storage.beginEditing()
            storage.deleteCharacters(in: range)
            storage.endEditing()
            pendingCompletion = nil
        }

        /// Walk the storage looking for our custom `ghostAttribute`. Returns
        /// the (possibly shifted) range of the ghost text, or nil when the
        /// ghost is no longer present.
        @MainActor
        private func currentGhostRange(in storage: NSTextStorage) -> NSRange? {
            guard storage.length > 0 else { return nil }
            var found: NSRange?
            storage.enumerateAttribute(
                Self.ghostAttribute,
                in: NSRange(location: 0, length: storage.length),
                options: []
            ) { value, range, stop in
                if value as? Bool == true {
                    found = range
                    stop.pointee = true
                }
            }
            return found
        }

        /// Walk back from `location` over identifier characters and return
        /// the prefix.
        private func currentWordPrefix(in text: NSString, before location: Int) -> String? {
            var idx = location
            while idx > 0 {
                let prev = text.character(at: idx - 1)
                if !Self.isIdentifierChar(prev) { break }
                idx -= 1
            }
            guard idx < location else { return nil }
            return text.substring(with: NSRange(location: idx, length: location - idx))
        }

        private static func isIdentifierChar(_ c: unichar) -> Bool {
            // a-z, A-Z, 0-9, underscore, plus the common Unicode-letter range
            if c == 95 { return true }                   // _
            if c >= 48 && c <= 57 { return true }        // 0-9
            if c >= 65 && c <= 90 { return true }        // A-Z
            if c >= 97 && c <= 122 { return true }       // a-z
            // Above ASCII: trust Unicode letter classification
            if c > 127, let scalar = Unicode.Scalar(c) {
                return scalar.properties.isAlphabetic
            }
            return false
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.applyHighlight() }
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        private func scheduleDraftSnapshot() {
            draftSnapshotWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.document.writeDraftSnapshot()
                }
            }
            draftSnapshotWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        // Revision-history autosave runs on a slower cadence than the
        // crash-recovery draft snapshot above. The tracker also enforces
        // a minimum interval between recorded entries so that long editing
        // sessions don't churn through the rolling 25-snapshot cap.
        private func scheduleAutosaveRecord() {
            autosaveRecordWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.workspace?.recordAutosave(for: self.document)
                }
            }
            autosaveRecordWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: work)
        }

        @MainActor
        func applyHighlight() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let source = tv.string
            let lang = document.language
            let font = Preferences.editorFont

            isApplyingHighlight = true
            defer { isApplyingHighlight = false }

            let attributed: NSAttributedString = {
                if let hl = highlightr,
                   lang != "plaintext",
                   let result = hl.highlight(source, as: lang, fastRender: true) {
                    return result
                }
                return NSAttributedString(string: source, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.textColor,
                ])
            }()

            let mutable = NSMutableAttributedString(attributedString: attributed)
            let full = NSRange(location: 0, length: mutable.length)
            mutable.addAttribute(.font, value: font, range: full)

            let selected = tv.selectedRanges
            storage.beginEditing()
            storage.setAttributedString(mutable)
            storage.endEditing()

            // Re-stamp ghost-text attributes if a suggestion is currently
            // active — otherwise the highlighter just painted those
            // characters with regular syntax colors and the user can no
            // longer tell they were a suggestion.
            if let pending = pendingCompletion, pending.range.upperBound <= storage.length {
                storage.beginEditing()
                storage.addAttribute(Self.ghostAttribute, value: true, range: pending.range)
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: pending.range)
                storage.endEditing()
            }

            tv.selectedRanges = selected
            lastAppliedLanguage = lang
        }

        // MARK: - Smart edits

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn range: NSRange,
            replacementString: String?
        ) -> Bool {
            // Dismiss any pending ghost completion *before* AppKit lands
            // the user's character, so layout never holds the user's edit
            // and the ghost simultaneously. Otherwise the line briefly
            // includes both — wrapping + reflow shows up as a one-frame
            // jump-right-and-back to the eye.
            if pendingCompletion != nil {
                dismissGhostInline()
            }

            guard let replacement = replacementString else { return true }

            // Tab → spaces, when the document is space-indented.
            if replacement == "\t", document.indentation.kind == .spaces {
                let unit = document.indentation.unit
                textView.insertText(unit, replacementRange: range)
                return false
            }

            // Newline: preserve indentation, optionally add an extra level
            // after `{ ( [`, optionally split a pair onto two lines.
            if replacement == "\n" {
                return handleNewline(
                    textView: textView,
                    range: range,
                    indentUnit: document.indentation.unit
                )
            }

            // Auto-pair openers and selection wrapping.
            if let closer = SmartEdit.closerFor(opener: replacement) {
                return handleOpener(textView: textView, range: range,
                                    opener: replacement, closer: closer)
            }

            // Skip-over closers when overtyping the matching char.
            if SmartEdit.isCloser(replacement) {
                return handleCloser(textView: textView, range: range,
                                    char: replacement)
            }

            return true
        }

        private func handleOpener(
            textView: NSTextView,
            range: NSRange,
            opener: String,
            closer: String
        ) -> Bool {
            let nsString = textView.string as NSString

            // Quotes need extra context awareness — don't pair when typing
            // next to identifier characters (e.g. `don't`, `let's`, or right
            // before an identifier).
            if opener == "\"" || opener == "'" {
                if range.location < nsString.length,
                   SmartEdit.isIdentifierChar(nsString.substring(with: NSRange(location: range.location, length: 1))) {
                    return true
                }
                if range.location > 0,
                   SmartEdit.isIdentifierChar(nsString.substring(with: NSRange(location: range.location - 1, length: 1))) {
                    return true
                }
            }

            if range.length > 0 {
                // Wrap the selection.
                let selected = nsString.substring(with: range)
                let wrapped = opener + selected + closer
                textView.insertText(wrapped, replacementRange: range)
                let innerStart = range.location + opener.count
                textView.setSelectedRange(NSRange(location: innerStart, length: selected.count))
            } else {
                // Insert pair, place cursor between the two halves.
                textView.insertText(opener + closer, replacementRange: range)
                textView.setSelectedRange(NSRange(location: range.location + opener.count, length: 0))
            }
            return false
        }

        private func handleCloser(
            textView: NSTextView,
            range: NSRange,
            char: String
        ) -> Bool {
            let nsString = textView.string as NSString
            guard range.length == 0, range.location < nsString.length else { return true }
            let nextChar = nsString.substring(with: NSRange(location: range.location, length: 1))
            if nextChar == char {
                // Cursor is sitting right before the matching closer that
                // we auto-inserted earlier. Just step over it.
                textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                return false
            }
            return true
        }

        private func handleNewline(
            textView: NSTextView,
            range: NSRange,
            indentUnit: String
        ) -> Bool {
            let nsString = textView.string as NSString
            let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
            let beforeCursor = nsString.substring(
                with: NSRange(location: lineRange.location,
                              length: range.location - lineRange.location)
            )
            let leading = SmartEdit.leadingWhitespace(of: beforeCursor)
            let trimmedBefore = beforeCursor.trimmingCharacters(in: .whitespaces)
            let endsWithOpener = trimmedBefore.last.map { "{([".contains($0) } ?? false

            // Check whether cursor sits directly between a matched pair.
            var splitsPair = false
            if range.length == 0,
               range.location > 0, range.location < nsString.length {
                let prev = nsString.substring(with: NSRange(location: range.location - 1, length: 1))
                let next = nsString.substring(with: NSRange(location: range.location, length: 1))
                splitsPair = SmartEdit.isMatchedPair(opener: prev, closer: next)
            }

            if splitsPair {
                let insertion = "\n" + leading + indentUnit + "\n" + leading
                textView.insertText(insertion, replacementRange: range)
                let cursorPos = range.location + 1 + leading.count + indentUnit.count
                textView.setSelectedRange(NSRange(location: cursorPos, length: 0))
                return false
            }

            if endsWithOpener {
                let insertion = "\n" + leading + indentUnit
                textView.insertText(insertion, replacementRange: range)
                return false
            }

            if !leading.isEmpty {
                textView.insertText("\n" + leading, replacementRange: range)
                return false
            }

            return true
        }
    }
}

/// Pure helpers for the smart-edit logic — separated from the coordinator
/// so they're easy to unit-test.
private enum SmartEdit {
    static let pairs: [String: String] = [
        "{": "}",
        "(": ")",
        "[": "]",
        "\"": "\"",
        "'": "'",
        "`": "`",
    ]

    static func closerFor(opener: String) -> String? { pairs[opener] }

    static func isCloser(_ s: String) -> Bool {
        ["}", ")", "]", "\"", "'", "`"].contains(s)
    }

    static func isMatchedPair(opener: String, closer: String) -> Bool {
        pairs[opener] == closer
    }

    static func leadingWhitespace(of line: String) -> String {
        var prefix = ""
        for ch in line {
            if ch == " " || ch == "\t" { prefix.append(ch) } else { break }
        }
        return prefix
    }

    static func isIdentifierChar(_ s: String) -> Bool {
        s.rangeOfCharacter(from: .alphanumerics) != nil || s == "_"
    }
}
