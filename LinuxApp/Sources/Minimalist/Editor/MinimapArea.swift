import Adwaita
import CAdw
import CCodeEditor
import Foundation

/// The editor's minimap.
///
/// `GtkSourceMap` — GtkSourceView's built-in map — renders the document
/// at a 1pt font and *scrolls*, so a long file never fits. The macOS app
/// scales the whole document into the strip instead, so this draws the
/// same way: one bar per line, indented and sized like the code, with a
/// translucent viewport marker, on a `GtkDrawingArea`. Click or drag
/// anywhere in it to scroll the editor there.
final class MinimapState {

    /// One line's shape: how far it is indented and how long it runs.
    struct Line {
        let indent: Int
        let length: Int
        /// Blank lines draw nothing, so the file's paragraph structure
        /// stays readable at a glance.
        var isEmpty: Bool { length == 0 }
    }

    /// Widest line the map draws before clipping; wider lines just fill.
    private static let columns = 110.0
    /// Bars never grow past this, so a ten-line file doesn't draw slabs.
    private static let maxBarHeight = 3.0

    private(set) var lines: [Line] = []
    private var needsRecompute = true

    /// The editor's scrolled window and the current buffer, refreshed by
    /// `SourceEditor` as tabs change.
    var scroller: OpaquePointer?
    var buffer: OpaquePointer?

    func invalidate() {
        needsRecompute = true
    }

    /// Re-read the line shapes when the buffer changed since last draw.
    private func refreshIfNeeded() {
        guard needsRecompute, let buffer else { return }
        needsRecompute = false
        let start = UnsafeMutablePointer<GtkTextIter>.allocate(capacity: 1)
        let end = UnsafeMutablePointer<GtkTextIter>.allocate(capacity: 1)
        defer {
            start.deallocate()
            end.deallocate()
        }
        gtk_text_buffer_get_start_iter(buffer.cast(), start)
        gtk_text_buffer_get_end_iter(buffer.cast(), end)
        guard let raw = gtk_text_buffer_get_text(buffer.cast(), start, end, 1) else {
            lines = []
            return
        }
        defer { g_free(raw) }
        lines = String(cString: raw).split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let indent = line.prefix { $0 == " " || $0 == "\t" }.count
            return Line(indent: indent, length: line.count - indent)
        }
    }

    // MARK: - Drawing

    func draw(widget: UnsafeMutablePointer<GtkWidget>?, context: OpaquePointer?, width: Int32, height: Int32) {
        refreshIfNeeded()
        guard !lines.isEmpty, width > 0, height > 0 else { return }

        let mapWidth = Double(width)
        let mapHeight = Double(height)
        // The whole document always fits: line spacing is the strip's
        // height divided by the line count, exactly as on macOS.
        let lineHeight = mapHeight / Double(lines.count)
        // Past a certain length one bar per line is thinner than a pixel,
        // so lines are grouped and the group's longest line is drawn.
        let stride = max(1, Int((1.0 / max(lineHeight, 0.000_1)).rounded(.up)))
        let barHeight = min(Self.maxBarHeight, max(0.6, lineHeight * Double(stride) * 0.62))
        let columnWidth = mapWidth / Self.columns

        var color = GdkRGBA()
        gtk_widget_get_color(widget, &color)
        cairo_set_source_rgba(context, Double(color.red), Double(color.green), Double(color.blue), 0.38)

        var index = 0
        while index < lines.count {
            let group = lines[index..<min(index + stride, lines.count)]
            defer { index += stride }
            guard let widest = group.filter({ !$0.isEmpty }).max(by: { $0.length < $1.length }) else {
                continue
            }
            let x = min(Double(widest.indent) * columnWidth, mapWidth)
            let barWidth = min(Double(widest.length) * columnWidth, mapWidth - x)
            guard barWidth > 0 else { continue }
            cairo_rectangle(context, x, Double(index) * lineHeight, barWidth, barHeight)
        }
        cairo_fill(context)

        drawViewport(context: context, color: color, mapWidth: mapWidth, mapHeight: mapHeight)
    }

    /// The translucent marker showing which slice of the file is on screen.
    private func drawViewport(
        context: OpaquePointer?,
        color: GdkRGBA,
        mapWidth: Double,
        mapHeight: Double
    ) {
        guard let adjustment = vadjustment() else { return }
        let upper = gtk_adjustment_get_upper(adjustment)
        let page = gtk_adjustment_get_page_size(adjustment)
        guard upper > 0, page > 0, page < upper else { return }

        let top = gtk_adjustment_get_value(adjustment) / upper * mapHeight
        let markerHeight = max(6, page / upper * mapHeight)

        cairo_set_source_rgba(context, Double(color.red), Double(color.green), Double(color.blue), 0.10)
        cairo_rectangle(context, 0, top, mapWidth, markerHeight)
        cairo_fill(context)
    }

    // MARK: - Interaction

    /// Scroll the editor so the line clicked in the map is centered.
    func scrollTo(y: Double, height: Double) {
        guard height > 0, let adjustment = vadjustment() else { return }
        let upper = gtk_adjustment_get_upper(adjustment)
        let page = gtk_adjustment_get_page_size(adjustment)
        let target = (y / height) * upper - page / 2
        gtk_adjustment_set_value(adjustment, min(max(0, target), max(0, upper - page)))
    }

    func vadjustment() -> UnsafeMutablePointer<GtkAdjustment>? {
        guard let scroller else { return nil }
        return gtk_scrolled_window_get_vadjustment(scroller)?.cast()
    }
}
