import AppKit

final class LineNumberRulerView: NSRulerView {
    weak var hostTextView: NSTextView?

    /// Cached UTF-16 offsets of every line start, so scrolling doesn't
    /// re-walk the document from character zero on every draw (that walk
    /// made scrolling large files crawl). Invalidated whenever the text
    /// storage is edited; rebuilt lazily on the next draw.
    private var lineStartsCache: [Int]?
    private var lineStartsCacheLength = -1

    init(textView: NSTextView) {
        self.hostTextView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 44

        // Force a layer-backed transparent fill so AppKit's default ruler
        // chrome (a light gray fill) doesn't paint over the editor pane's
        // translucent background in Glass mode.
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        // User typing posts NSText.didChange, but programmatic edits
        // (external text replacement, ghost-suggestion insertions) only
        // surface at the storage level — observe it so the line-start
        // cache never goes stale.
        if let storage = textView.textStorage {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(storageDidProcessEditing),
                name: NSTextStorage.didProcessEditingNotification,
                object: storage
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(viewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceOrPrefsChanged),
            name: .editorPreferencesChanged,
            object: nil
        )
        textView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var isOpaque: Bool { false }

    /// Skip `NSRulerView`'s default `draw(_:)`, which paints a chrome fill
    /// before delegating to `drawHashMarksAndLabels(in:)`. We only want the
    /// labels — the editor pane's background should show through.
    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    @objc private func textDidChange() { needsDisplay = true }
    @objc private func storageDidProcessEditing() {
        lineStartsCache = nil
        needsDisplay = true
    }
    @objc private func viewBoundsDidChange() { needsDisplay = true }
    @objc private func appearanceOrPrefsChanged() { needsDisplay = true }

    /// Color for the line-number labels. Picks a value that has enough
    /// contrast against whatever's behind: a more solid label color when
    /// the pane is translucent (Glass) and the desktop bleeds through, a
    /// subtle tertiary color when the pane is solid. Both adapt to the
    /// effective appearance, so dark/light mode switches automatically.
    private var labelColor: NSColor {
        // Pick the gutter color based on the editor surface tone, not
        // the app appearance — otherwise a forced-dark editor under a
        // light system appearance gets near-black labels on near-black
        // pixels, which are unreadable.
        let editorIsDark = EditorBackgroundOption.editorIsDarkSurface()
        let glass = UserDefaults.standard.bool(forKey: PreferenceKeys.windowGlass)
        if editorIsDark {
            return NSColor.white.withAlphaComponent(glass ? 0.65 : 0.55)
        } else {
            return NSColor.black.withAlphaComponent(glass ? 0.65 : 0.55)
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = hostTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        // No background fill — let the editor pane's background show through
        // so the gutter matches whatever translucency the pane has (solid in
        // Solid mode, glass in Glass mode).

        // Convert text-view local coords to ruler local coords. This handles
        // the scroll offset cleanly and avoids the sub-pixel jitter we'd get
        // from manually subtracting visibleRect.origin.
        let yOffset = self.convert(NSPoint.zero, from: textView).y

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let nsString = textView.string as NSString

        let starts = lineStarts(for: nsString)
        var lineIdx = lineIndex(containing: charRange.location, in: starts)
        var currentLine = lineIdx + 1

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: labelColor,
        ]

        let inset = textView.textContainerInset.height
        var idx = starts[lineIdx]
        let endIdx = NSMaxRange(charRange)

        while idx <= endIdx {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: idx)
            var effectiveRange = NSRange(location: 0, length: 0)
            let lineFragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &effectiveRange
            )

            let yInRuler = lineFragmentRect.origin.y + inset + yOffset
            let label = "\(currentLine)" as NSString
            let labelSize = label.size(withAttributes: attrs)
            // Round to integer pixels — sub-pixel y for label drawing makes
            // line numbers visibly jitter relative to the text as it scrolls.
            let labelOrigin = NSPoint(
                x: floor(bounds.width - labelSize.width - 8),
                y: floor(yInRuler + (lineFragmentRect.height - labelSize.height) / 2)
            )
            label.draw(at: labelOrigin, withAttributes: attrs)

            let next = (lineIdx + 1 < starts.count) ? starts[lineIdx + 1] : nsString.length
            if next == idx { break }
            idx = next
            lineIdx += 1
            currentLine += 1
            if idx >= nsString.length { break }
        }
    }

    // MARK: - Line index

    /// Rebuild (or return) the cached array of line-start offsets. The
    /// scan copies characters out in chunks, so rebuilding a multi-
    /// megabyte document takes a few milliseconds — and it only happens
    /// after an edit, never per scroll frame.
    private func lineStarts(for nsString: NSString) -> [Int] {
        let length = nsString.length
        if let cached = lineStartsCache, lineStartsCacheLength == length {
            return cached
        }

        var starts: [Int] = [0]
        starts.reserveCapacity(max(16, length / 32))
        var buffer = [unichar](repeating: 0, count: 8192)
        var offset = 0
        var previousWasCR = false
        while offset < length {
            let chunkLength = min(buffer.count, length - offset)
            nsString.getCharacters(&buffer, range: NSRange(location: offset, length: chunkLength))
            for i in 0..<chunkLength {
                let char = buffer[i]
                let absolute = offset + i
                if previousWasCR {
                    previousWasCR = false
                    if char == 0x0A {
                        // CRLF is a single line break — move the start
                        // recorded after the CR past the LF.
                        starts[starts.count - 1] = absolute + 1
                        continue
                    }
                }
                // LF, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR, and CR(LF)
                // — the exact set NSString.lineRange(for:) breaks on
                // (notably *excluding* vertical tab and form feed).
                switch char {
                case 0x0A, 0x85, 0x2028, 0x2029:
                    starts.append(absolute + 1)
                case 0x0D:
                    starts.append(absolute + 1)
                    previousWasCR = true
                default:
                    break
                }
            }
            offset += chunkLength
        }

        lineStartsCache = starts
        lineStartsCacheLength = length
        return starts
    }

    /// Index of the line containing `location`: the last start ≤ location.
    private func lineIndex(containing location: Int, in starts: [Int]) -> Int {
        var lo = 0
        var hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= location { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}
