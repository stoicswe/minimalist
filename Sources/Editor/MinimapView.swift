import SwiftUI
import AppKit
import Highlightr

/// Side-panel minimap (à la Xcode):
///
/// - Renders the file as **colored bars** rather than tiny text. Each
///   non-whitespace token in the source becomes a small rectangle whose
///   color matches the active syntax theme — so the minimap reads as the
///   file's structure, not its content.
/// - Always shows the entire file fitted to the available height.
/// - Overlays a translucent rectangle showing the main editor's visible
///   region. As you scroll the editor it slides through the file range.
/// - Click or drag to scroll the editor — the line under your pointer
///   becomes the new top of the editor's viewport.
struct MinimapView: View {
    @ObservedObject var document: Document
    @ObservedObject var bridge: MinimapBridge

    var body: some View {
        ZStack(alignment: .topLeading) {
            MinimapCanvas(text: document.text, language: document.language)
            ViewportIndicator(bridge: bridge)
                .allowsHitTesting(false)
            MinimapDragLayer(bridge: bridge)
        }
        .clipped()
    }
}

// MARK: - Viewport indicator

private struct ViewportIndicator: View {
    @ObservedObject var bridge: MinimapBridge

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let indicatorHeight = max(20, bridge.visibleFraction * totalHeight)
            let yOffset = bridge.topFraction * totalHeight

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .overlay(
                    Rectangle().stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                )
                .frame(width: geo.size.width, height: indicatorHeight)
                .offset(y: yOffset)
        }
    }
}

// MARK: - Click / drag layer

private struct MinimapDragLayer: View {
    @ObservedObject var bridge: MinimapBridge

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard geo.size.height > 0 else { return }
                            let y = max(0, min(geo.size.height, value.location.y))
                            let fraction = Double(y / geo.size.height)
                            guard fraction.isFinite else { return }
                            bridge.scrollMainEditor?(fraction)
                        }
                )
                .onHover { _ in
                    NSCursor.pointingHand.set()
                }
        }
    }
}

// MARK: - Canvas-rendered colored-bar content

private struct MinimapCanvas: View {
    let text: String
    let language: String

    @AppStorage(PreferenceKeys.colorScheme) private var colorScheme: String = "system"
    @AppStorage(PreferenceKeys.syntaxThemeLight) private var syntaxThemeLight: String = SyntaxThemes.defaultLight
    @AppStorage(PreferenceKeys.syntaxThemeDark) private var syntaxThemeDark: String = SyntaxThemes.defaultDark

    @State private var snapshot: MinimapSnapshot = .empty

    /// Everything the snapshot depends on. Comparing an unchanged `text`
    /// is O(1) — both sides share the same string storage.
    private struct SnapshotKey: Equatable {
        let text: String
        let language: String
        let theme: String
        let dark: Bool
    }

