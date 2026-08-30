import Adwaita
import Foundation
import MinimalistCore

extension MainView {

    struct RevisionRow: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let isCommit: Bool
    }

    struct CommitRow: Identifiable, Equatable {
        let id: String
        let subject: String
        let subtitle: String
    }

    // MARK: - Revision history (the app's own `.minimal/` track)

    func openRevisionHistory(for path: String? = nil) {
        let target = path ?? activeTabID
        guard !target.isEmpty else {
            report("Open a file first.")
            return
        }
        historyTarget = target
        revisionRows = onMain { () -> [RevisionRow] in
            guard let tracker = DocumentStore.shared.revisionTracker else { return [] }
            return tracker.revisions(for: URL(fileURLWithPath: target)).map { revision in
                RevisionRow(
                    id: revision.id,
                    title: revision.summary,
                    subtitle: Self.dateFormatter.string(from: revision.date),
                    isCommit: revision.kind == .commit
                )
            }
        }
        revisionSelection = revisionRows.first?.id ?? ""
        historyPreview = revisionContent(revisionSelection)
        revisionsVisible = true
    }

    @ViewBuilder var revisionHistory: Body {
        // A split view rather than a hand-built HStack: it owns the pane
        // widths and the divider, which a Clamp + Separator pair can't do
        // inside a dialog.
        OverlaySplitView(visible: .init { true } set: { _ in }) {
            VStack {
                ScrollView {
                    if revisionRows.isEmpty {
                        Text("No revisions recorded yet")
                            .wrap()
                            .dimLabel()
                            .padding(20)
                    } else {
                        List(revisionRows, id: \.id, selection: nil) { row in
                            revisionRowView(row)
                        }
                        .sidebarStyle()
                    }
                }
                .vexpand()
                Button("Revert to This Revision") { revertToSelectedRevision() }
                    .destructive()
                    .padding(8)
            }
        } content: {
            historyPreviewPane
        }
        .sidebarWidthFraction(0.38)
        .minSidebarWidth(240)
        .maxSidebarWidth(360)
        .pinSidebar()
        .topToolbar {
            HeaderBar.empty()
        }
    }

    @ViewBuilder private func revisionRowView(_ row: RevisionRow) -> Body {
        Button(row.title) {
            revisionSelection = row.id
            historyPreview = revisionContent(row.id)
        }
        .child {
            HStack(spacing: 8) {
                Image()
                    .iconName(row.isCommit ? "object-select-symbolic" : "document-open-recent-symbolic")
                    .dimLabel()
                VStack(spacing: 0) {
                    Text(row.title).ellipsize().halign(.start)
                    Text(row.subtitle).ellipsize().caption().dimLabel().halign(.start)
                }
            }
            .halign(.start)
        }
        .flat()
        .style("tree-row")
        .style("row-active", active: row.id == revisionSelection)
    }

    /// The right-hand pane shared by both history dialogs: the selected
    /// revision's contents, or the selected commit's patch.
    @ViewBuilder private var historyPreviewPane: Body {
        ScrollView {
            Text(historyPreview.isEmpty ? "Nothing to preview" : historyPreview)
                .selectable()
                .xalign(0)
                .monospace()
                .halign(.start)
                .valign(.start)
                .dimLabel(historyPreview.isEmpty)
                .padding(12)
        }
        .vexpand()
        .hexpand()
    }

    private func revisionContent(_ id: String) -> String {
        guard !id.isEmpty else { return "" }
        return onMain { () -> String in
            guard let tracker = DocumentStore.shared.revisionTracker else { return "" }
            let url = URL(fileURLWithPath: historyTarget)
            guard let revision = tracker.revisions(for: url).first(where: { $0.id == id }),
                  let content = tracker.content(for: revision, file: url)
            else { return "" }
            return content
        }
    }

    private func revertToSelectedRevision() {
        let id = revisionSelection
        let target = historyTarget
        guard !id.isEmpty, !target.isEmpty else { return }
        let reverted = onMain { () -> String? in
            guard let tracker = DocumentStore.shared.revisionTracker else { return nil }
            let url = URL(fileURLWithPath: target)
            guard let revision = tracker.revisions(for: url).first(where: { $0.id == id }) else { return nil }
            return tracker.revert(file: url, to: revision)
        }
        guard let reverted else {
            report("Couldn't revert that revision.")
            return
        }
        onMain { DocumentStore.shared.document(for: target)?.text = reverted }
        chromeTick &+= 1
        revisionsVisible = false
    }

    // MARK: - Commit history (the user's own repository, read-only)

    func openCommitHistory(for path: String? = nil) {
        let target = path ?? activeTabID
        guard !target.isEmpty else {
            report("Open a file first.")
            return
        }
        historyTarget = target
        commitRows = onMain { () -> [CommitRow] in
            let url = URL(fileURLWithPath: target)
            guard let client = GitClient.open(containing: url),
                  let relative = client.repoRelativePath(of: url)
            else { return [] }
            return client.fileLog(relativePath: relative, limit: 60).map { commit in
                CommitRow(
                    id: commit.sha,
                    subject: commit.subject,
                    subtitle: "\(commit.author) · \(Self.dateFormatter.string(from: commit.date))"
                        + " · \(commit.sha.prefix(7))"
                )
            }
        }
        commitSelection = commitRows.first?.id ?? ""
        historyPreview = patch(for: commitSelection)
        commitsVisible = true
    }

    @ViewBuilder var commitHistory: Body {
        OverlaySplitView(visible: .init { true } set: { _ in }) {
            ScrollView {
                if commitRows.isEmpty {
                    Text("No commits touch this file")
                        .wrap()
                        .dimLabel()
                        .padding(20)
                } else {
                    List(commitRows, id: \.id, selection: nil) { row in
                        Button(row.subject) {
                            commitSelection = row.id
                            historyPreview = patch(for: row.id)
                        }
                        .child {
                            VStack(spacing: 0) {
                                Text(row.subject).ellipsize().halign(.start)
                                Text(row.subtitle).ellipsize().caption().dimLabel().halign(.start)
                            }
                            .halign(.start)
                        }
                        .flat()
                        .style("tree-row")
                        .style("row-active", active: row.id == commitSelection)
                    }
                    .sidebarStyle()
                }
            }
            .vexpand()
        } content: {
            historyPreviewPane
        }
        .sidebarWidthFraction(0.42)
        .minSidebarWidth(260)
        .maxSidebarWidth(400)
        .pinSidebar()
        .topToolbar {
            HeaderBar.empty()
        }
    }

    private func patch(for sha: String) -> String {
        guard !sha.isEmpty else { return "" }
        return onMain { () -> String in
            let url = URL(fileURLWithPath: historyTarget)
            guard let client = GitClient.open(containing: url),
                  let relative = client.repoRelativePath(of: url),
                  let patch = client.patch(commitSHA: sha, relativePath: relative)
            else { return "" }
            return patch
        }
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
