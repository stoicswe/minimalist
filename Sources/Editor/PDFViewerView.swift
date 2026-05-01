import SwiftUI
import PDFKit

/// Reader for `.pdf` documents. Wraps `PDFView` so we get native
/// scrolling, page navigation, and selection out of the box. Background
/// is left transparent so the workspace's pane background (and the
/// glass-mode blur) shows through behind the page chrome.
struct PDFViewerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Reload only when the URL flips (e.g., the file was renamed
        // on disk and the document was reopened against the new path).
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