    var body: some View {
        Canvas { ctx, size in
            draw(in: ctx, size: size)
        }
        .task(id: SnapshotKey(text: text, language: language, theme: theme, dark: isDark)) {
            // Debounce while the user types — every keystroke restarts
            // this task, and rebuilding the whole snapshot for each
            // intermediate state is wasted work. First build (empty
            // snapshot) runs immediately so the minimap doesn't flash in.
            if snapshot.lineCount > 0 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
            }
            let next = await MinimapSnapshot.buildAsync(
                text: text,
                language: language,
                theme: theme,
                dark: isDark
            )
            if !Task.isCancelled {
                snapshot = next
            }
        }
    }

    private func draw(in ctx: GraphicsContext, size: CGSize) {
        guard snapshot.lineCount > 0, snapshot.maxColumn > 0,
              size.width > 0, size.height > 0
        else { return }

        let lineHeight = size.height / CGFloat(snapshot.lineCount)
        let charWidth = size.width / CGFloat(snapshot.maxColumn)

        // When the file has far more lines than the canvas has points,
        // every bar lands on the same few pixels — draw a strided subset
        // (~2 bar rows per point of height) instead of overdrawing.
        let rowStride = max(1, snapshot.lineCount / max(1, Int(size.height) * 2))
        let barHeight = max(0.5, lineHeight * 0.6 * CGFloat(rowStride))
        let yPadding = max(0, (lineHeight * CGFloat(rowStride) - barHeight) / 2)

        // One path + one fill per distinct color, instead of one fill per
        // bar — the number of GPU/CG operations drops from thousands to
        // roughly the theme's palette size.
        for group in snapshot.groups {
            var path = Path()
            for bar in group.bars where bar.line % rowStride == 0 {
                path.addRect(CGRect(
                    x: CGFloat(bar.startColumn) * charWidth,
                    y: CGFloat(bar.line) * lineHeight + yPadding,
                    width: max(0.5, CGFloat(bar.length) * charWidth),
                    height: barHeight
                ))
            }
            ctx.fill(path, with: .color(group.color))
        }
    }

    /// Use the editor surface tone — same logic as the main editor —
    /// so the minimap's syntax-colored bars match what the user sees in
    /// the editor (e.g. dark syntax on a forced-dark background even
    /// when the app appearance is light).
    private var isDark: Bool {
        EditorBackgroundOption.editorIsDarkSurface()
    }

    private var theme: String {
        let saved = isDark ? syntaxThemeDark : syntaxThemeLight
        if saved.isEmpty {
            return isDark ? SyntaxThemes.defaultDark : SyntaxThemes.defaultLight
        }
        return saved
    }
}

// MARK: - Snapshot model

struct MinimapBar {
    let line: Int
    let startColumn: Int
    let length: Int
}

/// Bars that share a display color, so drawing can batch them into a
/// single fill.
struct MinimapBarGroup {
    let color: Color
    let bars: [MinimapBar]
}

struct MinimapSnapshot {
    let groups: [MinimapBarGroup]
    let lineCount: Int
    let maxColumn: Int

    static let empty = MinimapSnapshot(groups: [], lineCount: 0, maxColumn: 0)

    /// Serial queue that owns the minimap's Highlightr instance. Building
    /// a Highlightr spins up a JavaScriptCore context and loads
    /// highlight.js — far too expensive to do per keystroke, so the
    /// instance is cached here and recreated only on theme changes.
    private static let buildQueue = DispatchQueue(
        label: "com.stoicswe.minimalist.minimap-highlight",
        qos: .userInitiated
    )
    // Confined to `buildQueue`.
    private static var cachedHighlightr: Highlightr?
    private static var cachedTheme = ""

    /// Above this size (UTF-16 units), skip syntax highlighting for the
    /// minimap and render single-color structural bars — running a JS
    /// highlighter over megabytes of text costs far more than the colored
    /// overview is worth.
    private static let highlightCeiling = 1_000_000

    /// Hard cap on collected bars, as a backstop for pathological input
    /// (e.g. minified single-line sources with hundreds of thousands of
    /// tokens).
    private static let maxBars = 150_000

    /// Build a snapshot off the main thread.
    static func buildAsync(text: String, language: String, theme: String, dark: Bool) async -> MinimapSnapshot {
        await withCheckedContinuation { continuation in
            buildQueue.async {
                continuation.resume(returning: build(text: text, language: language, theme: theme, dark: dark))
            }
        }
    }

