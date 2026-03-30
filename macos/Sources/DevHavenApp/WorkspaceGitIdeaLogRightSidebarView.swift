import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogRightSidebarView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel
    let onOpenDiff: (WorkspaceGitCommitFileChange) -> Void
    @State private var detailsRatio = 0.56

    var body: some View {
        WorkspaceSplitView(
            direction: .vertical,
            ratio: detailsRatio,
            onRatioChange: { detailsRatio = $0 },
            minLeadingSize: 180,
            minTrailingSize: 160,
            leading: {
                WorkspaceGitIdeaLogChangesView(viewModel: viewModel, onOpenDiff: onOpenDiff)
                    .background(NativeTheme.window)
            },
            trailing: {
                WorkspaceGitIdeaLogDetailsView(viewModel: viewModel)
                    .background(NativeTheme.window)
            }
        )
        .background(NativeTheme.window)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(NativeTheme.border)
                .frame(width: 1)
        }
    }
}
