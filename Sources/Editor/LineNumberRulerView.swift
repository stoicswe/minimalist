import AppKit

final class LineNumberRulerView: NSRulerView {
    weak var hostTextView: NSTextView?

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

        // Walk from start to find the line number of the first visible character.
        var currentLine = 1
        var idx = 0
        while idx < charRange.location {
            let lineRange = nsString.lineRange(for: NSRange(location: idx, length: 0))
            idx = NSMaxRange(lineRange)
            currentLine += 1
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: labelColor,
        ]

        let inset = textView.textContainerInset.height
        idx = charRange.location
        let endIdx = NSMaxRange(charRange)

        while idx <= endIdx {
            let lineRange = nsString.lineRange(for: NSRange(location: idx, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
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

            if NSMaxRange(lineRange) == lineRange.location { break }
            idx = NSMaxRange(lineRange)
            currentLine += 1
            if idx >= nsString.length { break }
        }
    }
}
