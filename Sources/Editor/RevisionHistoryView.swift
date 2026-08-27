import SwiftUI

/// Sheet view listing every entry in `RevisionTracker`'s autosave +
/// `.minimal` git history for a file. Selecting an entry shows a
/// side-by-side preview against the file's current content; the user can
/// revert from there.
struct RevisionHistoryView: View {
    let url: URL
    let workspace: Workspace

    @Environment(\.dismiss) private var dismiss
    @State private var revisions: [Revision] = []
    @State private var selection: Revision?
    @State private var revisionContent: String = ""
    @State private var currentContent: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if revisions.isEmpty {
                emptyState
            } else {
                HSplitView {
                    revisionList
                        .frame(minWidth: 220, idealWidth: 260)
                    diffPane
                        .frame(minWidth: 360)
                        .layoutPriority(1)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, idealWidth: 880, minHeight: 460, idealHeight: 560)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Revision History")
                    .font(.headline)
                Text(url.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private var revisionList: some View {
        List(revisions, selection: $selection) { revision in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: revision.kind == .commit ? "checkmark.circle" : "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(revision.kind == .commit ? Color.accentColor : Color.secondary)
                    Text(revision.summary)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                Text(revision.date.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .tag(revision)
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, newValue in
            loadSelectedContent(newValue)
        }
    }

    @ViewBuilder
    private var diffPane: some View {
        if let revision = selection {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(revision.summary)
                            .font(.system(size: 13, weight: .semibold))
                        Text(revision.date.formatted(date: .complete, time: .standard))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revert to this version") {
                        revert(to: revision)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                Divider()
                ScrollView {
                    DiffView(oldText: currentContent, newText: revisionContent)
                        .padding(12)
                }
            }
        } else {
            VStack {
                Spacer()
                Text("Select a revision to compare")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No revisions yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Edits autosave automatically, and ⌘S commits a milestone.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(revisions.count) revision\(revisions.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Data loading

    private func load() {
        revisions = workspace.revisionTracker?.revisions(for: url) ?? []
        currentContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if selection == nil { selection = revisions.first }
        loadSelectedContent(selection)
    }

    private func loadSelectedContent(_ revision: Revision?) {
        guard let revision, let tracker = workspace.revisionTracker else {
            revisionContent = ""
            return
        }
        revisionContent = tracker.content(for: revision, file: url) ?? ""
    }

    private func revert(to revision: Revision) {
        guard let tracker = workspace.revisionTracker else { return }
        _ = tracker.revert(file: url, to: revision)
        // Refresh in-memory document if it's open.
        if let doc = workspace.openDocuments.first(where: { $0.url == url }),
           let restored = try? String(contentsOf: url, encoding: .utf8) {
            doc.text = restored
        }
        load()
    }
}

/// Unified diff renderer in the familiar `git diff` shape — `+` lines on a
/// green background for additions, `-` lines on red for removals, plain
/// context lines unmarked, hunk headers (`@@ … @@`) for orientation.
/// Diff itself is computed in-process by `DiffEngine` (Myers algorithm),
/// so the line alignment is true-LCS rather than naive index-by-index
/// matching.
struct DiffView: View {
    let oldText: String
    let newText: String

    @State private var lines: [DiffLine] = []
    @State private var loaded: Bool = false

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                Text("No differences from current.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        DiffLineRow(line: line)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: cacheKey) {
            await recompute()
        }
    }

    private var cacheKey: String {
        "\(oldText.count)-\(newText.count)"
    }

    @MainActor
    private func recompute() async {
        loaded = false
        lines = DiffEngine.unified(old: oldText, new: newText)
        loaded = true
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.marker)
                .frame(width: 12, alignment: .center)
                .foregroundStyle(line.markerColor)
            Text(line.text)
                .textSelection(.enabled)
                .foregroundStyle(line.textColor)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 0.5)
        .background(line.background)
    }
}

struct DiffLine {
    enum Kind { case context, added, removed, hunk }
    let kind: Kind
    let text: String

    var marker: String {
        switch kind {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        case .hunk: return ""
        }
    }

    var markerColor: Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        default: return .secondary
        }
    }

    var textColor: Color {
        switch kind {
        case .hunk: return .secondary
        default: return .primary
        }
    }

    var background: Color {
        switch kind {
        case .added: return Color.green.opacity(0.10)
        case .removed: return Color.red.opacity(0.10)
        case .hunk: return Color.primary.opacity(0.04)
        case .context: return .clear
        }
    }
}

enum DiffEngine {
    /// Compute a unified diff (3 lines of context, `@@` hunk headers)
    /// between two snapshots, entirely in-process — the sandbox can't
    /// spawn `/usr/bin/diff`. Uses Swift's built-in Myers difference.
    /// Returns an empty array when the snapshots are identical.
    static func unified(old: String, new: String) -> [DiffLine] {
        var oldLines = old.components(separatedBy: "\n")
        var newLines = new.components(separatedBy: "\n")
        // A trailing newline produces a final empty component that isn't
        // a real line — mirror `diff`'s treatment of line terminators.
        if oldLines.last == "" { oldLines.removeLast() }
        if newLines.last == "" { newLines.removeLast() }

        let difference = newLines.difference(from: oldLines)
        if difference.isEmpty { return [] }

        var removedOld = Set<Int>()
        var insertedNew = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removedOld.insert(offset)
            case .insert(let offset, _, _): insertedNew.insert(offset)
            }
        }

