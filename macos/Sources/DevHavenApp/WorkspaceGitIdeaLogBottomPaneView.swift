import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogBottomPaneView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel
    @State private var detailRatio = 0.42

    var body: some View {
        Group {
            if viewModel.displayOptions.showsDetails {
                WorkspaceSplitView(
                    direction: .horizontal,
                    ratio: detailRatio,
                    onRatioChange: { detailRatio = $0 },
                    leading: {
                        WorkspaceGitIdeaLogChangesView(viewModel: viewModel)
                    },
                    trailing: {
                        WorkspaceGitIdeaLogDetailsView(viewModel: viewModel)
                    }
                )
            } else {
                WorkspaceGitIdeaLogChangesView(viewModel: viewModel)
            }
        }
        .background(NativeTheme.window)
    }
}
