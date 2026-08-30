import Adwaita
import Foundation
import MinimalistCore

extension MainView {

    /// One row in the palette.
    struct SearchRow: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let path: String
        let line: Int?
    }

    func openSearch() {
        searchQuery = ""
        searchIndex = 0
        searchCandidates = onMain { DocumentStore.shared.folderURL }
            .map { WorkspaceSearch.files(under: $0).map(\.path) } ?? []
        searchVisible = true
    }

    func closeSearch() {
        searchVisible = false
        searchQuery = ""
    }

    /// Files, in-file line matches, and (for an empty query) recents —
    /// the same result mix as the macOS palette, plus `:line` jumps.
    var searchResults: [SearchRow] {
        let parsed = WorkspaceSearch.parseQuery(searchQuery)
        let query = parsed.text.trimmingCharacters(in: .whitespaces)
        let root = onMain { DocumentStore.shared.folderURL }

        if query.isEmpty {
            if let line = parsed.line, let tab = activeTab {
                return [SearchRow(
                    id: "jump-\(line)",
                    title: "Go to line \(line)",
                    subtitle: tab.title,
                    icon: "go-jump-symbolic",
                    path: tab.id,
                    line: line
                )]
            }
            return onMain { DocumentStore.shared.recentURLs }.map { url in
                SearchRow(
                    id: "recent-\(url.path)",
                    title: url.lastPathComponent,
                    subtitle: WorkspaceSearch.relativePath(of: url, root: root),
                    icon: "document-open-recent-symbolic",
                    path: url.path,
                    line: nil
                )
            }
        }

        var results: [SearchRow] = []
        if root != nil {
            let candidates = searchCandidates.map { URL(fileURLWithPath: $0) }
            for url in WorkspaceSearch.rank(candidates: candidates, query: query) {
                results.append(SearchRow(
                    id: "file-\(url.path)",
                    title: url.lastPathComponent,
                    subtitle: WorkspaceSearch.relativePath(of: url, root: root),
                    icon: "text-x-generic-symbolic",
                    path: url.path,
                    line: parsed.line
                ))
            }
        }
        if let tab = activeTab, tab.kind == .text {
            for hit in WorkspaceSearch.lineMatches(query: query, in: activeText) {
                results.append(SearchRow(
                    id: "line-\(hit.line)",
                    title: hit.text,
                    subtitle: "\(tab.title) · line \(hit.line)",
                    icon: "go-jump-symbolic",
                    path: tab.id,
                    line: hit.line
                ))
            }
        }
        return results
    }

    func activateSearchSelection() {
        let results = searchResults
        guard results.indices.contains(searchIndex) else { return }
        activate(results[searchIndex])
    }

    func activate(_ result: SearchRow) {
        closeSearch()
        if result.path == activeTabID, let line = result.line {
            jump(to: line)
            return
        }
        openFile(URL(fileURLWithPath: result.path), preview: false, scrollTo: result.line)
    }

    @ViewBuilder var searchPalette: Body {
        VStack(spacing: 0) {
            SearchEntry()
                .text($searchQuery)
                .placeholderText("Search files, or :line")
                .activate { activateSearchSelection() }
                .focus($searchFocus)
                .padding(10)
            let results = searchResults
            if !results.isEmpty {
                Separator()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(results.prefix(12)), id: \.id) { result in
                            searchRowView(result, selected: results.firstIndex(of: result) == searchIndex)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .style("palette")
        .frame(maxWidth: 520)
    }

    @ViewBuilder func searchRowView(_ result: SearchRow, selected: Bool) -> Body {
        Button(result.title) { activate(result) }
            .child {
                HStack(spacing: 10) {
                    Image()
                        .iconName(result.icon)
                        .dimLabel()
                    VStack(spacing: 0) {
                        Text(result.title)
                            .ellipsize()
                            .halign(.start)
                        Text(result.subtitle)
                            .ellipsize()
                            .caption()
                            .dimLabel()
                            .halign(.start)
                    }
                }
                .halign(.start)
            }
            .flat()
            .style("palette-row")
            .style("palette-row-active", active: selected)
    }
}
