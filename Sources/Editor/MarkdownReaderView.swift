import SwiftUI
import MarkdownUI

/// A full-featured markdown reader powered by MarkdownUI. Supports the
/// CommonMark spec plus GitHub-flavored extensions: tables, task lists,
/// strikethrough, footnotes, nested lists, images, syntax-highlighted code
/// blocks, and more.
struct MarkdownReaderView: View {
    let text: String

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
