import SwiftUI
import DevHavenCore

struct WorkspaceCommitRootView: View {
    @Bindable var viewModel: WorkspaceCommitViewModel
    @State private var topAreaRatio: Double = 0.7

    var body: some View {
        WorkspaceSplitView(
            direction: .vertical,
            ratio: topAreaRatio,
            onRatioChange: { topAreaRatio = $0 },
            onEqualize: { topAreaRatio = 0.7 }
        ) {
            WorkspaceCommitChangesBrowserView(viewModel: viewModel)
        } trailing: {
            WorkspaceCommitPanelView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.refreshChangesSnapshot()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
    }
}
