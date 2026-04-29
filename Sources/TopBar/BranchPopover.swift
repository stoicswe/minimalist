import SwiftUI

struct BranchPopover: View {
    @ObservedObject var git: GitState
    var dismiss: () -> Void

    @State private var filter: String = ""
    @State private var newBranchMode: Bool = false
    @State private var newBranchName: String = ""
    @State private var working: Bool = false

    private var filteredBranches: [String] {
        guard !filter.isEmpty else { return git.branches }
        return git.branches.filter {
            $0.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if newBranchMode {
                newBranchForm
            } else {
                branchList
            }
        }
        .frame(width: 280)
        .onChange(of: git.currentBranch) { _, _ in
            if working { working = false }
        }
    }

    private var branchList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter branches", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredBranches, id: \.self) { branch in
                        BranchRow(
                            name: branch,
                            isCurrent: branch == git.currentBranch,
                            disabled: working
                        ) {
                            guard branch != git.currentBranch else { return }
                            working = true
                            Task {
                                await git.checkout(branch)
                                if git.lastError == nil { dismiss() }
                            }
                        }
                    }
                    if filteredBranches.isEmpty {
                        Text("No branches match")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                }
            }
            .frame(maxHeight: 240)

            Divider()

            Button(action: { newBranchMode = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("New branch from \(git.currentBranch ?? "HEAD")…")
                        .font(.system(size: 12))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let error = git.lastError {
                Divider()
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .lineLimit(3)
            }
        }
    }

    private var newBranchForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New branch from \(git.currentBranch ?? "HEAD")")
                .font(.system(size: 12, weight: .semibold))
            TextField("branch-name", text: $newBranchName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitNewBranch() }
            HStack {
                Button("Cancel") {
                    newBranchMode = false
                    newBranchName = ""
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Create") { commitNewBranch() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
            }
        }
        .padding(12)
    }

    private func commitNewBranch() {
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        working = true
        Task {
            await git.createBranch(name)
            working = false
            if git.lastError == nil {
                newBranchMode = false
                newBranchName = ""
                dismiss()
            }
        }
    }
}

private struct BranchRow: View {
    let name: String
    let isCurrent: Bool
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isCurrent ? "checkmark" : "")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)
                    .foregroundStyle(isCurrent ? Color.primary : Color.clear)
                Text(name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(hovering ? Color.primary.opacity(0.07) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}
