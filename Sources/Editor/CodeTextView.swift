import AppKit

/// `NSTextView` subclass that draws a subtle highlight on the line containing
/// the cursor. The color adapts to dark/light appearance and to the user's
/// Solid / Glass window setting.
final class CodeTextView: NSTextView {
    /// Background drawing happens before the glyphs, so the highlight sits
    /// underneath the code text.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLineHighlight()
    }

    // This is for drawing the highlight for the selected line
    // This is a func that was generated with the help of claude.
    private func drawCurrentLineHighlight() {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer
        else { return }

        let nsString = string as NSString
        let selRange = selectedRange()
        let charIndex = min(selRange.location, nsString.length)
        let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: lineRange,
            actualCharacterRange: nil
        )
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        // Empty trailing line (e.g. cursor at end after \n) returns an empty
        // rect. Use a single line height as a fallback.
        if lineRect.height == 0 {
            let lineHeight = layoutManager.defaultLineHeight(for: font ?? NSFont.systemFont(ofSize: 13))
            lineRect.size.height = lineHeight
        }

        let highlight = NSRect(
            x: bounds.minX,
            y: lineRect.origin.y + textContainerInset.height,
            width: bounds.width,
            height: lineRect.height
        )

        currentLineColor.setFill()
        highlight.fill()
    }

    /// The highlight color adapts to:
    /// - **Light/Dark** automatically through dynamic AppKit colors.
    /// - **Solid/Glass** explicitly — Glass mode needs a slightly more solid
    ///   color to remain perceptible against the varied desktop showing
    ///   through the window.
    /// - **Accent tint** — when the user raises the "Current-line highlight"
    ///   slider, the highlight crossfades from neutral label-tinted to a
    ///   washed accent.
    private var currentLineColor: NSColor {
        let glass = UserDefaults.standard.bool(forKey: PreferenceKeys.windowGlass)
        let baseAlpha: CGFloat = glass ? 0.07 : 0.05

        // Pick the neutral tint based on the editor surface tone, so a
        // forced-dark background still gets a *light* current-line
        // wash under a light system appearance (and vice versa).
        let editorIsDark = EditorBackgroundOption.editorIsDarkSurface()
        let neutralBase: NSColor = editorIsDark ? .white : .black
        let neutral = neutralBase.withAlphaComponent(baseAlpha)

        let on = UserDefaults.standard.bool(forKey: PreferenceKeys.accentTintCurrentLine)
        guard on else { return neutral }

        let accent = AccentPresets.current.nsColor
        // Stronger ceiling than `baseAlpha` so the tinted highlight is
        // clearly visible without overwhelming the text.
        let accentAlpha: CGFloat = (glass ? 0.18 : 0.14)
        return accent.withAlphaComponent(accentAlpha)
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        let oldRange = selectedRange()
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        let newRange = selectedRange()
        if oldRange.location != newRange.location {
            // Cursor moved — old highlighted line and new highlighted line
            // both need a redraw.
            needsDisplay = true
        }
    }

    /// Tab accepts a pending ghost-text completion (Copilot-style). Falls
    /// back to a normal tab insertion when no suggestion is showing.
    override func insertTab(_ sender: Any?) {
        if let coord = delegate as? EditorView.Coordinator,
           coord.acceptPendingCompletion()
        {
            return
        }
        super.insertTab(sender)
    }

    /// Esc dismisses an active completion. Without an active suggestion
    /// we fall through to NSTextView's default (which historically opens
    /// the system completion popup — fine to keep as a fallback).
    override func cancelOperation(_ sender: Any?) {
        if let coord = delegate as? EditorView.Coordinator,
           coord.dismissPendingCompletion()
        {
            return
        }
        super.cancelOperation(sender)
    }

    /// When the user backspaces over an auto-inserted opener and the
    /// matching closer is sitting immediately to the right of the cursor
    /// (with nothing between), delete both — same feel as VS Code.
    override func deleteBackward(_ sender: Any?) {
        let range = selectedRange()
        let nsString = string as NSString
        if range.length == 0,
           range.location > 0,
           range.location < nsString.length {
            let prev = nsString.substring(with: NSRange(location: range.location - 1, length: 1))
            let next = nsString.substring(with: NSRange(location: range.location, length: 1))
            let pairs: [String: String] = [
                "{": "}", "(": ")", "[": "]",
                "\"": "\"", "'": "'", "`": "`",
            ]
            if pairs[prev] == next {
                let target = NSRange(location: range.location - 1, length: 2)
                if shouldChangeText(in: target, replacementString: "") {
                    replaceCharacters(in: target, with: "")
                    didChangeText()
                }
                return
            }
        }
        super.deleteBackward(sender)
    }
}