        // Interleave both sides into a single op stream: removals first
        // at each position, then insertions, then matched context.
        struct Op {
            let kind: DiffLine.Kind   // .context / .added / .removed
            let text: String
            let oldLine: Int          // 1-based, 0 when absent
            let newLine: Int
        }
        var ops: [Op] = []
        var i = 0
        var j = 0
        while i < oldLines.count || j < newLines.count {
            if i < oldLines.count, removedOld.contains(i) {
                ops.append(Op(kind: .removed, text: oldLines[i], oldLine: i + 1, newLine: 0))
                i += 1
            } else if j < newLines.count, insertedNew.contains(j) {
                ops.append(Op(kind: .added, text: newLines[j], oldLine: 0, newLine: j + 1))
                j += 1
            } else if i < oldLines.count, j < newLines.count {
                ops.append(Op(kind: .context, text: oldLines[i], oldLine: i + 1, newLine: j + 1))
                i += 1
                j += 1
            } else {
                break
            }
        }

        // Group changed ops into hunks with up to `contextRadius` shared
        // lines of context, exactly like `diff -u`.
        let contextRadius = 3
        var result: [DiffLine] = []
        var index = 0
        while index < ops.count {
            guard ops[index].kind != .context else {
                index += 1
                continue
            }
            // Found a change — expand backward for leading context…
            let hunkStart = max(0, index - contextRadius)
            // …and forward, merging any changes closer than 2×radius.
            var hunkEnd = index
            var cursor = index
            while cursor < ops.count {
                if ops[cursor].kind != .context {
                    hunkEnd = cursor
                }
                if cursor - hunkEnd >= contextRadius * 2 { break }
                cursor += 1
            }
            let end = min(ops.count - 1, hunkEnd + contextRadius)

            let hunk = ops[hunkStart...end]
            let oldStart = hunk.first(where: { $0.oldLine > 0 })?.oldLine ?? 0
            let newStart = hunk.first(where: { $0.newLine > 0 })?.newLine ?? 0
            let oldCount = hunk.filter { $0.kind != .added }.count
            let newCount = hunk.filter { $0.kind != .removed }.count
            result.append(DiffLine(
                kind: .hunk,
                text: "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
            ))
            for op in hunk {
                result.append(DiffLine(kind: op.kind, text: op.text))
            }
            index = end + 1
        }
        return result
    }
}
