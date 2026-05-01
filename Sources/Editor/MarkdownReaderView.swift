import SwiftUI
import MarkdownUI
import AppKit

/// A full-featured markdown reader powered by MarkdownUI. Supports the
/// CommonMark spec plus GitHub-flavored extensions: tables, task lists,
/// strikethrough, footnotes, nested lists, images, syntax-highlighted code
/// blocks, and more.
///
/// Local-file links (`[label](other-doc.md)`, relative paths, or
/// `file://` URLs) open as new tabs in the workspace instead of being
/// handed to the system. External URLs (`http(s)://`, `mailto:`, etc.)
/// fall through to the standard openURL action.
struct MarkdownReaderView: View {
    let text: String
    /// URL of the source document, used to resolve relative links to
    /// other local files. Pass `nil` for ad-hoc / unsaved markdown.
    var sourceURL: URL? = nil

    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        ScrollView {
            Markdown(text)
                .markdownTheme(transparentGitHub)
                .markdownTextStyle {
                    FontSize(15)
                    BackgroundColor(nil)
                }
                .textSelection(.enabled)
                .padding(.horizontal, 36)
                .padding(.vertical, 32)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .environment(\.openURL, OpenURLAction { url in
            handleLink(url)
        })
    }

    /// Resolve `url` against the source document, open it in the
    /// workspace if it points at a real local file, otherwise hand it
    /// back to the system to handle (web links, mail, etc.).
    private func handleLink(_ url: URL) -> OpenURLAction.Result {
        if let local = resolveLocalFileURL(url),
           FileManager.default.fileExists(atPath: local.path) {
            workspace.open(url: local)
            return .handled
        }
        return .systemAction
    }

    /// Map a link URL onto a local file URL if it's reasonable to do
    /// so. Returns nil for anything that's clearly an external link.
    private func resolveLocalFileURL(_ url: URL) -> URL? {
        if url.isFileURL {
            return url
        }
        // SwiftUI hands MarkdownUI's `[text](relative.md)` to us as a
        // URL with no scheme — `url.scheme == nil` and `path` containing
        // the relative string. Resolve it against the source document.
        if url.scheme == nil || url.scheme?.isEmpty == true {
            guard let base = sourceURL?.deletingLastPathComponent() else {
                return nil
            }
            // `URL(string:)` may have eaten the `./` or other prefix —
            // rebuild from the absolute string instead so we don't lose
            // any pre-existing relative components.
            let raw = url.absoluteString
            if raw.isEmpty { return nil }
            return URL(fileURLWithPath: raw, relativeTo: base).standardizedFileURL
        }
        // Anything with a scheme other than file:// — http, https,
        // mailto, custom schemes — is for the system to open.
        return nil
    }

    /// `.gitHub` theme with the opaque body / blockquote / table backgrounds
    /// cleared so the editor pane (or its glass blur) shows through.
    private var transparentGitHub: Theme {
        Theme.gitHub
            .text {
                BackgroundColor(nil)
            }
            .blockquote { configuration in
                configuration.label
                    .relativePadding(.horizontal, length: .em(1))
                    .relativeLineSpacing(.em(0.25))
                    .markdownTextStyle {
                        ForegroundColor(Color.secondary)
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 3)
                    }
            }
    }
}
