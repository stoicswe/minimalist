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

    var body: some View {
        Canvas { ctx, size in
            draw(in: ctx, size: size)
        }
        .task(id: cacheKey) {
            await rebuild()
        }
    }

    private func draw(in ctx: GraphicsContext, size: CGSize) {
        guard snapshot.lineCount > 0, snapshot.maxColumn > 0,
              size.width > 0, size.height > 0
        else { return }

        let lineHeight = size.height / CGFloat(snapshot.lineCount)
        let charWidth = size.width / CGFloat(snapshot.maxColumn)
        let barHeight = max(0.5, lineHeight * 0.6)
        let yPadding = max(0, (lineHeight - barHeight) / 2)

        for bar in snapshot.bars {
            let rect = CGRect(
                x: CGFloat(bar.startColumn) * charWidth,
                y: CGFloat(bar.line) * lineHeight + yPadding,
                width: CGFloat(bar.length) * charWidth,
                height: barHeight
            )
            ctx.fill(Path(rect), with: .color(bar.color))
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

    private var cacheKey: String {
        "\(text.count)-\(language)-\(theme)-\(isDark ? "d" : "l")"
    }

    @MainActor
    private func rebuild() async {
        let captured = (text, language, theme, isDark)
        let next = MinimapSnapshot.build(
            text: captured.0,
            language: captured.1,
            theme: captured.2,
            dark: captured.3
        )
        snapshot = next
    }
}

// MARK: - Snapshot model

struct MinimapBar {
    let line: Int
    let startColumn: Int
    let length: Int
    let color: Color
}

struct MinimapSnapshot {
    let bars: [MinimapBar]
    let lineCount: Int
    let maxColumn: Int

    static let empty = MinimapSnapshot(bars: [], lineCount: 0, maxColumn: 0)

    /// Walk the highlighted attributed string once, grouping consecutive
    /// non-whitespace characters that share the same foreground color into
    /// a single bar. Each bar carries its line index, starting column, and
    /// length (in characters) — sized at draw-time to fit the canvas.
    static func build(text: String, language: String, theme: String, dark: Bool) -> MinimapSnapshot {
        let highlightr = Highlightr()
        highlightr?.setTheme(to: theme)

        let attributed: NSAttributedString
        if language != "plaintext",
           let attr = highlightr?.highlight(text, as: language, fastRender: true) {
            attributed = attr
        } else {
            attributed = NSAttributedString(string: text, attributes: [
                .foregroundColor: NSColor.labelColor,
            ])
        }

        var bars: [MinimapBar] = []
        var maxColumn = 0
        var currentLine = 0
        var currentCol = 0
        var barStart: Int? = nil
        var barColor: NSColor? = nil
        var barLine = 0

        let nsText = attributed.string as NSString
        let length = nsText.length

        func flushBar() {
            if let start = barStart, let color = barColor, currentCol > start {
                bars.append(MinimapBar(
                    line: barLine,
                    startColumn: start,
                    length: currentCol - start,
                    color: Color(nsColor: adjusted(color, dark: dark))
                ))
            }
            barStart = nil
            barColor = nil
        }

        for i in 0..<length {
            let char = nsText.character(at: i)

            // Newline: flush any open bar and advance to next line.
            if char == 10 {
                flushBar()
                maxColumn = max(maxColumn, currentCol)
                currentLine += 1
                currentCol = 0
                continue
            }

            // Whitespace: end any current bar so token boundaries appear
            // as gaps (matches the way Xcode minimap renders indentation).
            let isWhitespace = char == 32 || char == 9
            if isWhitespace {
                flushBar()
            } else {
                let attrs = attributed.attributes(at: i, effectiveRange: nil)
                let color = (attrs[.foregroundColor] as? NSColor) ?? NSColor.labelColor
                if barStart == nil {
                    barStart = currentCol
                    barColor = color
                    barLine = currentLine
                } else if barColor != color {
                    flushBar()
                    barStart = currentCol
                    barColor = color
                    barLine = currentLine
                }
            }
            currentCol += 1
        }
        flushBar()
        maxColumn = max(maxColumn, currentCol)

        let lineCount = currentLine + 1
        return MinimapSnapshot(
            bars: bars,
            lineCount: max(1, lineCount),
            maxColumn: max(1, maxColumn)
        )
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