    /// Walk the highlighted string's color runs, grouping consecutive
    /// non-whitespace characters that share a foreground color into a
    /// single bar. Each bar carries its line index, starting column, and
    /// length (in characters) — sized at draw-time to fit the canvas.
    ///
    /// Runs on `buildQueue`.
    static func build(text: String, language: String, theme: String, dark: Bool) -> MinimapSnapshot {
        let attributed = highlighted(text: text, language: language, theme: theme)

        let nsText = attributed.string as NSString
        let length = nsText.length
        guard length > 0 else { return .empty }

        var barsByColor: [NSColor: [MinimapBar]] = [:]
        var barCount = 0
        var maxColumn = 0
        var currentLine = 0
        var currentCol = 0
        var barStart: Int? = nil
        var barColor: NSColor = .labelColor
        var barLine = 0

        func flushBar() {
            if let start = barStart, currentCol > start, barCount < maxBars {
                barsByColor[barColor, default: []].append(MinimapBar(
                    line: barLine,
                    startColumn: start,
                    length: currentCol - start
                ))
                barCount += 1
            }
            barStart = nil
        }

        // Enumerate color runs instead of asking for attributes per
        // character, and copy characters out in chunks instead of one
        // objc call per character.
        var buffer = [unichar](repeating: 0, count: 4096)
        attributed.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: length),
            options: []
        ) { value, range, _ in
            let runColor = (value as? NSColor) ?? NSColor.labelColor
            var offset = range.location
            let runEnd = NSMaxRange(range)
            while offset < runEnd {
                let chunkLength = min(buffer.count, runEnd - offset)
                nsText.getCharacters(&buffer, range: NSRange(location: offset, length: chunkLength))
                for i in 0..<chunkLength {
                    let char = buffer[i]

                    // Newline: flush any open bar and advance a line.
                    if char == 10 {
                        flushBar()
                        maxColumn = max(maxColumn, currentCol)
                        currentLine += 1
                        currentCol = 0
                        continue
                    }

                    // Whitespace: end any current bar so token boundaries
                    // appear as gaps (matches Xcode's minimap rendering).
                    if char == 32 || char == 9 {
                        flushBar()
                    } else if barStart == nil {
                        barStart = currentCol
                        barColor = runColor
                        barLine = currentLine
                    } else if barColor != runColor {
                        flushBar()
                        barStart = currentCol
                        barColor = runColor
                        barLine = currentLine
                    }
                    currentCol += 1
                }
                offset += chunkLength
            }
        }
        flushBar()
        maxColumn = max(maxColumn, currentCol)

        let groups = barsByColor.map { nsColor, bars in
            MinimapBarGroup(color: Color(nsColor: adjusted(nsColor, dark: dark)), bars: bars)
        }

        return MinimapSnapshot(
            groups: groups,
            lineCount: max(1, currentLine + 1),
            maxColumn: max(1, maxColumn)
        )
    }

    /// Highlight `text` with the cached Highlightr instance, falling back
    /// to a single-color attributed string for plaintext or oversized
    /// input. Runs on `buildQueue`.
    private static func highlighted(text: String, language: String, theme: String) -> NSAttributedString {
        if language != "plaintext", text.utf16.count <= highlightCeiling {
            if cachedTheme != theme || cachedHighlightr == nil {
                // Recreate rather than `setTheme(to:)` — the fast-render
                // path caches per-token style state and can serve stale
                // colors when the theme changes on an existing instance.
                let hl = Highlightr()
                hl?.setTheme(to: theme)
                cachedHighlightr = hl
                cachedTheme = theme
            }
            if let attr = cachedHighlightr?.highlight(text, as: language, fastRender: true) {
                return attr
            }
        }
        return NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.labelColor,
        ])
    }

    /// Tune a syntax-theme color for the minimap. Dark mode darkens the
    /// brightness so the bars read as a calmer structural overview against
    /// a dark editor; light mode lifts brightness slightly and saturation
    /// a touch so the bars don't disappear into the bright background.
    private static func adjusted(_ color: NSColor, dark: Bool) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newB: CGFloat
        let newS: CGFloat
        if dark {
            newB = b * 0.7
            newS = s
        } else {
            newB = min(1.0, max(b, 0.55) * 1.10)
            newS = min(1.0, s * 1.15)
        }
        return NSColor(hue: h, saturation: newS, brightness: newB, alpha: a)
    }
}
