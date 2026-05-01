import SwiftUI
import WebKit
import AppKit

/// Full-fidelity AsciiDoc reader. Loads a bundled HTML page that embeds
/// asciidoctor.js, then hands the document text to it for conversion.
/// Local-file links (relative paths or `file://` URLs) are intercepted
/// and opened as new tabs in the workspace; everything else falls
/// through to the system handler.
struct AsciiDocReaderView: View {
    let text: String
    var sourceURL: URL? = nil

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AsciiDocWebView(
            text: text,
            sourceURL: sourceURL,
            colorScheme: colorScheme,
            onOpenLocal: { url in workspace.open(url: url) }
        )
    }
}

private struct AsciiDocWebView: NSViewRepresentable {
    let text: String
    let sourceURL: URL?
    let colorScheme: ColorScheme
    let onOpenLocal: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenLocal: onOpenLocal, sourceURL: sourceURL)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        // Don't paint a default white card behind the page so the
        // workspace's pane background shows through (matching markdown).
        webView.underPageBackgroundColor = .clear

        context.coordinator.webView = webView
        context.coordinator.pendingText = text
        context.coordinator.sourceURL = sourceURL
        loadTemplate(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        coord.sourceURL = sourceURL
        coord.onOpenLocal = onOpenLocal

        if coord.lastRenderedText != text {
            coord.pendingText = text
            if coord.isReady {
                coord.renderNow(text: text)
            }
        }
    }

    private func loadTemplate(into webView: WKWebView, coordinator: Coordinator) {
        guard let renderURL = AsciiDocResources.renderHTMLURL else {
            coordinator.showLoadError("AsciiDoc resources not found in app bundle.")
            return
        }
        webView.loadFileURL(renderURL, allowingReadAccessTo: renderURL.deletingLastPathComponent())
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var onOpenLocal: (URL) -> Void
        var sourceURL: URL?
        var pendingText: String = ""
        var lastRenderedText: String = ""
        var isReady: Bool = false

        init(onOpenLocal: @escaping (URL) -> Void, sourceURL: URL?) {
            self.onOpenLocal = onOpenLocal
            self.sourceURL = sourceURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            renderNow(text: pendingText)
        }

        func renderNow(text: String) {
            guard let webView else { return }
            // Pass the asciidoc through as a JSON string so newlines,
            // quotes, backslashes, and any unicode all survive transit
            // into the JS context unscathed.
            let payload = Self.jsStringLiteral(text)
            let script = "window.minimalistRender(\(payload));"
            webView.evaluateJavaScript(script, completionHandler: nil)
            lastRenderedText = text
        }

        func showLoadError(_ message: String) {
            guard let webView else { return }
            let escaped = message
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let html = """
            <!doctype html><html><body style="font: -apple-system-body; padding: 24px;">
            <p style="color: #c33;">\(escaped)</p>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }

        nonisolated func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Delegate callbacks fire on the main thread, but the
            // protocol method itself is non-isolated — hop into the
            // main actor's isolation so we can read the navigation
            // action's properties without warnings.
            let (navType, url) = MainActor.assumeIsolated {
                (navigationAction.navigationType, navigationAction.request.url)
            }

            // Initial template load + any JS-driven nav report `.other`
            // and should pass through.
            if navType == .other {
                decisionHandler(.allow)
                return
            }

            guard let url else {
                decisionHandler(.cancel)
                return
            }

            // In-page anchor jumps (sectanchors, table-of-contents links
            // inside the rendered doc) keep the same path as our
            // template — let WKWebView handle them itself.
            if let template = AsciiDocResources.renderHTMLURL,
               url.path == template.path {
                decisionHandler(.allow)
                return
            }

            Task { @MainActor in
                self.handleClickedLink(url)
            }
            decisionHandler(.cancel)
        }

        private func handleClickedLink(_ url: URL) {
            if let local = resolveLocalFileURL(url),
               FileManager.default.fileExists(atPath: local.path) {
                onOpenLocal(local)
                return
            }
            // Anything else — http(s), mailto, custom schemes — hand
            // off to the system.
            NSWorkspace.shared.open(url)
        }

        /// Map a clicked URL onto a local file URL when reasonable.
        /// `file://` URLs come straight through; relative links arrive
        /// as `file://` against the page's base URL (asciidoctor
        /// resources directory) — we re-anchor them on the document's
        /// directory so they point at the user's neighboring files.
        private func resolveLocalFileURL(_ url: URL) -> URL? {
            guard let base = sourceURL?.deletingLastPathComponent() else {
                return url.isFileURL ? url : nil
            }
            if url.isFileURL {
                // Strip the bundled asciidoctor directory portion so we
                // can reanchor relative paths against the source doc.
                if let bundleDir = AsciiDocResources.directoryURL,
                   url.path.hasPrefix(bundleDir.path) {
                    let suffix = String(url.path.dropFirst(bundleDir.path.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    return base.appendingPathComponent(suffix).standardizedFileURL
                }
                return url.standardizedFileURL
            }
            if url.scheme == nil || url.scheme?.isEmpty == true {
                return URL(fileURLWithPath: url.absoluteString, relativeTo: base).standardizedFileURL
            }
            return nil
        }

        /// Encode `s` as a JavaScript string literal (including the
        /// enclosing double quotes). Using JSONSerialization gives us
        /// proper escaping for control characters, quotes, line
        /// separators, etc. without a custom escape table.
        private static func jsStringLiteral(_ s: String) -> String {
            if let data = try? JSONSerialization.data(
                withJSONObject: [s],
                options: [.fragmentsAllowed]
            ),
               let str = String(data: data, encoding: .utf8) {
                // Strip the outer `[ ... ]` wrapper.
                let inner = str.dropFirst().dropLast()
                return String(inner)
            }
            return "\"\""
        }
    }
}

/// Resolves the bundled asciidoctor template + scripts at runtime.
/// xcodegen places `Resources/asciidoctor` into the app bundle as a
/// folder reference, so we look it up under `Bundle.main.resourceURL`.
enum AsciiDocResources {
    static var directoryURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("asciidoctor", isDirectory: true)
    }

    static var renderHTMLURL: URL? {
        directoryURL?.appendingPathComponent("render.html")
    }
}
