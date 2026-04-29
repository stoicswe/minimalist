import SwiftUI

/// The strip across the top of the window, just below the traffic-light
/// buttons. Hosts the workspace folder name and current git branch.
/// Lives below the system title-bar region so its buttons actually receive
/// clicks instead of being captured by the window-drag area.
struct TopBar: View {
    @EnvironmentObject var workspace: Workspace
    @StateObject private var git = GitState()
    @State private var showBranchPopover = false

    /// Leading inset from the window edge to the folder name.
    private let leadingPadding: CGFloat = 14

    var body: some View {
        ZStack(alignment: .leading) {
            // The sidebar column's `PaneBackground` (in ContentView) shows
            // through the TopBar — that's how translucency settings flow up
            // here too. We just need a draggable layer behind the content.
            WindowDraggableArea()

            HStack(spacing: 0) {
                Color.clear.frame(width: leadingPadding)

                if let folder = workspace.rootNode?.url {
                    Text(folder.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if git.isRepo, let branch = git.currentBranch {
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)

                        BranchButton(branch: branch) {
                            showBranchPopover.toggle()
                        }
                        .popover(isPresented: $showBranchPopover, arrowEdge: .bottom) {
                            BranchPopover(git: git) {
                                showBranchPopover = false
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .frame(height: 26)
        .task(id: workspace.rootNode?.url) {
            await git.refresh(folder: workspace.rootNode?.url)
        }
    }
}

private struct BranchButton: View {
    let branch: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .medium))
                Text(branch)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.10 : 0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
